#!/bin/bash
# SPDX-License-Identifier: MIT
# Apply the Anbernic RG353V (RK3566) port to an ArchR rootfs sitting on
# TF1 partition 4. Run on the laptop with the card inserted:
#
#   sudo bash apply.sh [--safe] [/dev/mmcblk0]
#
#   --safe  also masks sway.service and archr-launcher-session.service so
#           the first boot cannot reach the GPU; use it whenever the GPU
#           stack is unproven. Start the UI later over SSH with
#           `systemctl unmask sway.service archr-launcher-session.service`.
#
# Idempotent: safe to run again after a partial run. Does not touch the
# eMMC, p1/p2 (dArkOS loader), p3 (boot) or p5 (stock ROMS partition).

set -euo pipefail

SAFE=0
[[ "${1:-}" == "--safe" ]] && { SAFE=1; shift; }
CARD="${1:-/dev/mmcblk0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
GPU_BLOB="${GPU_BLOB:-/home/souhail/Andr36oid/rg353v-backup/gpu/libmali-bifrost-g52-g24p0-wayland-gbm.so}"
GPU_HOOK="${GPU_HOOK:-/home/souhail/Andr36oid/rg353v-backup/gpu/libmali-hook-g24p0.so.1.9.0}"
SHIM_SO="${SHIM_SO:-$HERE/fchmodat2_compat.so}"
MNT=/mnt/archr-port

say() { printf '\n== %s\n' "$*"; }

[[ -e "$CARD" ]] || { echo "no such device or image: $CARD" >&2; exit 1; }
[[ -f "$GPU_BLOB" ]] || { echo "missing GPU blob: $GPU_BLOB" >&2; exit 1; }

# A block device is a card (partition 4 holds the rootfs); a regular file is
# an ext4 filesystem image (like rg353v-backup/arch-rootfs/archr-rootfs.img).
if [[ -b "$CARD" ]]; then
  LOOP=$(losetup -f --show -P "$CARD")
  PART="${LOOP}p4"
else
  LOOP=$(losetup -f --show "$CARD")
  PART="$LOOP"
fi
trap 'umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT

mkdir -p "$MNT"
mount "$PART" "$MNT"
R="$MNT"
echo "target: $CARD -> $LOOP, rootfs mounted at $R"

# The Arch-R rootfs (v3.1.1+) does not ship /etc/systemd/system; create it so
# the custom units below can be placed there. Safe for older images too.
mkdir -p "$R/etc/systemd/system"

say "1/10 device identity (HW_DEVICE RK3326 -> RK3566)"
sed -i \
  -e 's/^HW_DEVICE=.*/HW_DEVICE="RK3566"/' \
  -e 's/^HW_CPU=.*/HW_CPU="Rockchip RK3566"/' \
  -e 's/^DISTRO_DEVICE=.*/DISTRO_DEVICE="RK3566"/' \
  "$R/etc/os-release"

say "2/10 platform + device quirks"
mkdir -p "$R/usr/lib/autostart/quirks/platforms" "$R/usr/lib/autostart/quirks/devices"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/platforms/RK3566" \
      "$R/usr/lib/autostart/quirks/platforms/"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
      "$R/usr/lib/autostart/quirks/devices/"
find "$R/usr/lib/autostart/quirks/platforms/RK3566" \
     "$R/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
     -type f -exec chmod 0755 {} +

