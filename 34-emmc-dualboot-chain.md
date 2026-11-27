# 34 — The eMMC/SD dual-boot chain (RG353V): making the stock bootloader boot ROCKNIX from TF1

**Date:** 2026-11-27 · **Status:** verified on hardware · **Scope:** RG353V
(RK3566, eMMC GammaOS Android), stock Anbernic bootloader.

> This is the fix that made the whole mainline phase possible. It keeps the
> eMMC Android **installed and bootable** and adds "boot Linux from TF1" in
> front of it — without wiping a single Android partition.

---

## 1. The problem

ROCKNIX's wiki says P/M/V users must **wipe the Android partition** before
ROCKNIX will boot from SD. Observed behaviour on this unit:

| Card in TF1 | What boots |
|---|---|
| ARCH-R card (dArkOS chain + `/Image` + extlinux) | **Linux** (the card's kernel) |
| ROCKNIX card (mainline chain, then the dArkOS chain written by hand) | **Android** |
| ROCKNIX card whose own u-boot `bootcmd` was replaced with `reset` | **Android** |

That last row is the decisive one: even when the card's own bootloader is
told to reset immediately, Android still comes up. **The card's bootloader is
never executed — the eMMC chain owns the boot.** The SD boot the wiki calls
"works after wiping" is not the SD's own chain running; it is the eMMC's
u-boot being *forced* to fall through to the card.

Crucially, a bootloader running from the eMMC **can read TF1** (the stock
script already does `fatload mmc 1:3 …`). So the dual-boot belongs in the
**eMMC u-boot**, not on the card.

---

## 2. What the stock eMMC chain is (from `emmc-first16MiB-*.img`)

### Layout

| LBA / offset | Contents |
|---|---|
| 0x8000 (32 KiB) | RKNS idblock (SPL), **5 copies** at `0x8000 + n*0x80000` (0x8000, 0x88000, 0x108000, 0x188000, 0x208000) |
| GPT p1 `security` | 4–8 MiB |
| GPT p2 `uboot` | 8–12 MiB — **the u-boot FIT** (plus a duplicate at 10 MiB) |
| GPT p3 `trust` | 12–16 MiB (zeros on this unit) |
| GPT p4 `misc` | 16–20 MiB |
| … p7 `boot` | `ANDROID!` |

### The u-boot FIT (8 MiB)

```
FIT Image with ATF/OP-TEE/U-Boot/MCU  (01 Jan 2023)
  Image 0 (uboot)  standalone, uncompressed, 1 240 920 B  (load 0xa00000)  sha256
  atf-1 … atf-6, optee, fdt
```

* u-boot payload at **`data-position 0x1000`**, `data-size 0x12ef58`
* hash record: `/images/uboot/hash/value` (32 bytes, inside the 0xe00-byte FDT)
* **no signature** (`dumpimage -l` shows no *Sign algo*) — only sha256 hashes,
  which the SPL verifies
* a byte-identical **second copy at 0x200000 (10 MiB)** — patch both

### The default environment (compiled in, 44 vars)

| var | value |
|---|---|
| `bootcmd` | a 5 467-byte Anbernic script (see below) at offset **0xbfc50** |
| `bootdelay` | `0` |
| `scriptaddr` | `0x00c00000` |
| `kernel_addr_r` | `0x00280000` |
| `fdt_addr_r` | `0x0a100000` |
| `ramdisk_addr_r` | `0x0a200000` |
| `boot_targets` | `mmc1 mmc0 mtd2 mtd1 mtd0 usb0 pxe dhcp` |
| `rkimg_bootdev` | `if mmc dev 1 && rkimgtest mmc 1; then devnum=1; elif mmc dev 0; then devnum=0; …` |

### The stock `bootcmd` logic

```
boot_fit;                                       # FIT from boot/recovery partition
if test -e mmc 1:3 boot/anbernic; then … fi;    # Anbernic dual-boot markers
boot_android ${devtype} ${devnum};              # Android
run distro_bootcmd;                             # only if everything above failed
```

`boot_fit` = *"Boot FIT Image from memory or boot/recovery partition"* — the
eMMC `boot` partition is `ANDROID!`, not a FIT, so it fails. The marker block
does nothing on our cards (no `boot/anbernic`). `boot_android` succeeds, so
Android boots and `distro_bootcmd` is never reached.

### `rkimgtest` (why "resource partition" was a red herring)

`cmd/rkimgtest.c` reads **LBA 64** and accepts the old IDB magic
(`0xFCDC8C3B`) or the RKNS tag (`0x534E4B52`/`0x534E5252`). It does **not**
look at the GPT. Our card has `RKNS` at LBA 64, so it *is* accepted as a
Rockchip image — the problem was never the card.

---

## 3. How the ownership was proved (and a reusable probe)

1. **Card chain off:** patched the card's own u-boot `bootcmd` to `reset`
   (FIT hash recomputed). Android still booted ⇒ the card's chain never runs.
2. **eMMC-side probe:** replaced the eMMC `bootcmd` with a script that writes a
   marker byte to a scratch sector:
   ```
   mw.b 0x60000000 0x41;
   if test -e mmc 1:3 /extlinux/extlinux.conf; then mw.b 0x60000000 0x42;
   elif test -e mmc 1:3 extlinux/extlinux.conf; then mw.b 0x60000000 0x44;
   else mw.b 0x60000000 0x43; fi;
   mmc dev 0; mmc write 0x60000000 0x28 1;     # LBA 40 = free area
   boot_fit; boot_android mmc 0
   ```
   Reading LBA 40 from Android (`dd if=/dev/block/mmcblk0 bs=512 skip=40 …`)
   returned **`0x42`** ⇒ the eMMC chain ran **and** found the card's config.

### The `/` trap

`test -e mmc 1:3 extlinux/extlinux.conf` (relative) **fails** in this u-boot;
`test -e mmc 1:3 /extlinux/extlinux.conf` (leading slash) **succeeds**. The
first real attempt produced no `s1` marker for exactly this reason.

LBA 40 is safe: the GPT ends at LBA 33 and the idblock starts at 64.

---

## 4. The patch

### New `bootcmd` (299 bytes, padded with spaces to the 5 467-byte slot)

```
if test -e mmc 1:3 /extlinux/extlinux.conf; then
  mw.b 0x60000000 0x31; save mmc 1:3 0x60000000 s1 2;
  setenv kernel_addr_r 0x2000000;
  sysboot mmc 1:3 any 0xc00000 /extlinux/extlinux.conf;
  mw.b 0x60000000 0x32; save mmc 1:3 0x60000000 s2 2;
  setenv kernel_addr_r 0x00280000;
fi;
boot_fit; boot_android mmc 0
```

* `kernel_addr_r=0x2000000` (32 MiB, 2 MiB-aligned). The stock `0x00280000`
  is not 2 MiB aligned (arm64 `booti` requirement) and the old card chain's
  `0xa80000` also overlapped `scriptaddr` (12 MiB), so a 30 MB kernel was
  loaded *over* the boot config.
* `sysboot` with an explicit address avoids `distro_bootcmd`'s
  `part list -bootable` heuristics.
* The last two commands are the **untouched Android path** ⇒ if the card is
  absent, or `sysboot` returns, Android boots exactly as before.
* `s1`/`s2` are optional markers on the card's FAT (`/s1` written before
  `sysboot`, `/s2` if it returned) — boot-chain telemetry without a console.

