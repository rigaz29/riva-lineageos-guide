# Tutorial Build LineageOS 20 (Android 13) untuk Xiaomi Redmi 5A (`riva`)

> Source: **Mi-Thorium**, device tree unified `Mi8937`, branch `a13/master`. Diverifikasi langsung ke repo per Juli 2026.
>
> Versi 18.1: [`BUILD-LineageOS-18.1-Redmi5A.md`](./BUILD-LineageOS-18.1-Redmi5A.md) · Varian kernel 4.19: [`BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md`](./BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md)

---

## 1. Kabar baik: LineageOS 20 lebih gampang dari 18.1

Kalau kamu sudah baca tutorial 18.1, ada dua langkah menyebalkan di sana yang **hilang total** di LineageOS 20.

### Tidak ada patch dari Mi-Thorium yang perlu diterapkan

Repo `Mi-Thorium/local_manifests` menyimpan patch per versi Android. Isinya:

```
lineage-18.1/    → 2 patch (WAJIB)
lineage-20.0/    → tidak ada        ← ini versi kita
lineage-23.0/    → 4 patch
lineage-23.x/    → 2 patch
```

Kenapa 20.0 kosong? Karena kedua patch yang dulu wajib sekarang sudah masuk upstream:

| Patch 18.1 | Status di LineageOS 20 |
|---|---|
| `liblp: Allow to flash on bigger block device` | Sudah upstream. `system/core/fs_mgr/liblp/writer.cpp:141` di branch `lineage-20.0` sudah berisi `if (info.size < block_device.size)` — persis isi patch Mi-Thorium. |
| `Split msm8937 from UM_3_18_FAMILY` | Sudah upstream. `vendor/lineage/config/BoardConfigQcom.mk:28` di `lineage-20.0` sudah punya `UM_4_9_LEGACY_FAMILY := msm8937 msm8953`. Selain itu device tree `a13` tidak lagi memakai `TARGET_ENFORCE_QSSI`, jadi patch itu memang tidak relevan lagi. |

### SEPolicy dari upstream LineageOS

Manifest 18.1 harus menarik fork `android_device_qcom_sepolicy_mithorium`. Manifest 20.0 tidak lagi — `mithorium-common/BoardConfigCommon.mk:233` cukup meng-include `device/qcom/sepolicy-legacy-um/SEPolicy.mk`, dan repo itu sudah ada di manifest resmi LineageOS 20 (`snippets/lineage.xml:71`, revision `lineage-20.0-legacy-um`). Satu repo pihak ketiga lebih sedikit untuk diurus.

### Status branch `a13` — apa adanya

| Repo | Commit terakhir |
|---|---|
| `android_device_xiaomi_Mi8937` @ `a13/master` | authored Jan 2024, committed **Mei 2025** |
| `android_device_xiaomi_mithorium-common` @ `a13/master` | **Okt 2025** (merge dari `a12/master`) |
| `proprietary_vendor_xiaomi_Mi8937` @ `a13/master` | ada, aktif |
| Camera trees (`mi8937-camera`, `prada-camera`) | dipin ke `a11/master` — dipakai bersama semua versi |

Development paling aktif Mi-Thorium sekarang di Android 15/16. `a13` berstatus stabil/maintenance — cocok untuk dipakai, tapi jangan harap fitur baru.

---

## 2. Source yang Dipakai

| Komponen | Repo | Branch |
|---|---|---|
| Manifest ROM | `LineageOS/android` | `lineage-20.0` |
| Local manifest | `Mi-Thorium/local_manifests` | `master` → `lineage-20.0.xml` |
| Device tree | `Mi-Thorium/android_device_xiaomi_Mi8937` | `a13/master` |
| Common DT | `Mi-Thorium/android_device_xiaomi_mithorium-common` | `a13/master` |
| Vendor blobs | `Mi-Thorium/proprietary_vendor_xiaomi_Mi8937` | `a13/master` |
| QCOM HAL | `LineageOS/android_hardware_qcom_{media,display}` | `lineage-20.0-caf-msm8953` |
| QCOM HAL (fork) | `Mi-Thorium/android_hardware_qcom_{audio,media,display}_mithorium` | `mithorium/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0` |
| Kernel | `Mi-Thorium/kernel_manifest` | `mithorium-4.9` (sync terpisah) |

