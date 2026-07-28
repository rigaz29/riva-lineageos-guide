# Quickstart — LineageOS 20 untuk Redmi 5A dengan `build-all.sh`

> Dari mesin kosong sampai HP menyala, memakai [`scripts/build-all.sh`](./scripts/build-all.sh).
> Semua langkah & jebakan sudah dibungkus jadi satu perintah build. Untuk memahami **kenapa** tiap bagian bekerja, ikuti tautan ke panduan detail.

Hasil akhir (default): **LineageOS 20 + GApps built-in + root ReSukiSU + susfs v2.2.0** — konfigurasi yang sudah terbukti boot di Redmi 5A.

---

## 0. Yang kamu butuhkan

| | |
|---|---|
| Host | Ubuntu 22.04 LTS 64-bit (jangan 24.04 — lihat [panduan dasar](./BUILD-LineageOS-20-Redmi5A.md)) |
| RAM | 16 GB + swap 16 GB |
| Disk | **250 GB** kosong (SSD) |
| Waktu | sync 1–4 jam · build 3–8 jam (pertama) |
| HP | Redmi 5A, bootloader **sudah ter-unlock** |

---

## 1. Siapkan host

Dependency, `repo`, identitas git, ccache — persis [Bagian 3 panduan dasar](./BUILD-LineageOS-20-Redmi5A.md#3-persyaratan-host). Ringkasnya:

```bash
sudo apt update && sudo apt install -y bc bison build-essential ccache curl \
  flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
  lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev \
  libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc \
  zip zlib1g-dev python3 python-is-python3 openjdk-11-jdk-headless unzip

mkdir -p ~/bin && curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo && export PATH=~/bin:$PATH
git config --global user.name "Nama" && git config --global user.email "email@kamu.com"

# ccache — WAJIB kalau kamu berencana rebuild (ganti --gms/--root, uji kernel).
# Tanpa ini tiap build dari nol berjam-jam; dengan ccache panas, menit.
cat >> ~/.bashrc <<'RC'
export USE_CCACHE=1
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR=~/.ccache
RC
source ~/.bashrc
ccache -M 30G && ccache -o compression=true
```

> ccache disimpan di `~/.ccache` (terpisah dari tree), jadi tetap panas
> meski kamu bersihkan `out/`. Sesudah satu build penuh terisi ~5–6 GB.

---

## 2. Ambil repo panduan (berisi skrip)

```bash
git clone https://github.com/rigaz29/riva-lineageos-guide.git ~/riva-guide
```

> Semua `scripts/*.sh` dan `patches/*` dipanggil dari sini. Jalankan `build-all.sh` **dari dalam** `~/riva-guide`.

---

## 3. Init + sync source ROM

```bash
mkdir -p ~/android/lineage-20.0 && cd ~/android/lineage-20.0

repo init -u https://github.com/LineageOS/android.git -b lineage-20.0 --git-lfs --no-clone-bundle

mkdir -p .repo/local_manifests
curl -s -o .repo/local_manifests/mithorium.xml \
    https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-20.0.xml

repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
```

`--git-lfs` **wajib** — tanpa itu WebView cuma pointer 134 byte dan build gagal jauh di belakang. Detail: [panduan dasar](./BUILD-LineageOS-20-Redmi5A.md).

---

## 4. Kernel — otomatis (atau manual)

Kernel 4.19 disync sebagai `repo` tersendiri, terpisah dari ROM. **`build-all.sh` menyync-nya otomatis kalau belum ada** — jadi kamu bisa langsung lompat ke [Bagian 5](#5-build--satu-perintah).

Kalau lebih suka manual (atau ingin kernel 4.9), sync sendiri — `repo` tidak mendukung nested checkout, jadi init **di luar** tree ROM lalu pindahkan:

```bash
mkdir -p ~/mithorium-4.19 && cd ~/mithorium-4.19
repo init -u https://github.com/Mi-Thorium/kernel_manifest -b mithorium-4.19 --no-clone-bundle
repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags
mkdir -p ~/android/lineage-20.0/kernel/xiaomi
mv -T ~/mithorium-4.19 ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19
```

Latar belakang nested-repo: [panduan kernel 4.19](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md).

---

## 5. Build — satu perintah

```bash
cd ~/riva-guide
./scripts/build-all.sh --gms=gapps --root=resukisu-susfs
```

Itu default, jadi `./scripts/build-all.sh` saja sudah cukup. Skrip akan:

1. **Patch HAL audio** (selalu perlu — kalau tidak, gagal di `libcirrusspkrprot`)
2. **GApps CORE** — clone MindTheGapps, rakit `vendor/gapps` + wiring `WITH_GMS`
3. **ReSukiSU + susfs v2.2.0** — buang hook lama, patch susfs, pasang ReSukiSU, wire device tree
4. **Build** `mka bacon` dengan `WITH_GMS=true` (menangani `set +euo` + envsetup otomatis)
5. **Kemas kernel-only** AnyKernel3

Pilihan lain:

```bash
./scripts/build-all.sh --gms=microg --root=none          # microG, tanpa root
./scripts/build-all.sh --gms=gapps  --root=resukisu      # GApps + root tanpa susfs
./scripts/build-all.sh --gms=none   --root=none          # vanilla polos
./scripts/build-all.sh --prepare-only                    # rakit tree, cek cepat tanpa build
```

Hasil di akhir:

```
ROM        : ~/android/lineage-20.0/out/target/product/Mi8937_4_19/lineage-20.0-*.zip
Kernel zip : ~/riva-guide/rom/KERNEL_resukisu-susfs.zip
recovery   : .../recovery.img
```

---

## 6. Flashing

⚠️ **Format Data wajib** — kernel 4.19 memakai enkripsi FBE, dirty-flash pasti bootloop. Backup dulu.

```bash
cd ~/android/lineage-20.0/out/target/product/Mi8937_4_19

fastboot flash recovery recovery.img
fastboot reboot recovery

# di recovery: Format Data (ketik "yes"), lalu Wipe System/Cache/Dalvik

adb sideload lineage-20.0-*-Mi8937_4_19.zip
```

GApps dan root **sudah di dalam ROM** — tidak perlu sideload terpisah. Reboot; boot pertama 10–20 menit (enkripsi awal).

> Skema *retrofit dynamic partition* (`cust`+`system` jadi super 3,75 GB): balik ke MIUI harus lewat **fastboot ROM MIUI lengkap**, bukan ZIP.

---

## 7. Setelah boot

- **GApps:** Setup Wizard menampilkan login Google — masuk seperti biasa.
- **Root:** pasang manager [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU/releases); harusnya lapor versi **35032** + susfs **v2.2.0**.
- **Play Integrity:** bootloader unlocked → `STRONG` tetap gagal, `basic` biasanya lolos.

---

## 8. Ganti kernel saja nanti (tanpa flash ulang ROM)

Perbaikan kernel atau uji varian cukup lewat kernel-only zip 21 MB — **tanpa wipe data**:

```bash
adb sideload ~/riva-guide/rom/KERNEL_resukisu-susfs.zip
# atau: fastboot flash boot boot.img
```

---

## 9. Kalau gagal

| Gejala | Lihat |
|---|---|
| `libcirrusspkrprot` C23 error | seharusnya ditangani otomatis; kalau muncul, HAL audio tidak bersih |
| `no space left` di `out/soong.log` | disk penuh — `out/error.log` justru **kosong**, jangan cari di sana |
| manager "version too low" | kernel di-clone shallow — `build-all.sh` mencegah ini, tapi jangan `--depth 1` manual |
| bootloop setelah flash | Format Data lagi, install bersih |

Detail tiap kasus ada di [panduan LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md) dan [ReSukiSU](./RESUKISU-Redmi5A.md).

---

## Ringkas — dari nol

```bash
# host: deps + repo (Bagian 1)
git clone https://github.com/rigaz29/riva-lineageos-guide.git ~/riva-guide
mkdir -p ~/android/lineage-20.0 && cd ~/android/lineage-20.0
repo init -u https://github.com/LineageOS/android.git -b lineage-20.0 --git-lfs --no-clone-bundle
mkdir -p .repo/local_manifests
curl -s -o .repo/local_manifests/mithorium.xml https://raw.githubusercontent.com/Mi-Thorium/local_manifests/master/lineage-20.0.xml
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
cd ~/riva-guide && ./scripts/build-all.sh          # auto-sync kernel + ROM + kernel zip
```
