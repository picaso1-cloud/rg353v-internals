#!/bin/sh
# Our own initramfs init for the S2 bring-up.
# NOTE: the initramfs root has NO /dev /proc /sys /tmp — create them first.
export PATH=/sbin:/usr/sbin:/bin:/usr/bin

mkdir -p /dev /proc /sys /tmp /run /mnt /root
mount -t devtmpfs devtmpfs /dev   2>/dev/null || true
mount -t proc     proc     /proc 2>/dev/null || true
mount -t sysfs    sysfs    /sys  2>/dev/null || true

LOG=/tmp/boot.log
: > "$LOG" 2>/dev/null
say() {
  echo "$*" >> "$LOG" 2>/dev/null
  echo "$*" > /dev/tty1    2>/dev/null
  echo "$*" > /dev/console 2>/dev/null
}
dump() {
  for p in /dev/mmcblk1p3 /dev/mmcblk0p3; do
    [ -b "$p" ] || continue
    mount -t vfat -o rw "$p" /mnt 2>/dev/null || continue
    cp "$LOG" /mnt/BOOT-TRACE.txt 2>/dev/null
    sync
    umount /mnt 2>/dev/null
    return 0
  done
  say "WARN: could not write BOOT-TRACE.txt"
}

say "=== BOOT-TRACE: our init (pid1) $(date -u 2>/dev/null) ==="
say "cmdline : $(cat /proc/cmdline 2>/dev/null)"
say "devices : $(ls /dev/mmcblk* 2>/dev/null | tr '\n' ' ')"
say "--- kernel log tail ---"
dmesg 2>/dev/null | tail -15 >> "$LOG"
dump

say "=== mounting root ==="
if mount -t ext4 -o rw /dev/mmcblk1p4 /root 2>>"$LOG"; then
  say "root: /dev/mmcblk1p4 ext4 -> OK"
elif mount -o rw /dev/mmcblk1p4 /root 2>>"$LOG"; then
  say "root: auto mount -> OK"
else
  say "root mount FAILED"
  dmesg 2>/dev/null | tail -20 >> "$LOG"
  dump
  say "staying in initramfs; evidence in /BOOT-TRACE.txt"
  while :; do sleep 3600; done
fi
say "mounted : $(grep ' /root ' /proc/mounts 2>/dev/null)"
say "os      : $(grep PRETTY_NAME /root/etc/os-release 2>/dev/null)"
dump

say "=== preparing handover ==="
mkdir -p /root/dev /root/proc /root/sys /root/run /root/tmp
[ -e /root/dev/console ] || mknod -m 620 /root/dev/console c 5 1 2>/dev/null
[ -e /root/dev/null ]    || mknod -m 666 /root/dev/null    c 1 3 2>/dev/null
say "init before: $(ls -l /root/sbin/init 2>&1)"

if [ ! -e /root/s2-init-wrapper.installed ] && [ -x /scripts/s2-init-wrapper.sh ]; then
  cp -a /root/sbin/init /root/sbin/init.stock 2>/dev/null || true
  rm -f /root/sbin/init
  cp /scripts/s2-init-wrapper.sh /root/sbin/init
  chmod 0755 /root/sbin/init
  touch /root/s2-init-wrapper.installed
  say "installed visible init wrapper"
fi
say "init after : $(ls -l /root/sbin/init 2>&1)"
say "=== exec switch_root ==="
dump
exec switch_root /root /sbin/init
say "switch_root RETURNED rc=$?"
dmesg 2>/dev/null | tail -20 >> "$LOG"
dump
while :; do sleep 3600; done
