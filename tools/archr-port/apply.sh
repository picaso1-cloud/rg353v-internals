#!/bin/bash
# SPDX-License-Identifier: MIT
# Apply the Anbernic RG353V (RK3566) port to an ArchR rootfs sitting on
# TF1 partition 4. Run on the laptop with the card inserted:
#
#   sudo bash apply.sh [/dev/mmcblk0]
#
# Idempotent: safe to run again after a partial run. Does not touch the
# eMMC, p1/p2 (dArkOS loader), p3 (boot) or p5 (stock ROMS partition).

set -euo pipefail

CARD="${1:-/dev/mmcblk0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
MNT=/mnt/archr-port

say() { printf '\n== %s\n' "$*"; }

[[ -b "$CARD" ]] || { echo "not a block device: $CARD" >&2; exit 1; }

LOOP=$(losetup -f --show -P "$CARD")
trap 'umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT

mkdir -p "$MNT"
mount "${LOOP}p4" "$MNT"
R="$MNT"
echo "card: $CARD -> $LOOP, rootfs mounted at $R"

say "1/7 device identity (HW_DEVICE RK3326 -> RK3566)"
sed -i \
  -e 's/^HW_DEVICE=.*/HW_DEVICE="RK3566"/' \
  -e 's/^HW_CPU=.*/HW_CPU="Rockchip RK3566"/' \
  -e 's/^DISTRO_DEVICE=.*/DISTRO_DEVICE="RK3566"/' \
  "$R/etc/os-release"

say "2/7 platform + device quirks"
mkdir -p "$R/usr/lib/autostart/quirks/platforms" "$R/usr/lib/autostart/quirks/devices"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/platforms/RK3566" \
      "$R/usr/lib/autostart/quirks/platforms/"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
      "$R/usr/lib/autostart/quirks/devices/"
# dArkOS-style dialout/serial perms are not needed; make scripts executable
find "$R/usr/lib/autostart/quirks/platforms/RK3566" \
     "$R/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
     -type f -exec chmod 0755 {} +

say "3/7 persistent journal (so a failed sway boot leaves evidence)"
mkdir -p "$R/etc/systemd/journald.conf.d"
cat > "$R/etc/systemd/journald.conf.d/91-persistent.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=64M
EOF

say "4/7 storage: /storage on the rootfs, not the 137 MB ROMS partition"
sed -i -E 's|^([^#].*[[:space:]]/storage[[:space:]].*)$|# disabled for ArchR (rootfs /storage used): \1|' "$R/etc/fstab"
grep -q '^/storage\b' "$R/etc/fstab" && { echo "fstab still mounts /storage" >&2; exit 1; } || true
mkdir -p "$R/storage/.config/profile.d" \
         "$R/storage/.config/emulationstation" \
         "$R/storage/.config/retroarch/autoconfig/udev"
cp "$HERE/storage/.config/profile.d/098-controller" \
   "$R/storage/.config/profile.d/098-controller"
cp "$HERE/storage/.config/retroarch/autoconfig/udev/retrogame_joypad.cfg" \
   "$R/storage/.config/retroarch/autoconfig/udev/retrogame_joypad.cfg"

# Do not auto-mount the second SD / eMMC partitions on this unit: TF2 is the
# ROM collection and the eMMC holds Android. Re-enable in Settings
# (system.automount=1) when ArchR should pick the ROM card up by itself.
CFG="$R/storage/.config/system/configs/system.cfg"
mkdir -p "$(dirname "$CFG")"
touch "$CFG"
if grep -q '^system\.automount=' "$CFG"; then
  sed -i 's/^system\.automount=.*/system.automount=0/' "$CFG"
else
  echo 'system.automount=0' >> "$CFG"
fi

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

say "5/7 systemd: ArchR target, unmask the session, keep SSH/Wi-Fi"
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
# one network manager (wpa_supplicant) and one sshd (sshd-s2) only:
# iwd and the stock sshd are enabled statically in /usr/lib and would race
# our units for wlan0 / port 22.
for u in iwd.service sshd.service; do
  [[ -L "$S/$u" ]] || ln -sf /dev/null "$S/$u"
done

# autostart owns the UI start order (it writes 095-sway and the sway
# config first). Do NOT enable sway.service / archr-launcher-session.service
# directly, or graphical.target would start sway before its config exists.
mkdir -p "$S/archr.target.wants" "$S/multi-user.target.wants" "$S/getty.target.wants"
ln -sf /usr/lib/systemd/system/archr-autostart.service \
       "$S/archr.target.wants/archr-autostart.service"

for u in archr-levels.service input.service headphones.service; do
  ln -sf "/usr/lib/systemd/system/$u" "$S/multi-user.target.wants/$u"
done

# default target: archr.target (replaces the empty file used during bring-up)
rm -f "$S/default.target"
ln -sf /usr/lib/systemd/system/archr.target "$S/default.target"

# console: sway owns tty1; keep a shell on tty2 and drop the dashboard
rm -f "$S/multi-user.target.wants/s2-console.service"
rm -f "$S/getty.target.wants/getty@tty1.service"
ln -sf /usr/lib/systemd/system/getty@.service "$S/getty.target.wants/getty@tty2.service"

say "6/7 sanity: required units exist"
need=(archr.target archr-autostart.service archr-levels.service sway.service
      archr-launcher-session.service input.service headphones.service
      sshd-s2.service wpa-wlan0.service)
for u in "${need[@]}"; do
  [[ -e "$R/usr/lib/systemd/system/$u" || -e "$S/$u" ]] || {
    echo "MISSING unit: $u" >&2; exit 1; }
done

say "7/7 summary"
echo "HW_DEVICE       : $(grep ^HW_DEVICE= "$R/etc/os-release")"
echo "default.target  : $(readlink "$S/default.target")"
echo "archr.target    : $(ls "$S/archr.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "multi-user      : $(ls "$S/multi-user.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "getty           : $(ls "$S/getty.target.wants" 2>/dev/null | tr '\n' ' ')"
echo "fstab /storage  : $(grep '/storage' "$R/etc/fstab" || echo '(rootfs)')"
echo "quirks platform : $(ls "$R/usr/lib/autostart/quirks/platforms/RK3566" | tr '\n' ' ')"
echo "quirks device   : $(ls "$R/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" | tr '\n' ' ')"
echo "es_input GUID   : $(grep -c 'retrogame_joypad' "$ES") entry(ies)"

sync
echo
echo "done. put the card in the device and power on; SSH stays available."
