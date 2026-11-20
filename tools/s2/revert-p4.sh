#!/bin/bash
# Restore the stock dArkOS rootfs (p4) from the reference image.
#   revert-p4.sh --device /dev/mmcblk0 [--image dArkOS.img] [--yes]
set -euo pipefail
DEV=""; IMG=""; YES=0
HERE="$(cd "$(dirname "$0")" && pwd)"
DEF_IMG="$HERE/../../rg353v-backup/images/dArkOS_RG353v_trixie_11072026.img"
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEV="$2"; shift 2 ;;
    --image) IMG="$2"; shift 2 ;;
    --yes) YES=1; shift ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done
IMG="${IMG:-$DEF_IMG}"
[ -n "$DEV" ] && [ -b "$DEV" ] || { echo "usage: $0 --device /dev/mmcblk0 [--image dArkOS.img]"; exit 2; }
[ -f "$IMG" ] || { echo "missing image: $IMG"; exit 1; }
P4_OFFSET=121634816; P4_SIZE=7786520064
if [ "$YES" != 1 ]; then echo "Restore stock p4 from $IMG. Type ERASE:"; read -r a; [ "$a" = ERASE ] || exit 1; fi
sudo dd if="$IMG" of="$DEV" bs=8M skip=$((P4_OFFSET/8388608)) seek=$((P4_OFFSET/8388608)) \
        count=$((P4_SIZE/8388608 + 1)) conv=fsync,notrunc status=progress
sync; sudo partprobe "$DEV" 2>/dev/null || true
echo "restored stock dArkOS p4."
