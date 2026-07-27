# ReSukiSU — Redmi 5A (`riva`)

> **Opsional.** Root berbasis kernel, ditanam saat build. Untuk target **kernel 4.19** (`lineage_Mi8937_4_19`).
>
> Status: **terverifikasi di perangkat** (27 Juli 2026). ROM boot, dan **manager mengenali kernel di versi 35032** — artinya driver KSU hidup dan merespons. Kernel: `Image.gz-dtb` 19,8 MB, 221 simbol `ksu_*` di `System.map`.

---

## 1. Ringkasan

| | |
|---|---|
| Yang dipasang | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) branch `main` |
| Metode hook | **Manual Hook** + 3 auto-hook LSM |
| Penyesuaian kernel | **4 titik** — [Bagian 4](#4-empat-penyesuaian-kernel) |
| Jebakan versi | **jangan `--depth 1`** — [Bagian 4e](#4e-️-jangan-clone-dengan---depth-1) |
| susfs | belum diaktifkan — langkah terpisah |
| Otomatisasi | [`scripts/setup-resukisu.sh`](./scripts/setup-resukisu.sh) |

---

## 2. ReSukiSU vs SukiSU-Ultra

ReSukiSU adalah fork SukiSU-Ultra (Des 2025). Saya mencoba **keduanya** di perangkat ini; berikut perbandingan berdasarkan pengalaman nyata, bukan klaim README.

| | SukiSU-Ultra `builtin` | ReSukiSU `main` |
|---|---|---|
| Dukungan kernel | 4.14+ | 3.4+ |
| Opsi hook di Kconfig | **tidak ada** (docs menyebut, kode tidak) | `KSU_MANUAL_HOOK`, `KSU_TRACEPOINT_HOOK`, `KSU_SUSFS` |
| Bug internal di kernel <5.10 | **2** — harus ditambal sendiri | 0 |
| Penyesuaian kernel dibutuhkan | 0 (simbol kebetulan cocok) | **4** (terdokumentasi resmi) |
| Cara gagal | puluhan `implicit declaration` | **validator menyebut hook yang kurang + tautan panduan** |
| Percobaan sampai lolos | 2 | 3 |
| Simbol `ksu_*` di System.map | 180 | **225** |
| Ekstra | – | multi-manager, metamodules, dynamic manager |

**Kesimpulan:** SukiSU terasa lebih mudah di awal karena simbolnya kebetulan cocok dengan hook Mi-Thorium, tapi kodenya sendiri rusak untuk kernel <5.10. ReSukiSU menuntut lebih banyak penyesuaian, tapi setiap tuntutannya jelas dan kodenya sehat. Klaim *"build easily"* di README-nya benar — bukan karena langkahnya lebih sedikit, melainkan karena kegagalannya bisa ditindaklanjuti.

---

## 3. Prasyarat

Semua sudah terpenuhi di kernel Mi-Thorium 4.19:

| Syarat | Status |
|---|---|
| `CONFIG_KALLSYMS_ALL=y` | ✅ — membebaskan dari mengekspor ~8 simbol SELinux manual |
| Kernel < 6.8 | ✅ 4.19.325 — syarat auto-hook LSM |
| arm64 | ✅ |

---

## 4. Empat Penyesuaian Kernel

Akar semuanya sama: **titik hook bawaan Mi-Thorium ditulis untuk KernelSU generasi lama.**

Semuanya ada di [`patches/0003-kernel-Adapt-KSU-static-hooks-for-ReSukiSU.patch`](./patches).

### 4a. `fs/read_write.c` — hapus hook `vfs_read`

ReSukiSU **menolak build** kalau string `ksu_vfs_read_hook` ada:

```make
$(call check_ksu_hook_incompatible,ksu_vfs_read_hook,$(srctree)/fs/read_write.c)
```

Jalur `read()` ditangani `CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK` lewat LSM, jadi hook manualnya memang tidak diperlukan.

### 4b. `fs/stat.c` — tambah hook return-value

`manual_hook_check.mk` menuntut dua hook yang Mi-Thorium tidak punya:

```c
#ifdef CONFIG_KSU_MANUAL_HOOK
	ksu_handle_newfstat_ret(&fd, &statbuf);   // di SYSCALL_DEFINE2(newfstat)
	ksu_handle_fstat64_ret(&fd, &statbuf);    // di SYSCALL_DEFINE2(fstat64)
#endif
```

> ⚠️ `cp_new_stat64` muncul **3×** di `fs/stat.c` (fstat64, fstatat64, stat64). Pencocokan pola sederhana akan salah sasaran — targetkan per-fungsi.

### 4c. `kernel/reboot.c` — tambah hook `sys_reboot`

```c
#ifdef CONFIG_KSU_MANUAL_HOOK
	ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);
#endif
```

Diletakkan setelah deklarasi variabel di `SYSCALL_DEFINE4(reboot)`, sebelum pemeriksaan kapabilitas.

### 4d. `fs/exec.c` — buang toggle dan cabang `_sucompat`

Kode Mi-Thorium memakai pola KernelSU klasik:

```c
if (unlikely(ksu_execveat_hook))
    ksu_handle_execveat(...);
else
    ksu_handle_execveat_sucompat(...);
```

Dua-duanya bermasalah:

- `ksu_execveat_hook` — toggle itu **tidak ada** di ReSukiSU
- `ksu_handle_execveat_sucompat` — ada, tapi digerbangi `#ifdef CONFIG_KSU_SUSFS`; komentar sumbernya menjelaskan itu memang khusus jalur susfs

Keduanya menyebabkan `ld.lld: error: undefined symbol`. Perbaikannya: panggil `ksu_handle_execveat()` tanpa syarat, sesuai panduan ReSukiSU untuk kernel 3.14+.

---

## 4e. ⚠️ Jangan clone dengan `--depth 1`

Bukan penyesuaian kernel, tapi jebakan yang paling mahal — hanya ketahuan setelah ROM di-flash.

Versi KernelSU dihitung dari **jumlah commit** (`kernel/Kbuild`):

```make
KSU_LOCAL_VERSION := $(shell git rev-list --count HEAD)
KSU_VERSION := $(shell expr 30000 + $(KSU_LOCAL_VERSION) + 700)
```

Shallow clone membuat hitungannya `1`, sehingga versi jadi **30701**. Kernel tetap kompilasi bersih, ROM tetap boot — lalu manager menolak bekerja:

> *"the current kernelsu version 30701 is too low for manager to work properly. please upgrade to version 35032 or higher!"*

Dengan clone penuh, 4.332 commit menghasilkan **35032** — tepat memenuhi syarat.

```bash
git clone -b main https://github.com/ReSukiSU/ReSukiSU.git $K/KernelSU   # TANPA --depth
```

Riwayat git di sini **load-bearing**, bukan keborosan. Skrip repo ini memverifikasinya dan berhenti kalau versinya di bawah 35032.

---

## 5. Pemasangan

```bash
./scripts/setup-resukisu.sh ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel

cd ~/android/lineage-20.0/device/xiaomi/Mi8937
git am /path/ke/patches/0004-Mi8937-Enable-ReSukiSU-kernel-config.patch

cd ~/android/lineage-20.0
source build/envsetup.sh && set +e
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

Skrip ini idempoten, menerapkan patch 0003 otomatis, dan memverifikasi **keenam hook** plus **ketiga cek incompatible** sebelum kamu membuang waktu build.

Konfigurasi yang ditulis:

```
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK=y   # LSM, sah untuk kernel <6.8
CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK=y   # menggantikan hook sys_read
CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK=y
CONFIG_KSU_STATIC_HOOKS=y                   # titik hook Mi-Thorium
# CONFIG_KSU_SUSFS is not set
```

---

## 5b. Kernel-only ZIP (AnyKernel3)

Untuk iterasi kernel tanpa membangun ulang ROM 967 MB dan **tanpa wipe data**:

```bash
./scripts/make-anykernel-zip.sh
# → rom/KERNEL-ONLY_resukisu_4.19.zip (~21 MB)
adb sideload KERNEL-ONLY_resukisu_4.19.zip
```

[AnyKernel3](https://github.com/osm0sis/AnyKernel3) membongkar `boot.img` yang sudah ada di perangkat, menukar kernelnya, lalu mengemas ulang — ramdisk dan konfigurasi lain tetap utuh. Siklus uji kernel turun dari ~1 jam ke beberapa menit.

### Yang perlu disesuaikan untuk msm8937

**Path partisi boot.** `split_boot()` membatalkan instalasi kalau `$BLOCK` tidak ada:

```sh
if [ ! -e "$BLOCK" ]; then abort "Invalid partition. Aborting..."; fi
```

Path perangkat kerasnya `/dev/block/platform/soc/7824900.sdhci/by-name/`. Symlink `bootdevice` memang dibuat `init.xiaomi.rc`, tapi **hanya untuk `modemst1`, `modemst2`, `fsc`, `fsg`** — tidak termasuk `boot`. Sementara `/dev/block/by-name/` yang dipakai fstab belum tentu ada di recovery.

Karena itu skrip memprobe berurutan, bukan menebak satu path — **sudah terbukti bekerja di Redmi 5A**:

```sh
for _b in /dev/block/bootdevice/by-name/boot \
          /dev/block/platform/soc/7824900.sdhci/by-name/boot \
          /dev/block/by-name/boot; do
  [ -e "$_b" ] && BLOCK=$_b && break;
done;
```

**Device check** menerima kesembilan codename Mi8937 (`riva`, `rolex`, `santoni`, `land`, `prada`, `ugg`, `ugglite`, `Mi8937`, `Mi8937_4_19`), jadi tidak ditolak karena variasi `ro.product.device`.

> 💡 Jebakan skrip: jangan verifikasi isi ZIP dengan `unzip -l "$OUT" | grep -q "$f"` di bawah `set -o pipefail`. `grep -q` keluar di kecocokan pertama, `unzip` kena SIGPIPE, dan pipeline dianggap gagal — sehingga **hanya entri paling awal di listing** yang salah dilaporkan hilang. Ambil listing ke berkas dulu, baru grep.

---

## 6. Yang Divalidasi ReSukiSU

Berguna diketahui sebelum build, karena `manual_hook_check.mk` menghentikan build lebih awal kalau ada yang kurang:

**Wajib ada:**

| Simbol | File |
|---|---|
| `ksu_handle_execveat` | `fs/exec.c` |
| `ksu_handle_faccessat` | `fs/open.c` |
| `ksu_handle_stat` | `fs/stat.c` |
| `ksu_handle_newfstat_ret` | `fs/stat.c` |
| `ksu_handle_fstat64_ret` | `fs/stat.c` |
| `ksu_handle_sys_reboot` | `kernel/reboot.c` |

**Wajib TIDAK ada:** `ksu_vfs_read_hook` (`fs/read_write.c`), `is_ksu_transition` (`security/selinux/hooks.c`), `ksu_handle_rename` (`security/security.c`)

**Dilewati karena auto-hook aktif:** `ksu_handle_setresuid`, `ksu_handle_sys_read`, `ksu_handle_input_handle_event`

---

## 7. `repo sync` menghapus semuanya

```bash
(cd kernel/xiaomi/mithorium-4.19 && repo sync -c -j$(nproc --all) --no-tags)
./scripts/setup-resukisu.sh
cd device/xiaomi/Mi8937 && git am /path/ke/patches/0004-Mi8937-Enable-ReSukiSU-*.patch
```

Jangan lupa patch HAL audio juga — lihat [panduan LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md).

---

## 8. Setelah Flashing

Pasang **manager**-nya. ReSukiSU mendukung multi-manager (`CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`), jadi manager KernelSU resmi, RKSU, MKSU, maupun SukiSU bisa dipakai — atau [manager ReSukiSU sendiri](https://github.com/ReSukiSU/ReSukiSU/releases).

✅ ROM hasil konfigurasi ini **sudah terbukti boot** di Redmi 5A. Tetap backup ZIP lama sebelum flashing.

---

## 9. susfs

Belum diaktifkan di sini. Di ReSukiSU, `CONFIG_KSU_SUSFS` adalah **metode hook tersendiri** ("SuSFS Inline Hook") yang menggantikan Manual Hook, bukan tambahan di atasnya — dan tetap memerlukan patch susfs4ksu di kernel.

Bedanya dengan SukiSU: di sana susfs **mustahil** di 4.19 (butuh API v2.x, sumber non-GKI berhenti di v1.5.5). ReSukiSU mengklaim mendukung backport susfs ke kernel 4.3+, jadi jalurnya terbuka — tapi belum saya buktikan di perangkat ini.

---

## Referensi

- ReSukiSU — https://github.com/ReSukiSU/ReSukiSU · dokumentasi: https://resukisu.github.io
- Panduan manual hook — https://resukisu.github.io/guide/manual-integrate.html
- Perbandingan dengan SukiSU-Ultra — [`SUKISU-ULTRA-Redmi5A.md`](./SUKISU-ULTRA-Redmi5A.md)
