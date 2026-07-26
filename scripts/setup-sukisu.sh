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
say "1/5  Mengambil susfs4ksu ($SUSFS_BRANCH)"
git clone -q --depth 1 -b "$SUSFS_BRANCH" https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/susfs"
SUSFS_VER=$(grep -rhoE 'SUSFS_VERSION[^"]*"[^"]+"' "$WORK/susfs" 2>/dev/null | head -1 || echo "?")
echo "    $SUSFS_VER"

say "2/5  Menyalin berkas susfs ke kernel"
cp "$WORK/susfs/kernel_patches/fs/"*.c            "$KERNEL/fs/"
cp "$WORK/susfs/kernel_patches/include/linux/"*.h "$KERNEL/include/linux/"
echo "    fs/susfs.c, fs/sus_su.c, include/linux/susfs*.h, sus_su.h"

say "3/5  Menerapkan patch kernel susfs"
cd "$KERNEL"
if grep -q "CONFIG_KSU_SUSFS" fs/namei.c 2>/dev/null; then
    echo "    sudah diterapkan — dilewati"
else
    # 2 hunk fs/namespace.c memang gagal di kernel msm downstream (SUS_MOUNT).
    # Itu diharapkan; fiturnya dimatikan di config fragment.
    patch -p1 --fuzz=5 --no-backup-if-mismatch \
        < "$WORK/susfs/kernel_patches/50_add_susfs_in_kernel-${SUSFS_BRANCH#kernel-}.patch" || true
    [ -f fs/namespace.c.rej ] && echo "    catatan: fs/namespace.c.rej = 2 hunk SUS_MOUNT (diharapkan)"
fi

# -------------------------------------------------------------- SukiSU
say "4/5  Memasang SukiSU-Ultra (branch $SUKISU_BRANCH)"
if [ -d "$KERNEL/KernelSU" ]; then
    echo "    KernelSU/ sudah ada — dilewati"
else
    git clone -q --depth 1 -b "$SUKISU_BRANCH" \
        https://github.com/SukiSU-Ultra/SukiSU-Ultra.git "$KERNEL/KernelSU"
fi
echo "    $(git -C "$KERNEL/KernelSU" log -1 --format='%h %ad' --date=short)"

# PENTING: symlink relatif terhadap drivers/, jadi ../KernelSU/kernel — bukan ../../
ln -sfn ../KernelSU/kernel "$KERNEL/drivers/kernelsu"
[ -f "$KERNEL/drivers/kernelsu/Kconfig" ] || die "symlink drivers/kernelsu tidak resolve"

grep -q "kernelsu" "$KERNEL/drivers/Makefile" \
    || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KERNEL/drivers/Makefile"
grep -q "drivers/kernelsu/Kconfig" "$KERNEL/drivers/Kconfig" \
    || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KERNEL/drivers/Kconfig"

# -------------------------------------------------------------- config
say "5/5  Menulis fragment config"
cat > "$KERNEL/arch/arm64/configs/vendor/feature/sukisu.config" <<'EOF'
# SukiSU-Ultra (branch: builtin) + susfs
# Hook memakai titik hook statis bawaan Mi-Thorium — simbolnya cocok.
CONFIG_KSU=y
CONFIG_KSU_STATIC_HOOKS=y

CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y

# Dimatikan: 2 hunk fs/namespace.c tidak apply ke kernel msm downstream.
# CONFIG_KSU_SUSFS_SUS_MOUNT is not set
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
