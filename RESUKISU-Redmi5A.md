# ReSukiSU — Redmi 5A (`riva`)

> **Opsional.** Root berbasis kernel, ditanam saat build. Untuk target **kernel 4.19** (`lineage_Mi8937_4_19`).
>
> Status: **terverifikasi di perangkat** (27 Juli 2026). ROM boot, manager mengenali kernel di versi **35032**, dan **susfs v2.2.0 aktif** dengan seluruh sembilan fiturnya termasuk `SUS_MOUNT`.

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

## 4f. ⚠️ Default hook kini TRACEPOINT — yang menjebak **recovery kernel**

Jebakan yang muncul pada ReSukiSU **v4.1.0+** (tidak ada di versi lama yang dulu kita pakai). Blok `choice` "KernelSU Hooking Method" sekarang punya **tiga** opsi dengan **default `KSU_TRACEPOINT_HOOK`** — hook syscall lewat tracepoint, **hanya untuk GKI 2.0** (kernel 5.10+):

```
choice "KernelSU Hooking Method"   (depends on KSU, default KSU_TRACEPOINT_HOOK)
├── KSU_TRACEPOINT_HOOK   # GKI 2.0 saja
├── KSU_MANUAL_HOOK       # kernel 3.4+
└── KSU_SUSFS             # "SUSFS Inline Hook" — kernel 4.3+
```

**`KSU_SUSFS` adalah salah satu opsi hook di choice ini** (bukan add-on). Jadi menyetel `CONFIG_KSU_SUSFS=y` **sudah memilih** inline-hook itu dan otomatis menonaktifkan default TRACEPOINT. **Kernel boot kita aman** — fragment `resukisu.config` menyetel `CONFIG_KSU_SUSFS=y`, selesai.

Yang menjebak adalah **kernel recovery**. `config KSU` = **`default y`**, jadi begitu source ReSukiSU ada di tree, KSU **ikut menyala di recovery** juga. Recovery memakai `TARGET_KERNEL_RECOVERY_CONFIG` yang **tidak** memuat fragment boot kita — tidak ada opsi hook yang dipilih — sehingga choice jatuh ke **default TRACEPOINT**, lalu Kbuild abort di Non-GKI:

```
-- ReSukiSU TP Hooks are only supported on GKI 2.0 kernels.
drivers/kernelsu/Kbuild:170: *** TP hooks are incompatible with Non-GKI/GKI 1.0 kernels.  Stop.
```

Gejala khasnya: **build lolos jauh, lalu gagal di "Building Recovery Kernel Image"**, bukan di kernel boot. Recovery tak butuh root, jadi solusinya **matikan KSU di recovery** (tanpa KSU, `choice` yang `depends on KSU` ikut mati, tak ada hook yang perlu dipilih):

```make
# device/xiaomi/Mi8937/BoardConfig.mk
TARGET_KERNEL_RECOVERY_CONFIG += vendor/feature/norootrecovery.config
```

```conf
# arch/arm64/configs/vendor/feature/norootrecovery.config
# CONFIG_KSU is not set
```

Sudah otomatis di `setup-resukisu*.sh` (menulis fragment ini) + `build-all.sh` (menyambungkannya ke BoardConfig).

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

## 9. susfs v2.2.0 — berhasil

Sempat saya simpulkan mustahil **dua kali**. Keduanya salah, dan penyebabnya sama: menyimpulkan dari nama berkas dan README alih-alih membuka isinya.

| Kesimpulan saya | Kenyataan |
|---|---|
| *"susfs v2.x untuk 4.19 tidak ada"* | Ada — `Patches/Patch/susfs_patch_to_4.19.patch`, direktori yang saya lihat namanya lalu tidak pernah saya buka |
| *"backport itu proyek berminggu-minggu"* | 19 dari 20 file apply bersih; hanya 1 hunk perlu adaptasi |

Pemasangan otomatis: [`scripts/setup-resukisu-susfs.sh`](./scripts/setup-resukisu-susfs.sh)

### Urutannya menentukan

Tiap langkah bergantung pada hasil sebelumnya, dan menukarnya menghasilkan **kegagalan senyap** — bukan error yang jelas.

| # | Langkah | Kalau dilewat / salah urutan |
|---|---|---|
| 1 | Buang hook KSU Mi-Thorium | `susfs_inline_hook_patches.sh` melewati file ber-`ksu_handle`; sebagian hook tidak terpasang |
| 2 | Terapkan `susfs_patch_to_4.19.patch` | — |
| 3 | Adaptasi `fs/namespace.c` | `SUS_MOUNT` tidak bisa aktif |
| 4 | **Pasang ReSukiSU** | ← harus sebelum langkah 5 |
| 5 | Terapkan inline hook | Kalau ReSukiSU belum ada: hook `setresuid` dilewati diam-diam → `You lost ksu_handle_setresuid hook` |
| 6 | Fragment config | — |