### Byte-level edit

For every FIT copy at `base ∈ {0x0, 0x200000}`:

1. `base + 0xbfc50 + 8 … + 5468` ← new script + spaces (same length)
2. recompute `sha256(u-boot data at base+0x1000, 0x12ef58)`
3. find the **old** hash bytes inside the 0xe00-byte FDT and replace with the
   new digest (unique in that range)

Only those bytes change. Validate before writing:

```sh
dumpimage -l emmc-uboot-dualboot.img          # lists images + the new hash
# and re-hash the payload and compare with the recorded value
```

### Write + verify (from Android with root, or from any booted Linux)

```sh
dd if=emmc-uboot-dualboot.img of=/dev/block/mmcblk0 bs=1M seek=8 conv=fsync
# verify
dd if=/dev/block/mmcblk0 bs=1M skip=8 count=4 | sha256sum
```

`/dev/block/mmcblk0` at **8 MiB** is GPT p2 `uboot`; nothing else is touched.

### Rollback

```sh
dd if=emmc-first16MiB-20261127.img of=/dev/block/mmcblk0 bs=1M conv=fsync
```

(That image is the verified original: SPL `RKNS`, GPT `EFI PART`, 14
partitions, p7 `ANDROID!`.)

---

## 5. Result

| Situation | Boots |
|---|---|
| TF1 card with `/extlinux/extlinux.conf` (ROCKNIX, ARCH-R, …) | the **card's** kernel (mainline ROCKNIX 7.2.11 verified) |
| no card | **Android** on the eMMC (unchanged) |
| card with no extlinux config | **Android** |

First boot of ROCKNIX on this chain produced the expected kernel hand-off; the
only remaining blocker was the panel (see `35-rg353v-panel-v2-fix.md`).

## 6. The card's own bootloader is still a chain of last resort

Because the BootROM is eMMC-first, the card's own u-boot normally never runs.
But if the eMMC chain is ever zeroed/replaced, the card becomes the only boot
path again. Its own `bootcmd` must therefore stay valid — after the probes it
was restored to:

```
setenv kernel_addr_r 0x2000000;run distro_bootcmd;boot_android mmc 0
```

The same FIT-patch procedure applies (card: `bootcmd` at `0xbb820`, value 88
bytes, u-boot data at `0xe00`/`0x11f628`, FDT 0xc00, copies at 0/0x200000).

---

## 7. Open items

* Replace "card presence" with a selector: hold a button at power-on
  (`boot_mode`/ADC as the vendor does) or a marker file toggled from either OS.
* Package the whole edit as `tools/emmc-chain/patch-uboot.py` (see that dir).
* Consider mainline u-boot in the eMMC once `boot_android` is proven there —
  it would give a real menu, but the stock chain already does the job.
