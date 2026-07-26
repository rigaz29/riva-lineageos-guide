# SukiSU-Ultra + susfs — Redmi 5A (`riva`)

> **Opsional.** Root berbasis kernel dengan penyembunyian susfs, ditanam saat build. Ditulis untuk target **kernel 4.19** (`lineage_Mi8937_4_19`).
>
> Semua klaim di sini diverifikasi langsung ke source, bukan disalin dari dokumentasi upstream — yang, seperti dijelaskan di bawah, sudah tidak sinkron dengan kodenya.

---

## 1. Ringkasan

| | |
|---|---|
| Yang dipasang | SukiSU-Ultra branch **`builtin`** + susfs v1.5.5 |
| Perlu edit source kernel? | **Tidak** — hook statis Mi-Thorium sudah cocok |
| Perlu patch `frameworks/base`? | Tidak |
| Fitur yang tidak bisa | `SUS_MOUNT` (sembunyikan mount) — [Bagian 6](#6-satu-fitur-yang-tidak-bisa-sus_mount) |
| Otomatisasi | [`scripts/setup-sukisu.sh`](./scripts/setup-sukisu.sh) |

---

## 2. Dua jebakan dokumentasi upstream

**Jangan ikuti `docs/guide/how-to-integrate.md` milik SukiSU apa adanya.** Dua hal di sana menyesatkan:

1. Ia menyuruh menyetel `CONFIG_KSU_MANUAL_HOOK` atau `CONFIG_KSU_TRACEPOINT_HOOK`. **Kedua opsi itu tidak ada** di `kernel/Kconfig` branch `main` — repo itu cuma punya satu Kconfig dan tidak mendefinisikan keduanya.
2. Ia menyebut varian susfs `bash -s susfs-main`. **Branch `susfs-main` tidak ada** — yang tersedia hanya `susfs_new`.

Yang benar untuk perangkat non-GKI seperti Mi8937 adalah branch **`builtin`**.

---

## 3. Kenapa branch `builtin`, bukan `main`

Ini penentu keberhasilan, dan alasannya teknis.

Kernel Mi-Thorium **sudah memuat lima titik hook manual** yang digerbangi `CONFIG_KSU_STATIC_HOOKS` (`Kconfig:34`):

```
fs/exec.c:1898          ksu_handle_execveat, ksu_handle_execveat_sucompat
fs/open.c:352           ksu_handle_faccessat
fs/read_write.c:437     ksu_handle_vfs_read
fs/stat.c:151           ksu_handle_stat
drivers/input/input.c   ksu_handle_input_handle_event
```

Pertanyaannya cuma: fork mana yang menyediakan simbol dengan tanda tangan sama?

| | branch `main` | branch **`builtin`** |
|---|---|---|
| `config KSU` | `tristate` (bisa modul) | **`bool`** — built-in, tepat untuk non-GKI |
| Tata letak | direfaktor: `core/`, `hook/`, `infra/`, … | mendekati KernelSU klasik |
| API hook | `pt_regs` (`ksu_handle_faccessat_sucompat(int, struct pt_regs*)`) | **API klasik** |
| susfs di kernel | tidak ada | **`CONFIG_KSU_SUSFS` + 9 sub-opsi bawaan** |
| Cocok dgn hook Mi-Thorium | **1 dari 6** | **6 dari 6** |

Verifikasi simbol di branch `builtin`:

```
ksu_handle_execveat            ✓ feature/sucompat.c
ksu_handle_execveat_sucompat   ✓ feature/sucompat.c
ksu_handle_faccessat           ✓ feature/sucompat.c
ksu_handle_stat                ✓ feature/sucompat.c
ksu_handle_vfs_read            ✓ runtime/ksud.c
ksu_handle_input_handle_event  ✓ runtime/ksud.c
```

Konsekuensi praktisnya besar: **tidak ada satu baris pun source kernel yang perlu kamu edit.** Kalau memakai branch `main`, kamu harus menulis sendiri lapisan adaptasi untuk lima simbol yang tidak cocok.

Bonus: karena `builtin` sudah mengintegrasikan susfs, patch `10_enable_susfs_for_ksu.patch` dari susfs4ksu **tidak perlu dan memang tidak akan apply** — patch itu menyasar `kernel/ksu.c`, `kernel/core_hook.c`, dsb. yang sudah tidak ada.

---

## 4. Prasyarat

Semua sudah terpenuhi di kernel Mi-Thorium 4.19 — tidak ada yang perlu ditambah:

| Syarat | Asal | Status |
|---|---|---|
| `CONFIG_KPROBES=y` | `vendor/feature/kprobes.config` | ✅ |
| `CONFIG_EXT4_FS=y` | defconfig | ✅ |
| `CONFIG_KALLSYMS_ALL=y` | defconfig | ✅ |
| `THREAD_INFO_IN_TASK` | di-`select` `arch/arm64/Kconfig:183` | ✅ |
| Kernel ≥ 4.14 | 4.19.325 | ✅ |

`CONFIG_KSU_SUSFS` mensyaratkan `THREAD_INFO_IN_TASK`, dan arm64 menyalakannya otomatis.

---

## 5. Pemasangan

### Cara cepat

```bash
./scripts/setup-sukisu.sh ~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel
```

Skrip ini idempoten — aman dijalankan ulang setelah `repo sync`.

### Cara manual

```bash
K=~/android/lineage-20.0/kernel/xiaomi/mithorium-4.19/kernel

# 1. susfs (branch cocokkan dengan versi kernel: kernel-4.19 atau kernel-4.9)
git clone --depth 1 -b kernel-4.19 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs
cp /tmp/susfs/kernel_patches/fs/*.c            $K/fs/
cp /tmp/susfs/kernel_patches/include/linux/*.h $K/include/linux/
cd $K && patch -p1 --fuzz=5 < /tmp/susfs/kernel_patches/50_add_susfs_in_kernel-4.19.patch

# 2. SukiSU-Ultra branch builtin
git clone --depth 1 -b builtin https://github.com/SukiSU-Ultra/SukiSU-Ultra.git $K/KernelSU
ln -sfn ../KernelSU/kernel $K/drivers/kernelsu
echo 'obj-$(CONFIG_KSU) += kernelsu/' >> $K/drivers/Makefile
sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' $K/drivers/Kconfig
```

> ⚠️ **Jangan hardcode level symlink-nya.** Target yang benar adalah `../KernelSU/kernel`, **bukan** `../../KernelSU/kernel` — symlink itu berada *di dalam* `drivers/`, jadi satu `..` sudah membawa ke root kernel. Salah level bikin `drivers/kernelsu/Kconfig` tidak resolve dan build gagal dengan pesan yang membingungkan. Lebih aman menghitungnya:
> ```bash
> ln -sfn "$(realpath --relative-to="$K/drivers" "$K/KernelSU/kernel")" $K/drivers/kernelsu
> ls -l $K/drivers/kernelsu/Kconfig    # harus ada, ~4 KB
> ```

### Alternatif: pakai `setup.sh` upstream untuk langkah 2

Langkah 2 di atas bisa digantikan sepenuhnya oleh skrip resmi SukiSU:

```bash
cd $K
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s builtin
```

Ini **lebih aman daripada mengetik symlink manual** — skrip itu menghitung path dengan `realpath --relative-to`, jadi kesalahan level `../../` mustahil terjadi. Ia juga menangani wiring `drivers/Makefile` dan `drivers/Kconfig` dengan logika yang sama.

Yang perlu diketahui sebelum memakainya:

| | |
|---|---|
| Cakupan | Hanya langkah 2. **Tidak** menyentuh susfs, fragment config, maupun BoardConfig |
| Clone | Penuh (±60 MB), bukan `--depth 1`. Untuk tree 230 GB ini tidak berarti |
| Argumen | `builtin` diteruskan ke `git checkout`, jadi branch-nya benar |
| Risiko | `curl \| bash` menjalankan kode remote tanpa kamu baca dulu — pada skrip yang mengubah source kernel, itu keputusanmu |

### 3. Fragment config

Buat `arch/arm64/configs/vendor/feature/sukisu.config`:

```
CONFIG_KSU=y
CONFIG_KSU_STATIC_HOOKS=y

CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y

# CONFIG_KSU_SUSFS_SUS_MOUNT is not set
# CONFIG_KPM is not set
```

### 4. Sambungkan ke device tree

Tambahkan di `device/xiaomi/Mi8937/BoardConfig.mk`:

```makefile
# SukiSU-Ultra + susfs
TARGET_KERNEL_CONFIG += \
    vendor/feature/sukisu.config
```

Atau langsung pakai patch yang sudah disiapkan:

```bash
cd ~/android/lineage-20.0/device/xiaomi/Mi8937
git am /path/ke/riva-lineageos-guide/patches/0001-Mi8937-Enable-SukiSU-Ultra-susfs-kernel-config.patch
```

### 5. Build

```bash
cd ~/android/lineage-20.0
source build/envsetup.sh && set +e
lunch lineage_Mi8937_4_19-userdebug
mka bacon -j$(nproc --all)
```

---

## 6. Satu fitur yang tidak bisa: `SUS_MOUNT`

Dua hunk `fs/namespace.c` dari `50_add_susfs_in_kernel-4.19.patch` **tidak apply** ke kernel msm downstream Mi-Thorium:

- Hunk #7 menyasar `vfs_kern_mount()` — fungsi itu **tidak ada** di kernel ini
- Hunk #9 menyasar `clone_mnt()` — ada, tapi konteks sekitarnya berbeda

Sisanya (14 dari 16 hunk di file itu, plus semua file lain) apply normal. Karena seluruh kode fitur ini berada di dalam `#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT`, mematikan opsinya membuat kernel tetap kompilasi bersih. File `fs/namespace.c.rej` yang tertinggal boleh dibiarkan.

**Konsekuensi jujurnya:** mount milik modul root **tidak disembunyikan**. Aplikasi yang menyisir `/proc/mounts` atau `/proc/self/mountinfo` masih bisa melihat jejaknya. Fitur susfs lain tetap aktif: `SUS_PATH`, `SUS_KSTAT`, `SUS_MAP`, `SPOOF_UNAME`, `SPOOF_CMDLINE`, `OPEN_REDIRECT`, `HIDE_KSU_SUSFS_SYMBOLS`.

Mengaktifkannya butuh porting manual kedua hunk itu ke struktur mount kernel msm — pekerjaan riset tersendiri dengan risiko bootloop tinggi.

---

## 7. `repo sync` menghapus semuanya

Kernel disync lewat `kernel_manifest`, dan checkout `repo` berada di detached HEAD. Setiap `repo sync` di `kernel/xiaomi/mithorium-4.19` akan **mengembalikan seluruh perubahan** ini: patch susfs, wiring `drivers/`, dan fragment config. Direktori `KernelSU/` sendiri untracked, jadi biasanya selamat — tapi symlink dan wiring-nya tidak.

Jalankan ulang skrip setelah setiap sync kernel:

```bash
(cd kernel/xiaomi/mithorium-4.19 && repo sync -c -j$(nproc --all) --no-tags)
./scripts/setup-sukisu.sh
cd device/xiaomi/Mi8937 && git am /path/ke/patches/0001-Mi8937-Enable-SukiSU-Ultra-*.patch
```

Jangan lupa patch HAL audio juga — lihat [panduan LineageOS 20](./BUILD-LineageOS-20-Redmi5A.md).

---

## 8. Setelah Flashing

1. Pasang **SukiSU Manager** dari [rilis resmi](https://github.com/SukiSU-Ultra/SukiSU-Ultra/releases).
2. Buka aplikasinya — status harus menampilkan kernel terpasang beserta versi susfs.
3. Kelola izin root per aplikasi lewat **App Profile**.
4. Panel susfs ada di dalam manager; ingat `SUS_MOUNT` tidak tersedia di build ini.

⚠️ Backup ZIP yang lama sebelum flashing. Ini jalur yang belum banyak ditempuh di msm8937 — risiko bootloop nyata, dan pemulihannya berarti flash ulang ZIP sebelumnya.

---

## 9. Kalau Tidak Mau Menyentuh Kernel

Alternatif tanpa rebuild: **Magisk** — patch `boot.img` hasil build kamu langsung. Kehilangan integrasi susfs level kernel, tapi jauh lebih sederhana dan bisa di-revert dengan mem-flash ulang `boot.img` asli.

---

## Referensi

- SukiSU-Ultra — https://github.com/SukiSU-Ultra/SukiSU-Ultra (branch `builtin`)
- susfs4ksu — https://gitlab.com/simonpunk/susfs4ksu (branch `kernel-4.19`)
- Titik hook Mi-Thorium — `Kconfig:34`, `fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `drivers/input/input.c`
- Fork KernelSU lain — `tiann/KernelSU`, `KernelSU-Next`, `rsuntk/KernelSU`, `backslashxx/KernelSU`, `5ec1cff/KernelSU`
