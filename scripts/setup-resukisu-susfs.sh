#!/usr/bin/env bash
#
# ReSukiSU + susfs v2.2.0 untuk kernel Mi-Thorium 4.19 (non-GKI).
# Terbukti boot di Redmi 5A — manager melaporkan susfs v2.2.0.
#
# URUTAN ITU PENTING. Tiap langkah bergantung pada hasil langkah sebelumnya;
# menukar urutannya menghasilkan kegagalan yang senyap. Lihat komentar di
# tiap tahap.
#
# Pakai:  ./setup-resukisu-susfs.sh [path/ke/kernel]
#
set -euo pipefail

KERNEL="${1:-$HOME/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel}"
UPSTREAM="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$KERNEL/Makefile" ] && [ -d "$KERNEL/drivers" ] || die "bukan root kernel: $KERNEL"
grep -q "^PATCHLEVEL = 19" "$KERNEL/Makefile" || die "skrip ini untuk kernel 4.19"

# Idempotensi: kalau sudah terpasang lengkap, tidak ada yang perlu dikerjakan.
if [ -f "$KERNEL/include/linux/susfs.h" ] \
   && grep -q "ksu_handle_setresuid" "$KERNEL/kernel/sys.c" 2>/dev/null \
   && [ -d "$KERNEL/KernelSU" ]; then
    say "Sudah terpasang lengkap"
    echo "    susfs   : $(grep -m1 -oE 'v[0-9.]+' "$KERNEL/include/linux/susfs.h")"
    echo "    ReSukiSU: $(git -C "$KERNEL/KernelSU" rev-list --count HEAD) commit"
    echo "    Untuk memasang ulang dari nol: git -C \"$KERNEL\" reset --hard && rm -rf \"$KERNEL/KernelSU\""
    exit 0
fi

# ─────────────────────────────────────────────────────────── 1
# Hook KSU bawaan Mi-Thorium HARUS dibuang lebih dulu.
#
# CONFIG_KSU_SUSFS di ReSukiSU adalah *metode hook* dalam blok Kconfig
# `choice` -- saling eksklusif dengan KSU_MANUAL_HOOK. Kalau susfs aktif,
# susfs yang menyediakan hook, jadi hook Mi-Thorium hanya jadi hook ganda.
# Selain itu susfs_inline_hook_patches.sh MELEWATI file yang masih memuat
# "ksu_handle", jadi tanpa langkah ini sebagian hook tidak akan terpasang.
#
# clean_hook.sh milik upstream tidak dipakai: polanya `#ifdef CONFIG_KSU`
# tidak cocok dengan bentuk `#if IS_ENABLED(CONFIG_KSU_STATIC_HOOKS)` milik
# Mi-Thorium, dan sed rentang buta bisa salah potong. Kita telusuri kedalaman
# preprocessor.
say "1/6  Membuang hook KSU bawaan Mi-Thorium"
python3 - "$KERNEL" <<'PY'
import sys, pathlib
K = pathlib.Path(sys.argv[1])
total = 0
for rel in ["fs/exec.c","fs/open.c","fs/read_write.c","fs/stat.c","drivers/input/input.c"]:
    p = K/rel
    lines = p.read_text().splitlines(keepends=True)
    out, i, removed = [], 0, 0
    while i < len(lines):
        if "#if IS_ENABLED(CONFIG_KSU" in lines[i]:
            depth, j = 0, i
            while j < len(lines):
                s = lines[j].lstrip()
                if s.startswith("#if"): depth += 1
                elif s.startswith("#endif"):
                    depth -= 1
                    if depth == 0: break
                j += 1
            removed += 1; i = j + 1
            while i < len(lines) and lines[i].strip() == "" and out and out[-1].strip() == "":
                i += 1
            continue
        out.append(lines[i]); i += 1
    p.write_text("".join(out))
    total += removed
    # sanity: kurung kurawal harus tetap seimbang
    t = p.read_text()
    assert t.count("{") == t.count("}"), f"{rel}: kurung timpang setelah pembersihan"
    print(f"    {rel:24} {removed} blok")