say "3/10 GPU: Mali-G52 wayland-gbm DDK (g24p0; the G31 blob and the g29p1
fbdev-only build both fail under Wayland)"
B="$R/usr/lib"
[[ -f "$B/libmali.so.1.9.0" ]] || true
cp -f "$GPU_BLOB" "$B/libmali.so.1.9.0"
cp -f "$GPU_HOOK" "$B/libmali-hook.so.1.9.0"
[[ -f "$SHIM_SO" ]] && cp -f "$SHIM_SO" "$B/fchmodat2_compat.so"
# The PI2 futex shim: glibc >= 2.34 answers pthread_mutexattr_setprotocol
# (PTHREAD_PRIO_INHERIT) with FUTEX_LOCK_PI2, which only exists from Linux
# 5.14. On this 5.10 BSP kernel the syscall answers ENOSYS and glibc aborts
# the process ("The futex facility returned an unexpected error code.").
# libpulse's threaded mainloop asks for priority inheritance, so every pulse
# client died: the launcher (SDL2 pulse backend), archr-levels (the volume
# daemon) and everything else that talks to PipeWire's pulse server.
[[ -f "$HERE/pi2_compat.so" ]] && cp -f "$HERE/pi2_compat.so" "$B/pi2_compat.so"
find "$B" -maxdepth 1 -name "libmali*" -exec python3 -c "import os,sys; [os.chmod(p,0o755) for p in sys.argv[1:]]" {} + 2>/dev/null || true
chmod 0644 "$B/fchmodat2_compat.so" 2>/dev/null || true
chmod 0644 "$B/pi2_compat.so" 2>/dev/null || true
{ echo "/usr/lib/fchmodat2_compat.so"
  [[ -f "$B/pi2_compat.so" ]] && echo "/usr/lib/pi2_compat.so"
} > "$R/etc/ld.so.preload"
echo "blob: $(strings -a "$B/libmali.so.1.9.0" | grep -m1 'Bifrost-')  + fchmodat2 + pi2 shims preloaded"

say "3b/10 audio: SDL apps must use ALSA (SDL2 pulse backend aborts with pipewire-pulse)"
sed -i 's/export SDL_AUDIODRIVER=pulseaudio/export SDL_AUDIODRIVER=alsa/' \
  "$R/usr/bin/archr-launcher-session" 2>/dev/null || true
# The patch above lives in a file the archr-launcher package owns: every
# package upgrade puts the upstream file back and the launcher then dies with
# "The futex facility returned an unexpected error code." A pacman hook
# re-applies it (and the rewrite_config fix) after every transaction.
mkdir -p "$R/usr/local/bin" "$R/etc/pacman.d/hooks"
cp -f "$HERE/rootfs/usr/local/bin/rg353v-port-hooks" "$R/usr/local/bin/rg353v-port-hooks"
cp -f "$HERE/rootfs/etc/pacman.d/hooks/99-rg353v-port.hook" "$R/etc/pacman.d/hooks/99-rg353v-port.hook"
chmod 0755 "$R/usr/local/bin/rg353v-port-hooks" 2>/dev/null || true
chmod 0644 "$R/etc/pacman.d/hooks/99-rg353v-port.hook" 2>/dev/null || true

say "4/10 Wi-Fi: ship wpa_supplicant + units (the clean image has neither), wifi.enabled=1"
rm -f "$R/storage/.cache/rfkill/"* 2>/dev/null || true
mkdir -p "$R/storage/.cache/rfkill"
rm -f "$R/etc/modules-load.d/rtw88.conf"   # mainline module name, not in this kernel
# The original ArchR image ships iwd/connman but no wpa_supplicant. Ours comes
# from the dArkOS image (Debian 13 aarch64) plus its four missing libs.
mkdir -p "$R/usr/local/wpa/lib" "$R/usr/local/bin" "$R/etc/wpa_supplicant"
cp -f "$HERE/external/wpa/wpa_supplicant" "$R/usr/local/wpa/wpa_supplicant"
cp -f "$HERE/external/wpa/lib/"*           "$R/usr/local/wpa/lib/"
python3 -c "import os,sys; [os.chmod(p,0o755) for p in sys.argv[1:]]" \
  "$R/usr/local/wpa/wpa_supplicant" "$R/usr/local/wpa/lib/"* 2>/dev/null || true
cp -f "$HERE/../s2/rootfs-overlay/usr/local/bin/udhcpc-wlan0.sh" "$R/usr/local/bin/"
cp -f "$HERE/../s2/rootfs-overlay/etc/wpa_supplicant/wpa_supplicant-wlan0.conf" \
      "$R/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
# units: improved wpa (rfkill unblock in the wait loop), dhcp, and sshd-s2
# (the stock sshd has no ExecStartPre=ssh-keygen -A, and the clean image has
# no host keys at all)
cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/wpa-wlan0.service" \
      "$R/etc/systemd/system/wpa-wlan0.service"
cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/dhcp-wlan0.service" \
      "$R/etc/systemd/system/dhcp-wlan0.service"
cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/sshd-s2.service" \
      "$R/etc/systemd/system/sshd-s2.service"
