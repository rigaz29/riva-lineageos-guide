# ROM Siap Flash — Redmi 5A (`riva`)

> **Belum satupun pernah di-boot di perangkat.** Keduanya kompilasi bersih dan isinya sudah diverifikasi, tapi "build sukses" bukan bukti perangkat menyala. Flash dengan asumsi bisa bootloop.

Tanggal build: **26 Juli 2026** · Target: `lineage_Mi8937_4_19-userdebug` · Kernel **4.19.325**

---

## Isi folder

| Berkas | Ukuran | Isi |
|---|---|---|
| `ROM-A_resukisu-root_microg.zip` | 967 MiB | LineageOS 20 + **ReSukiSU (root)** + microG |
| `ROM-B_tanpa-root_microg.zip` | 967 MiB | LineageOS 20 + microG, **tanpa root** |
| `recovery.img` | 30 MiB | Recovery LineageOS untuk Mi8937 |
| `boot-ROM-A.img` | 22 MiB | boot.img milik ROM-A (cadangan, bukan untuk flash terpisah) |
| `*.sha256` | — | Checksum tiap berkas |

Verifikasi sebelum flash:

```bash
sha256sum -c ROM-A_resukisu-root_microg.zip.sha256
```

---

## Mana yang harus dicoba dulu

**Mulai dari `ROM-B` (tanpa root).**

Alasannya: ROM-B lebih sedikit variabelnya. Kalau ROM-B boot, kamu tahu dasarnya — device tree, kernel 4.19, vendor blob, microG — semuanya sehat. Kalau ROM-B saja bootloop, mencoba ROM-A tidak ada gunanya karena masalahnya bukan di root.

Baru setelah ROM-B terbukti menyala, coba `ROM-A` untuk menambahkan root.

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
