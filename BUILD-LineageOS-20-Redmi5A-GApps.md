# LineageOS 20 + GApps (BiTGApps CORE) — Redmi 5A (`riva`)

> Varian **Google Apps asli**, alternatif dari [microG bawaan](./MICROG-BUILT-IN-Redmi5A.md).
> Pelengkap [`BUILD-LineageOS-20-Redmi5A.md`](./BUILD-LineageOS-20-Redmi5A.md) — build ROM-nya **identik**, yang beda hanya: jangan pakai microG, lalu sideload GApps.

---

## 1. GApps vs microG — perbedaan mendasar

Sebelumnya kita membangun LineageOS 20 dengan **microG bawaan** (`WITH_GMS=true`). Sekarang **Google Play Services asli**. Perbedaannya bukan sekadar paket:

| | microG (build sebelumnya) | GApps (halaman ini) |
|---|---|---|
| Cara masuk | tertanam saat build (`WITH_GMS=true`) | **disideload setelah** build, ke ROM vanilla |
| Tanda tangan | butuh signature spoofing (sudah bawaan LOS) | tanda tangan Google asli — tidak perlu spoofing |
| Ukuran | ~108 MB | CORE ~70 MB |
| Play Integrity | lemah | `basic` lebih mungkin lolos |
| Privasi | tinggi (FOSS) | rendah (Google penuh) |
| Update GApps | ikut ROM | mandiri lewat Play Store |

⚠️ **Jangan campur keduanya.** Kalau kamu pernah build `WITH_GMS=true`, microG sudah tertanam di partisi `product` dan akan bentrok dengan Play Services. Untuk GApps, ROM harus **vanilla** (tanpa microG).

---

## 2. Paket GApps yang dipakai

