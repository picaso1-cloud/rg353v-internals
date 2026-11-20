#!/bin/bash
# Build the RAM-only live initramfs for the RG353V (5.10 BSP kernel only).
set -euo pipefail

ROOT=/home/souhail/Andr36oid/rg353v-backup
TREE=$ROOT/live/tree
STOCK=$ROOT/images/s1/uInitrd.orig
OUT=$ROOT/live/uInitrd.live
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. unpack stock initramfs (busybox + klibc-style tools, already aarch64)
gzip -dc "$STOCK" | ( cd "$WORK" && cpio -idm --quiet )

# 2. live payload
mkdir -p "$WORK/live" "$WORK/lib" "$WORK/etc/ssh" "$WORK/var/empty" "$WORK/run"
cp "$TREE/live/sbin/"* "$WORK/live/" || true
cp "$TREE/live/lib/"*  "$WORK/lib/"
mkdir -p "$WORK/live/modules" "$WORK/lib/firmware"
cp "$ROOT/live/8821cs.ko" "$WORK/live/modules/" 2>/dev/null || true
cp -r "$ROOT/live/firmware/." "$WORK/lib/firmware/" 2>/dev/null || true

# 2b. NSS modules + service name db (sshd resolves users/ports through these)
for nss in libnss_files.so.2 libnss_dns.so.2 libnss_compat.so.2; do
  [ -f "$ROOT/live/nss/$nss" ] && cp "$ROOT/live/nss/$nss" "$WORK/lib/"
done
for f in services protocols nsswitch.conf hosts resolv.conf; do
  [ -f "$ROOT/live/etc/$f" ] && cp "$ROOT/live/etc/$f" "$WORK/etc/"
done

# 2c. OpenSSH session helper (modern sshd needs /usr/lib/openssh/sshd-session)
mkdir -p "$WORK/usr/lib/openssh"
[ -d "$ROOT/live/libexec" ] && cp "$ROOT/live/libexec/"* "$WORK/usr/lib/openssh/" 2>/dev/null || true

# 3. identity files (root / ark)
cat > "$WORK/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
sshd:x:105:65534::/run/sshd:/bin/false
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
EOF
cat > "$WORK/etc/group" <<'EOF'
root:x:0:
nogroup:x:65534:
sshd:x:105:
EOF
HASH=$(openssl passwd -6 ark)
printf 'root:%s:19000:0:99999:7:::\n' "$HASH" > "$WORK/etc/shadow"
chmod 640 "$WORK/etc/shadow"
mkdir -p "$WORK/root"

# 4. sshd_config
cat > "$WORK/etc/ssh/sshd_config" <<'EOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
UsePAM no
PidFile /run/sshd.pid
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
Subsystem sftp internal-sftp
EOF

# 5. wpa config
cat > "$WORK/etc/wpa_supplicant.conf" <<'EOF'
ctrl_interface=/run/wpa_supplicant
network={
    ssid="CPE-C391"
    psk="1234567890"
    key_mgmt=WPA-PSK
}
EOF

# 6. live init
cat > "$WORK/init" <<'EOF'
#!/bin/sh
export PATH=/sbin:/usr/sbin:/bin:/usr/bin:/live
export LD_LIBRARY_PATH=/lib

mkdir -p /dev /proc /sys /tmp /run /root /var
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devpts devpts /dev/pts 2>/dev/null

say() { echo "$*" >> /live.log; echo "$*" > /dev/tty1 2>/dev/null; }
say "=============================================="
say "  RG353V LIVE (RAM only) - $(date -u)"
say "=============================================="

# ---- mode switch: a /NORMAL file on p3 boots the real rootfs instead ----
mkdir -p /mnt/boot
MODE=live
if mount -t vfat -o ro /dev/mmcblk1p3 /mnt/boot 2>/dev/null; then
  [ -f /mnt/boot/NORMAL ] && MODE=normal
  umount /mnt/boot 2>/dev/null
fi
if [ "$MODE" = normal ]; then
  say "NORMAL mode: booting the real rootfs (p4)"
  mkdir -p /root
  if mount -t ext4 -o rw /dev/mmcblk1p4 /root 2>/dev/null; then
    mkdir -p /root/dev /root/proc /root/sys /root/run
    [ -e /root/dev/console ] || mknod -m 620 /root/dev/console c 5 1 2>/dev/null
    [ -e /root/dev/null ]    || mknod -m 666 /root/dev/null    c 1 3 2>/dev/null
    say "rootfs mounted, switch_root"
    exec switch_root /root /sbin/init
  else
    say "rootfs mount FAILED - staying in LIVE mode"
  fi
fi

say "wifi module..."
insmod /live/modules/8821cs.ko 2>>/live.log || say "insmod failed (see /live.log)"
for i in $(seq 1 20); do [ -e /sys/class/net/wlan0 ] && break; sleep 1; done
say "wlan0: $([ -e /sys/class/net/wlan0 ] && echo present || echo MISSING)"

if [ -e /sys/class/net/wlan0 ]; then
  ifconfig wlan0 up 2>/dev/null
  say "wpa_supplicant..."
  /live/wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf -D nl80211 >>/live.log 2>&1
  for i in $(seq 1 30); do
    iw get 2>/dev/null >/dev/null
    if iw dev wlan0 link 2>/dev/null | grep -q "Connected"; then break; fi
    sleep 1
  done
  ifconfig wlan0 192.168.0.198 netmask 255.255.255.0 up 2>>/live.log
  route add default gw 192.168.0.1 2>>/live.log || true
  say "wlan0 ip: $(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([^ ]*\).*/\1/p')"
fi

say "starting sshd..."
ssh-keygen -A >>/live.log 2>&1 || say "ssh-keygen FAILED"
mkdir -p /run/sshd /var/empty
chmod 755 /run/sshd /var/empty
/live/sshd -D -e -f /etc/ssh/sshd_config >>/live.log 2>&1 &
sleep 3
if ps 2>/dev/null | grep -v grep | grep -q sshd; then
  say "sshd: RUNNING (pid $(ps | grep -v grep | grep sshd | awk '{print $1}' | head -1))"
else
  say "sshd: DIED - last log lines:"; tail -6 /live.log >> /dev/tty1 2>/dev/null
fi

mkdir -p /mnt/boot
if mount -t vfat -o rw /dev/mmcblk1p3 /mnt/boot 2>/dev/null; then
  cp /live.log /mnt/boot/LIVE-LOG.txt 2>/dev/null
  sync; umount /mnt/boot 2>/dev/null
fi
say "live system is RAM-only; the SD partitions are free to rewrite."
say "ssh root@192.168.0.198  (pw ark)   |  shell on tty1 below"
echo "" > /dev/tty1
exec /bin/sh
EOF
chmod 755 "$WORK/init"

# 7. pack (reproducible)
find "$WORK" -exec touch -h -d '1970-01-01 00:00:00 UTC' {} +
( cd "$WORK" && find . -print0 | cpio --null -o -H newc --owner 0:0 --reproducible --quiet ) | gzip -9 > "$OUT"
gzip -t "$OUT"
sh -n "$WORK/init"
echo "initramfs: $OUT  $(du -h "$OUT" | cut -f1)  sha256 $(sha256sum "$OUT" | cut -d' ' -f1)"
