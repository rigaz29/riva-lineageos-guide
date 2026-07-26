# LineageOS 18.1 Redmi 5A (`riva`) — Varian Kernel 4.19

> Pelengkap dari [`BUILD-LineageOS-18.1-Redmi5A.md`](./BUILD-LineageOS-18.1-Redmi5A.md).
> Langkah 1–5 (host, `repo init`, local manifest, sync, patch) **identik**. Yang berbeda hanya sync kernel dan target lunch.

---

## 1. Jawaban singkat: bisa

Kernel 4.19 adalah target **resmi** di device tree Mi-Thorium, bukan hack. Buktinya ada di `device/xiaomi/Mi8937/AndroidProducts.mk`:

```makefile
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/lineage_Mi8937.mk \
    $(LOCAL_DIR)/lineage_Mi8937_4_19.mk

COMMON_LUNCH_CHOICES := \
    lineage_Mi8937-user | -userdebug | -eng
    lineage_Mi8937_4_19-user | -userdebug | -eng
```

dan `lineage_Mi8937_4_19.mk` cuma beda satu baris dari versi 4.9:

```makefile
TARGET_KERNEL_VERSION := 4.19        # vs 4.9
PRODUCT_DEVICE := Mi8937_4_19
PRODUCT_NAME   := lineage_Mi8937_4_19
```

Sisanya inherit `device/xiaomi/Mi8937/device.mk` yang sama. Repo `android_device_xiaomi_Mi8937_4_19` sendiri isinya cuma placeholder — README-nya harfiah bilang *"Nothing is really here. The Mi8937_4_19 device tree files are in device/xiaomi/Mi8937."*

`riva` tetap didukung: assert OTA-nya `mi8937,land,santoni,prada,ulysse,ugglite,ugg,rolex,riva,Mi8937,Mi8937_4_19`.

---

## 2. Apa bedanya dengan 4.9?

Semua baris di bawah hasil pembacaan langsung source, bukan asumsi.

| Aspek | Kernel 4.9 | Kernel 4.19 |
|---|---|---|
| Repo kernel | `kernel_msm-4.9` @ `mithorium/a14/master` | `kernel_msm-4.19` @ `mithorium/a13/master` |
| Branch `kernel_manifest` | `mithorium-4.9` | `mithorium-4.19` |
| Direktori source | `kernel/xiaomi/mithorium-4.9` | `kernel/xiaomi/mithorium-4.19` |
| Target lunch | `lineage_Mi8937-userdebug` | `lineage_Mi8937_4_19-userdebug` |
| Direktori output | `out/target/product/Mi8937` | `out/target/product/Mi8937_4_19` |
| Vendor blobs | `vendor/xiaomi/mithorium-common` | `vendor/xiaomi/mithorium-common-4.19` |
| VINTF `target-level` | 3 | **5** |
| **Camera HAL1** | **aktif** | **dimatikan — HAL3 only** |
| Configstore HIDL | ada | `disable_configstore` |
| Storage emulasi | sdcardfs | FUSE + project quota + casefolding |
| Incremental FS | – | `ro.incremental.enable=1` |
| WireGuard in-kernel | – | ada (`vendor/feature/wireguard.config`) |
| Fragment defconfig khas | `vendor/feature/uclamp.config` | `vendor/msm8937-legacy.config` |
| DTS tambahan | – | `dts/vendor-legacy` (`kernel_devicetree_msm-4.19`) |
| fstab | `fstab_4_9.qcom` | `fstab_4_19.qcom` (**mount point identik**) |

### ⚠️ Trade-off utama: kamera

Ini poin terpenting sebelum kamu putuskan. Di `device/xiaomi/Mi8937/BoardConfig.mk`:

```makefile
ifeq ($(TARGET_KERNEL_VERSION),4.19)
TARGET_SUPPORT_HAL1 := false
endif
```

yang lalu dibaca `device/xiaomi/mi8937-camera/camera/QCamera2/Android.mk`:

```makefile
ifeq ($(TARGET_SUPPORT_HAL1),false)
LOCAL_CFLAGS += -DQCAMERA_HAL3_SUPPORT      # ← jalur 4.19
else
LOCAL_CFLAGS += -DQCAMERA_HAL1_SUPPORT      # ← jalur 4.9, + semua source HAL/*.cpp
endif
```

