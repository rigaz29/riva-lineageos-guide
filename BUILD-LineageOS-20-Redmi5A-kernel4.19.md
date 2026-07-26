# LineageOS 20 (Android 13) Redmi 5A (`riva`) — Varian Kernel 4.19

> Pelengkap dari [`BUILD-LineageOS-20-Redmi5A.md`](./BUILD-LineageOS-20-Redmi5A.md).
> Langkah 1–6 (host, `repo init`, local manifest, sync) **identik**. Yang berbeda hanya sync kernel dan target lunch.

---

## 1. Bisa — dan di LineageOS 20 alasannya jauh lebih kuat daripada di 18.1

Di tutorial 18.1 saya sarankan tetap pakai 4.9. **Untuk LineageOS 20, rekomendasi itu berubah.** Ada dua alasan konkret.

### Alasan 1: enkripsi `/data`

Ini yang paling penting dan paling mudah terlewat. Bandingkan `fstab` di branch `a13`:

**Kernel 4.9** — `Mi8937/rootdir/etc/fstab_4_9.qcom:23-26`
```
/dev/block/by-name/userdata  /data  f2fs  ...  latemount,wait,check,quota,formattable
# FBE /dev/block/by-name/userdata  /data  f2fs  ...  fileencryption=aes-256-xts,quota,formattable
```
Baris FBE-nya **dikomentari**. Artinya di LineageOS 20 dengan kernel 4.9, partisi `/data` kamu **tidak terenkripsi sama sekali**.

**Kernel 4.19** — `Mi8937/rootdir/etc/fstab_4_19.qcom:23-24`
```
/dev/block/by-name/userdata  /data  f2fs
    nosuid,nodev,noatime,discard,resgid=1065,inlinecrypt,reserve_root=32768,fsync_mode=nobarrier
    latemount,wait,check,quota,formattable,
    fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized,
    metadata_encryption=aes-256-xts,
    keydirectory=/metadata/vold/metadata_encryption,
    reservedsize=128M,
    checkpoint=fs
```

Yang kamu dapat di 4.19:
- **FBE v2** (File-Based Encryption) dengan **inline crypto** — enkripsi dipercepat hardware ICE, bukan CPU
- **Metadata encryption** — pakai partisi `/metadata` (dimount dari partisi `oem`, `fstab_4_19.qcom:22`; `BOARD_USES_METADATA_PARTITION := true` di `BoardConfig.mk:71`)
- **`checkpoint=fs`** — userdata checkpointing, update bisa di-rollback kalau gagal
- `reservedsize=128M` + `resgid` — cadangan ruang supaya `/data` tidak mentok penuh

Sebagai pembanding, di branch `a11` (LOS 18.1) kernel 4.9 setidaknya masih punya `encryptable=footer` (FDE lawas). Di `a13`, jalur 4.9 kehilangan itu dan tidak diganti apa pun.

Jadi kalau HP-mu dipakai sehari-hari dan kamu peduli data aman saat hilang, **4.19 adalah satu-satunya pilihan yang masuk akal di LineageOS 20**.

### Alasan 2: versi kernel yang segenerasi dengan device tree

| Target | `kernel_manifest` | Kernel yang ditarik |
|---|---|---|
| 4.9 | `mithorium-4.9` | `kernel_msm-4.9` @ **`mithorium/a14/master`** |
| 4.19 | `mithorium-4.19` | `kernel_msm-4.19` @ **`mithorium/a13/master`** |

Device tree yang kita pakai adalah `a13/master`. Jalur 4.19 menunjuk ke branch kernel `a13` yang segenerasi; jalur 4.9 menunjuk ke `a14`. Bukan berarti 4.9 rusak — Mi-Thorium memang berbagi satu kernel lintas versi Android — tapi 4.19 kebetulan cocok persis.

### Yang tetap jadi trade-off: kamera

Sama seperti di 18.1, dan masih berlaku di `a13`. `Mi8937/BoardConfig.mk:31-32`:

```makefile
ifeq ($(TARGET_KERNEL_VERSION),4.19)
TARGET_SUPPORT_HAL1 := false
endif
```