python3 -c "import os,sys; [os.chmod(p,0o755) for p in sys.argv[1:]]" \
  "$R/usr/local/bin/udhcpc-wlan0.sh" 2>/dev/null || true

say "5/10 settings: chmod->ENOSYS fix (fchmodat2 needs Linux 6.6, we run 5.10)"
F="$R/etc/profile.d/001-functions"
if ! grep -q "RG353V patch" "$F"; then
  cat "$HERE/rootfs/etc/profile.d/001-functions.rg353v-append" >> "$F"
  echo "appended rewrite_config fix to 001-functions"
else
  echo "rewrite_config fix already present"
fi

say "6/10 persistent journal + DNS + /storage as mountpoint + zram"
mkdir -p "$R/etc/systemd/journald.conf.d"
cat > "$R/etc/systemd/journald.conf.d/91-persistent.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=64M
EOF
# DNS comes from DHCP through systemd-resolved (the udhcpc hook registers the
# router per link). Do NOT pin a router IP here: it broke as soon as the
# device moved from 192.168.0.x to 192.168.31.x. Keep only a fallback.
mkdir -p "$R/storage/.config/resolved.conf.d"
printf '[Resolve]\nFallbackDNS=1.1.1.1 8.8.8.8\n' \
  > "$R/storage/.config/resolved.conf.d/rg353v.conf"
# /storage lives on the rootfs, but several ArchR services (memory-manager,
# automount, the session) require it to BE a mountpoint. An fstab "none bind"
# line is ignored by systemd's mount generator, so use a dedicated unit.
# This also makes automount's "system disk" detection see mmcblk1 instead of
# nothing (a second safety net against ever touching the eMMC).
cat > "$R/etc/systemd/system/rg353v-storage-bind.service" <<'EOF'
[Unit]
Description=Self-bind /storage so it is a mountpoint (ArchR expects one)
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target archr-memory-manager.service archr-automount.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'mountpoint -q /storage || mount -o bind /storage /storage'
[Install]
WantedBy=local-fs.target
EOF
mkdir -p "$R/etc/systemd/system/local-fs.target.wants"
ln -sf /etc/systemd/system/rg353v-storage-bind.service \
       "$R/etc/systemd/system/local-fs.target.wants/rg353v-storage-bind.service"
# correct mountpoint (the BusyBox one misreports self-binds). /usr/bin/mountpoint
# is a SYMLINK to busybox in this image: rm first, or cp -f overwrites the
# busybox BINARY through the link and the next boot dies at switch_root.
rm -f "$R/usr/bin/mountpoint"
cp -f "$HERE/rootfs/usr/bin/mountpoint" "$R/usr/bin/mountpoint"
chmod 0755 "$R/usr/bin/mountpoint"
# zram: 1536 MB zstd — the 2 GB handheld tier. Plain MB number (the script
# regex is ^[0-9]+$); no swap file (SD-card wear).
mkdir -p "$R/storage/.config"
cat > "$R/storage/.config/swap.conf" <<'EOF'
ZRAM_SIZE="1536"
ZRAM_ALGO="zstd"
SWAP_FILE_SIZE="0"
EOF
# TF2 ROMs + BIOS: automount mounts the second card at /storage/games-external
# (eMMC skipped via the mmcblk0boot0 guard) and publishes /run/archr/roms2.
# BIOS is shared by symlink, no copies.
ln -sfn /storage/games-external/bios "$R/storage/bios"
# The card's ROM folders: ARCH-R publishes roms2 -> <card>/roms, but this TF2
# card carries the ArkOS layout (psx/, snes/, gba/... at the card root next
# to bios/ and AnberNext/). A unit picks the right one after the automount.
mkdir -p "$R/usr/local/bin" "$R/etc/systemd/system"
cp -f "$HERE/rootfs/usr/local/bin/rg353v-roms2.sh" "$R/usr/local/bin/rg353v-roms2.sh"
chmod 0755 "$R/usr/local/bin/rg353v-roms2.sh" 2>/dev/null || true
cp -f "$HERE/rootfs/etc/systemd/system/rg353v-roms2.service" \
      "$R/etc/systemd/system/rg353v-roms2.service"
ln -sf /etc/systemd/system/rg353v-roms2.service \
       "$R/etc/systemd/system/multi-user.target.wants/rg353v-roms2.service"