`riva` didukung penuh — ada `rro_overlays/xiaomi_riva_overlay{,_lineage}`, `audio/mixer_paths/riva_mixer_paths_qrd_sku2.xml`, dan assert OTA:

```
TARGET_OTA_ASSERT_DEVICE := mi8937,land,santoni,prada,ulysse,ugglite,ugg,rolex,riva,Mi8937,Mi8937_4_19
```

---

## 3. Persyaratan Host

| Item | Minimum | Rekomendasi |
|---|---|---|
| OS | Ubuntu 20.04 / 22.04 LTS 64-bit | **Ubuntu 22.04 LTS** |
| RAM | 12 GB + swap 16 GB | 16–32 GB |
| Disk | **250 GB kosong** (SSD) | 300 GB+ |
| CPU | 4 core | 8 core+ |
| Internet | sync awal ~120–150 GB | — |

LineageOS 20 lebih berat dari 18.1 — source lebih besar dan Soong lebih rakus RAM. Kalau RAM pas-pasan, siapkan swap dan turunkan `-j`.

### Rincian disk (hasil pengukuran nyata, bukan perkiraan)

Angka di bawah diukur dari satu build `lineage_Mi8937_4_19` yang berjalan sampai tahap akhir:

| Komponen | Ukuran |
|---|---|
| Source tree (tanpa `out` & `.repo`) | 80 GB |
| `.repo` (objek git) | 62 GB |
| `out/` saat build hampir selesai | 84 GB |
| **Subtotal satu tree** | **~230 GB** |
| ccache setelah 1 build penuh | 5,5 GB |

`out/` masih tumbuh sampai sekitar 100–110 GB untuk `bacon` yang benar-benar selesai, jadi siapkan **250 GB** dan jangan pas-pasan.

⚠️ Kalau di disk yang sama ada tree build lain (TWRP, device lain), hitung juga. Kehabisan disk di menit ke-70 adalah kegagalan yang paling menjengkelkan karena tidak muncul di `out/error.log` — pesannya hanya ada di `out/soong.log`:

```
build/soong/ui/status/log.go:184: Failed to write file .../out/build_error:
  write .../out/build_error.tmp: no space left on device
```

Kalau ini terjadi, `out/error.log` justru **kosong 0 byte** dan tidak ada `FAILED:` sama sekali — jangan tertipu mencarinya di sana.

⚠️ Hindari Ubuntu 24.04+ (Python 3.12 menghapus `imp`/`distutils`, beberapa paket 32-bit di-rename). Pakai Docker `ubuntu:22.04` kalau host kamu sudah 24.04.

### 3a. Dependency

```bash
sudo apt update
sudo apt install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
    git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev \
    libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 libxml2-utils \
    lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev \
    python3 python-is-python3 openjdk-11-jdk-headless unzip
```

Paket yang tidak tersedia di Ubuntu 22.04+ (`libncurses5`, `lib32ncurses5-dev`) boleh dihapus dari daftar.

### 3b. `repo` + identitas git

```bash
mkdir -p ~/bin
curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
echo 'export PATH=~/bin:$PATH' >> ~/.bashrc
export PATH=~/bin:$PATH

git config --global user.name  "Nama Kamu"
git config --global user.email "email@kamu.com"
git config --global http.postBuffer 524288000
```

### 3c. ccache

```bash
cat >> ~/.bashrc <<'EOF'
export USE_CCACHE=1
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR=~/.ccache
EOF
source ~/.bashrc
ccache -M 30G
ccache -o compression=true
```

30 GB sudah cukup: setelah satu build penuh LineageOS 20, ccache hanya terisi 5,5 GB. Angka ini batas atas, bukan alokasi di muka — tapi jangan diset terlalu besar di disk yang sudah sesak.

---

## 4. Init Manifest LineageOS 20

```bash
mkdir -p ~/android/lineage-20.0
cd ~/android/lineage-20.0

repo init -u https://github.com/LineageOS/android.git -b lineage-20.0 --git-lfs --no-clone-bundle
```

