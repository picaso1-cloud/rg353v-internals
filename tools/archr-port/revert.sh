#!/bin/bash
# SPDX-License-Identifier: MIT
# Undo the RG353V ArchR port: go back to a plain multi-user boot with
# SSH + Wi-Fi and the dashboard, UI stack masked again.
#
#   sudo bash revert.sh [/dev/mmcblk0]

set -euo pipefail
CARD="${1:-/dev/mmcblk0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MNT=/mnt/archr-port

LOOP=$(losetup -f --show -P "$CARD")
trap 'umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT
mkdir -p "$MNT"; mount "${LOOP}p4" "$MNT"
R="$MNT"; S="$R/etc/systemd/system"

rm -f "$S/default.target"
ln -sf /usr/lib/systemd/system/multi-user.target "$S/default.target"
rm -rf "$S/archr.target.wants"

for u in archr-automount.service archr-autostart.service \
         archr-launcher-session.service archr-levels.service sway.service; do
  ln -sf /dev/null "$S/$u"
done
rm -f "$S/multi-user.target.wants/archr-levels.service" \
      "$S/multi-user.target.wants/input.service" \
      "$S/multi-user.target.wants/headphones.service"
ln -sf /etc/systemd/system/s2-console.service \
       "$S/multi-user.target.wants/s2-console.service" 2>/dev/null || true
ln -sf /usr/lib/systemd/system/getty@.service \
       "$S/getty.target.wants/getty@tty1.service"
rm -f "$S/getty.target.wants/getty@tty2.service"
sed -i -E 's|^# disabled for ArchR \(rootfs /storage used\): ||' "$R/etc/fstab"
sync
echo "reverted: default.target -> multi-user, UI masked, dashboard restored"
