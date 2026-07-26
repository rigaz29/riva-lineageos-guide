# Tutorial Build LineageOS 18.1 untuk Xiaomi Redmi 5A (`riva`)

> Berdasarkan source **Mi-Thorium** (device tree unified `Mi8937`) — hasil verifikasi repo per Juli 2026.
>
> Mau Android 13? Lihat [`BUILD-LineageOS-20-Redmi5A.md`](./BUILD-LineageOS-20-Redmi5A.md) — lebih baru dan **tanpa patch manual**.

---

## 0. Pilihan Source: kenapa Mi-Thorium, bukan iusmac?

Kamu menyebut dua sumber. Ini hasil pengecekan langsung ke kedua repo:

| Sumber | Cakupan `riva` | Status untuk Android 11 | Basis ROM |
|---|---|---|---|
| **Mi-Thorium** | `Mi8937` unified (land/prada/rolex/santoni/**riva**/ugg/ugglite) | branch `a11/master` — commit terakhir **Mar–Okt 2025** | **LineageOS murni** (`lineage_Mi8937`) |
| iusmac | `rova` unified (rolex/riva) | branch `11-dev` — commit terakhir **Des 2022** | `rova_builder` branch `11-stable` sebenarnya build **crDroid 7.x**, bukan LOS murni |

