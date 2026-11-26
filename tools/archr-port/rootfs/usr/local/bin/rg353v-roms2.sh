#!/bin/sh
# Point /run/archr/roms2 at the TF2 card's ROM collection.
#
# ARCH-R's automount publishes /run/archr/roms2 -> <card>/roms, the layout
# the Arch-R images write. The RG353V's TF2 card carries the ArkOS layout
# instead: the system folders (psx, snes, gba, dreamcast, ...) sit at the
# card root next to bios/ and AnberNext/, and <card>/roms holds only the
# empty folders ARCH-R created for itself.
#
# So: keep the default when <card>/roms really holds games, and use the card
# root when it does not but the root does. Nothing is copied; only the
# symlink changes.
set -u

MOUNT=/storage/games-external
LINK=/run/archr/roms2

[ -d "$MOUNT" ] || exit 0

has_games() {
    # a folder with something in it that is not ARCH-R's _info.txt marker
    find "$1" -mindepth 1 -maxdepth 2 -type f ! -name '_info.txt' 2>/dev/null | head -n 1 | grep -q .
}

if has_games "$MOUNT/roms"; then
    target="$MOUNT/roms"          # the usual Arch-R layout
elif has_games "$MOUNT"; then
    target="$MOUNT"               # the ArkOS layout: the folders are at the root
else
    exit 0                        # no games on the card (yet)
fi

if [ "$(readlink -f "$LINK" 2>/dev/null)" != "$target" ]; then
    ln -sfn "$target" "$LINK"
    echo "roms2 -> $target"
fi
