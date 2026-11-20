# 24 — RAM-only live system + dual-mode boot toggle (no more card pulls)

**Date:** 2026-11-21 · **Status:** ✅ working on hardware, used in anger

## What it is

A 23 MB initramfs that boots **entirely in RAM** (root = tmpfs, nothing from the
SD mounted), brings up Wi-Fi and sshd, and leaves the card free to rewrite from
inside the device. It is *also* the normal boot path: a marker file on p3
selects the mode.

| p3 state | Boot result |
|---|---|
| `/NORMAL` absent | **live mode** — RAM root, Wi-Fi + sshd, shell on tty1 |
| `/NORMAL` present | **normal mode** — mounts p4 and `switch_root` into ArchR |

Toggle from either side:

```sh
# live -> normal
mount /dev/mmcblk1p3 /mnt && touch /mnt/NORMAL && sync && umount /mnt && reboot
# normal -> live   (in the real system /boot is p3)
rm /boot/NORMAL && sync && reboot
```

## Why it matters

Every previous experiment cost a card pull. Now:

- write images to p4, swap files on p3, `e2fsck`/`fsck.vfat`, test userspace
  changes — all over SSH, then `reboot`;
- the toggle is a single file, so a broken *rootfs* can never lock us out
  (live mode does not depend on p4 at all).

**Limit:** a broken **kernel or initramfs on p3** still locks us out — u-boot
loads `/Image` and `/uInitrd` before anything we control. Kernel experiments
still need a card (or a u-boot fallback script, not yet built).

## What is inside

| Part | Source |
|---|---|
| busybox + initramfs base | dArkOS `uInitrd` |
| `8821cs.ko` + 8821c firmware | dArkOS 5.10.226 module set |
| `wpa_supplicant` + `libnl`/`pcsc` | dArkOS rootfs (ArchR has no wpa_supplicant) |
| `sshd`, `sshd-session`, `sshd-auth`, `ssh-keysign`, `sftp-server` | dArkOS rootfs + 21 libs |
| NSS (`libnss_files`, `libnss_dns`), `/etc/services`, `nsswitch.conf` | dArkOS rootfs |
| dashboard / console | our `s2-console` in the real system |

Networking uses a **static** `192.168.0.198/24` (gw `.1`) — no DHCP dependency in
RAM. Root password `ark`.

## Failure chain solved while building it (all from `/live.log` on p3)

1. `busybox` has no `telnetd`/`nc` → needed real `sshd`
2. `Privilege separation user sshd does not exist` → added `sshd`/`nogroup` users
3. `/usr/lib/openssh/sshd-session does not exist` → modern OpenSSH splits the
   binary; added `sshd-session`, `sshd-auth`, `ssh-keysign`
4. glibc NSS modules are `dlopen`ed, invisible to `DT_NEEDED` → added
   `libnss_files.so.2`, `libnss_dns.so.2`

Lesson: on a minimal initramfs, `DT_NEEDED` is **not** the full dependency set.

## Artifacts

- `~/Andr36oid/rg353v-backup/live/uInitrd.live` (23 MB, reproducible build)
- builder: `/tmp/opencode/build-live.sh` (to be moved into the repo)
- installed on p3 as `/uInitrd`; stock dArkOS initramfs kept in
  `boot-backup/uInitrd.tracer` on p4
