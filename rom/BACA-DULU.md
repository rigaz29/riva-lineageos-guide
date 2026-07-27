# ROM Siap Flash — Redmi 5A (`riva`)

> **ROM-A terbukti boot di perangkat.** ROM-B belum diuji.
>
> ROM-A adalah build ulang (27 Juli 2026) dengan versi ReSukiSU diperbaiki 30701 → **35032**; versi lama ditolak manager. **Manager sudah mengonfirmasi 35032**, jadi root berfungsi. Penyebab versi salah: shallow clone — lihat [`../RESUKISU-Redmi5A.md`](../RESUKISU-Redmi5A.md) Bagian 4e.
>
> `KERNEL-ONLY` sudah terbukti terpasang, dan **kernel susfs v2.2.0 juga sudah terbukti boot** — manager melaporkan susfs v2.2.0 dengan sembilan fitur aktif.
>
> ⚠️ Berkas `boot-*.img` di sini adalah **salinan nyata**, bukan hardlink. `mka bootimage` menulis `out/.../boot.img` di tempat, jadi hardlink ke sana akan ikut berubah tiap build — cadangan yang tidak menyelamatkan.
>
> Yang terbukti barulah sistem menyala. Fungsi root, microG, kamera, dan radio belum diverifikasi satu per satu.

Tanggal build: **26 Juli 2026** · Target: `lineage_Mi8937_4_19-userdebug` · Kernel **4.19.325**

---

## Isi folder

| Berkas | Ukuran | Isi |
|---|---|---|
| `ROM-A_resukisu-root_microg.zip` | 967 MiB | LineageOS 20 + **ReSukiSU (root)** + microG |
| `ROM-B_tanpa-root_microg.zip` | 967 MiB | LineageOS 20 + microG, **tanpa root** |
| `KERNEL-ONLY_resukisu-susfs_4.19.zip` | 21 MiB | **Kernel + susfs v2.2.0** (AnyKernel3) · ✅ terbukti boot |
| `boot-resukisu-susfs.img` | 22 MiB | Sama, untuk `fastboot flash boot` · ✅ terbukti boot |
| `KERNEL-ONLY_resukisu_4.19.zip` | 21 MiB | Kernel tanpa susfs (AnyKernel3) · ✅ terbukti |
| `boot-ROM-A.img` | 22 MiB | Kernel tanpa susfs, cadangan `fastboot` |
| `recovery.img` | 30 MiB | Recovery LineageOS untuk Mi8937 |
| `boot-ROM-A.img` | 22 MiB | boot.img milik ROM-A (cadangan, bukan untuk flash terpisah) |
| `*.sha256` | — | Checksum tiap berkas |

Verifikasi sebelum flash:

```bash
sha256sum -c ROM-A_resukisu-root_microg.zip.sha256
```

---

## Mana yang harus dicoba dulu

**`ROM-A` — sudah terbukti boot.**

Saran awal di dokumen ini adalah mencoba ROM-B dulu karena variabelnya lebih sedikit. Ternyata ROM-A langsung berhasil, jadi urutan itu tidak lagi relevan: ROM-A sekaligus membuktikan seluruh dasarnya sehat — device tree `Mi8937` branch `a13`, kernel 4.19.325, vendor blob, skema *retrofit dynamic partition*, enkripsi FBE v2, patch HAL audio, dan integrasi ReSukiSU.

`ROM-B` tetap berguna sebagai jalan mundur kalau ada masalah yang dicurigai berasal dari root.

---

## Cara identitasnya dipastikan

Bukan dari nama berkas atau tanggal, melainkan dari isi kernel di dalam `boot.img` — di-ekstrak dari ZIP, kernelnya di-dekompresi dari gzip, lalu dihitung simbolnya:

```
ROM-A : 175 kemunculan "ksu_"  → root ada
ROM-B :   0 kemunculan "ksu_"  → tanpa root
```

Keduanya berukuran ~1.014 GB, sedangkan build tanpa microG hanya 907 MB. Selisih ~108 MB itu paket microG. Untuk ROM-A, keberadaan microG sudah diverifikasi langsung saat build (`GmsCore`, `GsfProxy`, `FakeStore`, `FDroid`, `FDroidPrivilegedExtension` di partisi `product`); untuk ROM-B disimpulkan dari ukuran.

---

## Langkah flashing

⚠️ **Format Data wajib.** Kernel 4.19 memakai enkripsi FBE v2 + metadata encryption. Dirty-flash dari ROM lama pasti bootloop.

```bash
# 1. bootloader sudah unlocked, backup semua data dulu
fastboot flash recovery recovery.img
fastboot reboot recovery

# 2. di recovery: Format Data (ketik "yes"), lalu Wipe System/Cache/Dalvik

# 3. sideload
adb sideload ROM-B_tanpa-root_microg.zip
```

Boot pertama **10–20 menit** — enkripsi awal berjalan di latar. Jangan buru-buru menyimpulkan bootloop sebelum 20 menit.

Skema partisinya *retrofit dynamic partition* (`cust` + `system` digabung jadi super 3,75 GB), jadi kembali ke MIUI mengharuskan flash **fastboot ROM MIUI lengkap**, bukan ZIP recovery.

---

## Catatan tentang `recovery.img`

Tertanggal 13:07, dari build lebih awal — **bukan** dari build ROM-A/B. Secara fungsional tetap valid karena `fstab` tidak berubah di antara build-build itu. Kalau ingin yang segar:

```bash
cd ~/android/lineage-20.0
source build/envsetup.sh && set +e
lunch lineage_Mi8937_4_19-userdebug
mka recoveryimage
```

---

## Setelah ROM-A boot

Pasang manager root. ReSukiSU mendukung multi-manager (`CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`), jadi manager KernelSU resmi, RKSU, MKSU, atau SukiSU semuanya bisa — atau [manager ReSukiSU sendiri](https://github.com/ReSukiSU/ReSukiSU/releases).

**susfs tidak tersedia** di ROM-A. Untuk menyembunyikan root, pakai Zygisk/Shamiko lewat manager. Alasan lengkapnya ada di [`../RESUKISU-Redmi5A.md`](../RESUKISU-Redmi5A.md).

---

## Kalau bootloop

1. Masuk recovery → **Format Data** lagi
2. Sideload ROM yang lain (kalau ROM-A gagal, coba ROM-B)
3. Kalau dua-duanya gagal, kembali ke MIUI lewat fastboot ROM lengkap

Berkas di folder ini adalah **hardlink** ke `out/` dan `/root`, jadi tidak memakan disk tambahan. Tapi artinya juga: jangan hapus salah satu dengan asumsi yang lain jadi cadangan — keduanya menunjuk data yang sama. Untuk arsip sungguhan, salin ke media di luar mesin ini.