**Kesimpulan:** untuk LineageOS 18.1 yang paling baru + stabil, pakai **Mi-Thorium**. Source iusmac untuk Android 11 sudah stale 3+ tahun dan diarahkan ke crDroid. (Alternatif iusmac tetap saya tulis di [Bagian 10](#10-alternatif-source-iusmac-rova).)

Catatan realistis: development aktif Mi-Thorium sekarang ada di Android 13–16. Branch `a11` berstatus *maintenance* — masih disync & di-patch, tapi jangan harap fitur baru.

### Repo yang dipakai

| Komponen | Repo | Branch |
|---|---|---|
| Manifest ROM | `LineageOS/android` | `lineage-18.1` |
| Local manifest | `Mi-Thorium/local_manifests` | `master` → file `lineage-18.1.xml` |
| Device tree | `Mi-Thorium/android_device_xiaomi_Mi8937` | `a11/master` |
| Common DT | `Mi-Thorium/android_device_xiaomi_mithorium-common` | `a11/master` |
| Vendor blobs | `Mi-Thorium/proprietary_vendor_xiaomi_Mi8937` | `a11/master` |
| Kernel | `Mi-Thorium/kernel_manifest` | `mithorium-4.9` (sync terpisah!) |

---

## 1. Persyaratan Host

| Item | Minimum | Rekomendasi |
|---|---|---|
| OS | Ubuntu 20.04 / 22.04 LTS 64-bit | Ubuntu 22.04 LTS |
| RAM | 8 GB + swap 16 GB | 16 GB+ |
| Disk | ~200 GB kosong (SSD) | 250 GB |
| CPU | 4 core | 8 core+ |
| Internet | sync awal ~90–120 GB | — |

⚠️ **Ubuntu 24.04+ tidak disarankan.** Python 3.12 menghapus modul `imp`/`distutils` dan beberapa paket 32-bit legacy sudah di-rename, sehingga tree Android 11 sering gagal. Kalau host kamu 24.04, pakai Docker (lihat [Bagian 1b](#1b-opsional-build-di-docker-paling-aman)).

### 1a. Install dependency

```bash
sudo apt update
sudo apt install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
    git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev \
    libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
    lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev \
    python3 python-is-python3 openjdk-11-jdk-headless unzip
```

Kalau ada paket yang tidak ketemu (`libncurses5`, `lib32ncurses5-dev` di Ubuntu 22.04+), hapus dari daftar — build Android 11 tetap jalan tanpa itu.

### 1b. (Opsional) Build di Docker — paling aman

Kalau host bukan Ubuntu 20.04/22.04:

```bash
docker run -it --name los181 \
    -v "$HOME/android:/home/build/android" \
    -v "$HOME/.ccache:/home/build/.ccache" \
    ubuntu:22.04 bash
# lalu jalankan langkah 1a di dalam container
```

### 1c. Install `repo`

```bash
mkdir -p ~/bin
curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
echo 'export PATH=~/bin:$PATH' >> ~/.bashrc
export PATH=~/bin:$PATH

# repo wajib punya identitas git
git config --global user.name  "Nama Kamu"
git config --global user.email "email@kamu.com"
git config --global http.postBuffer 524288000   # bantu sync repo besar
```

### 1d. Setup ccache (sangat menghemat waktu rebuild)

```bash
cat >> ~/.bashrc <<'EOF'
export USE_CCACHE=1
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR=~/.ccache
EOF
source ~/.bashrc
ccache -M 50G
ccache -o compression=true
```

---

## 2. Init Manifest LineageOS 18.1

```bash
mkdir -p ~/android/lineage-18.1
cd ~/android/lineage-18.1

repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --no-clone-bundle
```

> Branch `lineage-18.1` masih ada di GitHub LineageOS (sudah EOL, tapi tetap bisa di-clone).

---

## 3. Tambahkan Local Manifest Mi-Thorium

Ini yang menarik semua device tree, vendor blob, dan QCOM HAL khusus mithorium.

```bash
mkdir -p .repo/local_manifests
curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-18.1.xml
```

Isi penting yang di-pull manifest ini:

```
device/xiaomi/Mi8937                  → android_device_xiaomi_Mi8937          (a11/master)
device/xiaomi/mithorium-common        → android_device_xiaomi_mithorium-common (a11/master)
device/xiaomi/mi8937-camera           → android_device_xiaomi_mi8937-camera   (a11/master)
vendor/xiaomi/Mi8937                  → proprietary_vendor_xiaomi_Mi8937      (a11/master)
vendor/xiaomi/mithorium-common        → proprietary_vendor_xiaomi_mithorium-common
hardware/mithorium/*                  → QCOM audio/display/media HAL fork (LA.UM.9.6.4.r2-04300)
device/qcom/sepolicy-legacy-um_mithorium
```

Blob proprietary **sudah tersedia di repo vendor** — kamu tidak perlu `extract-files.sh` dari HP.

### (Opsional) Pangkas device lain

Manifest ini juga menarik Mi439, Tiare, oxygen, vince, uter, onc (~beberapa GB ekstra). Kalau mau hemat, edit `.repo/local_manifests/mithorium.xml` dan hapus blok `<!-- Mi439 -->`, `<!-- Tiare -->`, `<!-- oxygen -->`, `<!-- vince -->`, `<!-- uter -->`, `<!-- onc -->`, `<!-- msm8937 -->`. **Jangan hapus** blok `Common`, `SEPolicy`, `Hardware`, `MiThoriumSSI`, dan `Mi8937`.

---

## 4. Sync Source

```bash
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

Butuh 1–4 jam tergantung koneksi. Kalau putus di tengah, ulangi perintah yang sama.

---

## 5. Terapkan Patch Wajib

**Ini langkah yang paling sering dilewat dan bikin build gagal.** Mi-Thorium menyimpan 2 patch yang harus diterapkan manual.

```bash
cd ~/android/lineage-18.1
git clone https://github.com/Mi-Thorium/local_manifests.git /tmp/mithorium-lm
```

### 5a. Patch `system/core` — liblp

Tanpa ini, flashing gagal dengan error *"Block device size mismatch"* karena Mi8937 memakai skema *retrofit dynamic partition*.

```bash
cd ~/android/lineage-18.1/system/core
git am /tmp/mithorium-lm/lineage-18.1/system/core/0001-liblp-Allow-to-flash-on-bigger-block-device.patch
```

### 5b. Patch `vendor/lineage` — pisahkan msm8937 dari UM_3_18_FAMILY

Device tree memakai `TARGET_ENFORCE_QSSI := true`, dan msm8937 harus masuk keluarga `UM_3_18_4_9_FAMILY` dengan `QCOM_HARDWARE_VARIANT := msm8953`. Tanpa patch ini build error saat resolve QCOM HAL.

```bash
cd ~/android/lineage-18.1/vendor/lineage
git am /tmp/mithorium-lm/lineage-18.1/vendor/lineage/0001-Split-msm8937-from-UM_3_18_FAMILY-and-fix-it.patch
```

Verifikasi kedua patch masuk:

```bash
cd ~/android/lineage-18.1
git -C system/core   log --oneline -1   # → "liblp: Allow to flash on bigger block device"
git -C vendor/lineage log --oneline -1  # → "Split msm8937 from UM_3_18_FAMILY and fix it"
```

---

## 6. Sync Kernel (repo terpisah — WAJIB)

Sejak Mei 2023 Mi-Thorium **mengeluarkan kernel dari local manifest ROM**. Kernel disync sebagai repo `repo` bersarang. Kalau langkah ini dilewat, build gagal karena `TARGET_KERNEL_SOURCE` (`kernel/xiaomi/mithorium-4.9/kernel`) tidak ada.

> ⚠️ **`repo` tidak mendukung nested checkout.** Kalau kamu menjalankan `repo init` di dalam direktori tree ROM, `repo` akan menelusuri direktori induk, menemukan `.repo` milik ROM, dan **menimpa manifest ROM kamu** dengan manifest kernel. Gejalanya: `repo: reusing existing repo client checkout in ...` diikuti `fatal: remote mi-thorium already exists with different attributes`.
>
> Solusinya: sync di luar tree ROM, lalu pindahkan. Lihat [Bagian 11](#11-troubleshooting) kalau kamu terlanjur mengalaminya.

```bash
# 1. Sync di LUAR tree ROM
mkdir -p ~/mithorium-4.9
cd ~/mithorium-4.9

repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-4.9 --no-clone-bundle
repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags

# 2. Pindahkan ke dalam tree ROM
mkdir -p ~/android/lineage-18.1/kernel/xiaomi
mv -T ~/mithorium-4.9 ~/android/lineage-18.1/kernel/xiaomi/mithorium-4.9

cd ~/android/lineage-18.1
```

> `mv -T` penting: tanpa `-T`, kalau direktori tujuan sudah ada (misalnya sisa percobaan sebelumnya), `mv` akan memindahkan source **ke dalam** direktori itu dan menghasilkan `mithorium-<versi>/mithorium-<versi>` yang bersarang. Dengan `-T`, direktori kosong akan diganti, dan kalau ternyata berisi `mv` gagal keras alih-alih diam-diam salah tempat.

Setelah dipindah, direktori kernel punya `.repo` sendiri. `repo sync` berikutnya dari dalam direktori itu aman — `repo` mencari `.repo` mulai dari direktori kerja, jadi ia menemukan milik sendiri lebih dulu dan tidak pernah menyentuh client ROM.

Manifest kernel ini otomatis menyusun:

```
kernel/                          ← kernel_msm-4.9 (branch mithorium/a14/master)
  arch/arm64/boot/dts/xiaomi-msm8937  ← symlink dari kernel_devicetree_xiaomi-msm8937
  techpack/xiaomi-msm8937             ← symlink dari kernel_techpack_xiaomi-msm8937
  techpack/audio-legacy               ← symlink
  techpack/camera-legacy              ← symlink (HAL1 camera)
  drivers/staging/prima               ← symlink (WLAN prima)
```

Pastikan file ini ada sebelum lanjut:

```bash
ls kernel/xiaomi/mithorium-4.9/kernel/Makefile
ls kernel/xiaomi/mithorium-4.9/kernel/arch/arm64/configs/vendor/msm8937-perf_defconfig
```

> **Mau kernel 4.19?** Bisa — ada target resmi `lineage_Mi8937_4_19`. Tutorial lengkapnya (termasuk trade-off kamera HAL1 yang dimatikan) ada di [`BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md`](./BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md). Untuk build pertama, tetap disarankan 4.9 sebagai baseline.

---

## 7. Build

```bash
cd ~/android/lineage-18.1
source build/envsetup.sh
lunch lineage_Mi8937-userdebug
mka bacon -j$(nproc --all)
```

⚠️ **Pakai `lunch`, jangan `breakfast` atau `brunch`.** Kedua perintah itu memanggil *roomservice* yang akan mencari `Mi8937` di GitHub LineageOS, gagal, lalu menimpa local manifest kamu.

Target lunch yang tersedia (dari `AndroidProducts.mk`):

```
lineage_Mi8937-user | -userdebug | -eng            ← kernel 4.9  (dipakai di tutorial ini)
lineage_Mi8937_4_19-user | -userdebug | -eng       ← kernel 4.19
```

Build pertama: 2–8 jam. Rebuild dengan ccache panas: 20–60 menit.

### Build recovery (opsional tapi disarankan)

```bash
mka recoveryimage
```

---

## 8. Hasil Build

```
out/target/product/Mi8937/lineage-18.1-<tanggal>-UNOFFICIAL-Mi8937.zip
out/target/product/Mi8937/recovery.img
out/target/product/Mi8937/boot.img
```

Satu ZIP ini jalan untuk **semua** device Mi8937. Deteksi varian dilakukan saat boot oleh `init_xiaomi_mi8937.cpp`, yang mengeset untuk `riva`:

```
ro.product.device = riva
ro.product.model  = Redmi 5A
ro.sf.lcd_density = 280
```

Assert OTA sudah termasuk `riva`:
```
TARGET_OTA_ASSERT_DEVICE := mi8937,land,santoni,prada,ulysse,ugglite,ugg,rolex,riva,Mi8937,Mi8937_4_19
```

---

## 9. Flashing ke Redmi 5A

⚠️ **Baca dulu — device tree ini memakai *retrofit dynamic partition*.**

```
BOARD_SUPER_PARTITION_BLOCK_DEVICES := cust system
BOARD_SUPER_PARTITION_SIZE          := 3.75 GB  (cust 512 MB + system 3 GB)
```

Artinya partisi `cust` + `system` digabung jadi *super partition*. Konsekuensi:

- Layout partisi berubah → **wajib format data**, tidak cukup wipe biasa.
- Butuh recovery yang mendukung dynamic partition (recovery hasil build sendiri, atau TWRP/OrangeFox terbaru untuk mi8937).
- Balik ke MIUI harus lewat **fastboot flash ROM MIUI fastboot lengkap**, bukan sekadar flash ZIP recovery.

Langkah:

1. Bootloader sudah ter-unlock (Mi Unlock Tool — ada masa tunggu dari Xiaomi).
2. Backup semua data. Serius.
3. Flash recovery:
   ```bash
   fastboot flash recovery out/target/product/Mi8937/recovery.img
   fastboot reboot recovery
   ```
4. Di recovery: **Format Data** (ketik `yes`), lalu Wipe → System, Cache, Dalvik.
5. Sideload / install ZIP:
   ```bash
   adb sideload lineage-18.1-<tanggal>-UNOFFICIAL-Mi8937.zip
   ```
6. (Opsional) Flash **MindTheGapps 11.0 arm64** langsung setelahnya, sebelum reboot pertama. Ingat storage 16 GB itu sempit — pertimbangkan varian pico/nano.
7. Reboot. Boot pertama bisa 5–10 menit.

---

## 10. Alternatif Source: iusmac (`rova`)

Kalau kamu tetap mau device tree khusus rolex/riva dari iusmac:

### 10a. Cara resmi iusmac — tapi ini crDroid, bukan LOS

```bash
git clone --recursive https://github.com/iusmac/rova_builder.git -b 11-stable
cd rova_builder
chmod +x builder.sh
curl -fsSL https://get.docker.com | sudo sh -
./builder.sh      # menu TUI: Sources > Init → Sources > Sync All → Build > Build ROM
```

Isi `builder.sh` pada branch `11-stable`:
```
--repo-url 'https://github.com/crdroidandroid/android.git'
--repo-revision '11.0'
--lunch-system 'lineage'  --lunch-device 'rova'  --lunch-flavor 'userdebug'
```
Jadi walau target lunch-nya `lineage_rova`, **manifest-nya crDroid 7.x**, dan device tree ditarik dari mirror `crdroidandroid/android_device_xiaomi_rova`.

### 10b. LineageOS 18.1 murni pakai tree iusmac

Bisa, dengan local manifest sendiri di atas `repo init -b lineage-18.1`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="iusmac" fetch="https://github.com/iusmac" revision="11-dev" />
  <project path="device/xiaomi/rova" name="device_rova" remote="iusmac" />
  <project path="kernel/xiaomi/rova" name="kernel_rova" remote="iusmac" />
  <project path="vendor/xiaomi/rova" name="vendor_rova" remote="iusmac" />
</manifest>
```
Lalu `lunch lineage_rova-userdebug`.

**Peringatan:** ketiga branch `11-dev` terakhir di-update **Desember 2022**. Tidak ada patch keamanan sejak itu, dan tidak diuji terhadap `lineage-18.1` HEAD saat ini. Pakai hanya kalau kamu siap debug sendiri.

---

## 11. Troubleshooting

| Gejala | Penyebab & Solusi |
|---|---|
| `Block device system size mismatch` saat flash | Patch [5a](#5a-patch-systemcore--liblp) belum diterapkan. Ulangi `git am`, rebuild. |
| Error build QCOM HAL / `QCOM_HARDWARE_VARIANT` kosong | Patch [5b](#5b-patch-vendorlineage--pisahkan-msm8937-dari-um_3_18_family) belum diterapkan. |
| `No such file: kernel/xiaomi/mithorium-4.9/kernel` | [Bagian 6](#6-sync-kernel-repo-terpisah--wajib) dilewat. |
| `grep: .../techpack/KernelSU/kernel/ksu.c: No such file` | Sync kernel belum selesai — jalankan ulang `repo sync` di dir kernel. |
| Local manifest hilang setelah build | Kamu pakai `breakfast`/`brunch`. Pakai `lunch` saja, lalu restore manifest. |
| OOM / `Killed` saat `metalava`/`droiddoc` | Tambah swap (`sudo fallocate -l 16G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`), atau turunkan `-j` ke `-j4`. |
| Error Python `No module named 'imp'` | Host Ubuntu 24.04+. Pindah ke 22.04 atau Docker ([1b](#1b-opsional-build-di-docker-paling-aman)). |
| `repo sync` gagal berulang di project tertentu | `repo sync --force-sync -j1 <path/project>` |
| `remote mi-thorium already exists with different attributes` | Kamu menjalankan `repo init` kernel di dalam tree ROM. Lihat pemulihannya di bawah. |
| Semua `ls` di verifikasi kernel gagal padahal sync sukses | Direktori bersarang: cek `ls kernel/xiaomi/mithorium-*/`. Kalau isinya `mithorium-<versi>/` lagi, `mv` tadi masuk ke dalam direktori kosong yang sudah ada. Rapikan: `cd kernel/xiaomi && mv mithorium-X/mithorium-X mithorium-X.tmp && rmdir mithorium-X && mv mithorium-X.tmp mithorium-X` |

### Pemulihan: `repo init` kernel dijalankan di dalam tree ROM

Gejala lengkapnya:

```
repo: reusing existing repo client checkout in /root/android/lineage-18.1
fatal: manifest 'default.xml' not available
fatal: remote mi-thorium already exists with different attributes
Repo command failed: UpdateManifestError
```

Penyebabnya: `repo` mencari `.repo` mulai dari direktori kerja lalu **naik ke direktori induk** sampai ketemu. Karena tree ROM punya `.repo`, `repo init` di subdirektori mana pun akan memakai client ROM — dan kode `repo` sendiri menyatakannya eksplisit di `subcmds/init.py`: *"repo doesn't do nested checkouts."*

Cek apakah manifest ROM-mu tertimpa:

```bash
cd ~/android/lineage-18.1
git -C .repo/manifests config --get remote.origin.url
```

Kalau hasilnya `https://github.com/Mi-Thorium/kernel_manifest`, perbaiki:

```bash
cd ~/android/lineage-18.1
repo init -u https://github.com/LineageOS/android.git -b lineage-18.1 --no-clone-bundle
git -C .repo/manifests config --get remote.origin.url   # → LineageOS/android
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

Source yang sudah ter-download tidak hilang — yang tertimpa hanya konfigurasi manifest di `.repo`. Patch di `system/core` dan `vendor/lineage` juga tetap aman; cek dengan `git -C system/core log --oneline -1`.

Setelah ROM pulih, sync kernel seperti di [Bagian 6](#6-sync-kernel-repo-terpisah--wajib): init di luar tree, lalu `mv` ke dalam.

---

## 12. Update Source Berkala

```bash
cd ~/android/lineage-18.1

# 1. Simpan patch lokal
git -C system/core   format-patch -1 -o /tmp/keep-core
git -C vendor/lineage format-patch -1 -o /tmp/keep-lineage

# 2. Update local manifest Mi-Thorium
curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-18.1.xml

# 3. Sync ROM
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags

# 4. Sync kernel
(cd kernel/xiaomi/mithorium-4.9 && repo sync -c -j$(nproc --all) --no-tags)

# 5. Terapkan ulang patch bila hilang
git -C system/core   am /tmp/keep-core/*.patch    || true
git -C vendor/lineage am /tmp/keep-lineage/*.patch || true

# 6. Rebuild
source build/envsetup.sh && lunch lineage_Mi8937-userdebug && mka bacon
```

---

## Referensi

- Mi-Thorium local manifests — https://github.com/Mi-Thorium/local_manifests
- Device tree Mi8937 — https://github.com/Mi-Thorium/android_device_xiaomi_Mi8937/tree/a11/master
- Common DT — https://github.com/Mi-Thorium/android_device_xiaomi_mithorium-common/tree/a11/master
- Kernel manifest — https://github.com/Mi-Thorium/kernel_manifest/tree/mithorium-4.9
- iusmac rova builder — https://github.com/iusmac/rova_builder/tree/11-stable
- LineageOS 18.1 manifest — https://github.com/LineageOS/android/tree/lineage-18.1