Deskripsi repo `Mi-Thorium/kernel_techpack_camera-legacy` juga menegaskan: *"Camera HAL1 doesn't work on kernel 4.19."*

Artinya di 4.19 seluruh source HAL1 (`QCamera2HWI.cpp`, `QCameraParameters.cpp`, dll.) tidak ikut dikompilasi. Kamera tetap jalan lewat HAL3, tapi aplikasi/mode yang bergantung pada HAL1 legacy berpotensi bermasalah. **Kalau kamera adalah prioritas utama kamu, pakai 4.9.**

### Kenapa tetap pilih 4.19?

- Kernel lebih baru → lebih banyak backport keamanan dan driver.
- Storage modern (FUSE + casefolding, tanpa sdcardfs yang deprecated).
- Treble `target-level 5` — lebih dekat ke standar Android R sesungguhnya.
- WireGuard in-kernel.

### Catatan jujur soal kematangan

Branch kernel yang dipakai adalah `mithorium/a13/master` — dinamai untuk Android 13, dipakai bersama lintas versi. Repo `android_device_xiaomi_Mi8937_4_19` terakhir di-push **Januari 2023** dan branch `a11/master`-nya dipakai ulang oleh manifest 19.1/20/21/22 (karena isinya memang placeholder). Jadi kombinasi **LOS 18.1 + kernel 4.19** jauh lebih jarang diuji dibanding 4.9.

**Saran:** build 4.9 dulu sebagai baseline. Kalau nanti ada bug di 4.19, kamu langsung tahu itu spesifik 4.19 atau bukan.

---

## 3. Langkah Build

### 3a. Langkah 1–5: sama persis dengan tutorial utama

Ikuti tutorial utama tanpa perubahan apa pun:

1. Persyaratan & dependency host
2. `repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --git-lfs --no-clone-bundle`
3. Local manifest Mi-Thorium (`lineage-18.1.xml`)
4. `repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags`
5. **Kedua patch wajib** (`liblp` + `vendor/lineage`) — tetap wajib, tidak ada bedanya

Local manifest yang sama sudah menarik semua yang dibutuhkan 4.19:

```
device/xiaomi/Mi8937_4_19             ← android_device_xiaomi_Mi8937_4_19  (a11/master)
vendor/xiaomi/mithorium-common-4.19   ← proprietary_vendor_xiaomi_mithorium-common-4.19
```

Jadi **tidak perlu edit manifest sama sekali**.

### 3b. Langkah 6′ — Sync kernel 4.19

Ini satu-satunya perbedaan di tahap sync:

> ⚠️ **`repo` tidak mendukung nested checkout.** `repo init` di dalam tree ROM akan menemukan `.repo` milik ROM dan menimpanya. Sync di luar, lalu pindahkan.

```bash
# 1. Sync di LUAR tree ROM
mkdir -p ~/mithorium-4.19
cd ~/mithorium-4.19

repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-4.19 --no-clone-bundle
repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags

# 2. Pindahkan ke dalam tree ROM
mkdir -p ~/android/lineage-18.1/kernel/xiaomi
mv -T ~/mithorium-4.19 ~/android/lineage-18.1/kernel/xiaomi/mithorium-4.19

cd ~/android/lineage-18.1
```

Struktur yang terbentuk (perhatikan `vendor-legacy`, ini eksklusif 4.19):

```
kernel/                                    ← kernel_msm-4.19 @ mithorium/a13/master
  arch/arm64/boot/dts/vendor-legacy        ← symlink ← kernel_devicetree_msm-4.19
  arch/arm64/boot/dts/xiaomi-msm8937       ← symlink ← dts/mi8937/4.19/master
  techpack/xiaomi-msm8937                  ← symlink ← techpack/mi8937/4.19/master
  techpack/audio-legacy                    ← symlink ← audio/4.19/mithorium/master
  techpack/camera-legacy                   ← symlink ← camera/LA.UM.8.6.r1-05300-89xx.0/4.19/mithorium
  drivers/staging/prima                    ← symlink ← wlan/LA.UM.9.6.4/mithorium/master
```

