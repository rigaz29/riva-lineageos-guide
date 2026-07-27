# LineageOS Build Guide — Xiaomi Redmi 5A (`riva`)

Panduan build LineageOS dari source untuk **Xiaomi Redmi 5A** (codename `riva`, MSM8917), berbasis device tree unified **`Mi8937`** dari [Mi-Thorium](https://github.com/Mi-Thorium).

Semua perintah, nama branch, dan path di panduan ini diverifikasi langsung ke repo sumber — bukan disalin dari tutorial lama.

> ✅ **Terbukti di perangkat.** ROM hasil panduan ini — LineageOS 20, kernel 4.19, microG bawaan, root ReSukiSU — sudah berhasil boot di Redmi 5A pada 26 Juli 2026.

---

## Pilih panduan

| Panduan | Android | Kernel | Patch manual | Enkripsi `/data` | Camera HAL1 |
|---|---|---|---|---|---|
| [LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md) | 13 | 4.9 | 1 (HAL audio) | ❌ tidak ada | ✅ |
| [LineageOS 20 + kernel 4.19](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md) | 13 | 4.19 | 1 (HAL audio) | ✅ FBE v2 + metadata | ❌ |
| [LineageOS 18.1](./BUILD-LineageOS-18.1-Redmi5A.md) | 11 | 4.9 | 2 wajib | ✅ FDE | ✅ |
| [LineageOS 18.1 + kernel 4.19](./BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md) | 11 | 4.19 | 2 wajib | ✅ FBE v2 | ❌ |

### Rekomendasi singkat

- **Mulai dari sini:** [LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md) — paling baru, dan tidak butuh dua patch Mi-Thorium yang wajib di 18.1.
- **Butuh `/data` terenkripsi di Android 13:** wajib [kernel 4.19](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md), karena jalur 4.9 di branch `a13` tidak mengenkripsi `/data` sama sekali.
- **Kamera prioritas utama:** tetap di kernel 4.9. Kernel 4.19 mematikan Camera HAL1.

### Panduan tambahan

- **[microG Bawaan (opsional)](./MICROG-BUILT-IN-Redmi5A.md)** — pasang microG langsung ke dalam ROM sebagai pengganti Google Play Services. LineageOS 18.1+ sudah punya *restricted signature spoofing* bawaan, jadi **tidak perlu patch `frameworks/base`** sama sekali.
- **[ReSukiSU (opsional, direkomendasikan)](./RESUKISU-Redmi5A.md)** — root berbasis kernel. Fork SukiSU dengan validator hook yang memberi pesan jelas dan kode yang sehat di kernel <5.10. Butuh 4 penyesuaian kernel, semuanya terdokumentasi dan otomatis lewat skrip.
- **[SukiSU-Ultra (opsional)](./SUKISU-ULTRA-Redmi5A.md)** — root berbasis kernel. Titik hook bawaan Mi-Thorium cocok dengan branch `builtin` SukiSU, jadi tidak perlu mengedit source kernel — tapi branch itu butuh 2 tambalan agar kompilasi di kernel <5.10, dan **susfs tidak bisa dipakai** di 4.19.
- **[Kernel-only ZIP](./scripts/make-anykernel-zip.sh)** — bikin flashable kernel AnyKernel3 (~21 MB) untuk menguji perubahan kernel tanpa build ROM penuh dan tanpa wipe data.
- **[Tuning RAM & Storage](./TUNING-RAM-Storage-Redmi5A.md)** — apakah perlu konfigurasi Android Go? (jawabannya: tidak), apa yang sudah disetel device tree, tuning selektif yang direkomendasikan, dan cara menyiasati super partition 3,75 GB.

---

## Device yang dicakup

Device tree `Mi8937` bersifat unified — satu ZIP jalan untuk 7 device, dan varian dideteksi saat boot:

| Codename | Device |
|---|---|
| `land` | Redmi 3S / 3X |
| `prada` | Redmi 4 Standard |
| `rolex` | Redmi 4A |
| `santoni` | Redmi 4X |
| **`riva`** | **Redmi 5A** |
| `ugglite` | Redmi Note 5A / Y1 Lite |
| `ugg` | Redmi Note 5A / Y1 Prime |

Panduan ini ditulis dari sudut pandang `riva`, tapi seluruh langkah build berlaku sama untuk keenam device lainnya.

---

## Yang dibahas

Setiap panduan mencakup satu alur penuh dari nol sampai ZIP siap flash:

- Persyaratan host, dependency, `repo`, dan ccache — termasuk **rincian disk hasil pengukuran nyata**
- `repo init` + local manifest Mi-Thorium
- Patch wajib (khusus 18.1) — lengkap dengan penjelasan kenapa dibutuhkan
- **Sync kernel sebagai repo terpisah** — langkah tak terdokumentasi yang paling sering bikin build gagal
- Build, verifikasi pra-build, dan output
- Flashing, termasuk konsekuensi *retrofit dynamic partition*
- Tabel troubleshooting
- Prosedur update source berkala

---

## Lima jebakan utama

Ringkasan hal yang paling sering menggagalkan build, dijelaskan detail di masing-masing panduan:

1. **Kernel disync terpisah — dan TIDAK boleh bersarang.** Local manifest Mi-Thorium tidak memuat project kernel sama sekali; kernel ditarik dari [`Mi-Thorium/kernel_manifest`](https://github.com/Mi-Thorium/kernel_manifest). Tapi `repo` tidak mendukung nested checkout — `repo init` di dalam tree ROM akan menimpa manifest ROM kamu. Init di luar, lalu `mv -T` ke `kernel/xiaomi/mithorium-<versi>/`.

2. **Pakai `lunch`, bukan `breakfast`/`brunch`.** Keduanya memanggil roomservice yang akan mencari `Mi8937` di GitHub LineageOS, gagal, lalu menimpa local manifest kamu.

3. **Dua patch wajib di LineageOS 18.1.** Tersimpan di `local_manifests/lineage-18.1/` dan harus di-`git am` manual. Di LineageOS 20 keduanya sudah masuk upstream.

4. **`repo init` wajib pakai `--git-lfs`.** Prebuilt WebView LineageOS disimpan lewat Git LFS. Tanpa flag ini `webview.apk` hanya berisi pointer 134 byte dan build gagal jauh di belakang dengan `zip: not a valid zip file`.

5. **HAL audio Mi-Thorium tidak kompilasi apa adanya.** Commit tip `a3ff9d54` (Agu 2025) memakai parameter `void*` tanpa nama — ekstensi C23 yang ditolak clang di bawah `-Werror`. Build gagal ~1 jam setelah dimulai. Patch-nya ada di [`patches/`](./patches).

---

## Sumber

- [Mi-Thorium](https://github.com/Mi-Thorium) — device tree, vendor blobs, kernel, dan local manifests
- [LineageOS](https://github.com/LineageOS/android) — manifest ROM
- [iusmac](https://github.com/iusmac) — device tree alternatif khusus `rolex`/`riva` (dibahas sebagai alternatif di panduan 18.1)

---

## Disclaimer

Build dan flashing custom ROM menanggung risiko sendiri. Unlock bootloader menghapus semua data, dan skema *retrofit dynamic partition* yang dipakai device tree ini mengubah layout partisi — kembali ke MIUI mengharuskan flash fastboot ROM lengkap. Backup dulu.

Panduan ini tidak berafiliasi dengan Mi-Thorium maupun LineageOS.
