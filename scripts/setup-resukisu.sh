#!/usr/bin/env bash
#
# Pasang ReSukiSU ke kernel Mi-Thorium 4.19 (non-GKI).
# Idempoten: aman dijalankan ulang setelah `repo sync` menghapus perubahan.
#
# Pakai:  ./setup-resukisu.sh [path/ke/kernel]
# Default: ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel
#
set -euo pipefail

KERNEL="${1:-$HOME/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel}"
BRANCH="main"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../patches" && pwd)"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$KERNEL/Makefile" ] && [ -d "$KERNEL/drivers" ] || die "bukan root kernel: $KERNEL"

# ------------------------------------------------------------ 1. ReSukiSU
say "1/3  Memasang ReSukiSU (branch $BRANCH)"
if [ -d "$KERNEL/KernelSU" ]; then
    echo "    KernelSU/ sudah ada — dilewati"
else
    # JANGAN pakai --depth 1. Versi KernelSU dihitung dari jumlah commit:
    #   KSU_VERSION = 30000 + $(git rev-list --count HEAD) + 700
    # Shallow clone membuat hitungannya 1 -> versi 30701, dan manager menolak
    # bekerja ("version too low"). Riwayat git di sini load-bearing.
    git clone -q -b "$BRANCH" https://github.com/ReSukiSU/ReSukiSU.git "$KERNEL/KernelSU"
fi
echo "    $(git -C "$KERNEL/KernelSU" log -1 --format='%h %ad' --date=short)"
N=$(git -C "$KERNEL/KernelSU" rev-list --count HEAD)
V=$((30000 + N + 700))
echo "    $N commit -> KSU_VERSION $V"
[ "$V" -ge 35032 ] || die "versi $V terlalu rendah; manager butuh >=35032. Clone tidak boleh shallow."

# Symlink dihitung, tidak di-hardcode: ia berada DI DALAM drivers/,
# jadi satu ".." sudah sampai root kernel.
REL="$(realpath --relative-to="$KERNEL/drivers" "$KERNEL/KernelSU/kernel")"
ln -sfn "$REL" "$KERNEL/drivers/kernelsu"
[ -f "$KERNEL/drivers/kernelsu/Kconfig" ] || die "symlink drivers/kernelsu tidak resolve ($REL)"
echo "    drivers/kernelsu -> $REL"

grep -q "kernelsu" "$KERNEL/drivers/Makefile" \
    || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KERNEL/drivers/Makefile"
grep -q "drivers/kernelsu/Kconfig" "$KERNEL/drivers/Kconfig" \
    || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig"

# --------------------------------------------------- 2. adaptasi hook kernel
say "2/3  Menyesuaikan titik hook kernel"
# Deteksi lewat simbol yang HANYA ada setelah patch — jangan grep string yang
# sudah ada di sumber aslinya.
if grep -q "ksu_handle_newfstat_ret" "$KERNEL/fs/stat.c"; then
    echo "    patch hook sudah diterapkan"
else
    git -C "$KERNEL" -c user.name=build -c user.email=build@local \
        am "$PATCH_DIR/0003-kernel-Adapt-KSU-static-hooks-for-ReSukiSU.patch" \
        && echo "    patch hook diterapkan" \
        || die "patch hook gagal — pastikan kernel bersih (git checkout fs/ kernel/reboot.c)"
fi

# ------------------------------------------------------------- 3. config
say "3/3  Menulis fragment config"
cat > "$KERNEL/arch/arm64/configs/vendor/feature/resukisu.config" <<'EOF'
# ReSukiSU — kernel 4.19 non-GKI
CONFIG_KSU=y

# Manual Hook: satu-satunya metode yang mendukung kernel <5.10.
# Tracepoint hook hanya untuk GKI2 (5.10+).
CONFIG_KSU_MANUAL_HOOK=y

# Auto-hook lewat LSM — sah untuk kernel <6.8, jadi setresuid / sys_read /
# input tidak perlu ditambal manual di source kernel.
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y

# Aktifkan titik hook statis bawaan Mi-Thorium (execveat/faccessat/stat/input),
# yang sudah disesuaikan oleh patch 0003.
CONFIG_KSU_STATIC_HOOKS=y

# susfs perlu langkah terpisah (patch susfs4ksu), belum diaktifkan.
# CONFIG_KSU_SUSFS is not set
EOF
echo "    arch/arm64/configs/vendor/feature/resukisu.config"

# ---------------------------------------------------------- verifikasi
say "Verifikasi hook yang divalidasi ReSukiSU"
miss=0
check() {  # nama_simbol  file
    if grep -q "$1" "$KERNEL/$2"; then printf '    ✓ %-28s %s\n' "$1" "$2"
    else printf '    ✗ %-28s %s\n' "$1" "$2"; miss=1; fi
}
check ksu_handle_execveat        fs/exec.c
check ksu_handle_faccessat       fs/open.c
check ksu_handle_stat            fs/stat.c
check ksu_handle_newfstat_ret    fs/stat.c
check ksu_handle_fstat64_ret     fs/stat.c
check ksu_handle_sys_reboot      kernel/reboot.c
[ "$miss" -eq 0 ] || die "ada hook yang hilang — build akan ditolak manual_hook_check.mk"

say "Verifikasi cek incompatible (harus 0 semua)"
for pair in "ksu_vfs_read_hook:fs/read_write.c" \
            "is_ksu_transition:security/selinux/hooks.c" \
            "ksu_handle_rename:security/security.c"; do
    s="${pair%%:*}"; f="${pair##*:}"
    # grep -c mencetak "0" DAN keluar status 1 saat tak ada match;
    # "|| echo 0" akan menghasilkan dua baris. Pakai fallback pada assignment.
    n=$(grep -c "$s" "$KERNEL/$f" 2>/dev/null) || n=0
    printf '    %-22s %s = %s\n' "$s" "$f" "$n"
    [ "$n" -eq 0 ] || die "$s masih ada di $f — ReSukiSU akan menolak build"
done

cat <<'EOF'

Selesai. Sisa langkah:

  1. Sambungkan fragment ke device tree (sekali, lalu simpan sebagai patch):

       cd ~/android/lineage-20.0/device/xiaomi/Mi8937
       git am /path/ke/patches/0004-Mi8937-Enable-ReSukiSU-kernel-config.patch

  2. Build:

       cd ~/android/lineage-20.0
       source build/envsetup.sh && set +e
       lunch lineage_Mi8937_4_19-userdebug
       mka bacon -j$(nproc --all)
EOF