### 3c. Verifikasi sebelum build

Jangan lewati ini — lebih baik gagal 10 detik daripada 3 jam:

```bash
cd ~/android/lineage-18.1
K=kernel/xiaomi/mithorium-4.19/kernel

# defconfig utama + fragment khas 4.19
ls $K/arch/arm64/configs/vendor/msm8937-perf_defconfig
ls $K/arch/arm64/configs/vendor/msm8937-legacy.config
ls $K/arch/arm64/configs/vendor/feature/wireguard.config
ls $K/arch/arm64/configs/vendor/xiaomi/msm8937/mi8937.config

# symlink DTS & techpack harus resolve (bukan broken link)
ls -Ld $K/arch/arm64/boot/dts/vendor-legacy
ls -Ld $K/arch/arm64/boot/dts/xiaomi-msm8937
ls -Ld $K/techpack/xiaomi-msm8937

# device tree & vendor blobs 4.19
ls device/xiaomi/Mi8937/lineage_Mi8937_4_19.mk
ls vendor/xiaomi/mithorium-common-4.19/mithorium-common-4.19-vendor.mk
```

Semua harus ada. Kalau ada symlink yang merah/broken, ulangi `repo sync` di direktori kernel.

### 3d. Langkah 7′ — Build

```bash
cd ~/android/lineage-18.1
source build/envsetup.sh
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

Ingat: **`lunch`, bukan `breakfast`/`brunch`** — roomservice akan menimpa local manifest kamu.

Recovery (fstab-nya beda, jadi build ulang kalau sebelumnya kamu build recovery 4.9):

```bash
mka recoveryimage
```

### 3e. Konfigurasi kernel final yang dipakai

Untuk referensi kalau kamu mau otak-atik, ini fragment yang digabung build system (dari `mithorium-common/BoardConfigCommon.mk` + `Mi8937/BoardConfig.mk`):

**Boot:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/android-12.config
vendor/feature/exfat.config
vendor/feature/kprobes.config
vendor/feature/lmkd.config
vendor/feature/wireguard.config          ← khas 4.19 (4.9 pakai uclamp.config)
vendor/msm8937-legacy.config             ← khas 4.19
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

**Recovery:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/exfat.config
vendor/feature/ntfs.config
vendor/feature/no-camera-stack.config
vendor/feature/no-wlan-driver.config
vendor/msm8937-legacy.config             ← khas 4.19
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

Kompilasi pakai Clang penuh: `TARGET_KERNEL_CLANG_COMPILE := true`, `TARGET_KERNEL_ADDITIONAL_FLAGS := LLVM=1`.

---

## 4. Hasil Build

```
out/target/product/Mi8937_4_19/lineage-18.1-<tanggal>-UNOFFICIAL-Mi8937_4_19.zip
out/target/product/Mi8937_4_19/recovery.img
out/target/product/Mi8937_4_19/boot.img
```

Perhatikan direktori dan nama ZIP-nya **berbeda** dari build 4.9 — jangan sampai tertukar saat flashing.

---

## 5. Flashing

**Prosedurnya identik dengan tutorial utama Bagian 9.** Sudah saya bandingkan `fstab_4_9.qcom` vs `fstab_4_19.qcom` — daftar mount point-nya sama persis, dan skema partisi (`BOARD_SUPER_PARTITION_BLOCK_DEVICES := cust system`, super 3,75 GB) tidak berubah karena didefinisikan di luar blok `ifeq TARGET_KERNEL_VERSION`.

Jadi tetap: bootloader unlocked → flash `recovery.img` (**yang dari `Mi8937_4_19`**) → **Format Data** → sideload ZIP → opsional GApps → reboot.

### Pindah dari build 4.9 ke 4.19 (atau sebaliknya)

Vendor blobs dan VINTF level berbeda, jadi **jangan dirty-flash**. Flash recovery yang sesuai, Format Data, baru install ZIP-nya.

---

## 6. Build 4.9 dan 4.19 berdampingan

Bisa, dan tanpa konflik — direktori kernel dan direktori `out` keduanya terpisah:

```bash
cd ~/android/lineage-18.1

