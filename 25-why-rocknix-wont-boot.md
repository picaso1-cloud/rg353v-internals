# 25 — Why ROCKNIX cannot boot while Android is on the eMMC (sourced)

**Date:** 2026-11-21 · **Verdict:** our hardware behaviour is the *documented*
behaviour, not a bug in our cards.

## The documented requirement

ROCKNIX wiki, **RG353 [P/M/V/VS/PS]**:

> "eMMC models with legacy bootloader is not supported."
> **"P/M/V Users — You will need to wipe the Android partition to boot into
> ROCKNIX."** *WARNING: this will remove Android completely.*

The documented procedure is done **from Android recovery via ADB**, not from a
PC-side flash tool:

1. power off, **both SD cards ejected**
2. hold **power + volume down** → Android recovery
3. connect the DC port, `adb root` (a timeout message is normal)
4. optional backup: `adb pull /dev/block/mmcblk0 android.img`
5. `adb shell` → `dd if=/dev/zero of=/dev/block/mmcblk0 bs=4M` (runs ~15 min,
   ends with "out of space" — normal)
6. insert the ROCKNIX card, `adb reboot`

## Community corroboration

- r/RG353V, r/ANBERNIC, r/SBCGaming: identical symptom — "boots straight to
  Android, as if no SD card is inserted" — and the same answer: *format/erase the
  Android partition first*.
- A user reports the inverse proof: after re-flashing Android to the eMMC,
  **ROCKNIX stops booting again**.
- Batocera's RG353V guide: Android-in-eMMC units are unsupported from v42 on,
  because *"the installed bootloader is not compatible with later Linux
  kernels"*, and the remedy is the same eMMC wipe.

## Mechanism (matches everything we measured)

- BootROM loads the **eMMC's boot chain first**. With Android present that is
  Anbernic's legacy dual-boot bootloader.
- That bootloader only accepts the ArkOS/dArkOS-family FIT (ATF/OP-TEE/U-Boot).
  It rejects mainline ROCKNIX u-boot — and, as we proved, does not even execute
  a raw ROCKNIX `Image` handed to it.
- Upstream **U-Boot for Anbernic RGxx3** says: the SD image is a complete boot
  chain written at **32 KiB** (`dd … seek=64`), board auto-detected by ADC
  (**RG353V = 695**), panel auto-detected by DSI probe with FDT fixups — and
  *"eMMC booting has not been tested"*. That full SD chain is exactly what the
  BootROM would run **if the eMMC chain weren't in the way**.
- Known upstream gotcha: mainline ATF + panel detection can cause a **reboot
  loop** unless the VO power domain is enabled (fixed in Sep-2024 patches).

## Reversible options (all need an eMMC backup first)

| Option | Effect on Android | Risk |
|---|---|---|
| **Zero only the bootloader area** (first ~16 MB: idbloader @32 KiB, u-boot @8 MiB, trust/resource) | Android no longer boots, `/data` and system partitions untouched | low, reversible by restoring those 16 MB |
| **Full wipe** `dd if=/dev/zero of=/dev/block/mmcblk0` (wiki) | Android gone | reversible only from a full 29 GB image |
| Keep Android | no mainline/ROCKNIX, stay on dArkOS 5.10 (current ArchR port) | none |

Backup sizes: eMMC is **29.1 GB** (`mmcblk0`, 14 partitions). We have ~156 GB
free, so a full image is feasible, and the partial 16 MB restore is trivial.

## What this means for the port

Mainline + panfrost on this unit is **not** a kernel problem and not a card
problem. It is the eMMC legacy bootloader, exactly as documented. The current
ArchR-on-5.10 system is the maximum achievable without touching the eMMC.

---

## 2026-11-21 — the loader's own memory map (extracted from dArkOS `uboot.img`)

```
kernel_addr_r           = 0x00a80000   (10.5 MiB)
ramdisk_addr_r          = 0x0a200000   (162 MiB)
fdt_addr_r              = 0x0a100000   (161 MiB)
bootcmd = boot_fit; boot_android ${devtype} ${devnum}; setenv distro_bootpart 3 && run distro_bootcmd
boot_targets = mmc1 mmc0 usb0 pxe dhcp
```

Consequences:

- **No memory-size problem** booting a mainline kernel: 7.2.11 is 29 MiB, loaded at
  10.5 MiB → ends ≈ 40 MiB, far below the initrd at 162 MiB. dArkOS's own 32 MiB
  kernel uses the same slot.
- The SD path is reached only after `boot_fit` and `boot_android` fail; the
  extlinux entry is loaded with `sysboot` at `distro_bootpart=3`.
- A clean-card test (FAT reformatted, files verified, 43 MB free) with the
  ROCKNIX 7.2.11 `Image` still produced **no tracer, no dmesg, no userspace log**
  → the kernel starts and dies before `init`, invisibly (console is `ttyUSB0`).

### Most likely mechanism (hypothesis, needs UART to confirm)

The kernel receives **dArkOS's ATF (`bl31`)**, which is inside dArkOS's u-boot FIT
on the SD. ROCKNIX's kernel expects the ATF shipped with ROCKNIX's own u-boot;
a PSCI/SMCCC or feature mismatch would panic before any driver initialises —
exactly the observed "nothing at all".

Confirming this needs the **debug UART** (`earlycon=uart8250,mmio32,0xfe660000`
is already in the bootargs): three pads + a USB-TTL, and we would see the panic
in one boot instead of guessing.

### What an Arch-R kernel would change

Nothing fundamental: Arch-R's kernel is the same mainline family (6.12/6.15) and
its config targets **RK3326**, not RK3566. It is a different sample of the same
class of kernel, so it would face the same ATF/PSCI question — while bringing no
RK3566 panel/Wi-Fi configuration.
