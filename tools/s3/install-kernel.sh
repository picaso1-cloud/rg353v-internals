#!/bin/bash
# S3: swap the running kernel to ROCKNIX mainline 7.2.11 (panfrost + rtw88).
#   install-kernel.sh [--device /dev/mmcblk0] [--revert]
# Touches: p4 /usr/lib/modules/7.2.11 + firmware, p3 /Image + /rk3566-353v.dtb.
# Backups: p3 /Image.darkos-5.10, /rk3566-353v.dtb.darkos (created once).
set -euo pipefail
DEV=/dev/mmcblk0; MODE=install
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEV="$2"; shift 2 ;;
    --revert) MODE=revert; shift ;;
    *) echo "unknown arg $1"; exit 2 ;;
  esac
done
B=/home/souhail/Andr36oid/rg353v-backup/rocknix-kernel
[ -b "$DEV" ] || { echo "no card at $DEV"; exit 1; }
L=$(sudo losetup -f --show -P "$DEV"); trap 'sudo umount /mnt/s3p3 /mnt/s3p4 2>/dev/null; sudo losetup -d "$L"' EXIT
sudo mkdir -p /mnt/s3p3 /mnt/s3p4

sudo mount "${L}p3" /mnt/s3p3
sudo mount "${L}p4" /mnt/s3p4

if [ "$MODE" = revert ]; then
  [ -f /mnt/s3p3/Image.darkos-5.10 ] && sudo cp -f /mnt/s3p3/Image.darkos-5.10 /mnt/s3p3/Image
  [ -f /mnt/s3p3/rk3566-353v.dtb.darkos ] && sudo cp -f /mnt/s3p3/rk3566-353v.dtb.darkos /mnt/s3p3/rk3566-353v.dtb
  sudo sync; echo "reverted to dArkOS 5.10 kernel"; exit 0
fi

# modules + firmware
sudo mkdir -p /mnt/s3p4/usr/lib/modules /mnt/s3p4/usr/lib/firmware
sudo cp -a "$B/7.2.11" /mnt/s3p4/usr/lib/modules/
sudo cp -an "$B/firmware/." /mnt/s3p4/usr/lib/firmware/
printf 'rtw88_8821cs\n' | sudo tee /mnt/s3p4/etc/modules-load.d/rtw88.conf >/dev/null

# kernel + dtb (backup once)
[ -f /mnt/s3p3/Image.darkos-5.10 ] || sudo cp /mnt/s3p3/Image /mnt/s3p3/Image.darkos-5.10
[ -f /mnt/s3p3/rk3566-353v.dtb.darkos ] || sudo cp /mnt/s3p3/rk3566-353v.dtb /mnt/s3p3/rk3566-353v.dtb.darkos
sudo cp -f "$B/KERNEL" /mnt/s3p3/Image
sudo cp -f "$B/rk3566-anbernic-rg353v.dtb" /mnt/s3p3/rk3566-353v.dtb
sudo sync
echo "installed 7.2.11 (revert: $0 --device $DEV --revert)"
ls -lh /mnt/s3p3/Image /mnt/s3p3/rk3566-353v.dtb /mnt/s3p4/usr/lib/modules
