#!/bin/sh
OUT=/s2-BOOTLOG.txt
while :; do
  {
    echo "=== S2 WATCH $(date -u 2>/dev/null) uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s ==="
    echo "-- system state --";  timeout 5 systemctl is-system-running 2>&1
    echo "-- running jobs --";  timeout 5 systemctl list-jobs --no-legend 2>&1
    echo "-- failed units --";  timeout 5 systemctl --failed --no-legend 2>&1
    echo "-- addresses --";     timeout 5 ip addr 2>&1
    echo "-- rfkill --";        cat /sys/class/rfkill/*/soft 2>/dev/null | tr '\n' ' '; echo
    echo "-- wifi --";          timeout 5 iw dev 2>&1 | head -12
    echo "-- modules --";       lsmod 2>/dev/null | grep -iE "8821|cfg80211"
    echo "-- journal (tail 200) --"; timeout 6 journalctl -b -n 200 --no-pager -o short-monotonic 2>&1
  } > "$OUT.tmp" 2>&1
  mv -f "$OUT.tmp" "$OUT" 2>/dev/null
  cp "$OUT" /boot/S2-BOOTLOG.txt 2>/dev/null
  cp "$OUT" /storage/s2-BOOTLOG.txt 2>/dev/null
  echo "S2 alive: uptime $(cut -d' ' -f1 /proc/uptime)s  ip: $(ip addr show wlan0 2>/dev/null | grep 'inet ')" > /dev/tty1 2>/dev/null
  sleep 10
done
