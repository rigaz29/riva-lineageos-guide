#!/usr/bin/env bash
#
# Bangun DUA kernel zip sekaligus dari tree yang sama:
#   1. rilis  — kernel harian
#   2. debug  — dengan kernel-fragments/debug.config, untuk berburu bug
#
# Hasil di rom/:
#   KERNEL_resukisu-susfs.zip
#   KERNEL_resukisu-susfs-DEBUG.zip
#
# Pakai:  ./build-kernel-zips.sh [release|debug|both]   (default: both)
#
set -euo pipefail

MODE="${1:-both}"
ROMROOT="$HOME/android/lineage-20.0"
KDIR="$ROMROOT/kernel/xiaomi/mithorium-4.19/kernel"
OUTIMG="$ROMROOT/out/target/product/Mi8937_4_19/obj/KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb"
DOTCONFIG="$ROMROOT/out/target/product/Mi8937_4_19/obj/KERNEL_OBJ/.config"
CFG="$KDIR/arch/arm64/configs/vendor/feature/resukisu.config"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEBUG_FRAG="$REPO/kernel-fragments/debug.config"
AK3="$REPO/scripts/make-anykernel-zip.sh"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$CFG" ]         || die "fragment ReSukiSU tidak ada: $CFG (jalankan setup dulu)"
[ -f "$DEBUG_FRAG" ]  || die "debug.config tidak ada: $DEBUG_FRAG"
[ -x "$AK3" ]         || die "make-anykernel-zip.sh tidak ditemukan/eksekutabel"

# Simpan config bersih; kembalikan apa pun yang terjadi (Ctrl-C, error, selesai).
CFG_ORIG="$(mktemp)"; cp "$CFG" "$CFG_ORIG"
restore() { cp "$CFG_ORIG" "$CFG"; rm -f "$CFG_ORIG"; }
trap restore EXIT

# LineageOS mengembalikan MKA_EXIT lewat stdout; tangkap dengan benar.
run_build() {   # $1 = label
    say "Build kernel: $1"
    cd "$ROMROOT"
    # Matikan -e DAN -u sebelum source: envsetup.sh mereferensikan variabel
    # tak-terdefinisi (mati oleh -u) dan mengembalikan non-nol (mati oleh -e).
    # pipefail juga dimatikan agar aman. Dikembalikan setelah build.
    set +euo pipefail
    source build/envsetup.sh >/dev/null 2>&1
    lunch lineage_Mi8937_4_19-userdebug >/dev/null 2>&1
    mka bootimage -j"$(nproc --all)"; local rc=$?
    set -euo pipefail
    [ "$rc" -eq 0 ] || die "$1: mka bootimage gagal (exit $rc) — cek out/error.log"
    [ -f "$OUTIMG" ] || die "$1: Image.gz-dtb tidak terbentuk"
}

verify_opts() {   # $@ = daftar CONFIG_ yang HARUS =y di .config hasil build
    local miss=0
    for opt in "$@"; do
        if grep -q "^${opt}=y" "$DOTCONFIG"; then printf '    ✓ %s\n' "$opt"
        else printf '    ✗ %s (tidak aktif di .config — dependency Kconfig?)\n' "$opt"; miss=1; fi
    done
    [ "$miss" -eq 0 ] || die "sebagian opsi debug tidak aktif — periksa dependency"
}

# ---------------------------------------------------------------- RILIS
if [ "$MODE" = "release" ] || [ "$MODE" = "both" ]; then
    cp "$CFG_ORIG" "$CFG"          # pastikan bersih dari debug
    run_build "RILIS"
    "$AK3" "$OUTIMG" "$REPO/rom/KERNEL_resukisu-susfs.zip" >/dev/null
    say "Rilis: rom/KERNEL_resukisu-susfs.zip ($(du -h "$REPO/rom/KERNEL_resukisu-susfs.zip" | cut -f1))"
fi

# ---------------------------------------------------------------- DEBUG
if [ "$MODE" = "debug" ] || [ "$MODE" = "both" ]; then
    # Tambahkan fragment debug DI AKHIR resukisu.config -> opsi debug diproses
    # terakhir saat merge, jadi menang.
    cp "$CFG_ORIG" "$CFG"
    { echo; echo "# === debug.config (disisipkan build-kernel-zips.sh) ==="; cat "$DEBUG_FRAG"; } >> "$CFG"
    run_build "DEBUG"
    say "Verifikasi opsi debug benar-benar aktif"
    verify_opts CONFIG_PANIC_ON_OOPS CONFIG_DETECT_HUNG_TASK CONFIG_DEBUG_ATOMIC_SLEEP \
                CONFIG_DEBUG_SPINLOCK CONFIG_DYNAMIC_DEBUG CONFIG_SCHED_STACK_END_CHECK
    "$AK3" "$OUTIMG" "$REPO/rom/KERNEL_resukisu-susfs-DEBUG.zip" >/dev/null
    say "Debug: rom/KERNEL_resukisu-susfs-DEBUG.zip ($(du -h "$REPO/rom/KERNEL_resukisu-susfs-DEBUG.zip" | cut -f1))"
fi

# config bersih dikembalikan oleh trap. Bangun ulang kernel rilis supaya
# out/ tidak tertinggal dalam keadaan debug.
if [ "$MODE" = "both" ] || [ "$MODE" = "debug" ]; then
    cp "$CFG_ORIG" "$CFG"
    run_build "kembalikan out/ ke rilis"
fi

cat <<EOF

Selesai.

  Harian  : rom/KERNEL_resukisu-susfs.zip
  Berburu : rom/KERNEL_resukisu-susfs-DEBUG.zip

Alur berburu bug:
  fastboot flash boot <boot debug>        # atau sideload zip DEBUG
  # pakai perangkat sampai gejala muncul
  su -c 'dmesg' | grep -iE "WARNING|BUG|atomic|lockdep|hung|susfs|call trace"
  # kalau bootloop -> flash balik kernel rilis, lalu:
  su -c 'cat /sys/fs/pstore/console-ramoops-0'
  su -c 'cat /sys/fs/pstore/dmesg-ramoops-0'

  Nyalakan log susfs runtime:
  su -c "echo 'file fs/susfs.c +p' > /sys/kernel/debug/dynamic_debug/control"
EOF