> ⚠️ **`--git-lfs` wajib, bukan opsional.** Prebuilt WebView LineageOS disimpan lewat Git LFS. Tanpa flag ini, `external/chromium-webview/prebuilt/*/webview.apk` hanya berisi pointer teks 134 byte, dan build gagal jauh di belakang dengan `zip: not a valid zip file`. Repo prebuilt itu hanya punya branch `main` yang dipakai semua versi LineageOS, jadi ini berlaku untuk 18.1 maupun 20.

---

## 5. Local Manifest Mi-Thorium

```bash
mkdir -p .repo/local_manifests
curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-20.0.xml
```

Yang ditarik untuk Mi8937:

```
device/xiaomi/Mi8937                  ← a13/master
device/xiaomi/mithorium-common        ← a13/master
device/xiaomi/MiThoriumSSI            ← a13/master
device/xiaomi/mi8937-camera           ← a11/master (shared)
device/xiaomi/prada-camera            ← a11/master (shared)
device/xiaomi/land-camera             ← sairam/a11/master
vendor/xiaomi/Mi8937                  ← a13/master
vendor/xiaomi/mithorium-common        ← a13/master
vendor/xiaomi/mithorium-common-graphics
hardware/mithorium/*                  ← QCOM audio/display/media (LA.UM.9.6.4.r2-04300 + lineage-20.0-caf-msm8953)
```

Blob proprietary sudah tersedia di repo vendor — **tidak perlu** `extract-files.sh` dari HP.

### (Opsional) Pangkas device lain

Manifest juga menarik Mi439, Tiare, oxygen, vince, uter, onc, msm8937. Untuk hemat bandwidth, hapus blok `<!-- Mi439 -->`, `<!-- Tiare -->`, `<!-- oxygen -->`, `<!-- vince -->`, `<!-- uter -->`, `<!-- onc -->`, `<!-- msm8937 -->` dari `.repo/local_manifests/mithorium.xml`.

**Jangan hapus** blok `Common`, `Hardware`, `MiThoriumSSI`, dan `Mi8937`.

---

## 6. Sync Source

```bash
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

1–5 jam tergantung koneksi. Kalau putus, ulangi perintah yang sama.

**Tidak ada langkah patch setelah ini.** Langsung ke sync kernel.

---

### 6b. Patch HAL audio — parameter pthread tanpa nama

Commit teratas HAL audio Mi-Thorium (`a3ff9d54`, Agustus 2025) mengubah definisi fungsi thread menjadi `void*` **tanpa nama parameter**. Itu ekstensi C23, dan clang `r450784d` yang dipakai LineageOS 20 menolaknya di bawah `-Werror`:

```
hardware/mithorium/audio/.../hal/hal/audio_extn/cirrus_playback.c:479:56: error:
  omitting the parameter name in a function definition is a C2x extension
  [-Werror,-Wc2x-extensions]
