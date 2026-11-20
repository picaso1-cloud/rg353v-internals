# 17 — Arch bring-up plan for the RG353V (ground-up, one variable per boot)

**Created:** 2026-11-20 · **Status:** ready to start at **S1** · **Supersedes the
"flash another distro" approach** in `13-archr-rk3566-plan.md`.

## Why ground-up (the ROCKNIX lesson)

The hybridA→hybridD series changed **four things at once** every time (loader
bytes, partition numbering, partition type GUIDs/names, kernel+dtb+cmdline).
Every failure was un-attributable, every test cost a 12-minute flash and a
device round-trip, and we still cannot say which boot stage rejected the card.
That is the wrong order of operations for a port.

A port is not "get someone else's image to boot". It is:

> own each layer in turn, with a **visible output** at every stage, changing
> exactly **one** layer per boot.

The **working dArkOS card is the hardware abstraction layer**. It already
proves: DDR init works, the eMMC SPL accepts an SD u-boot FIT, u-boot loads a
kernel off the boot vfat, the panel comes up, USB/input/Wi-Fi work. We keep all
of that fixed and replace layer by layer.

## The proven reference chain (dArkOS v11072026 on this unit)

Sector-exact map, taken from the image that **boots**:

| Offset | Size | Content |
|---|---|---|
| 0x4000 (sector 64, 32 KiB) | ~8 MiB | **idbloader** — Rockchip `RKNS` + DDR init + SPL |
| 8 MiB (sector 16384) | 4 MiB | p1 `uboot` — **FIT**: U-Boot + 6× ATF entries (load addr `0x00a00000`, ATF @ `0x00040000`/`0xfdcc1000`…) |
| 12 MiB (sector 24576) | 4 MiB | p2 `resource` — Rockchip `RKNS` resource image (DTB/bootargs blob) |
| 16 MiB (sector 32768) | 99 MiB | p3 `dArkOS_Fat` — vfat: `/Image`, `/uInitrd`, `/rk3566-353v.dtb`, `/extlinux/extlinux.conf`, `/overlays` |
| ~116 MiB | ~15.2 GB | p4 `rootfs` — btrfs, label `ROOTFS` |
| … | ~83 MB | p5 `4` — exfat, `/roms` (expands on first boot) |

Extlinux on the working card:

```
LABEL ArkOS
  LINUX /Image
  FDT   /rk3566-353v.dtb
  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootwait rw ...
```

Loader-format evidence (for S4 later): `dumpimage -l` on dArkOS's `uboot`
region prints `FIT description: FIT Image with ATF/OP-TEE/U-Boot/MCU`, images
`uboot` (Standalone Program, `0x00a00000`) + `atf-1 … atf-6` (Firmware). **That
node list is the format spec our own u-boot build must reproduce** for the eMMC
SPL to accept it.

## Stage ladder

Each stage: **one change**, one card, one boot, one acceptance criterion. If a
stage fails, the stage's own output tells us where — no guessing.

### S0 — Freeze the baseline (no device work)

- Keep `images/dArkOS_RG353v_trixie_11072026.img` as the reference; record
  hashes of the loader regions (done in `15-darkos-migration.md`).
- Establish the **good card** (Samsung `SD256`, 238 GiB, zero errors) as the
  work card. The 58.2 G `SD16G` stays as the throwaway/test card, writes
  ≤ 23.6 GB.
- Script the card build (`mkcard.sh`) so every variant is reproducible from
  the reference image + a diff of files, not from hand-edits.

**Acceptance:** one command rebuilds the exact card we tested.

### S1 — Boot visibility (the single most valuable step)

Replace **only** `/uInitrd` on the dArkOS boot vfat with a minimal initramfs
(static busybox) that:

1. prints a banner + `dmesg` to the framebuffer console (`console=tty1`),
2. waits for a keypress / timeout,
3. then execs the dArkOS rootfs (`switch_root` to `/dev/mmcblk1p4`) so the card
   still behaves like dArkOS if we do nothing.

Keep `/Image`, `/rk3566-353v.dtb`, `extlinux.conf` **untouched**.

**Acceptance:** banner and kernel messages visible on the 640×480 panel. From
then on, every failure on this device is a *photograph*, not a guess. If S1
shows nothing, the problem is before initramfs and the panel/UART question is
answered immediately.

