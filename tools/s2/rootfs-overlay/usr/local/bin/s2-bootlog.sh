#!/bin/sh
OUT=/root/s2-BOOTLOG.txt
{
  echo "=== S2 BOOT LOG $(date -u) ==="
  echo "kernel : $(uname -a)"
  echo "uptime : $(cat /proc/uptime)"
  echo "jobs   :"; systemctl list-jobs --no-legend
  echo; echo "--- failed units ---"; systemctl --failed --no-legend
  echo; echo "--- journal (tail 400) ---"
  journalctl -b --no-pager -o short-monotonic 2>/dev/null | tail -400
  echo; echo "--- mounts ---"; findmnt -rn -o TARGET,SOURCE,FSTYPE
} > "$OUT" 2>&1
cat "$OUT" > /dev/tty1 2>/dev/null
cat "$OUT" > /boot/S2-BOOTLOG.txt 2>/dev/null
