#!/bin/bash
# Read the "flight recorder" off TF1 p4 after a crash: last dmesg snapshots,
# persistent journal, sway/launcher logs, autostart trace.
#   sudo bash read-p4-logs.sh [/dev/mmcblk0]
set -euo pipefail
CARD="${1:-/dev/mmcblk0}"
OUT=/tmp/opencode/p4-logs
rm -rf "$OUT"; mkdir -p "$OUT"
L=$(losetup -f --show -P "$CARD"); sleep 1
trap 'umount /mnt/p4r 2>/dev/null || true; losetup -d "$L" 2>/dev/null || true' EXIT
mkdir -p /mnt/p4r; mount -o ro "${L}p4" /mnt/p4r
R=/mnt/p4r
for f in root/s2-BOOTLOG.txt root/s2-EARLY.txt var/log/boot.log var/log/sway.log \
         var/log/archr-launcher-session.log storage/.boot_last_step storage/.boot_last_hang \
         storage/.config/gpudriver.log; do
  [ -f "$R/$f" ] && cp "$R/$f" "$OUT/$(echo "$f" | tr '/' '_')" || true
done
# persistent journal: export the last boot as text
if [ -d "$R/var/log/journal" ]; then
  journalctl --directory="$R/var/log/journal" --no-pager -b -1 > "$OUT/journal-prev.txt" 2>/dev/null || true
  journalctl --directory="$R/var/log/journal" --no-pager -b -0 > "$OUT/journal-last.txt" 2>/dev/null || true
fi
echo "=== files pulled ==="; ls -la "$OUT"
echo
echo "=== last dmesg snapshot (tail) ==="; tail -30 "$OUT/root_s2-BOOTLOG.txt" 2>/dev/null || echo "(none)"
echo "=== autostart hung at ==="; cat "$OUT/storage_.boot_last_step" "$OUT/storage_.boot_last_hang" 2>/dev/null || echo "(no marker)"
echo "=== sway.log tail ==="; tail -30 "$OUT/var_log_sway.log" 2>/dev/null || echo "(none)"
