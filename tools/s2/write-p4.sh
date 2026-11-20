#!/bin/bash
# Replace ONLY partition 4 (the rootfs) of a dArkOS card with the S2 Arch rootfs.
#
#   write-p4.sh --image <archr-rootfs.img> --device /dev/mmcblk0 [--yes]
#
# The loader (p1/p2), boot files (p3) and /storage (p5) are untouched.
# No post-write verification: the device boot is the test.
set -euo pipefail
IMG=""; DEV=""; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMG="$2"; shift 2 ;;
    --device) DEV="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done
[ -n "$IMG" ] && [ -n "$DEV" ] || { echo "usage: $0 --image <img> --device /dev/mmcblk0 [--yes]"; exit 2; }
[ -f "$IMG" ] || { echo "no such image: $IMG"; exit 1; }
[ -b "$DEV" ] || { echo "not a block device: $DEV"; exit 1; }
case "$DEV" in *nvme*|*loop*) echo "refusing to write to $DEV"; exit 1 ;; esac
[ "$DEV" != "$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//')" ] || { echo "refusing: holds running root"; exit 1; }
mount | grep -q "^$DEV" && { echo "refusing: $DEV mounted"; exit 1; }

# dArkOS p4 geometry (verified on the 8 GB card and in the image)
P4_START_SECT=237568          # 121,634,816 B
P4_SIZE_SECT=15208047         # 7,786,520,064 B
P4_OFFSET=$((P4_START_SECT*512))
P4_SIZE=$((P4_SIZE_SECT*512))
ISIZE=$(stat -c %s "$IMG")
[ "$ISIZE" -le "$P4_SIZE" ] || { echo "image ($ISIZE) larger than p4 ($P4_SIZE)"; exit 1; }

printf 'image  : %s (%s)\n' "$IMG" "$(du -h "$IMG" | cut -f1)"
printf 'device : %s  p4 @%s +%s\n' "$DEV" "$P4_OFFSET" "$P4_SIZE"
if [ "$YES" != 1 ]; then
  echo "This overwrites p4 (rootfs) only. Type ERASE to continue:"; read -r a
  [ "$a" = ERASE ] || { echo aborted; exit 1; }
fi

# p4 starts at exactly 116 MiB -> bs=1M is aligned and ~10x faster than bs=512
P4_OFF_MIB=$((P4_START_SECT/2048))
sudo dd if="$IMG" of="$DEV" bs=1M seek=$P4_OFF_MIB count=$((ISIZE/1048576)) \
        conv=fsync,notrunc status=progress
sync; sudo partprobe "$DEV" 2>/dev/null || true
echo "done. cold boot (full power off) and expect S2-LOG.txt on the boot partition."
echo "revert: tools/s2/revert-p4.sh --device $DEV"