say "7/10 storage: /storage on the rootfs, not the 137 MB ROMS partition"
sed -i -E 's|^([^#].*[[:space:]]/storage[[:space:]].*)$|# disabled for ArchR (rootfs /storage used): \1|' "$R/etc/fstab"
sed -i '\|^/storage /storage none bind|d' "$R/etc/fstab"
grep -q '^/storage\b' "$R/etc/fstab" && { echo "fstab still mounts /storage" >&2; exit 1; } || true
mkdir -p "$R/storage/.config/profile.d" \
         "$R/storage/.config/emulationstation" \
         "$R/storage/.config/retroarch/autoconfig/udev" \
         "$R/storage/.cache" "$R/storage/cache"
cp "$HERE/storage/.config/profile.d/098-controller" \
   "$R/storage/.config/profile.d/098-controller"
cp "$HERE/storage/.config/retroarch/autoconfig/udev/retrogame_joypad.cfg" \
   "$R/storage/.config/retroarch/autoconfig/udev/retrogame_joypad.cfg"

# Do not auto-mount the second SD / eMMC partitions on this unit: TF2 is the
# ROM collection and the eMMC holds Android. The user can re-enable it in Settings
# (system.automount=1) when ArchR should pick the ROM card up by itself.
# 2026-11-21: TF2 wiring is DONE — automount is ON, the eMMC is guarded by the
# mmcblk0boot0 check and the /storage bind makes system-disk detection work.
# ROMs come from /storage/games-external/roms (roms2), BIOS via symlink.
CFG="$R/storage/.config/system/configs/system.cfg"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"
if grep -q '^system\.automount=' "$CFG"; then
  sed -i 's/^system\.automount=.*/system.automount=1/' "$CFG"
else
  echo 'system.automount=1' >> "$CFG"
fi

# Wi-Fi enable flag: the image ships wifi.enabled=0, and 099-networkservices
# then runs `wifictl boot-off`, which rfkill-BLOCKS the radio seconds after
# boot — that was our "Network is down" at every attempt. With =1 it runs
# `wifictl enable` (rfkill unblock) instead; its `connect` is a harmless
# no-op while iwd is parked (see below).
if grep -q '^wifi\.enabled=' "$CFG"; then
  sed -i 's/^wifi\.enabled=.*/wifi.enabled=1/' "$CFG"
else
  echo 'wifi.enabled=1' >> "$CFG"
fi
# Wi-Fi management runs on iwd — that is what the launcher's Settings page and
# wifictl speak. The image ships iwd, its main.conf already has the vendor
# driver quirks (ControlPortOverNL80211=false); add our driver name to the SAE
# blacklist (the 8821cs vendor driver advertises SAE but never delivers the
# external-auth events, iwd then hangs instead of falling back to WPA2).
IWD_CONF="$R/etc/iwd/main.conf"
if [[ -f "$IWD_CONF" ]] && ! grep -q "8821cs" "$IWD_CONF"; then
  sed -i 's|^SaeDisable=.*|&,8821cs|' "$IWD_CONF"
fi
[[ -f "$IWD_CONF" ]] && grep -m1 SaeDisable "$IWD_CONF"
# provisioned networks so the first boot associates without the UI (iwd is
# parked for now, but these stay current for the later UI migration)
mkdir -p "$R/var/lib/iwd"
cat > "$R/var/lib/iwd/CPE-C391.psk" <<'EOF'
[Security]
Passphrase=1234567890
EOF
cat > "$R/var/lib/iwd/HOME-NETWORK.psk" <<'EOF'
[Security]
Passphrase=1122334455
EOF
chmod 0644 "$R/var/lib/iwd/CPE-C391.psk" "$R/var/lib/iwd/HOME-NETWORK.psk"

# Merge the RG353V gamepad into es_input.cfg. The image already carries
# retrogame_joypad entries for older Anbernic boards (same driver, same
# vendor/product), but they map hotkeyenable to button 8 (SELECT). On this
# unit the F/MODE key is button 10, so patch every retrogame_joypad entry
# and add system_hk. mkcontroller then emits the right DEVICE_BTN_* set.
ES="$R/storage/.config/emulationstation/es_input.cfg"
if [[ ! -f "$ES" ]]; then
  printf '<?xml version="1.0"?>\n<inputList>\n</inputList>\n' > "$ES"
