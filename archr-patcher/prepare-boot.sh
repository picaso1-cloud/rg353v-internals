#!/bin/bash
# Prepare the boot partition (p3) of a built Arch-R RG353V image:
#
#   1. inject the RG353V's dual-mode initramfs (the dArkOS one is btrfs-only
#      and the Arch-R rootfs is ext4 - see 31-archr-ext4-rootfs-initrd.md)
#   2. cap the Wi-Fi SDIO bus (sdmmc2 / fe000000) to 25 MHz
#      (TurboRelic's proven fix: the board's SDIO signal integrity breaks
#      above 25 MHz and the probe hangs the kernel)
#   3. write the NORMAL marker so the initramfs boots the real rootfs
#
# Usage: sudo bash prepare-boot.sh <image.img> [initramfs]
set -euo pipefail

IMG="${1:?usage: prepare-boot.sh <image.img> [uInitrd]}"
LIVE="${2:-/home/souhail/Andr36oid/rg353v-backup/live/uInitrd.live}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
MNT=/mnt/archr-boot
WIFI_MMC_MAX=25000000   # 25 MHz, TurboRelic patch 0001

[[ -f "$IMG" ]] || { echo "no such image: $IMG" >&2; exit 1; }
[[ -f "$LIVE" ]] || { echo "no initramfs: $LIVE" >&2; exit 1; }

cleanup() { umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$MNT"
LOOP=$(losetup -f --show -P "$IMG")
partprobe "$LOOP"; sleep 1
mount "${LOOP}p3" "$MNT"

echo "== 1. initramfs =="
cp -f "$LIVE" "$MNT/uInitrd"
touch "$MNT/NORMAL"
ls -la "$MNT/uInitrd" "$MNT/NORMAL"

echo
echo "== 2. the Wi-Fi SDIO bus: cap it to ${WIFI_MMC_MAX} Hz =="
for dtb in rk3566-353v.dtb rk3566-353v-notimingchange.dtb; do
  [[ -f "$MNT/$dtb" ]] || { echo "  (no $dtb)"; continue; }
  cp -f "$MNT/$dtb" "$WORK/$dtb"
  dtc -I dtb -O dts -o "$WORK/$dtb.dts" "$WORK/$dtb" 2>/dev/null
  python3 - "$WORK/$dtb.dts" "$WIFI_MMC_MAX" <<'PY'
import re, sys
path, want = sys.argv[1], int(sys.argv[2])
s = open(path).read()
m = re.search(r'(dwmmc@fe000000 \{.*?\n\t\t\};)', s, re.S)
if not m:
    sys.exit("  ! the Wi-Fi node (dwmmc@fe000000) is not in this DTB")
node = m.group(1)
old = re.search(r'max-frequency = <0x[0-9a-f]+>;', node)
if old:
    print(f"  max-frequency {old.group(0)} -> <{want}>")
    node = re.sub(r'max-frequency = <0x[0-9a-f]+>;', f'max-frequency = <{want}>;', node, count=1)
else:
    node = node.replace('bus-width', f'max-frequency = <{want}>;\n\t\tbus-width', 1)
s = s[:m.start(1)] + node + s[m.end(1):]
open(path, "w").write(s)
PY
  dtc -@ -I dts -O dtb -o "$MNT/$dtb" "$WORK/$dtb.dts" 2>/dev/null
  printf "  %s -> " "$dtb"
  fdtget "$MNT/$dtb" /dwmmc@fe000000 max-frequency 2>/dev/null || \
    fdtget "$MNT/$dtb" /soc/sdmmc2@fe000000 max-frequency 2>/dev/null || echo "?"
done

echo
echo "== 3. the boot config =="
cat "$MNT/extlinux/extlinux.conf" 2>/dev/null || true
sync
umount "$MNT"
echo
echo "OK: the boot partition of $IMG is prepared"
