#!/usr/bin/env bash
#
# Pasang GApps CORE built-in ke source LineageOS 20 (Mi8937), berbasis
# MindTheGapps tau (Android 13) tapi HANYA paket inti — muat di super
# partition 3,75 GB Redmi 5A.
#
# Terbukti build sukses; GmsCore+Phonesky+GSF+sync masuk ke ROM.
# Wire lewat WITH_GMS=true (mekanisme sama seperti microG).
#
# Pakai:  ./setup-gapps-core.sh [ROMROOT]
#
set -euo pipefail

ROMROOT="${1:-$HOME/android/lineage-20.0}"
GAPPS="$ROMROOT/vendor/gapps"
PGMS="$ROMROOT/vendor/partner_gms"
BRANCH="tau"   # tau = Tiramisu = Android 13 = LineageOS 20

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mGAGAL: %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$ROMROOT/device/xiaomi/Mi8937" ] || die "bukan tree LineageOS: $ROMROOT"

# ─────────────────────────────────────────────────── 1. MindTheGapps tau
say "1/4  Mengambil MindTheGapps ($BRANCH = Android 13)"
if [ -d "$GAPPS/common" ]; then
    echo "    vendor/gapps sudah ada"
else
    git clone -q --depth 1 -b "$BRANCH" https://gitlab.com/MindTheGapps/vendor_gapps.git "$GAPPS"
    # Buang yang tak perlu: arch lain + tooling pembuat-zip. Hemat ~1,3 GB.
    rm -rf "$GAPPS"/.git "$GAPPS"/arm "$GAPPS"/x86 "$GAPPS"/x86_64 \
           "$GAPPS"/build "$GAPPS"/cicd "$GAPPS"/.gitlab-ci.yml
fi
for m in GmsCore Phonesky GoogleServicesFramework; do
    find "$GAPPS" -ipath "*/$m/$m.apk" -print -quit 2>/dev/null | grep -q . \
        || die "APK $m tidak ada — clone MindTheGapps gagal?"
done
echo "    ukuran tree: $(du -sh "$GAPPS" 2>/dev/null | cut -f1)"

# ─────────────────────────────────────────────── 2. makefile core-only
# Soong hanya memasang modul yang ADA di PRODUCT_PACKAGES. Jadi APK non-core
# (Velvet 361 MB, SpeechServices, talkback, ...) tetap di tree tapi TIDAK
# ikut ke ROM. Tidak perlu menyentuh Android.bp sama sekali.
say "2/4  Menulis gapps-core.mk (subset inti ~200 MB)"
cat > "$GAPPS/gapps-core.mk" <<'MK'
# GApps CORE untuk Mi8937 — subset MindTheGapps (tau/Android 13).
PRODUCT_SOONG_NAMESPACES += \
    vendor/gapps/common \
    vendor/gapps/arm64 \
    vendor/gapps/overlay

# XML izin/sysconfig — WAJIB. Tanpa ini GmsCore force-close saat boot.
PRODUCT_COPY_FILES += \
    vendor/gapps/common/proprietary/product/etc/default-permissions/default-permissions-google.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/default-permissions-google.xml \
    vendor/gapps/common/proprietary/product/etc/default-permissions/default-permissions-mtg.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/default-permissions-mtg.xml \
    vendor/gapps/common/proprietary/product/etc/permissions/privapp-permissions-google-product.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/permissions/privapp-permissions-google-product.xml \
    vendor/gapps/common/proprietary/product/etc/security/fsverity/gms_fsverity_cert.der:$(TARGET_COPY_OUT_PRODUCT)/etc/security/fsverity/gms_fsverity_cert.der \
    vendor/gapps/common/proprietary/product/etc/sysconfig/google.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/google.xml \
    vendor/gapps/common/proprietary/product/etc/sysconfig/google_build.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/google_build.xml \
    vendor/gapps/common/proprietary/product/etc/sysconfig/google-hiddenapi-package-allowlist.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/google-hiddenapi-package-allowlist.xml \
    vendor/gapps/common/proprietary/system_ext/etc/permissions/privapp-permissions-google-system-ext.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-google-system-ext.xml

# Paket inti: Play Services + Play Store + framework + sync + overlay.
PRODUCT_PACKAGES += \
    GmsCore \
    Phonesky \
    GoogleServicesFramework \
    GoogleContactsSyncAdapter \
    GoogleCalendarSyncAdapter \
    GmsOverlay \
    GmsSettingsProviderOverlay
MK
echo "    vendor/gapps/gapps-core.mk"

# ─────────────────────────────────────────── 3. wire lewat WITH_GMS
# partner_gms.mk LineageOS inherit vendor/partner_gms/products/gms.mk saat
# WITH_GMS=true. WITH_GMS=true juga menghapus cadangan product 800 MB.
say "3/4  Wire lewat WITH_GMS (mengganti microG kalau ada)"
[ -f "$ROMROOT/.repo/local_manifests/microg.xml" ] && \
    { rm -f "$ROMROOT/.repo/local_manifests/microg.xml"; echo "    microg.xml dihapus"; }
# Ganti vendor/partner_gms (mungkin microG) dengan penunjuk ke GApps.
rm -rf "$PGMS"; mkdir -p "$PGMS/products"
cat > "$PGMS/products/gms.mk" <<'MK'
# GApps CORE lewat mekanisme WITH_GMS LineageOS.
$(call inherit-product, vendor/gapps/gapps-core.mk)
MK
echo "    vendor/partner_gms/products/gms.mk -> inherit gapps-core.mk"

# ─────────────────────────────────────────── verifikasi
say "4/4  Verifikasi"
# -A12: privileged: berada setelah blok dex_preopt di dalam android_app_import.
gms_bp=$(grep -A12 'name: "GmsCore"' "$GAPPS/arm64/Android.bp")
grep -q "presigned: true"  <<<"$gms_bp" && echo "    ✓ GmsCore presigned"  || die "GmsCore tidak presigned"
grep -q "privileged: true" <<<"$gms_bp" && echo "    ✓ GmsCore privileged" || die "GmsCore tidak privileged"
echo "    ✓ gapps-core.mk: $(grep -cE '^\s+(Gms|Phonesky|Google)' "$GAPPS/gapps-core.mk") paket"

cat <<'EOF'

Selesai. Build:

  cd ~/android/lineage-20.0
  export WITH_GMS=true          # WAJIB — ini yang menarik GApps
  source build/envsetup.sh && set +e
  lunch lineage_Mi8937_4_19-userdebug
  mka bacon

Jangan lupa patch HAL audio (0001-audio-extn-*) kalau source baru di-sync.
Verifikasi setelah build:
  ls out/target/product/Mi8937_4_19/product/priv-app | grep -E "GmsCore|Phonesky"
EOF
