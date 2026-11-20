#!/bin/sh
# Snapshot boot state every 10 s; atomic write so a power cut leaves a usable file.
OUT=/root/s2-BOOTLOG.txt
while :; do
  {
    echo "=== S2 WATCH $(date -u 2>/dev/null) uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s ==="
    echo "-- running jobs --";  timeout 5 systemctl list-jobs --no-legend 2>&1
    echo "-- failed units --";  timeout 5 systemctl --failed --no-legend 2>&1
    echo "-- addresses --";     timeout 5 ip -br addr 2>&1
    echo "-- wifi --";          timeout 5 iw dev 2>&1 | head -20
    echo "-- modules --";       lsmod 2>/dev/null | grep -iE "8821|cfg80211|bcmdhd"
    echo "-- journal (tail 250) --"; timeout 5 journalctl -b -n 250 --no-pager -o short-monotonic 2>&1
  } > "$OUT.tmp" 2>&1
  mv -f "$OUT.tmp" "$OUT" 2>/dev/null
  cp "$OUT" /boot/S2-BOOTLOG.txt 2>/dev/null
  sleep 10
done
