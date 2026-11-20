# 22 — S2: Arch-R rootfs on the proven dArkOS boot chain

**Date:** 2026-11-20 · **Status:** rootfs image built, device boot pending

## Why this is the right shortcut

We already own a built Arch Linux ARM userland: **Arch-R's `ARCHR_ROOT`**
(p2 of `ArchR-R36S.aarch64-20261113-original.img`, ext4, 6 GiB). No ALARM
download, no fresh pacman bootstrap — extract, adapt, write.

And the boot side is already solved by S1's finding: dArkOS's initramfs
**hardcodes `/dev/mmcblk1p4`** as root (`22`/`21`), so *any* rootfs placed there
boots with dArkOS's kernel. No PARTUUID games, no loader work.

```
dArkOS loader (p1/p2, untouched)
  -> extlinux -> /Image (dArkOS 5.10.226) + /uInitrd (S1 patched) + dtb
     -> initramfs mounts /dev/mmcblk1p4            <- our Arch rootfs
        -> run-init -> systemd (ArchR 20261113)
```

## What is inside the S2 image

`~/Andr36oid/rg353v-backup/arch-rootfs/archr-rootfs.img`
(7,786,520,064 B = exactly dArkOS p4; `sha256 89aa6d7f…9460`)

| Change | Detail |
|---|---|
| Base | Arch-R `ARCHR_ROOT`, ext4, grown 6 GiB → 7.25 GiB |
| Kernel modules | dArkOS `5.10.226` (203 files) — matches the running kernel exactly |
| Firmware | dArkOS `/lib/firmware` (309 files) |
| `/usr/lib/modules` | **was a symlink** → `/run/kernel-overlays/modules` (Arch-R overlay design); replaced with a real directory |
| `/usr/lib/firmware` | same: symlink → `/run/kernel-overlays/firmware`; replaced |
| `/etc/shadow` | **was a symlink** → `/storage/.cache/shadow`; replaced with a real file, `root:ark` |
| `/etc/fstab` | `p4 /` ext4 · `p3 /boot` vfat · `p5 /storage` exfat (Arch-R expects `/storage`) |
| `getty@tty1` | enabled (login prompt on the panel) |
| `s2-report.service` | writes `/boot/S2-LOG.txt` and prints it on tty1 |

## Procedure

```bash
# card in the laptop (TF1)
cd ~/Andr36oid/rg353v-internals
sudo tools/s2/write-p4.sh \
  --image ../rg353v-backup/arch-rootfs/archr-rootfs.img \
  --device /dev/mmcblk0
```

Writes **only p4** (`@121,634,816` +7,786,520,064). Loader, `/boot` and
`/storage` stay as they are. Then **cold boot** (power off, wait, power on).

**Expected:** `S2-LOG.txt` on the boot partition, the report printed on the
panel, then a login prompt — user `root`, password `ark`.

**Revert:** `sudo tools/s2/revert-p4.sh --device /dev/mmcblk0` (restores the
stock dArkOS rootfs from the reference image).

## Watch items for this boot

- Arch-R ships a **kernel-overlay** mechanism (the symlinks above); with a
  non-Arch-R kernel its mount service may fail. Non-fatal: `s2-report.sh` lists
  failed units in the log.
- Arch-R's ES autostart expects its own labels (`ARCHR_ROOT`, `STORAGE`) and
  `/storage` quirks; autostart failure is acceptable at S2 — the acceptance
  criterion is **systemd + login prompt**, not the frontend.
- No GPU stack yet (vendor libmali / panfrost is S3 work).
- p5 on the 8 GB card is 135 MB and gets mounted at `/storage`; Arch-R may want
  more space there. Not fatal for the login test.

## Acceptance

`S2-LOG.txt` shows `os: ArchR 20261113`, `kernel: Linux 5.10.226`, root on
`/dev/mmcblk1p4` **ext4**, and a working tty1 login. That is the "our userspace
on their kernel" milestone — S3 then swaps the kernel.

---

## 2026-11-20 — written to the card

`write-p4.sh` completed on the 8 GB `NCard`. Read-back of the partition header:

```
/dev/mmcblk0p4: LABEL="ARCHR_ROOT" TYPE="ext4"
                PARTLABEL="rootfs" PARTUUID="56d34af8-…3212"   (table untouched)
```

p1/p2 (loader) and p3 (boot) unchanged. Device boot pending.

**Write-speed lesson:** with `bs=512` the 7.3 GB took **23 minutes at 5.5 MB/s**.
p4 starts at exactly **116 MiB**, so `bs=1M` is aligned — both scripts now use
that (≈10× faster). The last 52 KB of p4 were left untouched, which is beyond
the filesystem end (fs = 7,784,588,288 B) and harmless.

---

## 2026-11-21 — first S2 boot: stuck at splash, cause found in one diag pass

`S2-DIAG.txt` (saved to the boot FAT by the diagnostic initramfs) showed the
rootfs itself is perfect:

```
MOUNT OK (ext4) · ArchR 20261113 · systemd 255 (255.8)
SHELL_OK · uid=0(root) · root:$6$…
dev/console : No such file or directory      <-- the bug
```

dArkOS's initramfs ends with:

```sh
exec run-init … "${rootmnt}" "${init}" <"${rootmnt}/dev/console" >"${rootmnt}/dev/console"
```

Arch-R ships an **empty `/dev`**, so the redirection fails, `run-init` never
executes, and the resulting panic goes to `console=ttyUSB0` (invisible) — the
device just keeps showing the splash.

**Fix (two places):**

1. Rootfs image now carries static `/dev/console` (5:1) and `/dev/null` (1:3)
   — `archr-rootfs.img` sha256 `7d6e3a9d…`.
2. `tools/s2/uInitrd.s2fix` adds a shim before `run-init` that creates the node
   if missing (generic: works for any rootfs with an empty `/dev`). 12 MB write
   instead of rewriting 7.3 GB.

Installed on the card: `/uInitrd` sha256 `2f5b5d1e…cfb9`.

---

## 2026-11-21 — the handover works; the OS is booting

Our tracer init proved, on hardware:

```
root: /dev/mmcblk1p4 ext4 -> OK
os  : PRETTY_NAME="ArchR 20261113"
installed visible init wrapper
=== exec switch_root ===      (never returned = success)
```

Offline checks of p4 confirm systemd ran: `/etc/machine-id` created, Arch-R's
storage setup written (`/storage/.configured`, `.pacman/.initialized`). It just
never reaches `multi-user.target`, and the panel shows nothing because the
loader forces `console=ttyUSB0`.

Instrumentation added (rootfs-only, no reimage — overlay in
`tools/s2/rootfs-overlay/`):

| Item | Effect |
|---|---|
| `journald.conf.d/90-console.conf` | every journal line mirrored to `/dev/tty1` |
| `s2-bootlog.timer` (45 s) + service | dumps jobs, failed units, journal tail, mounts to `/root/s2-BOOTLOG.txt`, `/boot/S2-BOOTLOG.txt`, and the panel |
| `fstab` | p5 mount removed (it was failing); `/boot` stays nofail |

Note: the device has **no keyboard/mouse**, so a getty prompt cannot be used for
input — visible journal output is the practical interface until sway/ES work.
