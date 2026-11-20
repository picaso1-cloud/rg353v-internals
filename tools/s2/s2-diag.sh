#!/bin/sh
# S2 diagnostics: runs inside dArkOS's initramfs, after /dev exists.
# Mounts the Arch rootfs, reports what it finds, saves the report to the boot
# FAT, and then STOPS (does not hand over) so the screen can be read.
LOG=/tmp/s2diag.txt
: > "$LOG"
say() { echo "$*" >> "$LOG"; }
run() { say "\$ $*"; say "$(eval "$*" 2>&1 | head -20)"; }

say "=============================================================="
say "  S2 DIAGNOSTICS  (Arch rootfs on dArkOS initramfs)"
say "=============================================================="
say "cmdline: $(cat /proc/cmdline)"
say "block  : $(ls /dev/mmcblk1* 2>/dev/null | tr '\n' ' ')"
say ""

say "-- mount test --"
mkdir -p /mnt/rootfs
if mount -t ext4 /dev/mmcblk1p4 /mnt/rootfs 2>>"$LOG"; then
  say "MOUNT OK (ext4)"
elif mount /dev/mmcblk1p4 /mnt/rootfs 2>>"$LOG"; then
  say "MOUNT OK (auto)"
else
  say "MOUNT FAILED"
  umount /mnt/rootfs 2>/dev/null
  mount -t btrfs /dev/mmcblk1p4 /mnt/rootfs 2>>"$LOG" && say "btrfs mount OK (unexpected)"
fi
say "rootfs entries: $(ls /mnt/rootfs 2>/dev/null | tr '\n' ' ')"
say "os-release    : $(cat /mnt/rootfs/etc/os-release 2>/dev/null | tr '\n' ' ')"
say "init          : $(ls -l /mnt/rootfs/sbin/init 2>&1)"
say "init resolve  : $(readlink -f /mnt/rootfs/sbin/init 2>&1)"
say "init exists   : $([ -x /mnt/rootfs/usr/lib/systemd/systemd ] && echo yes || echo NO)"
say "dev/console   : $(ls -l /mnt/rootfs/dev/console 2>&1)"
say ""

say "-- chroot tests --"
mount -t proc proc /mnt/rootfs/proc 2>/dev/null
mount -t sysfs sys /mnt/rootfs/sys 2>/dev/null
mount --bind /dev /mnt/rootfs/dev 2>/dev/null
run "chroot /mnt/rootfs /usr/lib/systemd/systemd --version"
run "chroot /mnt/rootfs /bin/sh -c 'echo SHELL_OK; id; head -1 /etc/shadow | cut -c1-20'"
run "chroot /mnt/rootfs /usr/bin/systemctl --version"
say ""

say "-- kernel log tail --"
dmesg 2>/dev/null | tail -40 >> "$LOG"
say "=============================================================="
say "report: ${BOOTDEV:-boot partition not written}:/S2-DIAG.txt"
say "device will stay here (no handover) so the screen can be read."

# persist to boot FAT
for part in /dev/mmcblk1p3 /dev/mmcblk0p3; do
  [ -b "$part" ] || continue
  mkdir -p /mnt/boot
  if mount -t vfat -o rw "$part" /mnt/boot 2>/dev/null; then
    cp "$LOG" /mnt/boot/S2-DIAG.txt 2>/dev/null && BOOTDEV="$part"
    sync; umount /mnt/boot 2>/dev/null
    [ -n "$BOOTDEV" ] && break
  fi
done
# rewrite the header line now that BOOTDEV is known
if [ -n "$BOOTDEV" ]; then
  for part in /dev/mmcblk1p3 /dev/mmcblk0p3; do
    [ -b "$part" ] || continue
    if mount -t vfat -o rw "$part" /mnt/boot 2>/dev/null; then
      sed "s|boot partition not written|$BOOTDEV|" "$LOG" > /mnt/boot/S2-DIAG.txt 2>/dev/null
      sync; umount /mnt/boot 2>/dev/null; break
    fi
  done
fi

cat "$LOG" > /dev/tty1 2>/dev/null
# stop here on purpose
while :; do sleep 3600; done
