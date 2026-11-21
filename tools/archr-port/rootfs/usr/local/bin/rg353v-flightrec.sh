#!/bin/sh
# RG353V flight recorder: snapshot network / Wi-Fi / GPU / dmesg state every
# 10 s to /storage/.cache/log/flightrec.log and sync it, so a hang, kernel
# lock or hard power-off still leaves evidence on the card.
LOG=/storage/.cache/log/flightrec.log
mkdir -p "${LOG%/*}" 2>/dev/null
while :; do
  {
    echo "=== $(date -u +%FT%TZ) uptime=$(cut -d' ' -f1 /proc/uptime)s"
    echo "-- rfkill";        rfkill list 2>/dev/null
    echo "-- links";         ip -br addr 2>/dev/null
    echo "-- wifi link";     iw dev wlan0 link 2>/dev/null
    echo "-- wifi info";     iw dev wlan0 info 2>/dev/null | head -4
    echo "-- iwd station";   iwctl station wlan0 show 2>/dev/null | head -12
    echo "-- wpa state";     wpa_cli -i wlan0 status 2>/dev/null | head -8
    echo "-- dmesg";         dmesg | tail -10
  } >> "$LOG" 2>&1
  sync
  size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  if [ "$size" -gt 4000000 ]; then
    tail -c 2000000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
  sleep 10
done
