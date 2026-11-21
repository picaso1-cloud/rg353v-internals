#!/bin/sh
# Installed on the card as:
#   NEXTUI/.userdata/rg353/.hooks/boot.d/50-rescue.sh
#
# Runs at stage 2, before the menu. It:
#   1. logs DRM / backlight / dmesg state (for a black screen),
#   2. forces the panel backlight on if something left bl_power=4,
#   3. waits for Wi-Fi and starts the static rescue shell on :2323.
#
# NextUI's run_hooks.sh runs this in the background and waits for it to exit, so
# everything slow is detached in a subshell and the hook returns immediately.

SD=${SDCARD_PATH:-/mnt/SDCARD}
LOG="$SD/.userdata/rg353/logs/rescue.txt"
mkdir -p "${LOG%/*}" 2>/dev/null

{
	echo "=== $(date '+%F %T') boot hook ==="
	echo "-- drm"
	for f in /sys/class/drm/*/status /sys/class/drm/*/enabled; do
		[ -r "$f" ] && echo "$f: $(cat "$f" 2>/dev/null)"
	done
	echo "-- backlight"
	for f in /sys/class/backlight/*/bl_power /sys/class/backlight/*/brightness /sys/class/backlight/*/max_brightness; do
		[ -r "$f" ] && echo "$f: $(cat "$f" 2>/dev/null)"
	done
	echo "-- dmesg (display)"
	dmesg 2>/dev/null | grep -iE "panel|dsi|drm|backlight|mali|fb0" | tail -25
} >>"$LOG" 2>&1

# self-heal: NextUI's HDMI watcher turns the panel off with bl_power=4
if [ -w /sys/class/backlight/backlight/bl_power ]; then
	echo 0 >/sys/class/backlight/backlight/bl_power 2>/dev/null
fi

(
	i=0
	while [ $i -lt 40 ]; do
		if ip -4 addr show wlan0 2>/dev/null | grep -q "inet "; then break; fi
		i=$((i + 1)); sleep 1
	done
	chmod 0755 "$SD/.userdata/rg353/rescue-shell" 2>/dev/null
	ip4=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}')
	echo "rescue: starting on ${ip4:-no-wifi}" >>"$LOG"
	exec "$SD/.userdata/rg353/rescue-shell"
) >>"$LOG" 2>&1 &
