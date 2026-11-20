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
