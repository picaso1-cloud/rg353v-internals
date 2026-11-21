#!/bin/sh
# extract.sh — pull the proven AnberNext boot artifacts out of a card or image.
#
#   ./extract.sh /dev/mmcblk0            # a card in a reader
#   ./extract.sh anbernext-v3.26.img     # a raw image file
#   ./extract.sh /dev/mmcblk0 /tmp/out   # choose the output directory
#
# It finds the FAT partition labelled NEXTBOOT, mounts it read-only, copies the
# device trees, overlays, boot config and Android markers, decompiles the DTBs,
# and writes SHA256SUMS. Requires sudo (mount/loop) and dtc.
set -eu

src=${1:?usage: extract.sh <device|image> [outdir]}
out=${2:-$(cd "$(dirname "$0")" && pwd)/extracted}
img=""

[ -r "$src" ] || { echo "cannot read $src" >&2; exit 1; }

cleanup() {
	[ -n "${mnt:-}" ] && sudo umount "$mnt" 2>/dev/null || true
	[ -n "$img" ] && sudo losetup -d "$img" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ -f "$src" ]; then
	img=$(sudo losetup -f --show -P "$src")
	sleep 1
	dev=$img
else
	dev=$src
fi

# find the partition labelled NEXTBOOT that belongs to this device
part=""
for p in "$dev"?* "$dev"p*; do
	[ -b "$p" ] || continue
	[ "$(sudo blkid -s LABEL -o value "$p" 2>/dev/null)" = "NEXTBOOT" ] && { part=$p; break; }
done
[ -n "$part" ] || { echo "no partition labelled NEXTBOOT under $dev" >&2; exit 1; }

mnt=$(mktemp -d /tmp/anbernext-boot.XXXXXX)
sudo mount -o ro "$part" "$mnt"

mkdir -p "$out/overlays" "$out/extlinux"
sudo cp -a "$mnt"/rk3566-353v.dtb "$mnt"/rk3566-353v-notimingchange.dtb "$out"/
sudo cp -a "$mnt"/overlays/*.dtbo "$out/overlays/"
sudo cp -a "$mnt"/boot.scr "$mnt"/LEIA-ME.txt \
	"$mnt"/android.go "$mnt"/android.no "$mnt"/android.req "$out"/
sudo cp -a "$mnt"/boot/extlinux/extlinux.conf "$out/extlinux/"

sudo chown -R "$(id -u):$(id -g)" "$out"

for f in "$out"/*.dtb; do
	dtc -I dtb -O dts -s -o "${f%.dtb}.dts" "$f" 2>/dev/null
done
for f in "$out"/overlays/*.dtbo; do
	dtc -I dtb -O dts -s -o "${f%.dtbo}.dts" "$f" 2>/dev/null
done

( cd "$out" && sha256sum rk3566-353v.dtb rk3566-353v-notimingchange.dtb \
	overlays/*.dtbo boot.scr extlinux/extlinux.conf android.* > SHA256SUMS )
( cd "$out" && sha256sum -c SHA256SUMS >/dev/null ) && echo "hashes verified"

echo "extracted to $out"
ls -lh "$out"
