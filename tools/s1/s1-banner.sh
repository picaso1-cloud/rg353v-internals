#!/bin/sh
# S1 bring-up banner — archr-device-kit
# Purpose: prove we own the boot chain and capture ONE boot log to the SD card.
# Never blocks boot: every step is best-effort, always exits 0.

LOG=/tmp/s1-boot.log
BOOTDEV=""
: > "$LOG" 2>/dev/null || LOG=/dev/null

say() { echo "$*" >> "$LOG" 2>/dev/null; }
hr()  { say "----------------------------------------------------------------------"; }

SLEEP_S=8
for x in $(cat /proc/cmdline 2>/dev/null); do
  case "$x" in s1wait=*) SLEEP_S="${x#s1wait=}" ;; esac
done

say ""
say "======================================================================"
say "  RG353V  *  ARCH BRING-UP  *  STAGE S1"
say "  custom initramfs is running  ->  the boot chain is ours"
say "======================================================================"
say "time      : $(date -u 2>/dev/null)"
say "kernel    : $(uname -srm 2>/dev/null)"
MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\000')
COMPAT=$(tr -d '\000' < /proc/device-tree/compatible 2>/dev/null | tr '\0' ' ')
[ -z "$COMPAT" ] && COMPAT=$(cat /proc/device-tree/compatible 2>/dev/null | tr -d '\000')
say "model     : ${MODEL:-unknown}"
say "compatible: ${COMPAT:-unknown}"
say "cmdline   : $(cat /proc/cmdline 2>/dev/null)"
hr
say "displays  : $(ls /sys/class/drm 2>/dev/null | tr '\n' ' ')"
for st in /sys/class/drm/card*/status; do
  [ -f "$st" ] && say "  $(dirname "$st" | xargs basename): $(cat "$st")"
done
say "backlight : $(for b in /sys/class/backlight/*; do [ -d "$b" ] && echo "$(basename "$b")=$(cat "$b/brightness" 2>/dev/null)/$(cat "$b/max_brightness" 2>/dev/null)"; done)"
say "block     : $(ls /dev/mmcblk* 2>/dev/null | tr '\n' ' ')"
say "uart      : $([ -c /dev/ttyS2 ] && echo 'ttyS2 present' || echo 'no ttyS2 node')"
hr
say "kernel messages (first 40 + last 120 lines):"
dmesg 2>/dev/null | head -40 >> "$LOG"
say "  ..."
dmesg 2>/dev/null | tail -120 >> "$LOG"
hr

# Persist the log to the boot FAT so it can be read on any PC.
for part in /dev/mmcblk1p3 /dev/mmcblk0p3 /dev/mmcblk1p1 /dev/mmcblk0p1; do
  [ -b "$part" ] || continue
  mkdir -p /mnt/s1
  if mount -t vfat -o rw "$part" /mnt/s1 2>/dev/null; then
    cp "$LOG" /mnt/s1/S1-LOG.txt 2>/dev/null && BOOTDEV="$part"
    sync
    umount /mnt/s1 2>/dev/null
    [ -n "$BOOTDEV" ] && break
  fi
done

say "log file  : ${BOOTDEV:-NOT WRITTEN}:/S1-LOG.txt"
say "continuing to dArkOS in ${SLEEP_S}s (normal boot, nothing changed)"
say "======================================================================"
say ""

# Show it on the panel (and UART if wired).
if [ -w /dev/tty1 ]; then cat "$LOG" > /dev/tty1 2>/dev/null; fi
if [ -c /dev/ttyS2 ]; then cat "$LOG" > /dev/ttyS2 2>/dev/null; fi
if [ ! -w /dev/tty1 ] && [ -w /dev/console ]; then cat "$LOG" > /dev/console 2>/dev/null; fi

[ "$SLEEP_S" -gt 0 ] 2>/dev/null && sleep "$SLEEP_S"
exit 0