**Cost:** one file copy on a working card. Fully revertible (copy the original
`uInitrd` back). No reflash.

**Built (2026-11-20):** `tools/s1/` — the patched initramfs
(`uInitrd.s1`, sha256 `94544e46…`), the stock backup, `install-s1.sh`,
`revert-s1.sh`, and `19-s1-initramfs.md` (procedure, expected output, failure
matrix).

### S2 — Own the userspace

Still dArkOS kernel + dtb + loader. Replace the root filesystem with our own:

- option A: ext4/btrfs partition containing an **ArchLinuxARM aarch64** rootfs
  (pacman, rolling) with dArkOS's `/lib/modules/5.10.226-*` copied in,
- option B: minimal buildroot/busybox rootfs first (fastest "hello world"),
  then ALARM on top.

`APPEND root=` points at our partition; init mounts proc/sys/dev and starts a
getty on `tty1`.

**Acceptance:** login prompt on the device, `uname -a` = dArkOS's 5.10.226,
`pacman -Syu` works (option A).

**This is the milestone that makes it "our OS"**: from here we boot *our*
userland on *their* kernel.

### S3 — Own the kernel

Swap `/Image` for a kernel **we build**, same dtb, same everything else.
Order: (a) rebuild dArkOS's 5.10 BSP config → proves the toolchain and the
boot path, (b) mainline 6.x/7.x with `panfrost` + `panvk` → the open Vulkan
stack that ROCKNIX had and dArkOS does not.

**Acceptance:** S2's rootfs boots with our kernel; `dmesg | grep -i panfrost`
shows the G52 probe; `vulkaninfo` lists a panvk device (once Mesa is built).

### S4 — Own the loader

Only now touch the boot chain: build `idbloader` (DDR init blob + SPL) and
`uboot` FIT ourselves, matching the **component list/load addresses read from
dArkOS's FIT**. This is the stage where the eMMC-SPL gate actually matters — and
we enter it with a known-good FIT to diff against, plus panel-console output.

**Acceptance:** device boots our loader → our kernel → our rootfs.

### S5 — Distribution polish

EmulationStation frontend, controller mapping, audio (speaker/headphones),
Wi-Fi/BT, storage/ROM discovery on TF2, suspend/thermal, OTA/update path,
`archr-rk3566` device profile + build scripts published.

## Instrumentation policy

- **Panel console first** (`console=tty1`, `loglevel=7`, no splash): free, no
  hardware, sufficient for S1–S3.
- **UART only if needed** (S4 at the latest): RK3566 debug UART, 1 500 000 baud
  — this is the only way to see SPL/u-boot output. Opening the shell is a
  physical step; decide when S4 starts, not before.
- **No laptop-side "verification" beyond hashes.** A device boot is the test.
  Card mounts failing right after a long write are not evidence of anything.

## Repository layout (to create as we go)

```
archr/
  devices/rg353v/           # device profile: dtb, extlinux, panel quirks
  scripts/mkcard.sh         # reference image -> bootable card (one command)
  scripts/build-initramfs.sh
  scripts/build-kernel.sh
  scripts/build-uboot.sh
  rootfs/overlay/           # init, getty, ES config
```

## Immediate next action

**S1**: build the tiny initramfs, drop it on the working dArkOS card as
`/uInitrd`, boot once, photograph the panel. Nothing else changes.

---

## 2026-11-20 — distribution base chosen: **Arch-R**

The port is built on [`archr-linux/Arch-R`](https://github.com/archr-linux/Arch-R)
(Arch Linux ARM + LibreELEC/JELOS/ROCKNIX-derived pipeline) by adding a
**`projects/ArchR/devices/RK3566`** profile. Upstream analysis, the exact
device-profile files to add, the package gaps, and the transplant rule:
[`18-archr-upstream-analysis.md`](18-archr-upstream-analysis.md).

Relation to the stages below: **S1–S3 do not need Arch-R to build anything.**
They use the working dArkOS card with one file swapped. Arch-R enters at **S3**
(its kernel config, taken from ROCKNIX's RK3566 config) and becomes the whole
system at **S5**. The overlay/panel workflow is inherited from
`rgb10max2-internals` (see doc 18, "Reuse from our other device repos").
