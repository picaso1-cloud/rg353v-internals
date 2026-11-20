#!/bin/sh
# S2 visible init: runs as PID1 in the Arch rootfs, then execs systemd.
# Everything to the panel, because the loader forces console=ttyUSB0.
mkdir -p /dev /proc /sys /run /tmp
[ -e /dev/console ] || mknod -m 620 /dev/console c 5 1 2>/dev/null
[ -e /dev/null ]    || mknod -m 666 /dev/null    c 1 3 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount --bind /dev/tty1 /dev/console 2>/dev/null || true
exec >/dev/tty1 2>&1
echo ""
echo "=============================================================="
echo "  S2: ARCH ROOTFS REACHED - handover works"
echo "  $(uname -srm) | $(. /etc/os-release; echo "$PRETTY_NAME")"
echo "  root: $(findmnt -no SOURCE,FSTYPE / 2>/dev/null)"
echo "  exec'ing systemd (its output should appear below)"
echo "=============================================================="
exec /usr/lib/systemd/systemd --system --log-target=console --log-level=info
