# LineageOS 20 + GApps **built-in** — Redmi 5A (`riva`)

> Google Play Services asli **tertanam saat build** (bukan disideload), analog dengan [microG bawaan](./MICROG-BUILT-IN-Redmi5A.md).
> Status: **terbukti build sukses** — GmsCore + Phonesky + GSF + sync adapter masuk ke ROM. Boot & Play Services jalan hanya bisa dibuktikan di perangkat.
>
> Otomatis: [`scripts/setup-gapps-core.sh`](./scripts/setup-gapps-core.sh)

---

## 1. Kenapa BiTGApps CORE tidak bisa built-in (dan apa yang dipakai)

Awalnya sasarannya BiTGApps CORE. Saya bongkar paketnya sampai isinya — **BiTGApps adalah installer, bukan vendor tree**:

```
installer.sh (30 KB)  ·  META-INF/update-binary  ·  tar/core/*.tar.xz
NOL Android.mk / Android.bp
```

Ia bekerja dengan mengekstrak tarball saat flash. Tidak bisa `mka`-include. Hal yang sama berlaku untuk OpenGApps dan repo `vendor_gapps` MindTheGapps (itu pembangun-zip, `make gapps_arm64`).

**Yang bisa built-in** adalah branch **`tau`** MindTheGapps — vendor tree siap-`mka` dengan `Android.bp` (`android_app_import`), makefile, dan `proprietary/` tertata per partisi. Itu jalur built-in GApps standar LineageOS.

Tapi set penuh MindTheGapps ~900 MB (Velvet/Google Search 361 MB saja) — **tidak muat** di super partition 3,75 GB Redmi 5A. Solusinya: **struktur MindTheGapps + subset paket inti saja**.

---

## 2. Kunci arsitektur: Soong hanya pasang yang di `PRODUCT_PACKAGES`

Ini yang membuat trimming bersih dan tanpa risiko.

MindTheGapps mendefinisikan **semua** paket di `Android.bp`. Tapi Soong hanya **memasang** modul yang disebut di `PRODUCT_PACKAGES`. Jadi kita tulis makefile core-only yang menyebut 7 paket — Velvet, SpeechServices, talkback, dll. tetap ada di tree tapi **tidak ikut ke ROM**. **Tidak perlu menyentuh `Android.bp` sama sekali.**

Footprint inti (arm64):

| Paket | Ukuran | Lokasi |
|---|---|---|
| GmsCore (Play Services) | 111 MB | `product/priv-app` |
| Phonesky (Play Store) | 60 MB | `product/priv-app` |
| GoogleServicesFramework | ~7 MB | `system_ext/priv-app` |
| GoogleCalendar/ContactsSyncAdapter | kecil | `product/app` |
| **Total** | **~180 MB** | muat di cadangan 800 MB |

---

## 3. Pemasangan

```bash
./scripts/setup-gapps-core.sh ~/android/lineage-20.0
```

Skrip ini:
1. Clone MindTheGapps `tau` → `vendor/gapps`, buang arch lain + tooling zip (hemat ~1,3 GB)
2. Tulis `vendor/gapps/gapps-core.mk` (7 paket inti + XML izin/sysconfig)
3. Wire lewat `WITH_GMS` — buang microG (`microg.xml` + `vendor/partner_gms`), ganti `vendor/partner_gms/products/gms.mk` → inherit `gapps-core.mk`
4. Verifikasi GmsCore `presigned` + `privileged` (kalau tidak → FC saat boot)

### Wiring: sama persis dengan microG

`WITH_GMS=true` memicu `partner_gms.mk` LineageOS meng-inherit `vendor/partner_gms/products/gms.mk`. Bonus: `WITH_GMS=true` juga **menghapus cadangan `product` 800 MB** (`BoardConfig.mk:101`), membebaskan ruang untuk GApps.

Jadi GApps dan microG dipilih dari **saklar yang sama** (`WITH_GMS`), cuma isi `vendor/partner_gms` yang berbeda.

---

## 4. Build

```bash
cd ~/android/lineage-20.0
export WITH_GMS=true              # WAJIB — ini yang menarik GApps
source build/envsetup.sh && set +e
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

> **Patch HAL audio.** Kalau source baru di-`repo sync` atau di-revert, terapkan ulang `patches/0001-audio-extn-Name-the-unused-pthread-parameters.patch` di `hardware/mithorium/audio/.../hal` — kalau tidak, build gagal di `libcirrusspkrprot` (bukan soal GApps).

Verifikasi GApps masuk ROM:

```bash
ls out/target/product/Mi8937_4_19/product/priv-app | grep -E "GmsCore|Phonesky"
ls out/target/product/Mi8937_4_19/system_ext/priv-app | grep GoogleServicesFramework
```

Build sukses = **muat** — `mka bacon` gagal kalau partisi kelebihan.

---

## 5. GApps vs microG vs sideload

| | microG built-in | **GApps built-in (ini)** | GApps sideload |
|---|---|---|---|
| Cara | `WITH_GMS=true` + microG tree | `WITH_GMS=true` + MindTheGapps core | ROM vanilla + flash BiTGApps zip |
| Tanda tangan | signature spoofing | Google asli | Google asli |
| Footprint | ~108 MB | ~180 MB | ~70–200 MB |
| Update | ikut ROM | mandiri via Play Store | mandiri via Play Store |
| Keandalan | terbukti | terbukti build | paling andal (installer resmi) |
| Privasi | tinggi (FOSS) | rendah | rendah |

Sideload tetap opsi paling andal (installer BiTGApps resmi menangani semua kasus). Built-in praktis kalau kamu ingin GApps menyatu dengan ROM dan tidak perlu sideload terpisah tiap flash.

---

## 6. Setelah Flashing

Tidak perlu sideload GApps terpisah — sudah di dalam ROM. Boot, Setup Wizard menampilkan login Google, masuk seperti biasa.

⚠️ Bootloader **unlocked** → **Play Integrity `STRONG`/`DEVICE` tetap gagal** (soal verified boot, bukan GApps). `basic` biasanya lolos. Cek: Play Store → Settings → About → *Play Protect certification*.

---

## 7. Batas & kejujuran

- **Belum diuji boot.** Verifikasi berhenti di "GApps masuk ROM & kompilasi bersih". Memakai makefile MindTheGapps yang terbukti menurunkan risiko drastis dibanding hand-authoring, tapi tetap bukan jaminan.
- Kalau GmsCore FC saat boot pertama, tersangka utama: privapp-permissions XML kurang. Skrip sudah menyertakan `privapp-permissions-google-product.xml` + `system-ext`, yang seharusnya cukup untuk set core ini.
- `vendor/gapps` (~910 MB) **tidak** masuk repo panduan — hanya skrip reproduksinya. APK Google tidak boleh redistribusi.

---

## Referensi

- MindTheGapps `tau` — https://gitlab.com/MindTheGapps/vendor_gapps (branch `tau` = Android 13)
- Struktur `android_app_import` — `vendor/gapps/arm64/Android.bp`
- Wiring `WITH_GMS` — `vendor/lineage/config/partner_gms.mk`
- Cadangan partisi — `device/xiaomi/Mi8937/BoardConfig.mk:101-103`
- Referensi belajar — [NikGApps](https://github.com/nikgapps) · [OpenGApps](https://github.com/opengapps) · [MindTheGapps](https://gitlab.com/MindTheGapps)