fi
python3 - "$ES" "$HERE/storage/.config/emulationstation/es_input.retrogame.xml" <<'PY'
import re, sys
es, frag = sys.argv[1], sys.argv[2]
src = open(es).read()

def patch(m):
    b = m.group(0)
    b = re.sub(r'<input name="hotkeyenable"[^/]*/>',
               '<input name="hotkeyenable" type="button" id="10" value="1" />', b)
    if 'name="system_hk"' not in b:
        b = b.replace('</inputConfig>',
                      '\t\t<input name="system_hk" type="button" id="10" value="1" />\n\t</inputConfig>')
    return b

src, n = re.subn(r'<inputConfig[^>]*deviceName="retrogame_joypad"[^>]*>.*?</inputConfig>',
                 patch, src, flags=re.S)
if n == 0:
    src = src[:src.rindex('</inputList>')] + open(frag).read() + src[src.rindex('</inputList>'):]
    print("inserted retrogame_joypad entry")
else:
    print(f"patched {n} retrogame_joypad entries (hotkeyenable=10, system_hk=10)")
open(es, 'w').write(src)
PY

say "8/10 systemd: ArchR target, unmask the session, keep SSH/Wi-Fi"
S="$R/etc/systemd/system"
# units that were masked with /dev/null during bring-up
for u in archr-automount.service archr-autostart.service \
         archr-launcher-session.service archr-levels.service sway.service; do
  if [[ -L "$S/$u" && "$(readlink "$S/$u")" = /dev/null ]]; then
    rm -f "$S/$u"
    echo "unmasked $u"
  fi
done
# keep the ArchR ROM migration away: there is no exFAT /storage partition
if [[ ! -e "$S/archr-roms-migrate.service" ]]; then
  ln -sf /dev/null "$S/archr-roms-migrate.service"
fi
# one sshd only (sshd-s2) and no rfkill state daemon (it resurrected a stale
# WLAN soft-block on every boot). Wi-Fi runs on wpa_supplicant + udhcpc —
# the combo proven to associate on this 8821cs. iwd stays masked: it scanned
# but never issued a connect on this vendor driver, and the launcher's
# Settings page (wifictl/iwd) is a later optimisation, not a boot dependency.
# archr-modules-firewall needs iptable_filter, which this kernel does not
# build: mask it so the boot stays clean.
for u in sshd.service systemd-rfkill.service connman.service connman-vpn.service \
         iwd.service archr-modules-firewall.service; do
  [[ -L "$S/$u" ]] || ln -sf /dev/null "$S/$u"
done
mkdir -p "$S/multi-user.target.wants"
rm -f "$S/multi-user.target.wants/wpa-wlan0.service" \
      "$S/multi-user.target.wants/dhcp-wlan0.service"
# restore the shipped unit files (a stale mask at the same path is a symlink
# to /dev/null: remove it before enabling)
[[ -L "$S/wpa-wlan0.service" && "$(readlink "$S/wpa-wlan0.service")" = /dev/null ]] && rm -f "$S/wpa-wlan0.service" || true
[[ -L "$S/dhcp-wlan0.service" && "$(readlink "$S/dhcp-wlan0.service")" = /dev/null ]] && rm -f "$S/dhcp-wlan0.service" || true
[[ -f "$S/wpa-wlan0.service" ]] || cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/wpa-wlan0.service" "$S/wpa-wlan0.service"
[[ -f "$S/dhcp-wlan0.service" ]] || cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/dhcp-wlan0.service" "$S/dhcp-wlan0.service"
ln -sf /etc/systemd/system/wpa-wlan0.service "$S/multi-user.target.wants/wpa-wlan0.service"
ln -sf /etc/systemd/system/dhcp-wlan0.service "$S/multi-user.target.wants/dhcp-wlan0.service"
ln -sf /etc/systemd/system/sshd-s2.service "$S/multi-user.target.wants/sshd-s2.service"
# flight recorder: snapshots on disk survive hangs and hard power-offs
cp -f "$HERE/rootfs/usr/local/bin/rg353v-flightrec.sh" "$R/usr/local/bin/rg353v-flightrec.sh"
chmod 0755 "$R/usr/local/bin/rg353v-flightrec.sh"
cp -f "$HERE/rootfs/etc/systemd/system/rg353v-flightrec.service" "$S/rg353v-flightrec.service"
ln -sf /etc/systemd/system/rg353v-flightrec.service "$S/multi-user.target.wants/rg353v-flightrec.service"

