# LineageOS Build Guide — Xiaomi Redmi 5A (`riva`)

Panduan build LineageOS dari source untuk **Xiaomi Redmi 5A** (codename `riva`, MSM8917), berbasis device tree unified **`Mi8937`** dari [Mi-Thorium](https://github.com/Mi-Thorium).

Semua perintah, nama branch, dan path di panduan ini diverifikasi langsung ke repo sumber — bukan disalin dari tutorial lama.

---

## Pilih panduan

| Panduan | Android | Kernel | Patch manual | Enkripsi `/data` | Camera HAL1 |
|---|---|---|---|---|---|
| [LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md) | 13 | 4.9 | tidak ada | ❌ tidak ada | ✅ |
| [LineageOS 20 + kernel 4.19](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md) | 13 | 4.19 | tidak ada | ✅ FBE v2 + metadata | ❌ |
| [LineageOS 18.1](./BUILD-LineageOS-18.1-Redmi5A.md) | 11 | 4.9 | 2 patch wajib | ✅ FDE | ✅ |
| [LineageOS 18.1 + kernel 4.19](./BUILD-LineageOS-18.1-Redmi5A-kernel4.19.md) | 11 | 4.19 | 2 patch wajib | ✅ FBE v2 | ❌ |

### Rekomendasi singkat

- **Mulai dari sini:** [LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md) — paling baru, dan tidak butuh patch manual sama sekali.
- **Butuh `/data` terenkripsi di Android 13:** wajib [kernel 4.19](./BUILD-LineageOS-20-Redmi5A-kernel4.19.md), karena jalur 4.9 di branch `a13` tidak mengenkripsi `/data` sama sekali.
- **Kamera prioritas utama:** tetap di kernel 4.9. Kernel 4.19 mematikan Camera HAL1.

### Panduan tambahan

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

- Persyaratan host, dependency, `repo`, dan ccache
- `repo init` + local manifest Mi-Thorium
- Patch wajib (khusus 18.1) — lengkap dengan penjelasan kenapa dibutuhkan
- **Sync kernel sebagai repo terpisah** — langkah tak terdokumentasi yang paling sering bikin build gagal
- Build, verifikasi pra-build, dan output
- Flashing, termasuk konsekuensi *retrofit dynamic partition*
- Tabel troubleshooting
- Prosedur update source berkala

---

## Tiga jebakan utama

Ringkasan hal yang paling sering menggagalkan build, dijelaskan detail di masing-masing panduan:

1. **Kernel disync terpisah.** Local manifest Mi-Thorium tidak memuat project kernel sama sekali. Kernel ditarik lewat `repo init` bersarang dari [`Mi-Thorium/kernel_manifest`](https://github.com/Mi-Thorium/kernel_manifest) ke `kernel/xiaomi/mithorium-<versi>/`. Tanpa ini, build gagal karena `TARGET_KERNEL_SOURCE` tidak ditemukan.

2. **Pakai `lunch`, bukan `breakfast`/`brunch`.** Keduanya memanggil roomservice yang akan mencari `Mi8937` di GitHub LineageOS, gagal, lalu menimpa local manifest kamu.

3. **Dua patch wajib di LineageOS 18.1.** Tersimpan di `local_manifests/lineage-18.1/` dan harus di-`git am` manual. Di LineageOS 20 keduanya sudah masuk upstream, jadi tidak diperlukan lagi.

---

## Sumber

- [Mi-Thorium](https://github.com/Mi-Thorium) — device tree, vendor blobs, kernel, dan local manifests
- [LineageOS](https://github.com/LineageOS/android) — manifest ROM
- [iusmac](https://github.com/iusmac) — device tree alternatif khusus `rolex`/`riva` (dibahas sebagai alternatif di panduan 18.1)

---

## Disclaimer

Build dan flashing custom ROM menanggung risiko sendiri. Unlock bootloader menghapus semua data, dan skema *retrofit dynamic partition* yang dipakai device tree ini mengubah layout partisi — kembali ke MIUI mengharuskan flash fastboot ROM lengkap. Backup dulu.

Panduan ini tidak berafiliasi dengan Mi-Thorium maupun LineageOS.
