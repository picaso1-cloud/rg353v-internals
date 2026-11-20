#!/bin/bash
# Install the S1 initramfs onto a dArkOS card (block device) or image file.
#
#   install-s1.sh <block-device|image> [uInitrd.s1]
#
# Touches exactly one file: p3:/uInitrd. Keeps a backup as p3:/uInitrd.orig if
# none exists (12 MB; check free space first).
set -euo pipefail
TARGET="${1:?usage: install-s1.sh <block-device|image> [uInitrd.s1]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NEW="${2:-$HERE/uInitrd.s1}"
MNT=/tmp/opencode/s1boot
[ -f "$NEW" ] || { echo "missing $NEW (run patch-initramfs.sh first)"; exit 1; }
mkdir -p "$MNT"

case "$TARGET" in
  /dev/*) DEV="$TARGET"; OWN_LOOP=0 ;;
  *) DEV="$(sudo losetup -f --show -P "$TARGET")"; OWN_LOOP=1 ;;
esac
cleanup() { sudo umount "$MNT" 2>/dev/null || true; [ "$OWN_LOOP" = 1 ] && sudo losetup -d "$DEV" 2>/dev/null || true; }
trap cleanup EXIT

sudo mount "${DEV}p3" "$MNT"
[ -f "$MNT/Image" ] || { echo "p3 does not look like dArkOS_Fat (no /Image)"; exit 1; }

if [ ! -f "$MNT/uInitrd.orig" ] && [ ! -f "$HERE/uInitrd.orig" ]; then
  echo "no backup source (p3:/uInitrd.orig or $HERE/uInitrd.orig) — refusing"
  exit 1
fi
[ -f "$MNT/uInitrd.orig" ] || sudo cp "$HERE/uInitrd.orig" "$MNT/uInitrd.orig"

WANT="$(sha256sum "$NEW" | cut -d' ' -f1)"
sudo cp "$NEW" "$MNT/uInitrd.new"
sudo mv -f "$MNT/uInitrd.new" "$MNT/uInitrd"
sync
GOT="$(sudo sha256sum "$MNT/uInitrd" | cut -d' ' -f1)"
[ "$WANT" = "$GOT" ] || { echo "read-back mismatch: want $WANT got $GOT"; exit 1; }
echo "installed: ${DEV}p3:/uInitrd  ($GOT)"
echo "backup   : ${DEV}p3:/uInitrd.orig"