Langkah 4 sebelum 5 itu tidak intuitif. Skrip inline memutuskan hook mana yang perlu ditambahkan dengan **memeriksa isi `drivers/kernelsu/`**:

```bash
if grep -rq "ksu_handle_setresuid" "drivers/kernelsu/"; then ...
else echo "[-] KernelSU have no ksu_handle_setresuid, Skipped."
```

Pesan itu terbaca seperti "tidak diperlukan", padahal artinya "tidak bisa memeriksa".

### `CONFIG_KSU_SUSFS` adalah metode hook, bukan fitur

Ini yang paling mudah salah paham. Di `kernel/Kconfig` ReSukiSU:

```
choice
    prompt "KernelSU Hooking Method"
    config KSU_TRACEPOINT_HOOK   (GKI2 5.10+)
    config KSU_MANUAL_HOOK       (3.4+)
    config KSU_SUSFS             "SUSFS Inline Hook"
endchoice

menu "KernelSU - SUSFS"
    depends on KSU_SUSFS
```

Ketiganya **saling eksklusif**. Menyalakan susfs otomatis mengganti metode hook — itulah kenapa hook Mi-Thorium harus dibuang, bukan diadaptasi seperti pada jalur Manual Hook di [Bagian 4](#4-empat-penyesuaian-kernel).

Menyetel `KSU_MANUAL_HOOK=y` dan `KSU_SUSFS=y` bersamaan tidak menghasilkan error — yang belakangan diam-diam menang.

### Satu adaptasi yang tidak bisa diotomatiskan

Hunk susfs untuk `vfs_kern_mount()` tidak berlaku: kernel Mi-Thorium memakai API `fs_context` yang di-backport dari 5.x, sehingga `alloc_vfsmnt()` sudah pindah ke `vfs_create_mount()` (`fs/namespace.c:1084`). Logikanya dipindahkan ke sana, memakai helper yang disediakan patch itu sendiri.

> Kesalahan saya sebelumnya: menyimpulkan `vfs_kern_mount()` **tidak ada** di kernel ini. Ada — di baris 1134. Saya mencari string pemanggilan `alloc_vfsmnt(name)` dan menyimpulkan dari ketiadaannya.

### Hasil terverifikasi

```
-- ReSukiSU version code: 35032
-- ReSukiSU: using SuSFS Inline hook
-- SUSFS_VERSION: v2.2.0
225 simbol ksu_* · 65 simbol susfs_* di System.map
```

Kesembilan fitur aktif: `SUS_PATH`, `SUS_MOUNT`, `SUS_KSTAT`, `SUS_MAP`, `SPOOF_UNAME`, `SPOOF_CMDLINE_OR_BOOTCONFIG`, `OPEN_REDIRECT`, `HIDE_KSU_SUSFS_SYMBOLS`, `ENABLE_LOG`.

---

## 10. Berburu bug kernel

Kernel debug + pstore untuk mengejar bug yang tidak menggagalkan build tapi salah tingkah saat runtime.

- **`kernel-fragments/debug.config`** — opsi debug terverifikasi ada di Kconfig kernel ini
- **`scripts/build-kernel-zips.sh [release|debug|both]`** — bangun kernel rilis + debug dari tree sama; config debug disisipkan sementara, dipulihkan lewat `trap`

```bash
./scripts/build-kernel-zips.sh both
# → rom/KERNEL_resukisu-susfs.zip (harian)
# → rom/KERNEL_resukisu-susfs-DEBUG.zip (berburu)
```

Yang paling relevan untuk modifikasi kita: `DEBUG_ATOMIC_SLEEP` (adaptasi `vfs_create_mount()` di jalur mount), `DYNAMIC_DEBUG` (nyalakan log susfs runtime), `PANIC_ON_OOPS` + `DETECT_HUNG_TASK` (crash tercatat pstore).

> `CONFIG_PROVE_LOCKING` (lockdep) sengaja **tidak** dipakai: `kernel/locking/lockdep.c` di tree msm downstream ini sudah membusuk (fungsi mainline hilang, tak pernah dibangun) dan gagal kompilasi. Contoh nyata bug diam-diam yang baru muncul saat fiturnya diaktifkan.

Baca hasil:
```bash
su -c 'dmesg' | grep -iE "WARNING|BUG|atomic|hung|susfs|call trace"
su -c 'cat /sys/fs/pstore/console-ramoops-0'   # panic dari boot sebelumnya
su -c "echo 'file fs/susfs.c +p' > /sys/kernel/debug/dynamic_debug/control"
```

⚠️ Kernel debug lebih lambat & `PANIC_ON_OOPS` sengaja reboot saat ada masalah — bukan untuk harian.

---

## Referensi

- ReSukiSU — https://github.com/ReSukiSU/ReSukiSU · dokumentasi: https://resukisu.github.io
- Panduan manual hook — https://resukisu.github.io/guide/manual-integrate.html
- Perbandingan dengan SukiSU-Ultra — [`SUKISU-ULTRA-Redmi5A.md`](./SUKISU-ULTRA-Redmi5A.md)
