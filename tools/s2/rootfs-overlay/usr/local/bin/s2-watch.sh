#!/bin/sh
# S2/S3 watcher: full early capture once, then 10 s state snapshots.
OUT=/s2-BOOTLOG.txt
FIRST=1
while :; do
  if [ "$FIRST" = 1 ]; then
    {
      echo "=== S3 BOOT SNAPSHOT $(date -u 2>/dev/null) ==="
      uname -a
      echo "model : $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
      echo "cmdline: $(cat /proc/cmdline)"
      echo
      echo "=========== FULL DMESG (early capture) ==========="
      dmesg 2>/dev/null
      echo
      echo "=========== DRM / PANEL ==========="
      for s in /sys/class/drm/*/status; do echo "$s: $(cat $s 2>/dev/null)"; done
      ls -l /sys/class/drm/ 2>/dev/null
      for b in /sys/class/backlight/*; do [ -d "$b" ] && echo "$b brightness=$(cat $b/brightness 2>/dev/null)/$(cat $b/max_brightness 2>/dev/null)"; done
      dmesg 2>/dev/null | grep -iE "panel|dsi|drm|kd35t|nv3051|backlight|fbcon|Console:" 
      echo
      echo "=========== MODULES / STATE ==========="
      lsmod 2>/dev/null | head -40
      systemctl is-system-running 2>&1
    } > /s2-EARLY.txt 2>&1
    cp /s2-EARLY.txt /boot/S2-EARLY.txt 2>/dev/null
    FIRST=0
  fi
  {
    echo "=== S2 WATCH $(date -u 2>/dev/null) uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s ==="
    echo "-- kernel --";   uname -r
    echo "-- state --";    timeout 5 systemctl is-system-running 2>&1
    echo "-- jobs --";     timeout 5 systemctl list-jobs --no-legend 2>&1
    echo "-- failed --";   timeout 5 systemctl --failed --no-legend 2>&1
    echo "-- addr --";     timeout 5 ip addr 2>&1
    echo "-- rfkill --";   cat /sys/class/rfkill/*/soft 2>/dev/null | tr '\n' ' '; echo
    echo "-- drm --";      for s in /sys/class/drm/*/status; do echo "$s: $(cat $s 2>/dev/null)"; done
    echo "-- wifi --";     timeout 5 iw dev 2>&1 | head -10
    echo "-- mods --";     lsmod 2>/dev/null | grep -iE "panfrost|mali|8821|cfg80211"
    echo "-- journal --";  timeout 6 journalctl -b -n 60 --no-pager -o short-monotonic 2>&1 | grep -viE "archr-levels|system.cfg"
  } > "$OUT.tmp" 2>&1
  mv -f "$OUT.tmp" "$OUT" 2>/dev/null
  cp "$OUT" /boot/S2-BOOTLOG.txt 2>/dev/null
  echo "S2 alive $(cut -d' ' -f1 /proc/uptime)s  $(uname -r)  ip: $(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}')" > /dev/tty1 2>/dev/null
  sleep 10
done