static void *audio_extn_cirrus_calibration_thread(void*) {
```

Build gagal sekitar 1 jam setelah dimulai, tepat setelah kernel selesai. Tidak ada perbaikan upstream — commit itu adalah tip branch `mithorium/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0`.

Terapkan patch dari repo ini:

```bash
cd ~/android/lineage-20.0/hardware/mithorium/audio/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0/hal
git am /path/ke/riva-lineageos-guide/patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch
```

Patch memberi nama parameter dan menandainya `__unused` — konvensi yang memang sudah dipakai 26 file lain di HAL ini. Menamai saja tanpa `__unused` tidak cukup: `-Wno-unused` di clang **tidak** mencakup `-Wunused-parameter`, jadi akan gagal dengan error berbeda.

Mempengaruhi 5 definisi di 2 file:
```
hal/audio_extn/cirrus_playback.c   : 479, 579, 662
hal/audio_extn/spkr_protection.c   : 1173, 1956
```

> Branch HAL yang sama juga dipin oleh manifest 18.1, 21, 22, dan 23, jadi versi lain kemungkinan besar terdampak sama. Saya memverifikasinya di LineageOS 20.

---

## 7. Sync Kernel (repo terpisah — WAJIB)

Sama seperti 18.1: Mi-Thorium menaruh kernel di manifest `repo` terpisah, bukan di local manifest ROM. `mithorium-common/BoardConfigCommon.mk:51` menuntut:

```makefile
TARGET_KERNEL_SOURCE := kernel/xiaomi/mithorium-$(TARGET_KERNEL_VERSION)/kernel
```

Karena `lineage_Mi8937.mk` mengeset `TARGET_KERNEL_VERSION := 4.9`, direktorinya harus persis `kernel/xiaomi/mithorium-4.9`.

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
mkdir -p ~/android/lineage-20.0/kernel/xiaomi
mv -T ~/mithorium-4.9 ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.9

cd ~/android/lineage-20.0
```

> `mv -T` penting: tanpa `-T`, kalau direktori tujuan sudah ada (misalnya sisa percobaan sebelumnya), `mv` akan memindahkan source **ke dalam** direktori itu dan menghasilkan `mithorium-<versi>/mithorium-<versi>` yang bersarang. Dengan `-T`, direktori kosong akan diganti, dan kalau ternyata berisi `mv` gagal keras alih-alih diam-diam salah tempat.

Setelah dipindah, direktori kernel punya `.repo` sendiri. `repo sync` berikutnya dari dalam direktori itu aman — `repo` mencari `.repo` mulai dari direktori kerja, jadi ia menemukan milik sendiri lebih dulu dan tidak pernah menyentuh client ROM.

Struktur yang terbentuk:

```
kernel/                                  ← kernel_msm-4.9 @ mithorium/a14/master
  arch/arm64/boot/dts/xiaomi-msm8937     ← symlink ← dts/mi8937/4.9/master
  techpack/xiaomi-msm8937                ← symlink ← techpack/mi8937/4.9/master
  techpack/audio-legacy                  ← symlink ← audio/4.9/mithorium/master
  techpack/camera-legacy                 ← symlink ← camera/LA.UM.8.6.r1-05300-89xx.0/4.9/mithorium
  drivers/staging/prima                  ← symlink ← wlan/LA.UM.9.6.4/mithorium/master
```

### Verifikasi sebelum build

```bash
cd ~/android/lineage-20.0
K=kernel/xiaomi/mithorium-4.9/kernel

ls $K/arch/arm64/configs/vendor/msm8937-perf_defconfig
ls $K/arch/arm64/configs/vendor/feature/erofs.config
ls $K/arch/arm64/configs/vendor/feature/uclamp.config
ls $K/arch/arm64/configs/vendor/xiaomi/msm8937/mi8937.config
ls -Ld $K/arch/arm64/boot/dts/xiaomi-msm8937
ls -Ld $K/techpack/xiaomi-msm8937

ls device/xiaomi/Mi8937/lineage_Mi8937.mk
ls vendor/xiaomi/Mi8937
```

Semua harus ada. Symlink yang broken artinya `repo sync` di direktori kernel belum selesai.

### Fragment defconfig yang dipakai

Beda dari 18.1: **a13 menambahkan EROFS** di boot maupun recovery.

**Boot:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/android-12.config
vendor/feature/erofs.config          ← baru vs 18.1
vendor/feature/exfat.config
vendor/feature/kprobes.config
vendor/feature/lmkd.config
vendor/feature/uclamp.config         ← khusus kernel 4.9
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

**Recovery:**
```
vendor/msm8937-perf_defconfig
vendor/common.config
vendor/feature/erofs.config          ← baru vs 18.1
vendor/feature/exfat.config
vendor/feature/ntfs.config
vendor/feature/no-camera-stack.config
vendor/feature/no-wlan-driver.config
vendor/xiaomi/msm8937/common.config
vendor/xiaomi/msm8937/mi8937.config
```

Catatan: kernel mendukung EROFS, tapi image partisi tetap dibuat **ext4** (`BOARD_*IMAGE_FILE_SYSTEM_TYPE := ext4` di `BoardConfig.mk:15`).

---

## 8. Build

```bash
cd ~/android/lineage-20.0
source build/envsetup.sh
lunch lineage_Mi8937-userdebug
mka bacon -j$(nproc --all)
```

⚠️ **`lunch`, bukan `breakfast`/`brunch`** — keduanya memanggil roomservice yang akan mencari `Mi8937` di GitHub LineageOS, gagal, lalu menimpa local manifest kamu.

Target yang tersedia:
```
lineage_Mi8937-user | -userdebug | -eng            ← kernel 4.9  (default)
lineage_Mi8937_4_19-user | -userdebug | -eng       ← kernel 4.19 (lihat Bagian 12)
```

Build pertama: 3–10 jam. Rebuild dengan ccache panas: 30–90 menit.

Recovery:
```bash
mka recoveryimage
```

---

## 9. Hasil Build

```
out/target/product/Mi8937/lineage-20.0-<tanggal>-UNOFFICIAL-Mi8937.zip
out/target/product/Mi8937/recovery.img
out/target/product/Mi8937/boot.img
```

Satu ZIP untuk semua device Mi8937. Deteksi varian saat boot oleh `libinit/init_xiaomi_mi8937.cpp` — untuk `riva` diset `ro.product.device=riva`, `ro.product.model=Redmi 5A`, density 280.

---

## 10. Flashing ke Redmi 5A

Skema partisinya **identik dengan 18.1** — `BoardConfig.mk:80-87` di branch `a13` sama persis dengan `a11`:

```
BOARD_SUPER_PARTITION_BLOCK_DEVICES := cust system
BOARD_SUPER_PARTITION_SIZE          := 3,75 GB  (cust 512 MB + system 3 GB)
```

Ini *retrofit dynamic partition*: partisi `cust` + `system` digabung jadi super partition. Konsekuensinya:

- Layout partisi berubah → **wajib Format Data**, bukan wipe biasa.
- Butuh recovery yang paham dynamic partition (recovery hasil build sendiri, atau TWRP/OrangeFox terbaru untuk mi8937).
- Balik ke MIUI harus lewat **fastboot ROM MIUI lengkap**, bukan flash ZIP recovery.

Langkah:

1. Bootloader sudah ter-unlock (Mi Unlock Tool, ada masa tunggu dari Xiaomi).
2. Backup semua data.
3. Flash recovery:
   ```bash
   fastboot flash recovery out/target/product/Mi8937/recovery.img
   fastboot reboot recovery
   ```
4. Di recovery: **Format Data** (ketik `yes`), lalu Wipe → System, Cache, Dalvik.
5. Sideload:
   ```bash
   adb sideload lineage-20.0-<tanggal>-UNOFFICIAL-Mi8937.zip
   ```
6. (Opsional) **MindTheGapps 13.0 arm64** langsung setelahnya, sebelum reboot pertama.
   ⚠️ Redmi 5A 16 GB itu sempit dan Android 13 lebih gemuk dari 11 — pertimbangkan varian minimal, atau lewati GApps sama sekali.
7. Reboot. Boot pertama 5–15 menit.

### Upgrade dari LineageOS 18.1

Jangan dirty-flash. Beda major version berarti beda vendor blobs dan VINTF level. Format Data, install bersih.

---

## 11. Troubleshooting

| Gejala | Penyebab & Solusi |
|---|---|
| `No such file: kernel/xiaomi/mithorium-4.9/kernel` | [Bagian 7](#7-sync-kernel-repo-terpisah--wajib) dilewat. |
| `Can't find vendor/feature/erofs.config` | Kernel tree tersync tapi tidak lengkap, atau kamu pakai kernel tree lama dari build 18.1 yang belum di-`repo sync`. Sync ulang. |
| Symlink DTS/techpack broken | `repo sync` di direktori kernel belum selesai — jalankan ulang. |
| Local manifest hilang setelah build | Kamu pakai `breakfast`/`brunch`. Pakai `lunch`, lalu restore manifest. |
| `Killed` saat Soong / `metalava` | RAM kurang. Tambah swap: `sudo fallocate -l 24G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`, atau turunkan ke `-j4`. |
| Error Python `No module named 'imp'` | Host Ubuntu 24.04+. Pindah ke 22.04 atau Docker. |
| `zip: not a valid zip file` saat `target Prebuilt: webview` | `repo init` dijalankan tanpa `--git-lfs`, jadi `webview.apk` masih berupa pointer LFS. Lihat pemulihannya di bawah. |
| `no space left on device` di `out/soong.log` | Disk penuh. Lihat rincian kebutuhan nyata di [Bagian 3](#3-persyaratan-host). Cek `df -h /` dan `du -sh out .repo`. Build bisa dilanjutkan setelah ruang dibebaskan — `mka bacon` melanjutkan, tidak mengulang dari nol. |
| `repo sync` gagal berulang di satu project | `repo sync --force-sync -j1 <path/project>` |
| Kamu terlanjur mencari patch seperti di tutorial 18.1 | Memang tidak ada. `local_manifests/lineage-20.0/` tidak eksis — itu normal, bukan tanda sync gagal. |
| `remote mi-thorium already exists with different attributes` | Kamu menjalankan `repo init` kernel di dalam tree ROM. Lihat pemulihannya di bawah. |
| Semua `ls` di verifikasi kernel gagal padahal sync sukses | Direktori bersarang: cek `ls kernel/xiaomi/mithorium-*/`. Kalau isinya `mithorium-<versi>/` lagi, `mv` tadi masuk ke dalam direktori kosong yang sudah ada. Rapikan: `cd kernel/xiaomi && mv mithorium-X/mithorium-X mithorium-X.tmp && rmdir mithorium-X && mv mithorium-X.tmp mithorium-X` |

### Pemulihan: `repo init` kernel dijalankan di dalam tree ROM

Gejala lengkapnya:

```
repo: reusing existing repo client checkout in /root/android/lineage-20.0
fatal: manifest 'default.xml' not available
fatal: remote mi-thorium already exists with different attributes
Repo command failed: UpdateManifestError
```

Penyebabnya: `repo` mencari `.repo` mulai dari direktori kerja lalu **naik ke direktori induk** sampai ketemu. Karena tree ROM punya `.repo`, `repo init` di subdirektori mana pun akan memakai client ROM — dan kode `repo` sendiri menyatakannya eksplisit di `subcmds/init.py`: *"repo doesn't do nested checkouts."*

Akibatnya URL manifest ROM kamu tertimpa. Cek dulu:

```bash
cd ~/android/lineage-20.0
git -C .repo/manifests config --get remote.origin.url
```

Kalau hasilnya `https://github.com/Mi-Thorium/kernel_manifest`, itu memang tertimpa. Perbaiki:

```bash
cd ~/android/lineage-20.0
repo init -u https://github.com/LineageOS/android.git -b lineage-20.0 --git-lfs --no-clone-bundle

# verifikasi sudah kembali
git -C .repo/manifests config --get remote.origin.url   # → LineageOS/android
head -3 .repo/manifest.xml

# selaraskan lagi
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

**Kabar baiknya:** source yang sudah ter-download tidak hilang. Yang tertimpa hanya konfigurasi manifest di `.repo`, bukan project yang sudah tersync — `.repo/local_manifests/mithorium.xml` pun tetap utuh.

Setelah ROM pulih, sync kernel dengan cara yang benar seperti di [Bagian 7](#7-sync-kernel-repo-terpisah--wajib): init di luar tree, lalu `mv` ke dalam.

---

### Pemulihan: `webview.apk` masih pointer LFS

Tidak perlu sync ulang seluruh tree. `external/chromium-webview` bukan satu project melainkan container berisi sub-project per arsitektur, jadi `git lfs pull` harus dijalankan di sub-direktorinya:

```bash
cd ~/android/lineage-20.0/external/chromium-webview
for a in arm64 arm; do (cd prebuilt/$a && git lfs pull); done
```

Verifikasi — ukurannya harus ratusan MB, bukan 134 byte:

```bash
cd ~/android/lineage-20.0
for a in arm64 arm; do
    stat -c "%n %s byte" external/chromium-webview/prebuilt/$a/webview.apk
    zipinfo external/chromium-webview/prebuilt/$a/webview.apk 'lib/*.so' >/dev/null && echo "  → ZIP valid"
done
```

Patokan: arm64 ≈ 262 MB, arm ≈ 95 MB. `x86`/`x86_64` tidak perlu untuk Redmi 5A.

Setelah itu `mka bacon` bisa dilanjutkan — tidak mengulang dari nol.

---

## 12. Opsi Kernel 4.19

Branch `a13` juga punya target `lineage_Mi8937_4_19`. **Untuk LineageOS 20, opsi ini layak dipertimbangkan serius** — bukan sekadar alternatif eksperimental seperti di 18.1.

Alasannya: di branch `a13`, jalur kernel 4.9 **tidak mengenkripsi `/data` sama sekali** (baris FBE di `fstab_4_9.qcom:25-26` dikomentari), sementara jalur 4.19 mendapat FBE v2 + inline crypto + metadata encryption. Trade-off-nya tetap camera HAL1 yang dimatikan (`BoardConfig.mk:31-32`).

Tutorial lengkapnya — termasuk konsekuensi enkripsi saat flashing dan tabel perbandingan keempat kombinasi — ada di **[`BUILD-LineageOS-20-Redmi5A-kernel4.19.md`](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md)**.

---

## 13. Update Berkala

Lebih sederhana dari 18.1 — hanya satu patch yang perlu diselamatkan (18.1 punya dua, plus patch HAL audio ini):

```bash
cd ~/android/lineage-20.0

curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-20.0.xml

repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
(cd kernel/xiaomi/mithorium-4.9 && repo sync -c -j$(nproc --all) --no-tags)

# WAJIB: terapkan ulang patch HAL audio yang baru saja terhapus repo sync
(cd hardware/mithorium/audio/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0/hal && \
    git am /path/ke/riva-lineageos-guide/patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch)

source build/envsetup.sh && lunch lineage_Mi8937-userdebug && mka bacon
```

> ⚠️ **`repo sync` menghapus patch lokal.** Checkout `repo` berada di detached HEAD, jadi commit lokalmu akan menjadi yatim dan project dikembalikan ke revisi manifest. Patch HAL audio **wajib** diterapkan ulang setiap kali sync — kalau tidak, build gagal lagi di `libcirrusspkrprot`.

```bash
cd ~/android/lineage-20.0/hardware/mithorium/audio/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0/hal
git am /path/ke/riva-lineageos-guide/patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch
cd ~/android/lineage-20.0
```

---

## 14. Ringkasan Perbedaan 18.1 vs 20

| | LineageOS 18.1 | LineageOS 20 |
|---|---|---|
| Android | 11 | 13 |
| Branch manifest | `lineage-18.1` | `lineage-20.0` |
| Local manifest | `lineage-18.1.xml` | `lineage-20.0.xml` |
| Branch device tree | `a11/master` | `a13/master` |
| **Patch manual** | **2 (wajib)** | **tidak ada** |
| SEPolicy | fork `sepolicy_mithorium` | upstream `sepolicy-legacy-um` |
| `hardware/lineage/compat` | perlu | tidak perlu |
| FMRadio | diganti fork `mi-sdm439` | pakai upstream |
| QCOM HAL LineageOS | `lineage-18.1-caf-msm8953` | `lineage-20.0-caf-msm8953` |
| EROFS di kernel | – | ya |
| Enkripsi `/data` (kernel 4.9) | FDE (`encryptable=footer`) | **tidak ada** — pakai 4.19 kalau butuh enkripsi |
| Kernel | `kernel_msm-4.9` @ `mithorium/a14/master` | sama |
| Skema partisi | super 3,75 GB retrofit | sama |
| Disk host | ~250 GB | ~300 GB |

---

## Panduan Terkait

- **[microG bawaan (opsional)](./MICROG-BUILT-IN-Redmi5A.md)** — tanam microG ke dalam ROM. Tidak perlu patch: LineageOS 20 sudah punya restricted signature spoofing.
- **[Tuning RAM & Storage](./TUNING-RAM-Storage-Redmi5A.md)** — perlukah konfigurasi Android Go, dan cara menyiasati super partition 3,75 GB.

---

## Referensi

- Local manifests — https://github.com/Mi-Thorium/local_manifests/blob/master/lineage-20.0.xml
- Device tree Mi8937 — https://github.com/Mi-Thorium/android_device_xiaomi_Mi8937/tree/a13/master
- Common DT — https://github.com/Mi-Thorium/android_device_xiaomi_mithorium-common/tree/a13/master
- Vendor blobs — https://github.com/Mi-Thorium/proprietary_vendor_xiaomi_Mi8937/tree/a13/master
- Kernel manifest — https://github.com/Mi-Thorium/kernel_manifest/tree/mithorium-4.9
- Manifest LineageOS 20 — https://github.com/LineageOS/android/tree/lineage-20.0
