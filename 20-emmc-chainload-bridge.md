# 20 — eMMC chain-load bridge (the GarlicOS trick) on the RG353V

**Date:** 2026-11-20 · **Status:** feasibility analysis, no device changes ·
**Depends on:** `19-garlicos-bootloader-analysis.md` (T618 case), `15-darkos-migration.md` (the SD gate)

## The idea

On the RG405V, GarlicOS proved a boot strategy that does not touch the
bootloader: keep the stock verified boot chain, **replace only the ramdisk it
loads**, and have that ramdisk mount a rootfs from SD and `chroot` into it.

The RG353V equivalent: the eMMC's Android boot chain (BootROM → SPL → u-boot →
`boot.img`) still runs; we replace `boot.img`'s **ramdisk** with an init that
finds the SD card, mounts a rootfs and hands off. The kernel stays the vendor
kernel, the drivers stay vendor, Android stays in `/system` untouched.

This is a **second, independent boot path** that does not depend on the SD
u-boot FIT being accepted by the eMMC chain.

## What it buys, and what it does not

| Question | Answer |
|---|---|
| Does it bypass the ROCKNIX "blocking wall"? | **No.** The wall is the eMMC boot chain refusing ROCKNIX's SD u-boot FIT. This path never uses that FIT |
| Does it let us boot *a* Linux? | **Yes** — any rootfs on SD, with the Android 5.10 BSP kernel |
| Does it let us boot a *mainline* kernel? | **Only with `kexec`** in the vendor kernel (`CONFIG_KEXEC`/`KEXEC_FILE`). Unverified on this unit |
| Does it replace dArkOS? | No — dArkOS already gives a full Linux with the same class of kernel, with zero eMMC writes |
| When is it worth doing? | If the SD-loader path is a dead end **and** kexec is available, i.e. as the route to mainline without wiping Android |

So it is not a shortcut around the gate; it is a **fallback door** that could
turn into a real one if kexec exists.

## Why the RG353V is easier than the T618 case

Our unit is **unlocked**: `androidboot.verifiedbootstate=orange`, vbmeta present
but not enforcing (`02-gammaos-internals.md`). That means:

- no need to reproduce Unisoc's `DHTB` wrapper or re-sign a whole vbmeta chain,
- a modified `boot.img` ramdisk can be flashed as-is (orange = bootloader warns
  but boots), and
- masking a single partition is reversible from a backup.

Rockchip recovery is well understood on this SoC: Maskrom/Loader mode +
`rkdeveloptool` (`07-rebuild-firmware.md`), so a bad flash is recoverable
without a hardware programmer.

## Decisive unknowns (check before touching eMMC)

| # | Question | How to check | Why it decides |
|---|---|---|---|
| 1 | Does u-boot expose `fastboot` and support `fastboot boot`? | `adb reboot bootloader` → `fastboot devices`, `fastboot getvar all` | zero-write test of the whole idea |
| 2 | Is `CONFIG_KEXEC` / `CONFIG_KEXEC_FILE` enabled? | `zcat /proc/config.gz \| grep KEXEC` (or `/boot/config-*` on dArkOS: not applicable — must be the Android kernel) | decides vendor-kernel-only vs mainline |
| 3 | Does the vendor kernel have the SD/MMC, vfat/ext4, and USB-gadget bits our init needs? | inspect the unpacked `boot.img` config (`survey/`) or boot and check | bridge feasibility |
| 4 | Are `boot`, `recovery`, `vbmeta` partitions readable/writable from Android (root)? | `/dev/block/by-name/*`, Magisk `su` | backup + minimal flashing |

## Ladder (each step is a stop/go)

### E0 — zero-write probe (10 minutes)
`adb reboot bootloader` → `fastboot devices` → `fastboot getvar all`.
If `fastboot boot <patched-boot.img>` is accepted, we can test the bridge
**without writing anything**. If the command is unsupported, stop here and go
to E1 only.

### E1 — read-only facts (no writes)
On Android: kernel config (kexec, mmc, filesystems), `ls /dev/block/by-name`,
`cat /proc/cmdline`, partition sizes. This decides whether the bridge can
chain-load and what it can mount.

### E2 — recovery-partition bridge (least invasive write)
Patch **`recovery.img`** only. Normal boot stays Android; the bridge runs when
we deliberately boot recovery. Reversible; keeps the daily driver intact.

### E3 — boot-partition bridge (default boot)
Patch `boot.img` ramdisk: flash → device boots the bridge by default, Android
still reachable in `/system` (and by removing the SD card the bridge can fall
back to Android's init). Requires backing up `boot` + `vbmeta` first.

### E4 — kexec to a mainline kernel
Only if E1 shows kexec support. The bridge then loads our Arch/dArkOS initramfs
and `kexec`s a mainline kernel — this is the only variant that genuinely escapes
the vendor kernel.

## Risk / recovery

| Risk | Mitigation |
|---|---|
| Bad `boot` flash → no Android | backup `boot`+`vbmeta` partitions first; restore via `fastboot flash` or Maskrom + `rkdeveloptool` |
| AVB/verity complaints | device is orange (unlocked); if a partition is verified, flash the matching vbmeta with verification disabled |
| eMMC wear | partition images written once, not repeatedly; 7.5 GB backups already exist |
| Losing the dArkOS card | card is independent; dArkOS image + S1 image are in `rg353v-backup/images/` |

## Position in the plan

Do **E1 (read-only facts) during S2**, while we are already on the device with a
working Linux — it costs one SSH session and no writes. E0 can be tried in the
same session. E2/E3 only if S3/S4 stall, and only after the eMMC `boot`/`vbmeta`
backup exists.

None of this changes the primary path: S1 → S2 → S3 → S4 on the dArkOS chain.