dibaca oleh `device/xiaomi/mi8937-camera/camera/QCamera2/Android.mk:41`:

```makefile
ifeq ($(TARGET_SUPPORT_HAL1),false)
LOCAL_CFLAGS += -DQCAMERA_HAL3_SUPPORT      # ← jalur 4.19
else
LOCAL_CFLAGS += -DQCAMERA_HAL1_SUPPORT      # ← jalur 4.9, + semua source HAL/*.cpp
endif
```

Deskripsi repo `Mi-Thorium/kernel_techpack_camera-legacy` menegaskan: *"Camera HAL1 doesn't work on kernel 4.19."* Kamera tetap jalan lewat HAL3, tapi aplikasi/mode yang bergantung HAL1 legacy berpotensi bermasalah.

### Putusannya

| Prioritas kamu | Pilih |
|---|---|
| Enkripsi `/data`, kernel lebih baru, storage modern | **4.19** |
| Kamera semaksimal mungkin, jalur paling banyak diuji | 4.9 |

Kalau ragu: build 4.9 dulu, uji kamera, lalu build 4.19 dan bandingkan. Keduanya bisa hidup berdampingan ([Bagian 6](#6-build-49-dan-419-berdampingan)).

---

## 2. Semua Perbedaan 4.9 vs 4.19 di Branch `a13`

Semua baris hasil pembacaan langsung source.

| Aspek | Kernel 4.9 | Kernel 4.19 |
|---|---|---|
| Repo kernel | `kernel_msm-4.9` @ `mithorium/a14/master` | `kernel_msm-4.19` @ `mithorium/a13/master` |
| Branch `kernel_manifest` | `mithorium-4.9` | `mithorium-4.19` |
| Direktori source | `kernel/xiaomi/mithorium-4.9` | `kernel/xiaomi/mithorium-4.19` |
| Target lunch | `lineage_Mi8937-userdebug` | `lineage_Mi8937_4_19-userdebug` |
| Direktori output | `out/target/product/Mi8937` | `out/target/product/Mi8937_4_19` |
| Vendor blobs | `vendor/xiaomi/mithorium-common` | `vendor/xiaomi/mithorium-common-4.19` |
| **Enkripsi `/data`** | **tidak ada** | **FBE v2 + inline crypto + metadata encryption** |
| **fs checkpointing** | – | `checkpoint=fs` |
| VINTF | `target-level 3` | `target-level 5` + `<kernel target-level="6"/>` |
| **Camera HAL1** | **aktif** | **dimatikan — HAL3 only** |
| Configstore HIDL | ada | `disable_configstore` |
| Storage emulasi | sdcardfs | FUSE + project quota + casefolding |
| FUSE passthrough | – | `persist.sys.fuse.passthrough.enable=true` |
| Incremental FS | – | `ro.incremental.enable=1` |
| DebugFS restrictions | – | `PRODUCT_SET_DEBUGFS_RESTRICTIONS := true` → `vendor/debugfs.config` |
| WireGuard in-kernel | – | ada |
| DCVS init script | – | `init.qti.dcvs.sh` |
| Fragment defconfig khas | `vendor/feature/uclamp.config` | `vendor/msm8937-legacy.config` |
| DTS tambahan | – | `dts/vendor-legacy` (`kernel_devicetree_msm-4.19`) |

Referensi baris: `mithorium.mk:16-18` (debugfs), `:205` (configstore), `:491` (dcvs), `:613-614` (vendor blobs); `Mi8937/device.mk:65-72` (emulated storage + FUSE passthrough); `mithorium-common/vendor_k4.19.prop` (incremental FS); `mithorium-common/manifest_k4.19.xml` (VINTF).

---

## 3. Langkah Build

### 3a. Langkah 1–6: sama persis dengan tutorial LOS 20

Ikuti tanpa perubahan apa pun:

1. Persyaratan & dependency host
2. `repo init -u https://github.com/LineageOS/android.git -b lineage-20.0 --no-clone-bundle`
3. Local manifest Mi-Thorium (`lineage-20.0.xml`)
4. `repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags`

**Tetap tanpa patch manual** — sama seperti jalur 4.9.

Manifest `lineage-20.0.xml` yang sama sudah menarik semua kebutuhan 4.19:
```
device/xiaomi/Mi8937_4_19            ← baris 70 (revision a11/master, isinya placeholder)
vendor/xiaomi/mithorium-common-4.19  ← baris 25
```
Jadi **tidak perlu edit manifest sama sekali**.

### 3b. Langkah 7′ — Sync kernel 4.19

> ⚠️ **`repo` tidak mendukung nested checkout.** `repo init` di dalam tree ROM akan menemukan `.repo` milik ROM dan menimpanya. Sync di luar, lalu pindahkan.

```bash
# 1. Sync di LUAR tree ROM
mkdir -p ~/mithorium-4.19
cd ~/mithorium-4.19

repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-4.19 --no-clone-bundle
repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags

# 2. Pindahkan ke dalam tree ROM
mkdir -p ~/android/lineage-20.0/kernel/xiaomi
mv ~/mithorium-4.19 ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19

cd ~/android/lineage-20.0
```

Struktur yang terbentuk (perhatikan `vendor-legacy`, eksklusif 4.19):

```
kernel/                                    ← kernel_msm-4.19 @ mithorium/a13/master
  arch/arm64/boot/dts/vendor-legacy        ← symlink ← kernel_devicetree_msm-4.19 @ dts/master
  arch/arm64/boot/dts/xiaomi-msm8937       ← symlink ← dts/mi8937/4.19/master
  techpack/xiaomi-msm8937                  ← symlink ← techpack/mi8937/4.19/master
  techpack/audio-legacy                    ← symlink ← audio/4.19/mithorium/master
  techpack/camera-legacy                   ← symlink ← camera/LA.UM.8.6.r1-05300-89xx.0/4.19/mithorium
  drivers/staging/prima                    ← symlink ← wlan/LA.UM.9.6.4/mithorium/master
```

### 3c. Verifikasi sebelum build

```bash
cd ~/android/lineage-20.0
K=kernel/xiaomi/mithorium-4.19/kernel

# defconfig + fragment (semua sudah saya cek ada di mithorium/a13/master)
ls $K/arch/arm64/configs/vendor/msm8937-perf_defconfig
ls $K/arch/arm64/configs/vendor/msm8937-legacy.config
ls $K/arch/arm64/configs/vendor/debugfs.config
ls $K/arch/arm64/configs/vendor/feature/erofs.config
ls $K/arch/arm64/configs/vendor/feature/wireguard.config
ls $K/arch/arm64/configs/vendor/xiaomi/msm8937/mi8937.config

# symlink harus resolve, bukan broken
ls -Ld $K/arch/arm64/boot/dts/vendor-legacy
ls -Ld $K/arch/arm64/boot/dts/xiaomi-msm8937
ls -Ld $K/techpack/xiaomi-msm8937

# device tree & vendor blobs 4.19
ls device/xiaomi/Mi8937/lineage_Mi8937_4_19.mk
ls vendor/xiaomi/mithorium-common-4.19/mithorium-common-4.19-vendor.mk
```

### 3d. Langkah 8′ — Build

```bash
cd ~/android/lineage-20.0
source build/envsetup.sh
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

⚠️ **`lunch`, bukan `breakfast`/`brunch`** — roomservice akan menimpa local manifest kamu.

Recovery — **wajib build ulang** kalau sebelumnya kamu punya recovery dari build 4.9, karena `TARGET_RECOVERY_FSTAB` berbeda (`BoardConfig.mk:112-116`):

```bash
mka recoveryimage
```

### 3e. Konfigurasi kernel final

**Boot:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/android-12.config
vendor/feature/erofs.config
vendor/feature/exfat.config
vendor/feature/kprobes.config
vendor/feature/lmkd.config
vendor/feature/wireguard.config        ← khas 4.19 (4.9 pakai uclamp.config)
vendor/debugfs.config                  ← khas 4.19 di a13
vendor/msm8937-legacy.config           ← khas 4.19
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

**Recovery:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/erofs.config
vendor/feature/exfat.config
vendor/feature/ntfs.config
vendor/feature/no-camera-stack.config
vendor/feature/no-wlan-driver.config
vendor/msm8937-legacy.config           ← khas 4.19
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

Kompilasi pakai LLVM penuh: `TARGET_KERNEL_ADDITIONAL_FLAGS := LLVM=1`.

---

## 4. Hasil Build

```
out/target/product/Mi8937_4_19/lineage-20.0-<tanggal>-UNOFFICIAL-Mi8937_4_19.zip
out/target/product/Mi8937_4_19/recovery.img
out/target/product/Mi8937_4_19/boot.img
```

Direktori dan nama ZIP **berbeda** dari build 4.9 — jangan tertukar saat flashing.

---

## 5. Flashing

Skema partisi tidak berubah (`BOARD_SUPER_PARTITION_BLOCK_DEVICES := cust system`, super 3,75 GB retrofit), jadi alur dasarnya sama dengan tutorial utama Bagian 10. Tapi ada **dua hal khusus 4.19** yang wajib kamu perhatikan.

### ⚠️ 5a. Recovery harus yang dari build `Mi8937_4_19`

`fstab` 4.9 dan 4.19 di `a13` **berbeda isi** (bukan cuma mount point) — opsi enkripsi, `checkpoint`, dan `reservedsize` semua beda. Recovery dari build 4.9 akan salah memount `/data`.

```bash
fastboot flash recovery out/target/product/Mi8937_4_19/recovery.img
fastboot reboot recovery
```

### ⚠️ 5b. `/data` akan terenkripsi — siapkan konsekuensinya

Karena FBE v2 + metadata encryption aktif:

- **TWRP/OrangeFox kemungkinan besar tidak bisa decrypt `/data`** dan hanya menampilkan nama file teracak. Ini normal, bukan kerusakan. Untuk backup/restore, gunakan recovery hasil build Lineage sendiri.
- **Wajib Format Data** saat pindah dari build 4.9 (yang `/data`-nya tidak terenkripsi) ke 4.19. Dirty-flash pasti gagal boot.
- Boot pertama lebih lama karena proses enkripsi awal.
- Kalau nanti balik ke 4.9, **Format Data lagi** — 4.9 tidak bisa membaca `/data` yang terenkripsi FBE.

### Langkah lengkap

1. Bootloader ter-unlock.
2. Backup semua data.
3. Flash `recovery.img` dari `Mi8937_4_19` (lihat 5a).
4. Di recovery: **Format Data** (ketik `yes`), lalu Wipe → System, Cache, Dalvik.
5. `adb sideload lineage-20.0-<tanggal>-UNOFFICIAL-Mi8937_4_19.zip`
6. (Opsional) MindTheGapps 13.0 arm64 sebelum reboot pertama. Ingat 16 GB itu sempit.
7. Reboot. Boot pertama 10–20 menit (lebih lama dari 4.9 karena enkripsi awal).

---

## 6. Build 4.9 dan 4.19 Berdampingan

Bisa tanpa konflik — direktori kernel dan `out` terpisah:

```bash
cd ~/android/lineage-20.0

# Sync kedua kernel DI LUAR tree ROM, lalu pindahkan
for v in 4.9 4.19; do
    mkdir -p ~/mithorium-$v && (cd ~/mithorium-$v && \
        repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-$v --no-clone-bundle && \
        repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags)
done

mkdir -p ~/android/lineage-20.0/kernel/xiaomi
mv ~/mithorium-4.9 ~/mithorium-4.19 ~/android/lineage-20.0/kernel/xiaomi/

cd ~/android/lineage-20.0
source build/envsetup.sh

lunch lineage_Mi8937-userdebug      && mka bacon    # → out/target/product/Mi8937
lunch lineage_Mi8937_4_19-userdebug && mka bacon    # → out/target/product/Mi8937_4_19
```

Siapkan disk ekstra: dua direktori `out` masing-masing sekitar 60–80 GB (Android 13 lebih gemuk dari 11), plus ~5 GB untuk kernel tree kedua. Total kebutuhan jadi sekitar **400 GB**. ccache aman dipakai bersama.

---

## 7. Troubleshooting Khusus 4.19

| Gejala | Penyebab & Solusi |
|---|---|
| `No such file: kernel/xiaomi/mithorium-4.19/kernel` | Nama direktori **harus** persis `mithorium-4.19` — `TARGET_KERNEL_SOURCE` menyusunnya dari `mithorium-$(TARGET_KERNEL_VERSION)`. |
| `Can't find vendor/msm8937-legacy.config` atau `vendor/debugfs.config` | Kamu init `kernel_manifest` dengan branch `mithorium-4.9`. Fragment ini hanya ada di `kernel_msm-4.19`. Hapus direktori, init ulang dengan `-b mithorium-4.19`. |
| DTS error `vendor-legacy not found` | Symlink belum terbentuk — `repo sync` di direktori kernel belum selesai. |
| `mithorium-common-4.19-vendor.mk not found` | `repo sync` tree utama belum lengkap. |
| **Bootloop setelah dirty-flash dari build 4.9** | Enkripsi `/data` berubah dari "tidak ada" jadi FBE. **Format Data**, install bersih. |
| TWRP tampilkan nama file teracak di `/data` | Normal — FBE v2 + metadata encryption. Pakai recovery hasil build Lineage. |
| Boot pertama sangat lama | Normal — enkripsi awal `/data`. Tunggu sampai 20 menit sebelum panik. |
| Kamera FC / mode tertentu hilang | Ekspektasi — HAL1 dimatikan di 4.19. Bukan bug build kamu. |
| Full rebuild setelah ganti target lunch | Normal — `PRODUCT_DEVICE` beda berarti direktori `out` beda. ccache membantu. |

---

## 8. Update Berkala

```bash
cd ~/android/lineage-20.0

curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-20.0.xml

repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
(cd kernel/xiaomi/mithorium-4.19 && repo sync -c -j$(nproc --all) --no-tags)

source build/envsetup.sh && lunch lineage_Mi8937_4_19-userdebug && mka bacon
```

Tidak ada patch yang perlu diselamatkan — sama seperti jalur 4.9 di LineageOS 20.

---

## 9. Perbandingan Semua Kombinasi

| | 18.1 + 4.9 | 18.1 + 4.19 | 20 + 4.9 | 20 + 4.19 |
|---|---|---|---|---|
| Android | 11 | 11 | 13 | 13 |
| Branch DT | `a11/master` | `a11/master` | `a13/master` | `a13/master` |
| Patch manual | 2 | 2 | tidak ada | tidak ada |
| Enkripsi `/data` | FDE (`encryptable=footer`) | FBE v2 | **tidak ada** | **FBE v2 + metadata** |
| Camera HAL1 | ✅ | ❌ | ✅ | ❌ |
| Kernel | 4.9 @ `a14/master` | 4.19 @ `a13/master` | 4.9 @ `a14/master` | 4.19 @ `a13/master` |
| EROFS di kernel | – | – | ✅ | ✅ |
| Disk host | ~250 GB | ~250 GB | ~300 GB | ~300 GB |

---

## Referensi

- Kernel manifest 4.19 — https://github.com/Mi-Thorium/kernel_manifest/tree/mithorium-4.19
- Kernel source — https://github.com/Mi-Thorium/kernel_msm-4.19/tree/mithorium/a13/master
- DTS msm8937 (4.19) — https://github.com/Mi-Thorium/kernel_devicetree_xiaomi-msm8937/tree/dts/mi8937/4.19/master
- DTS vendor-legacy — https://github.com/Mi-Thorium/kernel_devicetree_msm-4.19/tree/dts/master
- Vendor blobs 4.19 — https://github.com/Mi-Thorium/proprietary_vendor_xiaomi_mithorium-common-4.19/tree/a13/master
- Device tree Mi8937 — https://github.com/Mi-Thorium/android_device_xiaomi_Mi8937/tree/a13/master
- Local manifest — https://github.com/Mi-Thorium/local_manifests/blob/master/lineage-20.0.xml
