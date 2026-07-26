# Tuning RAM & Storage — Redmi 5A (`riva`)

> Apakah LineageOS di Redmi 5A perlu pakai konfigurasi **Android Go**? Jawaban singkat: **tidak perlu** — dan config Go milik LineageOS isinya jauh lebih sedikit dari yang orang kira.
>
> Dokumen ini berlaku untuk semua panduan build di repo ini. Referensi baris merujuk ke branch `a13/master` (LineageOS 20); untuk `a11/master` (18.1) isinya setara kecuali disebutkan.

---

## 1. Ringkasan

| | Kesimpulan |
|---|---|
| Perlu config Go? | **Tidak.** Manfaatnya kecil, risikonya nyata. |
| Kenapa? | `common_full_go_phone.mk` LineageOS cuma mengganti launcher — bukan optimisasi memori. |
| Device tree sudah ngapain? | Sudah memakai profil heap AOSP untuk perangkat **2 GB**. |
| Kalau tetap mau irit RAM? | Pakai [tuning selektif](#6-cara-1-tuning-selektif-rekomendasi) — tanpa `ro.config.low_ram`. |
| Masalah sebenarnya di Redmi 5A? | **Storage**, bukan RAM. Lihat [Bagian 8](#8-tuning-storage). |

---

## 2. Yang Sudah Disetel Device Tree (baseline)

Sebelum menambah apa pun, ketahui dulu kondisi awalnya.

### Heap sudah disetel untuk 2 GB

`device/xiaomi/Mi8937/device.mk:9`:

```makefile
$(call inherit-product, frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk)
```

Isinya (`frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk`):

```makefile
dalvik.vm.heapstartsize?=8m
dalvik.vm.heapgrowthlimit?=192m
dalvik.vm.heapsize?=512m
dalvik.vm.heaptargetutilization?=0.75
dalvik.vm.heapminfree?=512k
dalvik.vm.heapmaxfree?=8m
```

`2048` = profil resmi AOSP untuk perangkat **2 GB RAM**. Jadi Mi-Thorium sudah menargetkan 2 GB sebagai baseline — hanya lebih longgar dibanding Go (192/512 vs 128/256).

### Swap sudah diatur

`device/xiaomi/mithorium-common/rootdir/etc/init.target.rc:40`
```
write /proc/sys/vm/swappiness 60
```
`device/xiaomi/mithorium-common/rootdir/etc/init.qcom.rc:62`
```
write /sys/fs/cgroup/memory/bg/memory.swappiness 140
```

Proses background jauh lebih rela di-swap (140) daripada foreground (60). Ini sudah setelan yang masuk akal untuk perangkat kecil.

### Satu variabel yang menyesatkan

`device/xiaomi/mithorium-common/mithorium.mk:620`:

```makefile
EXTRA_DEVICE_BRACKET := low-end
```

Kelihatan seperti optimisasi, tapi **variabel ini tidak dibaca siapa pun**. Sudah saya grep di seluruh `vendor/lineage` LineageOS 20 dan di semua device tree Mi-Thorium — nol hasil. Ini peninggalan mati, jangan dijadikan alasan menganggap tree-nya sudah "mode low-end".

---

## 3. Mitos: config Go LineageOS

LineageOS 20 memang menyediakan `vendor/lineage/config/common_full_go_phone.mk` dan `common_mini_go_phone.mk`. Tapi isi lengkap file pertama hanya ini:

```makefile
# Set Lineage specific identifier for Android Go enabled products
PRODUCT_TYPE := go

# Inherit full common Lineage stuff
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)
```

`PRODUCT_TYPE` dipakai di **satu tempat saja**, `vendor/lineage/config/common_mobile.mk:21`:

```makefile
ifeq ($(PRODUCT_TYPE), go)
PRODUCT_PACKAGES += TrebuchetQuickStepGo
...
else
PRODUCT_PACKAGES += TrebuchetQuickStep
...
endif
```

**Itu saja.** File ini tidak meng-inherit `go_defaults.mk` AOSP sama sekali.

> ⚠️ Kalau kamu sekadar mengganti `common_full_phone.mk` → `common_full_go_phone.mk` di `lineage_Mi8937.mk`, satu-satunya perubahan adalah launcher. Nol manfaat memori.

---

## 4. Optimisasi Go yang Sebenarnya

Yang benar-benar membuat build jadi "Go" ada di AOSP `build/make/target/product/go_defaults.mk` → `go_defaults_common.mk`, dan harus di-inherit terpisah.

| Setting | Efek |
|---|---|
| `ro.config.low_ram=true` | Framework mengurangi proses cached, thumbnail recents, dan animasi |
| `PRODUCT_SYSTEM_SERVER_COMPILER_FILTER := speed-profile` | system_server hemat RAM & storage |
| `PRODUCT_ALWAYS_PREOPT_EXTRACTED_APK := true` | Cegah ekstraksi dex saat runtime |
| `PRODUCT_MINIMIZE_JAVA_DEBUG_INFO := true` | Buang local variable table → image lebih kecil |
| `PRODUCT_ART_TARGET_INCLUDE_DEBUG_BUILD := false` | Tidak build `libartd` |
| `TARGET_VNDK_USE_CORE_VARIANT := true` | Dedupe library VNDK → **image lebih kecil** |
| `go_handheld_core_hardware.xml` | Feature set perangkat dipangkas |

Plus properti dari `build/make/target/board/go_defaults_common.prop`:

```
ro.lmk.critical_upgrade=true
ro.lmk.upgrade_pressure=40
ro.lmk.downgrade_pressure=60
ro.lmk.kill_heaviest_task=false
pm.dexopt.downgrade_after_inactive_days=10
pm.dexopt.shared=quicken
dalvik.vm.heapgrowthlimit=128m
dalvik.vm.heapsize=256m
```

Catatan penting soal `pm.dexopt.shared=quicken`: komentar AOSP sendiri menyebut ini **trade-off** — hemat RAM, tapi APK bersama (GMS, Chrome) jadi di-JIT ulang di tiap proses, artinya lebih boros CPU dan baterai.

---

## 5. Kapan Go Layak, Kapan Tidak

| Kondisi kamu | Rekomendasi |
|---|---|
| Redmi 5A **2GB/16GB** + LineageOS 20 + pasang GApps | Go bisa dipertimbangkan — alasan terkuatnya **storage**, bukan RAM |
| Redmi 5A **3GB/32GB** | **Jangan.** Rugi tanpa perlu; heap 256m membatasi percuma |
| Sering pakai browser / app berat | **Jangan.** `heapsize=256m` bikin app besar sering GC atau OOM |
| Ingin jalur paling teruji | **Jangan.** Mi-Thorium tidak menguji konfigurasi Go |

Satu hal lagi: ROM ini **unified untuk 7 device** dengan RAM berbeda-beda (Redmi 3S sampai Redmi Note 5A). Build Go otomatis berlaku ke semuanya, jadi kamu perlu ZIP terpisah.

---

## 6. Cara 1: Tuning Selektif (rekomendasi)

Ambil manfaat terbesar tanpa `ro.config.low_ram` yang efek sampingnya paling luas ke framework.

Tambahkan ke `device/xiaomi/Mi8937/lineage_Mi8937.mk`, **sebelum** blok `# Device identifier`:

```makefile
# Tuning RAM — jalan tengah antara profil 2048 dan Android Go
PRODUCT_VENDOR_PROPERTIES += \
    dalvik.vm.heapgrowthlimit=160m \
    dalvik.vm.heapsize=384m \
    ro.lmk.critical_upgrade=true \
    ro.lmk.upgrade_pressure=40 \
    ro.lmk.downgrade_pressure=60 \
    ro.lmk.kill_heaviest_task=false
```

Kenapa ini lebih baik untuk Redmi 5A:

- Heap 160/384 menahan app rakus tanpa mencekik browser seperti 128/256.
- Properti `ro.lmk.*` memberi manfaat lmkd Go **tanpa** menyentuh `ro.config.low_ram`.
- Tidak ada `pm.dexopt.shared=quicken`, jadi GMS/Chrome tidak jadi lebih lambat.
- Gampang di-revert kalau tidak terasa bedanya.

Karena ini mengedit repo yang dilacak git, `repo sync` berikutnya akan mengembalikannya. Simpan sebagai patch:

```bash
cd device/xiaomi/Mi8937
git add -A && git commit -m "Mi8937: RAM tuning for 2GB variants"
git format-patch -1 -o ~/patches-mi8937
```

Terapkan ulang setelah sync dengan `git am ~/patches-mi8937/*.patch`.

---

## 7. Cara 2: Build Android Go Penuh

Kalau kamu tetap mau Go sepenuhnya, **bikin product varian terpisah** — jangan modifikasi `lineage_Mi8937.mk` yang ada, supaya kamu masih bisa build versi normal untuk pembanding.

### 7a. Buat `device/xiaomi/Mi8937/lineage_Mi8937_go.mk`

```makefile
#
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_n_mr1.mk)

# ← ini yang sebenarnya bikin ringan, bukan common_full_go_phone.mk
$(call inherit-product, $(SRC_TARGET_DIR)/product/go_defaults.mk)

# Identifier Go LineageOS + launcher TrebuchetQuickStepGo
$(call inherit-product, vendor/lineage/config/common_full_go_phone.mk)

# Kernel
TARGET_KERNEL_VERSION := 4.9

$(call inherit-product, device/xiaomi/Mi8937/device.mk)

DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay-lineage

PRODUCT_PACKAGES += \
    xiaomi_prada_overlay_lineage \
    xiaomi_riva_overlay_lineage \
    xiaomi_rolex_overlay_lineage \
    xiaomi_ulysse_overlay_lineage \
    xiaomi_wt8937_overlay_lineage

# WAJIB — lihat penjelasan 7c
PRODUCT_VENDOR_PROPERTIES += \
    dalvik.vm.heapgrowthlimit=128m \
    dalvik.vm.heapsize=256m

PRODUCT_DEVICE := Mi8937
PRODUCT_NAME := lineage_Mi8937_go
BOARD_VENDOR := Xiaomi
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := MSM8937
PRODUCT_MANUFACTURER := Xiaomi
TARGET_VENDOR := Xiaomi

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="land-user 6.0.1 MMB29M V10.2.2.0.MALMIXM release-keys"

BUILD_FINGERPRINT := "Xiaomi/land/land:6.0.1/MMB29M/V10.2.2.0.MALMIXM:user/release-keys"
```

### 7b. Daftarkan di `AndroidProducts.mk`

```makefile
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_Mi8937.mk \
    $(LOCAL_DIR)/lineage_Mi8937_go.mk \
    $(LOCAL_DIR)/lineage_Mi8937_4_19.mk

COMMON_LUNCH_CHOICES := \
    lineage_Mi8937-userdebug \
    lineage_Mi8937_go-userdebug \
    lineage_Mi8937_4_19-userdebug
```

Lalu:

```bash
source build/envsetup.sh
lunch lineage_Mi8937_go-userdebug
mka bacon
```

### 7c. ⚠️ Jebakan: heap prop bisa bentrok

Ini bagian yang paling gampang bikin build Go-mu diam-diam tidak berefek.

- `phone-xhdpi-2048-dalvik-heap.mk` (dari `device.mk`) menulis `heapsize=512m` ke **vendor** `build.prop`, lewat `PRODUCT_VENDOR_PROPERTIES` dengan operator lunak `?=`.
- `go_defaults` menulis `heapsize=256m` ke **system** `build.prop`, lewat `TARGET_SYSTEM_PROP` yang menempelkan file `.prop` mentah.

Dua mekanisme berbeda, dua partisi berbeda — jadi keduanya bisa muncul bersamaan dan hasil akhirnya bergantung urutan pembacaan properti. Blok `PRODUCT_VENDOR_PROPERTIES` di 7a adalah assignment keras, yang mengalahkan `?=` di sisi vendor sehingga nilainya konsisten.

**Selalu verifikasi setelah flash** dengan perintah di [Bagian 9](#9-verifikasi-setelah-flash). Kalau `dalvik.vm.heapsize` masih `512m`, berarti override-mu tidak jalan.

---

## 8. Tuning Storage

Untuk Redmi 5A, ini sebenarnya masalah yang lebih mendesak daripada RAM.

### Batasannya

`device/xiaomi/Mi8937/BoardConfig.mk:80-88`:

```makefile
BOARD_SUPER_PARTITION_BLOCK_DEVICES := cust system
BOARD_SUPER_PARTITION_CUST_DEVICE_SIZE   := 536870912    # 512 MB
BOARD_SUPER_PARTITION_SYSTEM_DEVICE_SIZE := 3221225472   # 3 GB
BOARD_SUPER_PARTITION_SIZE := 3.75 GB
BOARD_MI8937_DYNPART_PARTITION_LIST := product system system_ext odm vendor
```

**Lima partisi harus muat dalam 3,75 GB.** Android 13 + GApps membuat ini sesak.

### Sudah ada cadangan 800 MB untuk GApps

`BoardConfig.mk:101-103`:

```makefile
ifneq ($(WITH_GMS),true)
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 838860800 # 800 MB
endif
```

Kalau kamu build **tanpa** GMS (default), tree sudah menyisakan 800 MB kosong di partisi `product` supaya GApps bisa di-sideload belakangan. Jadi jangan panik melihat `product` terlihat "boros" — itu memang disengaja.

Kalau kamu **tidak akan** pakai GApps sama sekali, kamu bisa mengecilkan atau menghapus baris ini untuk memberi ruang ke partisi lain.

### Opsi EROFS (eksperimental, penghematan terbesar)

Ini temuan menarik. Kernel `a13` sudah mengompilasi dukungan EROFS di **boot maupun recovery** (`mithorium-common/BoardConfigCommon.mk:57,65` → `vendor/feature/erofs.config`), dan tree sudah menyiapkan flag kompatibilitasnya (`BoardConfigCommon.mk:154-157`):

```makefile
ifeq ($(TARGET_USES_MITHORIUM_KERNEL),true)
ifeq ($(TARGET_KERNEL_VERSION),4.9)
BOARD_EROFS_USE_LEGACY_COMPRESSION := true
endif
endif
```

Tapi image-nya **tetap dibuat ext4** — `Mi8937/BoardConfig.mk:15` mengeset `BOARD_*IMAGE_FILE_SYSTEM_TYPE := ext4` untuk semua partisi.

EROFS adalah filesystem read-only terkompresi, jadi memindahkan partisi read-only ke EROFS bisa memangkas ukuran image cukup banyak. Untuk mencoba, ubah baris 15-17 `BoardConfig.mk` agar partisi read-only memakai `erofs`:

```makefile
$(foreach p, $(call to-upper, $(ALL_PARTITIONS)), \
    $(eval BOARD_$(p)IMAGE_FILE_SYSTEM_TYPE := erofs) \
    $(eval TARGET_COPY_OUT_$(p) := $(call to-lower, $(p))))
```

⚠️ **Status eksperimental.** Mi-Thorium mengirim ext4 sebagai default, jadi jalur ini tidak mereka uji. Dukungan kernel jelas ada, tapi kamu perlu recovery yang bisa memount EROFS — gunakan `recovery.img` hasil build sendiri, bukan TWRP. Uji dulu sebelum dipakai harian.

### Cara paling aman: buang paket yang tidak dipakai

Tree menyediakan flag untuk memangkas komponen:

```makefile
TARGET_HAS_NO_CONSUMERIR := true   # buang HAL infrared (mithorium.mk:72,211)
TARGET_HAS_NO_RADIO := true        # buang seluruh stack telepon — HANYA untuk pemakaian wifi-only
```

`TARGET_HAS_NO_RADIO` dipakai di 8 tempat berbeda di `mithorium.mk` dan membuang banyak paket RIL. Jangan dipakai kalau HP-nya masih untuk menelepon.

---

## 9. Verifikasi Setelah Flash

Jangan berasumsi tuning-mu jalan — cek langsung:

```bash
# Heap & lmkd — pastikan nilainya sesuai yang kamu set
adb shell getprop | grep -E "dalvik.vm.heap(size|growthlimit)|ro.config.low_ram|ro.lmk"

# RAM terpakai
adb shell cat /proc/meminfo | head -3
adb shell dumpsys meminfo | head -20

# Ruang tiap partisi — cek sisa di /product dan /system
adb shell df -h /data /system /product /vendor /system_ext /odm

# Filesystem tiap partisi (cek kalau kamu coba EROFS)
adb shell mount | grep -E "system|product|vendor"
```

Kalau `dalvik.vm.heapsize` tidak sesuai harapan, baca ulang [7c](#7c-️-jebakan-heap-prop-bisa-bentrok).

---

## 10. Rekomendasi Akhir

Untuk Redmi 5A, urutan prioritas saya:

1. **Jangan pakai config Go.** Manfaat resminya kecil, dan `common_full_go_phone.mk` LineageOS bukan yang kamu kira.
2. **Pakai [tuning selektif](#6-cara-1-tuning-selektif-rekomendasi)** kalau HP terasa sesak — heap 160/384 plus properti `ro.lmk.*`.
3. **Fokus ke storage, bukan RAM.** Lewati GApps atau pakai varian paling minimal. Ini memberi dampak paling terasa di perangkat 16 GB.
4. **Baru coba Go penuh atau EROFS** kalau dua langkah di atas belum cukup — dan simpan build normal sebagai pembanding.

---

## Referensi Source

Semua klaim di dokumen ini bisa diverifikasi sendiri:

- `vendor/lineage/config/common_full_go_phone.mk` — https://github.com/LineageOS/android_vendor_lineage/blob/lineage-20.0/config/common_full_go_phone.mk
- `vendor/lineage/config/common_mobile.mk` — https://github.com/LineageOS/android_vendor_lineage/blob/lineage-20.0/config/common_mobile.mk
- `build/make/target/product/go_defaults_common.mk` — https://github.com/LineageOS/android_build/blob/lineage-20.0/target/product/go_defaults_common.mk
- `build/make/target/board/go_defaults_common.prop` — https://github.com/LineageOS/android_build/blob/lineage-20.0/target/board/go_defaults_common.prop
- `frameworks/native/build/phone-xhdpi-2048-dalvik-heap.mk` — https://github.com/LineageOS/android_frameworks_native/blob/lineage-20.0/build/phone-xhdpi-2048-dalvik-heap.mk
- Device tree Mi8937 — https://github.com/Mi-Thorium/android_device_xiaomi_Mi8937/tree/a13/master
- Common DT — https://github.com/Mi-Thorium/android_device_xiaomi_mithorium-common/tree/a13/master
