#!/usr/bin/env bash
#
# Bikin flashable kernel-only ZIP (AnyKernel3) untuk Redmi 5A / Mi8937.
# ~21 MB, dipasang tanpa wipe data — untuk iterasi kernel tanpa build ROM penuh.
#
# Pakai:  ./make-anykernel-zip.sh [Image.gz-dtb] [output.zip]
#
set -euo pipefail

KIMG="${1:-$HOME/android/lineage-20.0/out/target/product/Mi8937_4_19/obj/KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb}"
OUT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rom/KERNEL-ONLY_resukisu_4.19.zip}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -f "$KIMG" ] || die "kernel tidak ditemukan: $KIMG"

say "1/4  Mengambil AnyKernel3"
git clone -q --depth 1 https://github.com/osm0sis/AnyKernel3.git "$WORK/ak3"
rm -rf "$WORK/ak3"/{.git,.github,modules,patch,ramdisk,README.md}

say "2/4  Mengonfigurasi untuk Mi8937"
python3 - "$WORK/ak3/anykernel.sh" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()

old_props = """kernel.string=ExampleKernel by osm0sis @ xda-developers
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=maguro
device.name2=toro
device.name3=toroplus
device.name4=tuna
device.name5="""
new_props = """kernel.string=LineageOS 20 kernel 4.19 + ReSukiSU (Mi8937)
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=riva
device.name2=rolex
device.name3=santoni
device.name4=land
device.name5=prada
device.name6=ugg
device.name7=ugglite
device.name8=Mi8937
device.name9=Mi8937_4_19"""
assert t.count(old_props) == 1, "blok properties tidak cocok — AnyKernel3 berubah?"
t = t.replace(old_props, new_props)

old_blk = "BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;"
new_blk = """# msm8937: path by-name berbeda antar recovery, jadi diprobe berurutan.
# Path perangkat kerasnya platform/soc/7824900.sdhci/by-name/; symlink
# bootdevice hanya dibuat init.xiaomi.rc untuk modemst/fsc/fsg, BUKAN boot.
for _b in /dev/block/bootdevice/by-name/boot \\
          /dev/block/platform/soc/7824900.sdhci/by-name/boot \\
          /dev/block/by-name/boot; do
  [ -e "$_b" ] && BLOCK=$_b && break;
done;
[ "$BLOCK" ] || BLOCK=/dev/block/platform/soc/7824900.sdhci/by-name/boot;"""
assert t.count(old_blk) == 1, "baris BLOCK tidak cocok — AnyKernel3 berubah?"
p.write_text(t.replace(old_blk, new_blk))
print("    anykernel.sh dikonfigurasi")
PY

say "3/4  Menyalin kernel"
cp "$KIMG" "$WORK/ak3/Image.gz-dtb"
echo "    $(basename "$KIMG") — $(du -h "$KIMG" | cut -f1)"

say "4/4  Mengemas"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
( cd "$WORK/ak3" && zip -q -r9 "$OUT" . )
# nama berkas relatif, supaya `sha256sum -c` jalan di sisi pengunduh
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )

say "Verifikasi"
sh -n "$WORK/ak3/anykernel.sh" || die "sintaks anykernel.sh rusak"
miss=0
# Daftar isi diambil sekali ke berkas: "unzip -l | grep -q" akan gagal di bawah
# `set -o pipefail` karena grep keluar lebih dulu dan unzip kena SIGPIPE —
# efeknya hanya entri paling awal di listing yang salah dilaporkan gagal.
unzip -l "$OUT" > "$WORK/listing.txt"
for f in META-INF/com/google/android/update-binary \
         META-INF/com/google/android/updater-script \
         anykernel.sh tools/ak3-core.sh Image.gz-dtb; do
    if grep -qF "$f" "$WORK/listing.txt"; then printf '    ✓ %s\n' "$f"
    else printf '    ✗ %s\n' "$f"; miss=1; fi
done
[ "$miss" -eq 0 ] || die "komponen AnyKernel3 tidak lengkap"

echo
echo "Selesai: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "Pasang lewat recovery — tanpa Format Data:"
echo "    adb sideload $(basename "$OUT")"