# sync kedua kernel sekali saja
# Sync kedua kernel DI LUAR tree ROM, lalu pindahkan
for v in 4.9 4.19; do
    mkdir -p ~/mithorium-$v && (cd ~/mithorium-$v && \
        repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-$v --no-clone-bundle && \
        repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags)
done

mkdir -p ~/android/lineage-18.1/kernel/xiaomi
for v in 4.9 4.19; do mv -T ~/mithorium-$v ~/android/lineage-18.1/kernel/xiaomi/mithorium-$v; done

cd ~/android/lineage-18.1
source build/envsetup.sh

lunch lineage_Mi8937-userdebug      && mka bacon    # → out/target/product/Mi8937
lunch lineage_Mi8937_4_19-userdebug && mka bacon    # → out/target/product/Mi8937_4_19
```

Siapkan disk ekstra: dua direktori `out` masing-masing sekitar 40–60 GB, plus ~5 GB untuk kernel tree kedua. Total kebutuhan naik jadi sekitar **300 GB**. ccache aman dipakai bersama.

---

## 7. Troubleshooting Khusus 4.19

| Gejala | Penyebab & Solusi |
|---|---|
| `No such file: kernel/xiaomi/mithorium-4.19/kernel` | Sync kernel masih di direktori `mithorium-4.9`. Nama direktori **harus** persis `mithorium-4.19` karena `TARGET_KERNEL_SOURCE` menyusunnya dari `mithorium-$(TARGET_KERNEL_VERSION)`. |
| `Can't find vendor/msm8937-legacy.config` | Kamu init `kernel_manifest` dengan branch `mithorium-4.9`. Fragment ini hanya ada di repo `kernel_msm-4.19`. Hapus direktori, init ulang dengan `-b mithorium-4.19`. |
| DTS error `vendor-legacy not found` | Symlink belum terbentuk — `repo sync` di direktori kernel belum selesai. Jalankan ulang. |
| `mithorium-common-4.19-vendor.mk not found` | `repo sync` tree utama belum lengkap; project `vendor/xiaomi/mithorium-common-4.19` belum turun. |
| Kamera FC / mode tertentu hilang | Ekspektasi — HAL1 memang dimatikan di 4.19. Bukan bug build kamu. Kalau butuh HAL1, pindah ke 4.9. |
| Boot loop setelah dirty-flash dari 4.9 | Vendor blobs & VINTF level berbeda. Format Data, install bersih. |
| Bangun ulang setelah ganti target lunch terasa full rebuild | Normal — `PRODUCT_DEVICE` berbeda berarti direktori `out` berbeda. ccache membantu. |

---

## 8. Update Berkala (4.19)

```bash
cd ~/android/lineage-18.1

git -C system/core    format-patch -1 -o /tmp/keep-core
git -C vendor/lineage format-patch -1 -o /tmp/keep-lineage

curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-18.1.xml

repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
(cd kernel/xiaomi/mithorium-4.19 && repo sync -c -j$(nproc --all) --no-tags)

git -C system/core    am /tmp/keep-core/*.patch    || true
git -C vendor/lineage am /tmp/keep-lineage/*.patch || true

source build/envsetup.sh && lunch lineage_Mi8937_4_19-userdebug && mka bacon
```

---

## Referensi

- Kernel manifest 4.19 — https://github.com/Mi-Thorium/kernel_manifest/tree/mithorium-4.19
- Kernel source — https://github.com/Mi-Thorium/kernel_msm-4.19/tree/mithorium/a13/master
- DTS msm8937 (4.19) — https://github.com/Mi-Thorium/kernel_devicetree_xiaomi-msm8937/tree/dts/mi8937/4.19/master
- DTS vendor-legacy — https://github.com/Mi-Thorium/kernel_devicetree_msm-4.19/tree/dts/master
- Vendor blobs 4.19 — https://github.com/Mi-Thorium/proprietary_vendor_xiaomi_mithorium-common-4.19/tree/a11/master
- Device tree Mi8937 — https://github.com/Mi-Thorium/android_device_xiaomi_Mi8937/tree/a11/master
