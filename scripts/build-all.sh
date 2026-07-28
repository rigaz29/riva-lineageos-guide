#!/usr/bin/env bash
#
# All-in-one: rakit + build LineageOS 20 untuk Redmi 5A (Mi8937) dengan
# pilihan Google-services dan root, lalu hasilkan ROM + kernel-only zip.
#
# Menyatukan semua langkah/jebakan sesi ini jadi satu perintah:
#   - patch HAL audio (selalu perlu setelah sync/revert)
#   - microG / GApps built-in  (lewat WITH_GMS)
#   - ReSukiSU / ReSukiSU+susfs (lewat setup-*.sh)
#   - export WITH_GMS + set +euo sebelum source envsetup
#   - auto-sync kernel 4.19 kalau belum ada (nested-repo gotcha)
#   - kemas kernel-only AnyKernel3
#
# Pakai:
#   ./build-all.sh [--gms=none|microg|gapps] [--root=none|resukisu|resukisu-susfs]
#                  [--rom=PATH] [--prepare-only]
#
# Default: --gms=gapps --root=resukisu-susfs   (konfigurasi yang terbukti boot)
#
set -euo pipefail

# ─────────────────────────────────────────────────────────── argumen
GMS="gapps"; ROOT="resukisu-susfs"; ROMROOT="$HOME/android/lineage-20.0"; PREPARE_ONLY=0
for a in "$@"; do case "$a" in
    --gms=*)  GMS="${a#*=}";;
    --root=*) ROOT="${a#*=}";;
    --rom=*)  ROMROOT="${a#*=}";;
    --prepare-only) PREPARE_ONLY=1;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) echo "argumen tak dikenal: $a" >&2; exit 1;;
esac; done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KDIR="$ROMROOT/kernel/xiaomi/mithorium-4.19/kernel"
LUNCH="lineage_Mi8937_4_19-userdebug"
OUT="$ROMROOT/out/target/product/Mi8937_4_19"
AUDIO_PATCH="$REPO/patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
step() { printf '  \033[36m%s\033[0m\n' "$*"; }
die()  { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

case "$GMS"  in none|microg|gapps) ;; *) die "--gms harus none|microg|gapps";; esac
case "$ROOT" in none|resukisu|resukisu-susfs) ;; *) die "--root harus none|resukisu|resukisu-susfs";; esac
[ -d "$ROMROOT/device/xiaomi/Mi8937" ] || die "bukan tree LineageOS: $ROMROOT"
# Kernel disync sebagai repo terpisah (nested-repo gotcha). Ini langkah
# paling mudah lupa, jadi build-all menyync-nya OTOMATIS kalau belum ada.
# ROM sync tetap prasyarat (langkah obvious yang dilakukan sekali).
if [ ! -d "$KDIR" ]; then
    command -v repo >/dev/null || die "kernel belum ada dan 'repo' tidak terpasang"
    say "Kernel belum ada — sync otomatis (mithorium-4.19)"
    TMP_K="$(mktemp -d)"
    ( cd "$TMP_K"
      repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-4.19 --no-clone-bundle
      repo sync -c -j"$(nproc --all)" --no-clone-bundle --no-tags )         || die "sync kernel gagal (butuh internet)"
    # KDIR = .../mithorium-4.19/kernel (SOURCE). Checkout repo berisi
    # kernel/ + dts/ + module/, jadi ia dipindah ke INDUK KDIR
    # (.../mithorium-4.19), bukan ke KDIR sendiri.
    KROOT="$(dirname "$KDIR")"
    mkdir -p "$(dirname "$KROOT")"
    mv -T "$TMP_K" "$KROOT" || die "gagal memindah kernel ke $KROOT"
    [ -f "$KDIR/Makefile" ] || die "kernel source tidak di $KDIR setelah sync (struktur berubah?)"
    step "kernel tersync: $KDIR"
fi

# ─────────────────────────────────────────────────────────── rencana
WITH_GMS_FLAG=0; [ "$GMS" != "none" ] && WITH_GMS_FLAG=1
say "Rencana build"
echo "  ROM tree   : $ROMROOT"
echo "  Google svc : $GMS"
echo "  Root       : $ROOT"
echo "  Target     : $LUNCH  (kernel 4.19)"
echo "  WITH_GMS   : $([ $WITH_GMS_FLAG = 1 ] && echo true || echo '(tidak)')"
[ "$PREPARE_ONLY" = 1 ] && echo "  MODE       : PREPARE-ONLY (tidak build)"

# ───────────────────────────────────────────── 1. patch HAL audio
# Selalu perlu: commit a3ff9d54 upstream memakai parameter tanpa nama (C23),
# clang menolaknya. Idempoten via subjek commit.
say "1  Patch HAL audio"
HAL="$(ls -d "$ROMROOT"/hardware/mithorium/audio/*/hal 2>/dev/null | head -1)"
[ -d "$HAL" ] || die "HAL audio tidak ditemukan"
if git -C "$HAL" log --format=%s -5 | grep -q "^audio-extn: Name the unused pthread parameters$"; then
    step "sudah diterapkan"
else
    git -C "$HAL" -c user.name=build -c user.email=build@local am "$AUDIO_PATCH" >/dev/null \
        && step "diterapkan" || die "patch audio gagal (HAL tidak bersih?)"
fi

