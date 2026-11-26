#!/bin/bash
# Inject the proven dual-mode initramfs into p3 of a built Arch-R RG353V image.
#
# WHY THIS IS NEEDED
# ------------------
# The dArkOS boot chain (p1/p2/p3) ships dArkOS's own initramfs, which is
# built for a **btrfs** rootfs (scripts/local-premount/btrfs; no ext4 module).
# The Arch-R rootfs we write into p4 is **ext4**. The dArkOS init would have to
# auto-detect the filesystem; the RG353V's own live initramfs does not guess:
#
#     mount -t ext4 -o rw /dev/mmcblk1p4 /root
#
# and then switch_root into Arch-R when the NORMAL marker exists on p3.
# That combination (5.10.226 + this initramfs + ext4 p4) is the one that
# booted on the device before, so the build injects it.
#
# Usage:
#   sudo bash inject-initrd.sh <image.img> [uInitrd.live]
set -euo pipefail

IMG="${1:?usage: inject-initrd.sh <image.img> [initramfs]}"
LIVE="${2:-/home/souhail/Andr36oid/rg353v-backup/live/uInitrd.live.latest}"
MNT=/mnt/archr-inject

[[ -f "$IMG" ]] || { echo "no such image: $IMG" >&2; exit 1; }
[[ -f "$LIVE" ]] || { echo "no initramfs: $LIVE" >&2; exit 1; }

mkdir -p "$MNT"
LOOP=$(losetup -f --show -P "$IMG")
trap 'umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT
partprobe "$LOOP"; sleep 1

mount "${LOOP}p3" "$MNT"
cp -f "$LIVE" "$MNT/uInitrd"
touch "$MNT/NORMAL"
sync
echo "== p3 after injection =="
ls -la "$MNT/uInitrd" "$MNT/NORMAL"
cat "$MNT/extlinux/extlinux.conf" 2>/dev/null || true
umount "$MNT"
echo "OK: initramfs + NORMAL marker injected into $IMG"
