#!/bin/bash
# Restore the stock uInitrd from p3:/uInitrd.orig (or a local copy).
#   revert-s1.sh <block-device|image> [uInitrd.orig]
set -euo pipefail
TARGET="${1:?usage: revert-s1.sh <block-device|image> [uInitrd.orig]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${2:-}"
MNT=/tmp/opencode/s1boot; mkdir -p "$MNT"
case "$TARGET" in
  /dev/*) DEV="$TARGET"; OWN_LOOP=0 ;;
  *) DEV="$(sudo losetup -f --show -P "$TARGET")"; OWN_LOOP=1 ;;
esac
cleanup() { sudo umount "$MNT" 2>/dev/null || true; [ "$OWN_LOOP" = 1 ] && sudo losetup -d "$DEV" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${DEV}p3" "$MNT"
if [ -z "$SRC" ] && [ -f "$MNT/uInitrd.orig" ]; then SRC="$MNT/uInitrd.orig"; fi
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "no backup found (pass uInitrd.orig path)"; exit 1; }
sudo cp "$SRC" "$MNT/uInitrd.new" && sudo mv -f "$MNT/uInitrd.new" "$MNT/uInitrd"
sync
echo "reverted: ${DEV}p3:/uInitrd <- $SRC"
echo "sha256  : $(sudo sha256sum "$MNT/uInitrd" | cut -d' ' -f1)"
