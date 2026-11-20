# 19 — S1: our initramfs stage on the working dArkOS card

**Date:** 2026-11-20 · **Status:** artifact built and verified · **device boot pending**

## Why this stage exists

Every ROCKNIX attempt failed invisibly: the device showed Android and we could
not tell *which* stage gave up. S1 fixes that permanently. It is the smallest
possible change that proves we control the boot chain:

- the stock `/init` (Debian initramfs-tools) is kept and still does the real
  handover (`run-init` into dArkOS),
- our banner runs once, after `/dev` exists, before root mounting,
- it writes `S1-LOG.txt` to the **boot FAT**, so the evidence comes back on the
  card even if the device never reaches userspace.

## Change set (verified by pristine-vs-patched diff)

| Entry in `uInitrd` | Change |
|---|---|
| `scripts/s1-banner.sh` | new, 8 KB shell script (banner + facts + `dmesg` + FAT write) |
| `init` | +5 guarded lines after the `devpts` mount |

Nothing else changes: no kernel, no DTB, no `extlinux.conf`, no rootfs.

## Artifacts (`tools/s1/`)

| File | SHA-256 |
|---|---|
| `uInitrd.orig` | `6f65778bab4060befc465a3bd6d4394b9f9d8aa87b66a167093332a3beb23173` |
| `uInitrd.s1` | `94544e464018098c06c6e6fec92d0f51bf225e205285e0f0bedd2152b5c22011` |

`patch-initramfs.sh` reproduces `uInitrd.s1` byte-identically (432 entries,
`cpio --reproducible`, owner 0:0, mtimes normalised).

## Procedure

1. `sudo tools/s1/install-s1.sh /dev/mmcblk0` (writes only `p3:/uInitrd`,
   keeps `p3:/uInitrd.orig`, verifies read-back hash).
2. Boot the RG353V with TF1.
3. Photograph the panel; then pull the card and copy **`S1-LOG.txt`** from the
   boot partition.
4. Revert when done: `sudo tools/s1/revert-s1.sh /dev/mmcblk0`.

## What the log gives us (the point of the stage)

- the **real** cmdline the loader passes (proves whether u-boot reads
  `extlinux.conf` or uses a hardcoded `bootcmd`),
- the DT model/compatible actually in use,
- DRM connector state and backlight values (panel v2 `0x3821` confirmation),
- block-device topology (`mmcblk0` = eMMC Android, `mmcblk1` = TF1; and whether
  TF2 exists as `mmcblk1`/`mmcblk0` alternative),
- the kernel log from early boot — the first real boot log this device has
  produced for us.

## Interpretation guide

| Result | Conclusion | Next |
|---|---|---|
| Banner + normal dArkOS | initramfs stage is ours | S2: Arch rootfs on dArkOS's kernel |
| Banner + hang | initramfs ran, handover broke | the log's last lines say which mount/step; revert |
| No banner, dArkOS boots | loader ignores `/uInitrd` | u-boot uses a fixed `bootcmd`; S1 must move to the `Image` path instead |
| Black screen | initramfs load/format problem | revert; compare size/compression with stock |

## Risk

Low and bounded: two entries, guarded call, stock handover untouched, backup on
the card and in this repo. Worst case the card needs `revert-s1.sh`.

---

## 2026-11-21 — first hardware result: S1 works

Boot on the 8 GB `NCard` with `dArkOS_S1.img`:

1. **The banner appeared** (a `====…` line with a trailing dmesg fragment
   `…ontroller` remained visible at the bottom of the screen after dArkOS's
   splash took over). ⇒ the patched initramfs ran; we own that stage.
2. dArkOS userspace started (first-boot wizard, setup log) ⇒ the stock
   `run-init` handover still worked with our insertion.
3. Then the **first-boot expansion failed** and the system rebooted — see
   `15-darkos-migration.md` ("8 GB card: the expansion is mathematically
   impossible"). This is a card-size problem, not an S1 problem.
4. After that reboot the device landed on Android.

`S1-LOG.txt` was not retrieved yet (card stayed in the device). It is written on
every boot, so any later insertion of that card still has it.
