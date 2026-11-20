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
P4_START_SECT=237568; P4_SIZE_SECT=15208047
if [ "$YES" != 1 ]; then echo "Restore stock p4 from $IMG. Type ERASE:"; read -r a; [ "$a" = ERASE ] || exit 1; fi
P4_OFF_MIB=$((P4_START_SECT/2048))
sudo dd if="$IMG" of="$DEV" bs=1M skip=$P4_OFF_MIB seek=$P4_OFF_MIB \
        count=$((P4_SIZE_SECT/2048)) conv=fsync,notrunc status=progress
sync; sudo partprobe "$DEV" 2>/dev/null || true
echo "restored stock dArkOS p4."
