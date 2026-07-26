#!/usr/bin/env bash
#
# Pasang SukiSU-Ultra (branch `builtin`) + susfs ke kernel Mi-Thorium 4.19.
# Idempoten: aman dijalankan ulang setelah `repo sync` menghapus perubahan.
#
# Pakai:  ./setup-sukisu.sh [path/ke/kernel]
# Default path: ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel
#
set -euo pipefail

KERNEL="${1:-$HOME/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel}"
SUSFS_BRANCH="kernel-4.19"          # sesuaikan ke kernel-4.9 kalau pakai target 4.9
SUKISU_BRANCH="builtin"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$KERNEL/Makefile" ] && [ -d "$KERNEL/drivers" ] || die "bukan root kernel: $KERNEL"
grep -q "^PATCHLEVEL = 19" "$KERNEL/Makefile" || echo "PERINGATAN: kernel bukan 4.19 — cek SUSFS_BRANCH"

# ---------------------------------------------------------------- susfs
# susfs SENGAJA TIDAK dipasang.
#
# SukiSU `builtin` (2026) memanggil API susfs v2.x — susfs_add_sus_path_loop,
# susfs_add_sus_map, susfs_start_sdcard_monitor, SUSFS_MAGIC. Sementara
# susfs4ksu branch kernel-4.19 berhenti di v1.5.5 (Feb 2025) dan tidak punya
# satu pun dari itu; branch GKI sudah v2.2.0 tapi jalur non-GKI tidak lagi
# dirawat upstream. Memasangnya membuat kernel gagal kompilasi di
# KernelSU/kernel/supercall/dispatch.c.
say "1/3  Melewati susfs (tidak kompatibel di kernel 4.19 — lihat komentar)"

# -------------------------------------------------------------- SukiSU
say "2/3  Memasang SukiSU-Ultra (branch $SUKISU_BRANCH)"
if [ -d "$KERNEL/KernelSU" ]; then
    echo "    KernelSU/ sudah ada — dilewati"
else
    git clone -q --depth 1 -b "$SUKISU_BRANCH" \
        https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "$KERNEL/KernelSU"
fi
echo "    $(git -C "$KERNEL/KernelSU" log -1 --format='%h %ad' --date=short)"

# Perbaiki dua bug upstream yang membuat branch builtin gagal di kernel <5.10.
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../patches" && pwd)"
# Deteksi lewat subjek commit, BUKAN grep string: upstream ksud.c sudah
# memuat "KERNEL_VERSION(5, 10, 0)" di tempat lain (false positive).
if git -C "$KERNEL/KernelSU" log --format=%s | grep -q "^Fix build on kernels older than 5.10$"; then
    echo "    patch <5.10 sudah diterapkan"
else
    git -C "$KERNEL/KernelSU" -c user.name=build -c user.email=build@local \
        am "$PATCH_DIR/0002-sukisu-Fix-build-on-kernels-older-than-5.10.patch" \
        && echo "    patch <5.10 diterapkan" || die "patch SukiSU gagal diterapkan"
fi

# Hitung path relatif seperti setup.sh upstream, bukan hardcode.
# Menulis "../../KernelSU/kernel" adalah kesalahan yang mudah terjadi:
# symlink ini berada DI DALAM drivers/, jadi satu ".." sudah sampai root kernel.
REL="$(realpath --relative-to="$KERNEL/drivers" "$KERNEL/KernelSU/kernel")"
ln -sfn "$REL" "$KERNEL/drivers/kernelsu"
[ -f "$KERNEL/drivers/kernelsu/Kconfig" ] || die "symlink drivers/kernelsu tidak resolve ($REL)"
echo "    drivers/kernelsu -> $REL"

grep -q "kernelsu" "$KERNEL/drivers/Makefile" \
    || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KERNEL/drivers/Makefile"
grep -q "drivers/kernelsu/Kconfig" "$KERNEL/drivers/Kconfig" \
    || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig"

# -------------------------------------------------------------- config
say "3/3  Menulis fragment config"
cat > "$KERNEL/arch/arm64/configs/vendor/feature/sukisu.config" <<'EOF'
# SukiSU-Ultra (branch: builtin)
# Hook memakai titik hook statis bawaan Mi-Thorium — simbolnya cocok.
CONFIG_KSU=y
CONFIG_KSU_STATIC_HOOKS=y

# susfs DIMATIKAN — tidak bisa dipakai di kernel 4.19.
# SukiSU `builtin` (2026) menargetkan API susfs v2.x
# (susfs_add_sus_path_loop, susfs_add_sus_map, susfs_start_sdcard_monitor,
# SUSFS_MAGIC), sementara susfs4ksu branch kernel-4.19 berhenti di v1.5.5
# (Feb 2025). Mengaktifkannya membuat kernel gagal kompilasi di
# KernelSU/kernel/supercall/dispatch.c. Branch GKI sudah v2.2.0, tapi
# non-GKI tidak lagi dirawat upstream.
# CONFIG_KSU_SUSFS is not set

# CONFIG_KPM is not set
EOF
echo "    arch/arm64/configs/vendor/feature/sukisu.config"

# ------------------------------------------------------------ verifikasi
say "Verifikasi simbol hook"
miss=0
for s in ksu_handle_execveat ksu_handle_execveat_sucompat ksu_handle_faccessat \
         ksu_handle_stat ksu_handle_vfs_read ksu_handle_input_handle_event; do
    if grep -rqE "\b$s\s*\(" "$KERNEL/KernelSU/kernel/" --include=*.c; then
        printf '    ✓ %s\n' "$s"
    else
        printf '    ✗ %s\n' "$s"; miss=1
    fi
done
[ "$miss" -eq 0 ] || die "ada simbol hook yang hilang — link kernel akan gagal"

cat <<'EOF'

Selesai. Sisa langkah (tidak otomatis):

  1. Pastikan device tree memuat fragment-nya. Sekali saja, lalu simpan
     sebagai patch karena repo sync akan menghapusnya:

       TARGET_KERNEL_CONFIG += vendor/feature/sukisu.config

     di device/xiaomi/Mi8937/BoardConfig.mk
     (atau: git am patches/0001-Mi8937-Enable-SukiSU-Ultra-susfs-kernel-config.patch)

  2. Build:

       cd ~/android/lineage-20.0
       source build/envsetup.sh && set +e
       lunch lineage_Mi8937_4_19-userdebug
       mka bacon -j$(nproc --all)
EOF