print(f"    total {total} blok dibuang")
PY
# Hook Mi-Thorium ditandai CONFIG_KSU_STATIC_HOOKS; hook susfs memakai
# CONFIG_KSU_SUSFS. Jangan uji dengan "ksu_handle" generik -- keduanya memakainya.
for f in fs/exec.c fs/open.c fs/read_write.c fs/stat.c drivers/input/input.c; do
    n=$(grep -c "CONFIG_KSU_STATIC_HOOKS" "$KERNEL/$f") || n=0
    [ "$n" -eq 0 ] || die "$f masih memuat hook Mi-Thorium ($n blok)"
done

# ─────────────────────────────────────────────────────────── 2
say "2/6  Menerapkan susfs v2.2.0 (core)"
curl -sSL -o "$WORK/susfs.patch" "$UPSTREAM/Patches/Patch/susfs_patch_to_4.19.patch"
grep -q 'SUSFS_VERSION "v2' "$WORK/susfs.patch" || die "patch susfs tidak seperti yang diharapkan"
cd "$KERNEL"
# 1 hunk memang gagal (fs/namespace.c) -- ditangani di langkah 3.
patch -p1 --fuzz=5 --no-backup-if-mismatch < "$WORK/susfs.patch" || true
[ -f include/linux/susfs.h ] || die "susfs core tidak terpasang"
echo "    $(grep -m1 SUSFS_VERSION include/linux/susfs.h)"

# ─────────────────────────────────────────────────────────── 3
# Hunk vfs_kern_mount() dari susfs tidak berlaku: kernel Mi-Thorium memakai
# API fs_context yang di-backport dari 5.x, sehingga alloc_vfsmnt() sudah
# berpindah ke vfs_create_mount(). Tanpa adaptasi ini SUS_MOUNT tidak aktif.
say "3/6  Mengadaptasi hunk fs/namespace.c ke vfs_create_mount()"
if grep -q "bypass_orig_flow" fs/namespace.c; then
    echo "    sudah diadaptasi"
else
    python3 - "$KERNEL" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])/"fs/namespace.c"
t = p.read_text()
old = '\tmnt = alloc_vfsmnt(fc->source ?: "none");\n\tif (!mnt)\n\t\treturn ERR_PTR(-ENOMEM);'
new = '''#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
\t/* Adaptasi hunk vfs_kern_mount() milik susfs v2.2.0: kernel ini memakai
\t * API fs_context yang di-backport, sehingga alloc_vfsmnt() berpindah
\t * dari vfs_kern_mount() ke vfs_create_mount(). */
\tif (static_branch_unlikely(&susfs_is_sdcard_android_data_not_decrypted)) {
\t\tif (susfs_is_current_ksu_domain()) {
\t\t\tmnt = susfs_alloc_non_unshare_ksu_vfsmnt(fc->source ?: "none");
\t\t\tgoto bypass_orig_flow;
\t\t}
\t}
#endif
\tmnt = alloc_vfsmnt(fc->source ?: "none");
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
bypass_orig_flow:
#endif
\tif (!mnt)
\t\treturn ERR_PTR(-ENOMEM);'''
assert t.count(old) == 1, f"pola vfs_create_mount tidak cocok ({t.count(old)}x)"
p.write_text(t.replace(old, new))
print("    diadaptasi")
PY
fi
rm -f fs/namespace.c.rej
[ "$(find . -name '*.rej' | wc -l)" -eq 0 ] || die "masih ada hunk yang ditolak"

# ─────────────────────────────────────────────────────────── 4
# ReSukiSU HARUS terpasang SEBELUM skrip inline hook: skrip itu memeriksa isi
# drivers/kernelsu/ untuk memutuskan hook mana yang perlu ditambahkan. Kalau
# direktorinya belum ada, hook setresuid dilewati diam-diam dan build gagal
# dengan "You lost ksu_handle_setresuid hook in your kernel".
#
# JANGAN --depth 1: versi dihitung dari jumlah commit
# (30000 + rev-list --count + 700); shallow clone -> 30701, ditolak manager.
say "4/6  Memasang ReSukiSU"
if [ -d "$KERNEL/KernelSU" ]; then
    echo "    KernelSU/ sudah ada"
