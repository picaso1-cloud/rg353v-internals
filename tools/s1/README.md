# S1 — boot visibility on the dArkOS card

**Goal:** prove we control the boot chain and get one boot log off the device,
with a change small enough to revert in seconds.

## What it changes

Exactly two entries inside `uInitrd` (the initramfs dArkOS already loads):

| Entry | Change |
|---|---|
| `scripts/s1-banner.sh` | **new** — prints the banner, the boot facts and `dmesg` to the panel, writes `S1-LOG.txt` to the boot FAT, then returns |
| `init` | **+5 lines**, right after `/dev` and `/dev/pts` exist: `[ -x /scripts/s1-banner.sh ] && /scripts/s1-banner.sh \|\| true` |

Nothing else: no kernel, no DTB, no `extlinux.conf`, no rootfs. The stock
`/init` continues into dArkOS exactly as before (same `run-init`).

Verified by diffing pristine vs patched extractions: only the two items above.

## Artifacts

| File | SHA-256 |
|---|---|
| `uInitrd.orig` (stock, backup) | `6f65778bab4060befc465a3bd6d4394b9f9d8aa87b66a167093332a3beb23173` |
| `uInitrd.s1` (patched) | `94544e464018098c06c6e6fec92d0f51bf225e205285e0f0bedd2152b5c22011` |

`patch-initramfs.sh` rebuilds `uInitrd.s1` **byte-identically** from
`uInitrd.orig` (timestamps normalised, owner 0:0, `cpio --reproducible`).

## Prebuilt image (no card surgery needed)

`../rg353v-backup/images/dArkOS_S1.img` is the working dArkOS image with S1
already installed (`sha256 5ed05b2a4d5f4f31889eb9182ec4bd4be406f24e8a13c765d845f5ea7d5a47b4`).
Flash it and the card is ready:

```bash
tools/s1/flash-image.sh --image ../rg353v-backup/images/dArkOS_S1.img --device /dev/mmcblk0
```

## Install / revert

```bash
# card in the laptop (TF1, the dArkOS card) — writes only p3:/uInitrd
sudo tools/s1/install-s1.sh /dev/mmcblk0

# or onto an image file
tools/s1/install-s1.sh /path/to/dArkOS.img

# revert
sudo tools/s1/revert-s1.sh /dev/mmcblk0
```

`install-s1.sh` refuses if `p3` has no `/Image`, keeps `p3:/uInitrd.orig` once,
and verifies the read-back hash.

## What you should see

Before the dArkOS splash, on the 640×480 panel:

```
======================================================================
  RG353V  *  ARCH BRING-UP  *  STAGE S1
  custom initramfs is running  ->  the boot chain is ours
======================================================================
time      : ...
kernel    : Linux 5.10.226 ...
model     : Anbernic RG353V
compatible: rockchip,rk3566-anbernic-rg353v ...
cmdline   : root=/dev/mmcblk1p4 initrd=/uInitrd ...
displays  : card0 card0-DSI-1 ...
backlight : ...
block     : /dev/mmcblk0 /dev/mmcblk0p1 ... /dev/mmcblk1p5
uart      : no ttyS2 node
kernel messages (first 40 + last 120 lines):
  ...
log file  : /dev/mmcblk1p3:/S1-LOG.txt
continuing to dArkOS in 8s (normal boot, nothing changed)
```

Then dArkOS boots normally. Wait time is adjustable without rebuilding the
initramfs: add `s1wait=20` to the `APPEND` line in `extlinux.conf`.

## Reading the result

Pull the card (or mount p3 on any PC): **`S1-LOG.txt`** at the root of the
boot partition. That file is the artifact we need — it contains the real
cmdline, the DT model, the DRM/backlight state, block devices and the kernel log.

## Failure modes

| Symptom | Meaning | Action |
|---|---|---|
| Banner appears, then dArkOS | ✅ S1 done, we own the initramfs stage | send `S1-LOG.txt` |
| Banner appears, then hangs | our stage ran, dArkOS handover failed — log is still on the card | `S1-LOG.txt` tells us where; revert |
| No banner, dArkOS boots | the loader is not using `/uInitrd` (u-boot bootcmd ignores extlinux) | important finding — revert and reassess |
| Nothing / black screen | initramfs rejected or too large | revert with `revert-s1.sh` |

Revert is always safe: `uInitrd.orig` is both on the card and in this folder.
