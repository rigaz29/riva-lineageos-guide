# SukiSU-Ultra — Redmi 5A (`riva`)

> **Opsional.** Root berbasis kernel, ditanam saat build. Ditulis untuk target **kernel 4.19** (`lineage_Mi8937_4_19`).
>
> Status: **terbukti build sukses** dan terverifikasi tertanam di kernel. Semua klaim di sini diverifikasi ke source atau ke hasil build, bukan disalin dari dokumentasi upstream.

---

## 1. Ringkasan

| | |
|---|---|
| Yang dipasang | SukiSU-Ultra branch **`builtin`** |
| **susfs** | **Tidak bisa** di kernel 4.19 — [Bagian 6](#6-kenapa-susfs-tidak-bisa) |
| Perlu edit source kernel? | Tidak |
| Perlu patch SukiSU sendiri? | **Ya, 2 bug upstream** — [Bagian 5](#5-dua-bug-upstream-yang-harus-ditambal) |
| Otomatisasi | [`scripts/setup-sukisu.sh`](./scripts/setup-sukisu.sh) |

Hasil build yang terverifikasi:

```
CONFIG_KSU=y
CONFIG_KSU_FEATURE_ADBROOT=y
CONFIG_KSU_STATIC_HOOKS=y
# CONFIG_KSU_SUSFS is not set
→ 180 simbol ksu_* di System.map, Image.gz-dtb 18,9 MB
```

---

## 2. Tiga jebakan dokumentasi upstream

**Jangan ikuti `docs/guide/how-to-integrate.md` milik SukiSU apa adanya:**

1. Ia menyuruh menyetel `CONFIG_KSU_MANUAL_HOOK` atau `CONFIG_KSU_TRACEPOINT_HOOK`. **Kedua opsi itu tidak ada** di Kconfig mana pun.
2. Ia menyebut varian `bash -s susfs-main`. **Branch `susfs-main` tidak ada** — yang tersedia hanya `susfs_new`.
3. Ia tidak menyebut bahwa branch `builtin` **tidak kompilasi di kernel <5.10** tanpa tambalan.

---

## 3. Kenapa branch `builtin`

Kernel Mi-Thorium **sudah memuat lima titik hook manual** yang digerbangi `CONFIG_KSU_STATIC_HOOKS` (`Kconfig:34`):

```
fs/exec.c:1898          ksu_handle_execveat, ksu_handle_execveat_sucompat
fs/open.c:352           ksu_handle_faccessat
fs/read_write.c:437     ksu_handle_vfs_read
fs/stat.c:151           ksu_handle_stat
drivers/input/input.c   ksu_handle_input_handle_event
```

| | branch `main` | branch **`builtin`** |
|---|---|---|
| `config KSU` | `tristate` | **`bool`** — tepat untuk non-GKI |
| API hook | `pt_regs` | **API klasik** |
| Cocok dgn hook Mi-Thorium | **1 dari 6** | **6 dari 6** |

Karena keenam simbol cocok, **tidak ada satu baris pun source kernel yang perlu diedit**.

Prasyarat semuanya sudah terpenuhi: `CONFIG_KPROBES=y`, `CONFIG_EXT4_FS=y`, `CONFIG_KALLSYMS_ALL=y`, kernel 4.19.325.

---

## 4. Pemasangan

### Cara cepat

```bash
./scripts/setup-sukisu.sh ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel
```

Idempoten, dan otomatis menerapkan patch di [Bagian 5](#5-dua-bug-upstream-yang-harus-ditambal).

### Cara manual

```bash
K=~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel

git clone --depth 1 -b builtin https://github.com/SukiSU-Ultra/SukiSU-Ultra.git $K/KernelSU
git -C $K/KernelSU am /path/ke/patches/0002-sukisu-Fix-build-on-kernels-older-than-5.10.patch

ln -sfn "$(realpath --relative-to="$K/drivers" "$K/KernelSU/kernel")" $K/drivers/kernelsu
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> $K/drivers/Makefile
sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' $K/drivers/Kconfig
ls -l $K/drivers/kernelsu/Kconfig     # wajib resolve
```

> `setup.sh` upstream (`curl -LSs .../kernel/setup.sh | bash -s builtin`) juga sah untuk langkah clone+symlink+wiring, dan menghitung symlink dengan `realpath` sehingga lebih aman daripada mengetik manual. Tapi ia **tidak** menerapkan patch Bagian 5, dan tidak menyentuh fragment config maupun BoardConfig.

Fragment `arch/arm64/configs/vendor/feature/sukisu.config`:

```
CONFIG_KSU=y
CONFIG_KSU_STATIC_HOOKS=y
# CONFIG_KSU_SUSFS is not set
# CONFIG_KPM is not set
```

Sambungkan di `device/xiaomi/Mi8937/BoardConfig.mk`:

```makefile
TARGET_KERNEL_CONFIG += \
    vendor/feature/sukisu.config
```

Build:

```bash
cd ~/android/lineage-20.0
source build/envsetup.sh && set +e
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

---

## 5. Dua bug upstream yang harus ditambal

Branch `builtin` **tidak kompilasi apa adanya di kernel 4.19**. Ironisnya branch itu justru ditujukan untuk perangkat non-GKI, yang umumnya berkernel lama.

### 5a. `selinux_hide` dipanggil tanpa gerbang versi

`ksu.c` hanya meng-include implementasinya untuk kernel ≥ 5.10:

```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
#include "feature/selinux_hide.c"
#endif
```

Tapi `runtime/ksud.c` memanggilnya di tiga tempat tanpa syarat apa pun:

```
ksud.c:64   error: implicit declaration of 'ksu_selinux_hide_handle_post_fs_data'
ksud.c:226  error: implicit declaration of 'ksu_selinux_hide_handle_second_stage'
ksud.c:298  (idem)
```

Perbaikan: beri ketiganya gerbang versi yang sama seperti di `ksu.c`.

### 5b. `USER_ARG_NULL` mengembalikan pointer

`sulog/event.c:377` mendefinisikan `#define USER_ARG_NULL user_arg_null_ptr()`, sedangkan `ksu_sulog_capture` menerima `const struct user_arg_ptr` **by value**:

```
event.c:379  error: passing 'struct user_arg_ptr *' to parameter of incompatible type
```

Perbaikan: `#define USER_ARG_NULL (*user_arg_null_ptr())`.

Keduanya ada di [`patches/0002-sukisu-Fix-build-on-kernels-older-than-5.10.patch`](./patches).

> ⚠️ **Jangan deteksi patch ini dengan `grep "KERNEL_VERSION(5, 10, 0)"`.** String itu sudah ada di `ksud.c` upstream untuk keperluan lain, jadi hasilnya false positive dan patch tidak akan pernah diterapkan. Skrip repo mendeteksinya lewat subjek commit `git log`.

---

## 6. Kenapa susfs tidak bisa

Rencana awal memasang susfs, dan gagal — layak dicatat supaya tidak diulang.

SukiSU `builtin` (2026) memanggil API susfs **v2.x**:

```
susfs_start_sdcard_monitor   SUSFS_MAGIC
susfs_add_sus_path_loop      susfs_add_sus_map
```

Sementara sumber susfs untuk kernel non-GKI berhenti jauh di belakang:

| Branch susfs4ksu | Versi | Terakhir |
|---|---|---|
| `gki-android13-5.10` | **v2.2.0** | aktif |
| `kernel-4.19` | **v1.5.5** | Feb 2025 |
| `kernel-4.9` | v1.5.5 | Feb 2025 |

Keempat simbol di atas **tidak ada** di v1.5.5, dan kernel gagal kompilasi di `KernelSU/kernel/supercall/dispatch.c`. Upstream susfs sudah **berhenti merawat jalur non-GKI** — jadi ini bukan soal memilih versi lain, melainkan perlu mem-porting susfs v2.2.0 ke 4.19 sendiri.

Seluruh kode susfs digerbangi `#ifdef CONFIG_KSU_SUSFS`, jadi mematikannya membuat kernel kompilasi bersih.

**Konsekuensi:** root tidak disembunyikan di level kernel. Untuk itu pakai modul userspace (Zygisk/Shamiko lewat manager SukiSU), atau tetap di Magisk.

---

## 7. `repo sync` menghapus semuanya

Setiap `repo sync` di `kernel/xiaomi/mithorium-4.19` mengembalikan wiring `drivers/` dan fragment config. Jalankan ulang skrip:

```bash
(cd kernel/xiaomi/mithorium-4.19 && repo sync -c -j$(nproc --all) --no-tags)
./scripts/setup-sukisu.sh
cd device/xiaomi/Mi8937 && git am /path/ke/patches/0001-Mi8937-Enable-SukiSU-Ultra-*.patch
```

Jangan lupa patch HAL audio juga — lihat [panduan LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md).

---

## 8. Setelah Flashing

1. Pasang **SukiSU Manager** dari [rilis resmi](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases).
2. Buka aplikasinya — statusnya harus menampilkan kernel terpasang.
3. Kelola izin root per aplikasi lewat **App Profile**.

⚠️ Backup ZIP lama sebelum flashing. Build ini kompilasi bersih dan terverifikasi tertanam, tapi **belum diuji boot di perangkat nyata**.

---

## 9. Alternatif

- **Tanpa rebuild:** Magisk — patch `boot.img` hasil build kamu.
- **Butuh susfs sungguhan di kernel lama:** pertimbangkan `backslashxx/KernelSU` yang secara eksplisit menargetkan Linux 3.0–5.4, atau `rsuntk/KernelSU` untuk non-GKI. Keduanya belum diuji di Mi8937.

---

## Referensi

- SukiSU-Ultra — https://github.com/SukiSU-Ultra/SukiSU-Ultra (branch `builtin`)
- susfs4ksu — https://gitlab.com/simonpunk/susfs4ksu
- Titik hook Mi-Thorium — `Kconfig:34`, `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `drivers/input/input.c`