Diambil dari [BiTGApps](https://github.com/BiTGApps/release/releases) — varian **CORE** (paling ramping, sesuai permintaan) untuk **arm64 Android 13**:

```
BiTGApps-arm64-13.0.0-20260517-105809-CORE.zip   (70 MB)
```

Kenapa spesifik ini:

- **`arm64`** — Mi8937 memakai `core_64_bit.mk` (`lineage_Mi8937.mk:8`), jadi 64-bit. Jangan ambil varian `arm`.
- **`13.0.0`** — LineageOS 20 = Android 13. Cocokkan versi Android, bukan versi LineageOS.
- **`CORE`** — hanya Play Services + Play Store + kerangka minimal. Untuk super partition 3,75 GB Redmi 5A yang sempit, CORE adalah pilihan paling aman. Varian lebih besar (`MINI` 197 MB, `OMNI` 162 MB, `FULL` 401 MB) berisiko tidak muat.

Unduh:

```bash
curl -LO https://github.com/BiTGApps/release/releases/download/20260517-105809-release/BiTGApps-arm64-13.0.0-20260517-105809-CORE.zip
```

> Ada juga add-on terpisah (Gmail, Maps, Photos, Dialer, …) di rilis `-addons` kalau nanti mau menambah tanpa mengganti CORE.

---

## 3. Kenapa Redmi 5A justru cocok untuk GApps sideload

Ini detail device tree yang membuat alur ini bekerja. `device/xiaomi/Mi8937/BoardConfig.mk:101-103`:

```makefile
ifneq ($(WITH_GMS),true)
BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 838860800 # 800 MB
endif
```

Artinya: kalau kamu build **tanpa** `WITH_GMS` (yaitu ROM vanilla untuk GApps), Mi-Thorium otomatis **menyisakan 800 MB kosong** di partisi `product` — persis supaya GApps bisa disideload belakangan. Ruang itu hilang kalau `WITH_GMS=true`.

Jadi build GApps dan build microG saling eksklusif secara desain: satu memakai 800 MB itu untuk cadangan sideload, satunya mengisinya dengan microG.

CORE 70 MB muat lega di dalam 800 MB itu.

---

## 4. Build ROM (vanilla — TANPA microG)

Ikuti [`BUILD-LineageOS-20-Redmi5A.md`](./BUILD-LineageOS-20-Redmi5A.md) langkah 1–7 **persis**, dengan satu perbedaan: **jangan** setel `WITH_GMS`.

```bash
cd ~/android/lineage-20.0
# JANGAN: export WITH_GMS=true   ← itu untuk microG
source build/envsetup.sh
lunch lineage_Mi8937_4_19-userdebug     # atau lineage_Mi8937 untuk kernel 4.9
mka bacon -j$(nproc --all)
```

> Kalau shell-mu masih punya `WITH_GMS=true` dari sesi microG sebelumnya, **buka terminal baru** atau `unset WITH_GMS`. Kalau tidak, kamu diam-diam membangun microG lagi.

Verifikasi ROM vanilla (tidak ada microG):

```bash
ls out/target/product/Mi8937_4_19/product/priv-app | grep -i gmscore
# HARUS kosong. Kalau ada GmsCore, kamu tak sengaja build microG.
```

Local manifest, kernel, dan patch HAL audio **sama persis** dengan build microG — tidak ada yang berubah di sana.

---

## 5. Flashing — GApps di sesi recovery yang sama

**Ini bagian yang kritis.** GApps harus ada **saat boot pertama** supaya Setup Wizard mengenali Google. Sideload GApps **sebelum** reboot pertama, di sesi recovery yang sama dengan ROM.

```bash
# 1. bootloader unlocked, backup data. Kernel 4.19 -> Format Data WAJIB (FBE).
fastboot flash recovery out/target/product/Mi8937_4_19/recovery.img
fastboot reboot recovery

# 2. di recovery: Format Data (ketik "yes"), lalu Wipe System/Cache/Dalvik

# 3. sideload ROM
adb sideload lineage-20.0-<tanggal>-UNOFFICIAL-<id>-Mi8937_4_19.zip

# 4. LANGSUNG sideload GApps — JANGAN reboot dulu
adb sideload BiTGApps-arm64-13.0.0-20260517-105809-CORE.zip

# 5. baru reboot
```

⚠️ **Kalau kamu terlanjur boot sebelum sideload GApps:** Setup Wizard sudah jalan tanpa Google, dan menambahkan GApps belakangan sering bikin `com.google.process.gapps has stopped` berulang. Solusinya: masuk recovery lagi → **Format Data** → sideload ROM + GApps bersama → boot. Tidak bisa ditambal setengah jalan.

Boot pertama 10–20 menit (enkripsi awal + optimasi GApps).

---

## 6. Setelah Boot

1. Setup Wizard akan menampilkan login Google — masuk seperti perangkat normal.
2. Play Store update Play Services sendiri; biarkan beberapa menit.
3. **Sertifikasi Play:** Settings → Apps → Google Play Store → Storage → hapus data, lalu tunggu. Cek status di Play Store → Settings → About → *Play Protect certification*.

Perlu jujur soal batasnya: bootloader kamu **unlocked**, jadi **Play Integrity `STRONG`/`DEVICE` tetap gagal** — ini bukan soal GApps, tapi soal verified boot. `basic` biasanya lolos, cukup untuk sebagian besar aplikasi. Bank/game yang menuntut integrity kuat butuh langkah lain (di luar cakupan halaman ini).

---

## 7. Update ROM tanpa kehilangan GApps

BiTGApps memasang skrip `addon.d` yang **menyelamatkan GApps saat dirty-flash update ROM**. Jadi update LineageOS berikutnya (sideload ZIP ROM baru saja, tanpa Format Data) akan mempertahankan GApps otomatis.

Kalau setelah update GApps hilang, sideload ulang ZIP CORE di sesi recovery yang sama seperti [Bagian 5](#5-flashing--gapps-di-sesi-recovery-yang-sama).

---

## 8. Kombinasi dengan root

GApps + ReSukiSU bisa berdampingan — flash ROM, GApps, lalu kernel root ([`RESUKISU-Redmi5A.md`](./RESUKISU-Redmi5A.md)) di sesi yang sama, atau kernel-only zip belakangan.

Catatan: Play Services asli **lebih agresif** mendeteksi root daripada microG. Kalau kamu pakai GApps **dan** root **dan** ingin aplikasi sensitif jalan, susfs + Zygisk/Shamiko jadi lebih relevan — lihat [`RESUKISU-Redmi5A.md`](./RESUKISU-Redmi5A.md) Bagian 9.

---

## 9. Ringkasan pilihan Google-services

| Kebutuhan | Pilih |
|---|---|
| Privasi, FOSS, ringan | [microG](./MICROG-BUILT-IN-Redmi5A.md) |
| Play Store asli, kompatibilitas app maksimal | **BiTGApps CORE** (halaman ini) |
| Play Store asli + aplikasi & fitur Google lengkap | BiTGApps MINI/OMNI — **cek muat** di super 3,75 GB dulu |

---

## Referensi

- BiTGApps rilis — https://github.com/BiTGApps/release/releases
- Paket CORE arm64 13 — `BiTGApps-arm64-13.0.0-20260517-105809-CORE.zip`
- Cadangan partisi GApps — `device/xiaomi/Mi8937/BoardConfig.mk:101-103`
- Build ROM dasar — [`BUILD-LineageOS-20-Redmi5A.md`](./BUILD-LineageOS-20-Redmi5A.md)
