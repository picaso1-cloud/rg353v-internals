#!/bin/sh
# build-pak.sh — pack a "<Name>.pak" folder the way the stores expect.
#
#   ./build-pak.sh "template/System Info.pak" [output-dir]
#
# Output: <Name>.pak.zip with the pak's CONTENTS at the zip root, plus .sha256.
# Spaces become dots in the asset name (Game.Manager.pak.zip convention) and the
# name is cross-checked against "release_filename" in pak.json when present.
set -eu

pak=${1:?usage: build-pak.sh <path/to/Name.pak> [output-dir]}
[ -d "$pak" ] || { echo "no such folder: $pak" >&2; exit 1; }
[ -f "$pak/launch.sh" ] || { echo "$pak has no launch.sh" >&2; exit 1; }

root=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "${2:-$root/dist}" && cd "${2:-$root/dist}" && pwd)

name=$(basename "$pak" .pak)
asset=$(printf '%s' "$name" | tr ' ' '.')
zipfile="$out/$asset.pak.zip"

(cd "$pak" && zip -qr "$zipfile" . -x '.*' -x '*/.*')

want=$(sed -n 's/.*"release_filename"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pak/pak.json" 2>/dev/null | head -1)
if [ -n "$want" ] && [ "$want" != "$asset.pak.zip" ]; then
	echo "warning: pak.json says release_filename=\"$want\" but this build made \"$asset.pak.zip\"" >&2
fi

( cd "$out" && sha256sum "$asset.pak.zip" >"$asset.pak.zip.sha256" )
ls -lh "$zipfile" "$zipfile.sha256"
echo "contents:"
unzip -Z1 "$zipfile" | head -20