# ───────────────────────────────────────────── 2. Google services
say "2  Google services: $GMS"
rm -f "$ROMROOT/.repo/local_manifests/microg.xml"
case "$GMS" in
  none)
    rm -rf "$ROMROOT/vendor/gapps" "$ROMROOT/vendor/partner_gms"
    step "vanilla (tanpa GMS)";;
  gapps)
    "$REPO/scripts/setup-gapps-core.sh" "$ROMROOT" >/dev/null || die "setup GApps gagal"
    step "GApps CORE (MindTheGapps) terpasang + wired"
    ;;
  microg)
    rm -rf "$ROMROOT/vendor/gapps"
    step "menambahkan local manifest microG + sync"
    cp "$REPO/patches/.microg.xml" "$ROMROOT/.repo/local_manifests/microg.xml" 2>/dev/null || \
      cat > "$ROMROOT/.repo/local_manifests/microg.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="vendor/partner_gms" name="lineageos4microg/android_vendor_partner_gms" remote="github" revision="master" />
</manifest>
XML
    ( cd "$ROMROOT" && repo sync -c -j"$(nproc --all)" --no-clone-bundle --no-tags vendor/partner_gms ) \
        >/dev/null 2>&1 || die "sync microG partner_gms gagal (butuh internet)"
    step "microG tersync"
    ;;
esac

# ───────────────────────────────────────────── 3. root (kernel)
say "3  Root: $ROOT"
case "$ROOT" in
  none)
    # kembalikan kernel bersih kalau ada sisa KernelSU
    if [ -d "$KDIR/KernelSU" ]; then git -C "$KDIR" checkout -q -- . ; git -C "$KDIR" clean -qffd; fi
    step "tanpa root (kernel stock)";;
  resukisu)
    "$REPO/scripts/setup-resukisu.sh" "$KDIR" >/dev/null || die "setup ReSukiSU gagal"
    step "ReSukiSU (manual hook) terpasang";;
  resukisu-susfs)
    "$REPO/scripts/setup-resukisu-susfs.sh" "$KDIR" >/dev/null || die "setup ReSukiSU+susfs gagal"
    step "ReSukiSU + susfs v2.2.0 terpasang";;
esac
# wire fragment kernel ke device tree kalau root aktif.
# Append langsung (idempoten) alih-alih git am -- patch rapuh saat konteks
# BoardConfig bergeser.
if [ "$ROOT" != "none" ]; then
    BC="$ROMROOT/device/xiaomi/Mi8937/BoardConfig.mk"
    # kernel boot: fragment ReSukiSU (manual hook + susfs)
    if grep -q "vendor/feature/resukisu.config" "$BC"; then
        step "device tree sudah wired (boot)"
    else
        printf '\n# ReSukiSU (build-all.sh)\nTARGET_KERNEL_CONFIG += \\\n    vendor/feature/resukisu.config\n' >> "$BC"
        grep -q "vendor/feature/resukisu.config" "$BC" \
            && step "device tree wired ke resukisu.config" || die "gagal menulis BoardConfig"
    fi
    # kernel recovery: matikan KSU (default y). Tanpa ini recovery memakai hook
    # default TRACEPOINT (GKI 2.0) dan Kbuild abort di Non-GKI 4.19.
    if grep -q "vendor/feature/norootrecovery.config" "$BC"; then
        step "device tree sudah wired (recovery)"
    else
        printf '\n# recovery tanpa KSU (build-all.sh)\nTARGET_KERNEL_RECOVERY_CONFIG += \\\n    vendor/feature/norootrecovery.config\n' >> "$BC"
        grep -q "vendor/feature/norootrecovery.config" "$BC" \
            && step "device tree wired ke norootrecovery.config" || die "gagal menulis BoardConfig recovery"
    fi
fi

if [ "$PREPARE_ONLY" = 1 ]; then
    say "PREPARE-ONLY selesai — tree siap. Build manual:"
    echo "  cd $ROMROOT && $([ $WITH_GMS_FLAG = 1 ] && echo 'export WITH_GMS=true; ')source build/envsetup.sh && set +e && lunch $LUNCH && mka bacon"
    exit 0
fi

# ───────────────────────────────────────────── 4. build
say "4  Build ROM (mka bacon) — bisa ~1 jam"
( cd "$ROMROOT"
  [ $WITH_GMS_FLAG = 1 ] && export WITH_GMS=true
  set +euo pipefail                      # envsetup mereferensikan var tak-terdefinisi
  source build/envsetup.sh >/dev/null 2>&1
  lunch "$LUNCH" >/dev/null 2>&1
  mka bacon -j"$(nproc --all)" ) || die "mka bacon gagal — cek $OUT/../error.log"
ZIP="$(ls -t "$OUT"/lineage-20.0-*.zip 2>/dev/null | head -1)"
[ -f "$ZIP" ] || die "ZIP ROM tidak terbentuk"

# ───────────────────────────────────────────── 5. kernel-only zip
say "5  Kemas kernel-only (AnyKernel3)"
KZIP="$REPO/rom/KERNEL_${ROOT}.zip"
"$REPO/scripts/make-anykernel-zip.sh" \
    "$OUT/obj/KERNEL_OBJ/arch/arm64/boot/Image.gz-dtb" "$KZIP" >/dev/null \
    && step "kernel zip: $KZIP" || step "(lewati kernel zip)"

# ───────────────────────────────────────────── selesai
say "Selesai"
echo "  ROM         : $ZIP ($(du -h "$ZIP"|cut -f1))"
[ -f "$KZIP" ] && echo "  Kernel zip  : $KZIP ($(du -h "$KZIP"|cut -f1))"
echo "  recovery    : $OUT/recovery.img"
echo
echo "  Flash: fastboot flash recovery recovery.img ; reboot recovery ;"
echo "         Format Data (FBE) ; adb sideload $(basename "$ZIP")"
