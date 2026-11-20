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
GPU_BLOB="${GPU_BLOB:-/home/souhail/Andr36oid/rg353v-backup/gpu/libmali-bifrost-g52-g29p1.so}"
GPU_HOOK="${GPU_HOOK:-/home/souhail/Andr36oid/rg353v-backup/gpu/libmali-hook-g52.so.1.9.0}"
MNT=/mnt/archr-port

say() { printf '\n== %s\n' "$*"; }

[[ -b "$CARD" ]] || { echo "not a block device: $CARD" >&2; exit 1; }
[[ -f "$GPU_BLOB" ]] || { echo "missing GPU blob: $GPU_BLOB" >&2; exit 1; }

LOOP=$(losetup -f --show -P "$CARD")
trap 'umount "$MNT" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT

mkdir -p "$MNT"
mount "${LOOP}p4" "$MNT"
R="$MNT"
echo "card: $CARD -> $LOOP, rootfs mounted at $R"

say "1/8 device identity (HW_DEVICE RK3326 -> RK3566)"
sed -i \
  -e 's/^HW_DEVICE=.*/HW_DEVICE="RK3566"/' \
  -e 's/^HW_CPU=.*/HW_CPU="Rockchip RK3566"/' \
  -e 's/^DISTRO_DEVICE=.*/DISTRO_DEVICE="RK3566"/' \
  "$R/etc/os-release"

say "2/8 platform + device quirks"
mkdir -p "$R/usr/lib/autostart/quirks/platforms" "$R/usr/lib/autostart/quirks/devices"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/platforms/RK3566" \
      "$R/usr/lib/autostart/quirks/platforms/"
cp -a "$HERE/rootfs/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
      "$R/usr/lib/autostart/quirks/devices/"
find "$R/usr/lib/autostart/quirks/platforms/RK3566" \
     "$R/usr/lib/autostart/quirks/devices/Anbernic RG353V-VS" \
     -type f -exec chmod 0755 {} +

say "3/8 GPU: Mali-G52 DDK blob (the G31 blob rejects the G52 and locks the kernel)"
B="$R/usr/lib"
if [[ -f "$B/libmali.so.1.9.0" && ! -f "$B/libmali.so.1.9.0.g31.bak" ]]; then
  cp "$B/libmali.so.1.9.0" "$B/libmali.so.1.9.0.g31.bak"
fi
cp -f "$GPU_BLOB" "$B/libmali.so.1.9.0"
if [[ -f "$GPU_HOOK" ]]; then
  [[ -f "$B/libmali-hook.so.1.9.0" && ! -f "$B/libmali-hook.so.1.9.0.g31.bak" ]] && \
    cp "$B/libmali-hook.so.1.9.0" "$B/libmali-hook.so.1.9.0.g31.bak"
  cp -f "$GPU_HOOK" "$B/libmali-hook.so.1.9.0"
fi
chmod 0755 "$B/libmali.so.1.9.0" "$B/libmali-hook.so.1.9.0"
echo "blob: $(strings -a "$B/libmali.so.1.9.0" | grep -m1 'Bifrost-')"

say "4/8 Wi-Fi: drop the saved rfkill soft-block, unblock with the unit, drop dead module conf"
rm -f "$R/storage/.cache/rfkill/"* 2>/dev/null || true
mkdir -p "$R/storage/.cache/rfkill"
cp -f "$HERE/../s2/rootfs-overlay/etc/systemd/system/wpa-wlan0.service" \
      "$R/etc/systemd/system/wpa-wlan0.service"
rm -f "$R/etc/modules-load.d/rtw88.conf"   # mainline module name, not in this kernel

say "5/8 settings: chmod->ENOSYS fix (fchmodat2 needs Linux 6.6, we run 5.10)"
F="$R/etc/profile.d/001-functions"
if ! grep -q "RG353V patch" "$F"; then
  cat "$HERE/rootfs/etc/profile.d/001-functions.rg353v-append" >> "$F"
  echo "appended rewrite_config fix to 001-functions"
else
  echo "rewrite_config fix already present"
fi

say "6/8 persistent journal (so a failed sway boot leaves evidence)"
mkdir -p "$R/etc/systemd/journald.conf.d"
cat > "$R/etc/systemd/journald.conf.d/91-persistent.conf" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=64M
EOF

say "7/8 storage: /storage on the rootfs, not the 137 MB ROMS partition"
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

say "8/8 systemd: ArchR target, unmask the session, keep SSH/Wi-Fi"
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
# our units for wlan0 / port 22. systemd-rfkill re-applies stale soft-blocks
# (it killed Wi-Fi on every boot); the wpa unit unblocks by itself now.
for u in iwd.service sshd.service systemd-rfkill.service; do
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

say "sanity: required units exist"
need=(archr.target archr-autostart.service archr-levels.service sway.service
      archr-launcher-session.service input.service headphones.service
      sshd-s2.service wpa-wlan0.service)
for u in "${need[@]}"; do
  [[ -e "$R/usr/lib/systemd/system/$u" || -e "$S/$u" ]] || {
    echo "MISSING unit: $u" >&2; exit 1; }
done

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
[[ "$SAFE" = 1 ]] && echo "SAFE mode: start the UI over SSH with: systemctl unmask sway archr-launcher-session && systemctl start sway"