else
    git clone -q -b main https://github.com/ReSukiSU/ReSukiSU.git "$KERNEL/KernelSU"
fi
N=$(git -C "$KERNEL/KernelSU" rev-list --count HEAD)
V=$((30000 + N + 700))
echo "    $N commit -> KSU_VERSION $V"
[ "$V" -ge 35032 ] || die "versi $V terlalu rendah (manager butuh >=35032) -- clone tidak boleh shallow"

REL="$(realpath --relative-to="$KERNEL/drivers" "$KERNEL/KernelSU/kernel")"
ln -sfn "$REL" "$KERNEL/drivers/kernelsu"
[ -f "$KERNEL/drivers/kernelsu/Kconfig" ] || die "symlink drivers/kernelsu tidak resolve ($REL)"
grep -q "kernelsu" "$KERNEL/drivers/Makefile" \
    || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KERNEL/drivers/Makefile"
grep -q "drivers/kernelsu/Kconfig" "$KERNEL/drivers/Kconfig" \
    || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig"

# ─────────────────────────────────────────────────────────── 5
say "5/6  Menerapkan susfs inline hook"
curl -sSL -o "$WORK/inline.sh" "$UPSTREAM/Patches/susfs_inline_hook_patches.sh"
bash "$WORK/inline.sh" 2>&1 | grep -E "Patched|Skipped|Warning" | sed 's/^/    /'
grep -q "ksu_handle_setresuid" kernel/sys.c \
    || die "hook setresuid tidak terpasang -- ReSukiSU terpasang sebelum langkah ini?"

# ─────────────────────────────────────────────────────────── 6
say "6/6  Menulis fragment config"
cat > "$KERNEL/arch/arm64/configs/vendor/feature/resukisu.config" <<'EOF'
# ReSukiSU + susfs v2.2.0 — kernel 4.19 non-GKI
# CONFIG_KSU_SUSFS adalah METODE HOOK (SuSFS Inline Hook), satu blok `choice`
# dengan KSU_MANUAL_HOOK dan KSU_TRACEPOINT_HOOK. Jangan setel lebih dari satu.
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y

CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
EOF
echo "    $(grep -c '^CONFIG_KSU' "$KERNEL/arch/arm64/configs/vendor/feature/resukisu.config") opsi"

# ───────────────────────────────────────────────────── verifikasi
say "Verifikasi"
for pair in "ksu_vfs_read_hook:fs/read_write.c" \
            "is_ksu_transition:security/selinux/hooks.c" \
            "ksu_handle_rename:security/security.c"; do
    s="${pair%%:*}"; f="${pair##*:}"
    n=$(grep -c "$s" "$KERNEL/$f" 2>/dev/null) || n=0
    [ "$n" -eq 0 ] || die "$s masih ada di $f -- ReSukiSU akan menolak build"
    printf '    ✓ %-22s tidak ada (benar)\n' "$s"
done
printf '    ✓ %-22s %s\n' "susfs core" "$(grep -m1 -oE 'v[0-9.]+' "$KERNEL/include/linux/susfs.h")"
printf '    ✓ %-22s %s baris\n' "fs/susfs.c" "$(wc -l < "$KERNEL/fs/susfs.c")"
printf '    ✓ %-22s ada\n' "hook setresuid"
printf '    ✓ %-22s ada\n' "adaptasi SUS_MOUNT"

cat <<'EOF'

Selesai. Sisa langkah:

  1. Sambungkan fragment ke device tree (sekali, simpan sebagai patch):
       cd ~/android/lineage-20.0/device/xiaomi/Mi8937
       git am /path/ke/patches/0004-Mi8937-Enable-ReSukiSU-kernel-config.patch

  2. Build & kemas:
       cd ~/android/lineage-20.0
       source build/envsetup.sh && set +e
       lunch lineage_Mi8937_4_19-userdebug
       mka bootimage
       ./scripts/make-anykernel-zip.sh

  3. Uji (tanpa wipe data):
       fastboot flash boot out/target/product/Mi8937_4_19/boot.img
EOF
