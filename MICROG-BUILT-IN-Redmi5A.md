# microG Bawaan (Built-in) — Redmi 5A (`riva`)

> **Opsional.** Panduan ini menambahkan microG langsung ke dalam ROM saat build, sebagai pengganti Google Play Services. Berlaku untuk LineageOS 18.1 maupun 20.
>
> Sumber: [lineageos4microg](https://github.com/lineageos4microg) — proyek "LineageOS for microG".

---

## 1. Kabar baiknya: tidak perlu patch apa pun

Panduan microG yang beredar umumnya menyuruh mem-patch `frameworks/base` untuk mengaktifkan *signature spoofing*. **Untuk LineageOS 18.1 ke atas, itu sudah tidak diperlukan.**

LineageOS sudah menyertakan *restricted signature spoofing* di source-nya. Buktinya ada di `frameworks/base/services/core/java/com/android/server/pm/ComputerEngine.java`:

```java
418:  private static final Signature MICROG_FAKE_SIGNATURE = new Signature("30820443...");  // tanda tangan Google
419:  private static final Signature MICROG_REAL_SIGNATURE = new Signature("308202ed...");  // kunci rilis microG
1616: public static boolean isMicrogSigned(AndroidPackage p) { ... }
1637: private static Optional<Signature> generateFakeSignature(AndroidPackage p) { ... }
```

README `android_vendor_partner_gms` juga menegaskannya:

> *"LineageOS now support **restricted** signature spoofing, in 18.1 and later branches, so it is no longer necessary to patch their sources, unless you want **unrestricted** signature spoofing"*

## 2. Cara kerja restricted spoofing — dan batasannya

`generateFakeSignature()` punya **dua gerbang**, keduanya harus lolos:

| Gerbang | Aturan |
|---|---|
| 1. Siapa yang boleh | Aplikasi harus ditandatangani **kunci rilis resmi microG** (`isMicrogSigned`) |
| 2. Boleh menyamar jadi siapa | Hanya tanda tangan **Google** (`MICROG_FAKE_SIGNATURE`) — komentar di source: *"Only MICROG_FAKE_SIGNATURE can be faked"* |

Konsekuensi praktis yang perlu kamu tahu:

- ✅ **APK microG resmi bekerja langsung**, tanpa patch, tanpa root, tanpa memberi izin manual.
- ❌ **microG hasil build sendiri tidak akan bekerja** — tanda tangannya berbeda dari kunci rilis resmi.
- ❌ Aplikasi lain **tidak bisa** memakai fitur ini untuk memalsukan tanda tangan apa pun.
- ℹ️ Tidak ada syarat harus menjadi *system app*. Yang menentukan murni tanda tangan APK-nya.

Kalau kamu butuh spoofing tanpa batas, lihat [Bagian 7](#7-kalau-butuh-unrestricted-signature-spoofing).

---

## 3. Langkah

### 3a. Tambahkan local manifest

Hook resminya sudah ada di LineageOS (`vendor/lineage/config/partner_gms.mk`), yang aktif kalau `WITH_GMS := true`. Kita cukup mengisi `vendor/partner_gms` dengan versi microG.

```bash
cd ~/android/lineage-20.0
curl -s -o .repo/local_manifests/microg.xml \
    https://raw.githubusercontent.com/lineageos4microg/l4m-manifests/main/l4m_gms.xml
```

Isinya cuma satu baris project:

```xml
<project path="vendor/partner_gms"
         name="lineageos4microg/android_vendor_partner_gms"
         remote="github" revision="master" />
```

### 3b. Sync

```bash
repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags
```

> ⚠️ **Sync ini akan menghapus patch HAL audio kamu.** Checkout `repo` berada di detached HEAD, jadi commit lokal menjadi yatim dan project dikembalikan ke revisi manifest — termasuk `hardware/mithorium/audio/...`. Kalau tidak diterapkan ulang, build gagal di `libcirrusspkrprot` dengan error C23 yang sama seperti sebelumnya.
>
> ```bash
> cd ~/android/lineage-20.0/hardware/mithorium/audio/LA.UM.9.6.4.r2-04300-89xx.QSSI13r2.0/hal
> git am /path/ke/riva-lineageos-guide/patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch
> cd ~/android/lineage-20.0
> ```

### 3c. Build dengan `WITH_GMS=true`

```bash
cd ~/android/lineage-20.0
export WITH_GMS=true

source build/envsetup.sh
set +e                      # ← WAJIB, lihat peringatan di bawah

lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

> ⚠️ **Jalankan `set +e` setelah `source build/envsetup.sh`.**
>
> `build/envsetup.sh:1958` menjalankan setiap `vendorsetup.sh` dengan `. "$T/$f"` — **di-source ke shell kamu**, bukan subshell. Sementara `vendor/partner_gms/vendorsetup.sh` diawali `set -e`. Akibatnya `set -e` menempel di shell interaktif kamu: perintah apa pun yang mengembalikan status non-nol setelah itu akan **menutup terminal**. Kalau unduhan APK gagal, terminalnya juga langsung tertutup di tengah proses.

`vendorsetup.sh` mengunduh APK microG otomatis saat `envsetup.sh` dijalankan — APK-nya tidak disimpan di dalam repo git. Pastikan koneksi internet aktif pada langkah ini.

### 3d. Alternatif: setel permanen di device tree

Kalau tidak mau mengetik `export` tiap kali, tambahkan ke `device/xiaomi/Mi8937/lineage_Mi8937_4_19.mk`:

```makefile
WITH_GMS := true
```

Ingat ini mengedit repo yang dilacak git — simpan sebagai patch (`git format-patch`) supaya tidak hilang saat `repo sync`.

---

## 4. Yang ikut terpasang

Dari `vendor/partner_gms/products/gms.mk`:

```
GmsCore                      microG Services Core (pengganti Play Services)
GsfProxy                     Google Services Framework proxy
FakeStore                    stub Play Store — supaya app yang mensyaratkannya tidak menolak
FDroid                       toko aplikasi F-Droid
FDroidPrivilegedExtension    supaya F-Droid bisa memasang tanpa konfirmasi manual
additional_repos.xml/json    repo F-Droid tambahan
```

Versi microG saat dokumen ini ditulis: **v0.3.15.250932**.

Modulnya dipasang ke partisi `product` (`LOCAL_PRODUCT_MODULE := true`), lengkap dengan `privapp-permissions-com.google.android.gms.xml` dan `default-permissions-com.google.android.gms.xml` di `product/etc/`.

> **Jangan tertipu nama varian.** `partner_gms.mk` menyebut pilihan `gms_go.mk`, `gms_go_2gb.mk`, dan `gms_minimal.mk` untuk perangkat RAM kecil. Saya cek isinya: `gms_go_2gb.mk` dan `gms_minimal.mk` **hanya berisi `-include $(LOCAL_PATH)/gms.mk`** — persis sama dengan varian penuh. Varian itu ada demi kompatibilitas dengan GApps asli, bukan karena microG punya versi lebih ramping. Jadi tidak ada gunanya menyetel `GMS_MAKEFILE` untuk Redmi 5A.

---

## 5. Dampak ke Partisi

`device/xiaomi/Mi8937/BoardConfig.mk:101-103`:

```makefile
ifneq ($(WITH_GMS),true)
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 838860800 # 800 MB
endif
```

Dengan `WITH_GMS := true`, cadangan 800 MB di partisi `product` **tidak lagi dipesan**. Itu memang masuk akal: cadangan itu ada supaya kamu bisa sideload GApps belakangan, dan sekarang tidak perlu.

Karena microG jauh lebih kecil dari GApps asli, ini kabar bagus untuk super partition 3,75 GB milik Mi8937 — lihat [Tuning RAM & Storage](./TUNING-RAM-Storage-Redmi5A.md).

---

## 6. Verifikasi

### Setelah build

```bash
cd ~/android/lineage-20.0/out/target/product/Mi8937_4_19
ls product/priv-app product/app | grep -iE "gmscore|fakestore|gsfproxy|fdroid"
ls product/etc/permissions/privapp-permissions-com.google.android.gms.xml
```

### Setelah flashing

1. Buka **microG Settings** → **Self-Check**.
2. Baris *"System supports signature spoofing"* harus tercentang **tanpa** kamu memberi izin apa pun secara manual — itulah tanda restricted spoofing bawaan LineageOS bekerja.
3. Aktifkan **Google device registration** dan **Cloud Messaging** kalau butuh notifikasi push.

Kalau baris signature spoofing tidak tercentang, penyebab paling mungkin: APK microG yang terpasang bukan build resmi (misalnya kamu menggantinya dengan hasil kompilasi sendiri).

---

## 7. Kalau Butuh Unrestricted Signature Spoofing

Hanya perlu kalau kamu ingin memakai microG non-resmi, atau aplikasi lain yang butuh memalsukan tanda tangan. Untuk pemakaian microG normal, **lewati bagian ini**.

Patch tersedia di [lineageos4microg/docker-lineage-cicd](https://github.com/lineageos4microg/docker-lineage-cicd/tree/master/src/signature_spoofing_patches):

```bash
mkdir -p ~/patches-microg
B=https://raw.githubusercontent.com/lineageos4microg/docker-lineage-cicd/master/src/signature_spoofing_patches
curl -sS -o ~/patches-microg/fb.patch   $B/android_frameworks_base-Android13.patch
curl -sS -o ~/patches-microg/perm.patch $B/packages_modules_Permission-Android13.patch

# frameworks/base — git apply GAGAL, harus pakai patch dengan fuzz
cd ~/android/lineage-20.0/frameworks/base
patch -p1 --fuzz=5 < ~/patches-microg/fb.patch

# packages/modules/Permission — git apply bersih
cd ~/android/lineage-20.0/packages/modules/Permission
git apply ~/patches-microg/perm.patch
```

Hasil uji saya di tree LineageOS 20 per Juli 2026:

| Patch | `git apply` | `patch -p1 --fuzz=5` |
|---|---|---|
| `android_frameworks_base-Android13.patch` | ❌ gagal di `ComputerEngine.java:1603` | ✅ semua hunk masuk (offset 35/8/55 baris, fuzz 1 pada satu hunk) |
| `packages_modules_Permission-Android13.patch` | ✅ bersih | — |

> `git apply -3` (3-way merge) **tidak bisa dipakai** sebagai jalan pintas: tree yang di-sync dengan `-c --no-tags` tidak menyimpan blob pembanding, dan `git` gagal dengan *"repository lacks the necessary blob to perform 3-way merge"*.

Untuk Android 11 gunakan `android_frameworks_base-R.patch` dan `packages_apps_PermissionController-R.patch`.

Setelah patch, permission `FAKE_PACKAGE_SIGNATURE` muncul di Settings dan harus diberikan manual ke aplikasi yang membutuhkannya.

---

## 8. Ringkasan Keputusan

| Kebutuhan | Yang harus dilakukan |
|---|---|
| microG resmi, terpasang bawaan | Local manifest + `WITH_GMS=true`. **Tanpa patch.** |
| microG dipasang sendiri sebagai APK biasa | Tetap jalan tanpa patch, asal APK resmi |
| microG hasil build sendiri | Perlu patch unrestricted ([Bagian 7](#7-kalau-butuh-unrestricted-signature-spoofing)) |
| App non-microG yang perlu spoofing | Perlu patch unrestricted |
| Google Play Services asli (GApps) | Di luar cakupan dokumen ini — pakai MindTheGapps |

---

## Referensi

- Manifest microG — https://github.com/lineageos4microg/l4m-manifests/blob/main/l4m_gms.xml
- Vendor package — https://github.com/lineageos4microg/android_vendor_partner_gms
- Patch unrestricted — https://github.com/lineageos4microg/docker-lineage-cicd/tree/master/src/signature_spoofing_patches
- Hook LineageOS — `vendor/lineage/config/partner_gms.mk`
- Implementasi restricted spoofing — `frameworks/base/services/core/java/com/android/server/pm/ComputerEngine.java`
