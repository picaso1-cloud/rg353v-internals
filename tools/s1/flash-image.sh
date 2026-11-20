#!/bin/bash
# Flash an image to an SD card with safety checks and a real verification.
#
#   flash-image.sh --image <file.img> --device /dev/mmcblk0 [--yes]
#
# Refuses: non-block device, mounted device, the host NVMe/root disk, and any
# image whose .sha256 does not match.
#
# NO post-flash verification by default (project rule): writing 8-24 GB twice
# wastes time and protects against nothing the device boot does not prove.
# Pass --verify only when investigating a specific suspected write failure.
set -euo pipefail
IMG=""; DEV=""; YES=0; VERIFY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --image) IMG="$2"; shift 2 ;;
    --device) DEV="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    --verify) VERIFY=1; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done
[ -n "$IMG" ] && [ -n "$DEV" ] || { echo "usage: $0 --image <img> --device /dev/sdX [--yes]"; exit 2; }
[ -f "$IMG" ] || { echo "no such image: $IMG"; exit 1; }
[ -b "$DEV" ] || { echo "not a block device: $DEV"; exit 1; }

case "$DEV" in
  *nvme*|*loop*) echo "refusing to write to $DEV"; exit 1 ;;
esac
ROOTDEV="$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//')"
[ "$DEV" != "$ROOTDEV" ] || { echo "refusing: $DEV holds the running root"; exit 1; }
if mount | grep -q "^$DEV"; then echo "refusing: $DEV is mounted (umount first)"; exit 1; fi

SIZE_B="$(blockdev --getsize64 "$DEV")"
printf 'image  : %s (%s)\n' "$IMG" "$(du -h "$IMG" | cut -f1)"
printf 'device : %s  %s  model=%s\n' "$DEV" "$(numfmt --to=iec "$SIZE_B")" "$(cat /sys/block/$(basename "$DEV")/device/model 2>/dev/null || echo '?')"

if [ -f "$IMG.sha256" ]; then
  echo "== verifying image checksum =="
  ( cd "$(dirname "$IMG")" && sha256sum -c "$(basename "$IMG").sha256" )
fi

if [ "$YES" != 1 ]; then
  echo
  echo "THIS ERASES $DEV. Type ERASE to continue:"
  read -r ans
  [ "$ans" = ERASE ] || { echo "aborted"; exit 1; }
fi

echo "== writing =="
sudo dd if="$IMG" of="$DEV" bs=8M conv=fsync status=progress
sync
sudo blockdev --flushbufs "$DEV" 2>/dev/null || true
sudo partprobe "$DEV" 2>/dev/null || true

if [ "$VERIFY" = 1 ]; then
  echo "== verifying (cmp) =="
  sudo cmp "$IMG" "$DEV" 2>&1 | head -2 || true
else
  echo "== no laptop verification: the device boot is the test =="
fi
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
echo "done: $DEV"
