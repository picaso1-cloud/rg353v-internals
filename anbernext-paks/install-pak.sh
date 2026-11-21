#!/bin/sh
# install-pak.sh — copy a pak onto a NEXTUI card that is mounted on this computer.
#
#   ./install-pak.sh /media/you/NEXTUI "template/System Info.pak"
#
# The card must be the NEXTUI (FAT32) partition — the one with .system/rg353.
# Nothing else on the card is touched. Power the device off and sync before you
# unplug it.
set -eu

card=${1:?usage: install-pak.sh <NEXTUI mount point> <path/to/Name.pak>}
pak=${2:?usage: install-pak.sh <NEXTUI mount point> <path/to/Name.pak>}

[ -d "$card/.system/rg353" ] || {
	echo "$card does not look like the NEXTUI card (no .system/rg353)" >&2
	echo "mount the FAT32 partition labelled NEXTUI, not NEXTBOOT/NEXTROOT" >&2
	exit 1
}
[ -f "$pak/launch.sh" ] || { echo "$pak has no launch.sh" >&2; exit 1; }

dest="$card/Tools/rg353"
mkdir -p "$dest"
rm -rf "$dest/$(basename "$pak")"
cp -a "$pak" "$dest/"
chmod 0755 "$dest/$(basename "$pak")/launch.sh" 2>/dev/null || true
sync
echo "installed: $dest/$(basename "$pak")"