# autostart owns the UI start order (it writes 095-sway and the sway
# config first). Do NOT enable sway.service / archr-launcher-session.service
# directly, or graphical.target would start sway before its config exists.
mkdir -p "$S/archr.target.wants" "$S/multi-user.target.wants" "$S/getty.target.wants"
ln -sf /usr/lib/systemd/system/archr-autostart.service \
       "$S/archr.target.wants/archr-autostart.service"

for u in archr-levels.service input.service headphones.service; do
  ln -sf "/usr/lib/systemd/system/$u" "$S/multi-user.target.wants/$u"
done

if [[ "$SAFE" = 1 ]]; then
  echo "SAFE mode: masking the UI so the first boot cannot touch the GPU"
  ln -sf /dev/null "$S/sway.service"
  ln -sf /dev/null "$S/archr-launcher-session.service"
fi

# default target: archr.target
rm -f "$S/default.target"
ln -sf /usr/lib/systemd/system/archr.target "$S/default.target"

# console: sway owns tty1; keep a shell on tty2 and drop the dashboard
rm -f "$S/multi-user.target.wants/s2-console.service"
rm -f "$S/getty.target.wants/getty@tty1.service"
ln -sf /usr/lib/systemd/system/getty@.service "$S/getty.target.wants/getty@tty2.service"

say "9/10 kernel overlays: the dArkOS 5.10 modules and firmware"
# The Arch-R image is an RK3326 one: /usr/lib/modules and /usr/lib/firmware are
# symlinks into /run/kernel-overlays/..., which ARCH-R's *busybox init*
# populates (busybox init -> chroot /sysroot /usr/sbin/kernel-overlays-setup).
# Our initramfs replaces that init, so without this step the rootfs ends up
# with NO modules and NO firmware at all: no 8821cs (no wlan0), no rtl_bt
# firmware, and kmod-static-nodes skipped ("modules.devname" not found).
KTAR="${DARKOS_KERNEL_TAR:-/home/souhail/Andr36oid/rg353v-backup/darkos-kernel/kernel-5.10.226.tar.gz}"
OV="$R/usr/lib/kernel-overlays/base/lib"
if [ -f "$KTAR" ]; then
  TMPD=$(mktemp -d)
  tar -xzf "$KTAR" -C "$TMPD"
  mkdir -p "$OV/modules/5.10.226" "$OV/firmware"
  cp -a "$TMPD/usr/lib/modules/5.10.226/." "$OV/modules/5.10.226/" 2>/dev/null || true
  # firmware: keep what the image already ships, add what dArkOS has
  cp -rn "$TMPD/lib/firmware/." "$OV/firmware/" 2>/dev/null || true
  rm -rf "$TMPD"
  echo "modules: $(find "$OV/modules/5.10.226" -name '*.ko' | wc -l) ko   firmware: $(ls "$OV/firmware" | wc -l) entries"
  echo "8821cs: $(ls "$OV/modules/5.10.226/kernel/drivers/net/wireless/rockchip_wlan/rtl8821cs/" 2>/dev/null | tr '\n' ' ')"
else
  echo "!! dArkOS kernel tarball not found: $KTAR"
fi

say "10/10 boot: kernel-overlays-setup, the 8821cs driver, pipewire's dbus policy"
# (a) run kernel-overlays-setup ourselves (upstream does it in the busybox init)
# NOTE: no sysinit.target and no ordering against systemd-tmpfiles-setup here.
# An earlier version ordered this unit Before=systemd-modules-load.service with
# After=local-fs.target and WantedBy=sysinit.target: systemd then hit an
# ordering cycle and DELETED the systemd-tmpfiles-setup jobs, so /var/run,
# /var/lock, /var/tmp and /run/archr were never created. Without /var/run
# sway could not make /run/sway/sway-daemon.conf (the UI died in a restart
# loop), the pulse socket path (/var/run/0-runtime-dir/pulse/native) was
# missing, and every button was dead.
cat > "$R/etc/systemd/system/rg353v-kernel-overlays.service" <<'EOF'
[Unit]
Description=Kernel overlays (modules and firmware) for this kernel
After=local-fs.target
Before=rg353v-wifi-driver.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/kernel-overlays-setup
# kernel-overlays-setup only runs depmod when a *user* overlay exists, so the
# module index of the base overlay would stay missing.
ExecStartPost=-/usr/sbin/depmod -a

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/rg353v-kernel-overlays.service \
       "$R/etc/systemd/system/multi-user.target.wants/rg353v-kernel-overlays.service"
