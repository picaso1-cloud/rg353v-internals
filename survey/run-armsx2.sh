#!/bin/bash
# ARMSX2 launcher for ArkOS (RG353V): stop ES, Xorg(fbdev), ARMSX2(xcb)
# usage: run-armsx2.sh [start|stop] ; optional $2 = ISO path
case "$1" in
  stop)
    pkill -f armsx2-qt 2>/dev/null; pkill Xorg 2>/dev/null
    systemctl start emulationstation 2>/dev/null
    echo "stopped (ES restarted)"; exit 0;;
esac

pkill -f armsx2-qt 2>/dev/null; pkill Xorg 2>/dev/null
# free the display: ES holds the DRM master / fbdev
systemctl stop emulationstation 2>/dev/null; pkill -f emulationstation 2>/dev/null
sleep 3

cat > /etc/X11/xorg.conf << 'XEOF'
Section "Device"
  Identifier "fb"
  Driver "fbdev"
EndSection
Section "Screen"
  Identifier "screen"
  Device "fb"
EndSection
XEOF

chvt 1 2>/dev/null
openvt -c 9 -s -w -- Xorg :0 -noreset > /home/ark/xorg.log 2>&1 &
sleep 7
if ! DISPLAY=:0 xdpyinfo >/dev/null 2>&1; then
  echo "Xorg failed (see /var/log/Xorg.0.log)"; tail -4 /home/ark/xorg.log; exit 1
fi
echo "Xorg OK: $(DISPLAY=:0 xdpyinfo | grep dimensions)"

cd /home/ark/squashfs-root
export DISPLAY=:0
export QT_QPA_PLATFORM=xcb
export LIBGL_ALWAYS_SOFTWARE=1
LD_LIBRARY_PATH="/home/ark/armsx2-syslibs/usr/lib/aarch64-linux-gnu:/home/ark/squashfs-root/usr/lib:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu" \
/home/ark/armsx2-syslibs/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 \
  --library-path "/home/ark/armsx2-syslibs/usr/lib/aarch64-linux-gnu:/home/ark/squashfs-root/usr/lib:/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu" \
  ./usr/bin/armsx2-qt $2 > /home/ark/armsx2.log 2>&1 &
sleep 8

echo "--- procs: xorg=$(pgrep -c Xorg) armsx2=$(pgrep -c -f armsx2-qt)"
echo "--- armsx2 log:"; grep -vE "^qt.core" /home/ark/armsx2.log | head -6