# (b) the Wi-Fi driver: the initramfs loads it early, this is the safety net
# (and the way to load it after a module reload)
cat > "$R/etc/systemd/system/rg353v-wifi-driver.service" <<'EOF'
[Unit]
Description=Load the 8821cs Wi-Fi driver (the Arch-R image is an RK3326 one)
After=rg353v-kernel-overlays.service
Before=wpa-wlan0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'test -e /sys/class/net/wlan0 || modprobe 8821cs'
ExecStartPost=/bin/sh -c 'i=0; while [ $i -lt 20 ] && [ ! -e /sys/class/net/wlan0 ]; do sleep 1; i=$((i+1)); done'
EOF
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/rg353v-wifi-driver.service \
       "$R/etc/systemd/system/multi-user.target.wants/rg353v-wifi-driver.service"
# (c) pipewire-pulse could not own org.pulseaudio.Server: the image ships no
# dbus policy for it, so pactl (and anything else that asks over dbus) failed.
mkdir -p "$R/usr/share/dbus-1/system.d"
cat > "$R/usr/share/dbus-1/system.d/pipewire-pulse.conf" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy context="default">
    <allow own="org.pulseaudio.Server"/>
    <allow own="org.pulseaudio.server"/>
    <allow send_destination="org.pulseaudio.Server"/>
    <allow send_destination="org.pulseaudio.server"/>
    <allow send_destination="org.pulseaudio.server.control"/>
    <allow send_destination="org.pulseaudio.Control"/>
  </policy>
</busconfig>
EOF

say "sanity: required units exist"
need=(archr.target archr-autostart.service archr-levels.service sway.service
      archr-launcher-session.service input.service headphones.service
      sshd-s2.service iwd.service)
for u in "${need[@]}"; do
  [[ -e "$R/usr/lib/systemd/system/$u" || -e "$S/$u" ]] || {
    echo "MISSING unit: $u" >&2; exit 1; }
done
# safety net for the symlink-clobber class of bug: busybox must still be an ELF
if ! head -c4 "$R/usr/bin/busybox" | grep -q $'\x7fELF'; then
  echo "FATAL: /usr/bin/busybox is not an ELF binary (a cp overwrote it?)" >&2
  exit 1
fi

say "summary"
echo "HW_DEVICE       : $(grep ^HW_DEVICE= "$R/etc/os-release")"
echo "default.target  : $(readlink "$S/default.target")"
echo "archr.target    : $(ls "$S/archr.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "multi-user      : $(ls "$S/multi-user.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "getty           : $(ls "$S/getty.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "masks           : $(for f in "$S"/*.service; do [ -L "$f" ] && [ "$(readlink "$f")" = /dev/null ] && basename "$f"; done | tr '\n' ' ')"
echo "fstab /storage  : $(grep '/storage' "$R/etc/fstab" || echo '(rootfs)')"
echo "GPU blob        : $(strings -a "$B/libmali.so.1.9.0" | grep -m1 'Bifrost-')"
echo "rfkill saved    : $(ls "$R/storage/.cache/rfkill/" 2>/dev/null | wc -l) file(s)"
echo "quirks platform : $(ls "$R/usr/lib/autostart/quirks/platforms/RK3566" | grep -v bin | grep -v sleep | tr '\n' ' ')"
echo "quirks device   : $(ls "$R/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" | tr '\n' ' ')"
echo "chmod fix       : $(grep -c 'RG353V patch' "$F") marker(s)"

sync
echo
echo "done. put the card in the device and power on; SSH stays available."
if [[ "$SAFE" = 1 ]]; then
  echo "SAFE mode: start the UI over SSH with: systemctl unmask sway archr-launcher-session && systemctl start sway"
fi
exit 0
