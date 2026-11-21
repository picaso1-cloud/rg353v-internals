#!/bin/sh
# System Info.pak — a working starting point for your own AnberNext pak.
#
# It demonstrates, in order:
#   * the environment variables NextUI exports (PLATFORM, SDCARD_PATH, ...)
#   * logging to $LOGS_PATH, the only way to debug from a PC
#   * gathering real device data (battery, thermal, Wi-Fi, free space)
#   * show2.elf in daemon mode, driven through /tmp/show2.fifo
#   * dropping the CPU governor for a light app (the launcher resets it on exit)
#
# Copy this folder, rename it (the menu label is the folder name minus ".pak"),
# replace the info gathering, and ship it. See ../README.md.
#
# It only reads: nothing here writes to the games card (TF2) or the eMMC.

PAK_DIR=$(cd "$(dirname "$0")" && pwd)
PAK_NAME=$(basename "$PAK_DIR" .pak)

# defaults so the script also runs when started by hand over a shell
: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${SYSTEM_PATH:=$SDCARD_PATH/.system/rg353}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/rg353}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"
: "${PLATFORM:=rg353}"

LOG="$LOGS_PATH/$PAK_NAME.txt"
mkdir -p "$LOGS_PATH" 2>/dev/null
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') $PAK_NAME start (platform=$PLATFORM device=${DEVICE:-none})"

# ---------------------------------------------------------------- UI plumbing

SHOW="$SYSTEM_PATH/bin/show2.elf"
LOGO="$SDCARD_PATH/.system/res/logo.png"
FIFO=/tmp/show2.fifo          # hard-coded inside show2.elf — one instance at a time
UI_PID=""

[ -x "$SHOW" ] || chmod 0755 "$SHOW" 2>/dev/null

ui_start() {
	[ -x "$SHOW" ] || { echo "show2.elf not found, staying headless"; return 0; }
	[ -f "$LOGO" ] || { echo "logo.png not found, staying headless"; return 0; }
	rm -f "$FIFO" 2>/dev/null
	"$SHOW" --mode=daemon --image="$LOGO" \
		--bgcolor=0x120c02 --fontcolor=0xf2a53a --text="$1" >/dev/null 2>&1 &
	UI_PID=$!
	n=0
	while [ "$n" -lt 15 ] && [ ! -p "$FIFO" ]; do sleep 0.2; n=$((n + 1)); done
}
ui_text() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'TEXT:%s\n' "$1" >"$FIFO"; }
ui_prog() { [ -n "$UI_PID" ] && [ -p "$FIFO" ] && printf 'PROGRESS:%s\n' "$1" >"$FIFO"; }
ui_stop() {
	[ -n "$UI_PID" ] || return 0
	printf 'QUIT\n' >"$FIFO" 2>/dev/null
	wait "$UI_PID" 2>/dev/null
	UI_PID=""
}
ui_final() {   # quit the daemon, then show one last message for N seconds
	ui_stop
	[ -x "$SHOW" ] && [ -f "$LOGO" ] && "$SHOW" --mode=simple --image="$LOGO" \
		--bgcolor=0x120c02 --fontcolor=0xf2a53a --text="$1" --timeout="${2:-5}" >/dev/null 2>&1
	return 0
}
trap 'ui_stop' EXIT INT TERM

# ------------------------------------------------------------- gather the data

battery() {
	for f in /sys/class/power_supply/*/capacity; do
		[ -r "$f" ] && { cat "$f"; return; }
	done
}

temp_c() {
	for f in /sys/class/thermal/thermal_zone*/temp; do
		[ -r "$f" ] || continue
		v=$(cat "$f" 2>/dev/null)
		case "$v" in ''|*[!0-9]*) continue ;; esac
		[ "$v" -gt 1000 ] && v=$((v / 1000))
		echo "$v"; return
	done
}

wifi_line() {
	ssid=$(iw dev wlan0 link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p')
	addr=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}')
	if [ -n "$ssid" ]; then
		echo "Wi-Fi: $ssid  ${addr:-no IP}"
	else
		echo "Wi-Fi: off"
	fi
}

BATT=$(battery)
TEMP=$(temp_c)
FREE=$(df -h "$SDCARD_PATH" 2>/dev/null | awk 'NR==2 {print $4}')
UP=$(cut -d. -f1 /proc/uptime 2>/dev/null)
UP_H=$(( ${UP:-0} / 3600 ))
UP_M=$(( (${UP:-0} % 3600) / 60 ))

b1="Battery: ${BATT:-?}%   Temp: ${TEMP:-?} C"
b2=$(wifi_line)
b3="Card free: ${FREE:-?}   Up: ${UP_H}h ${UP_M}m"

echo "battery=$BATT temp=$TEMP free=$FREE uptime=${UP}s"
echo "$b2"

# ---------------------------------------------------------------- show it off

# a light info panel does not need the full clock
[ -f "$SYSTEM_PATH/bin/governor.sh" ] && sh "$SYSTEM_PATH/bin/governor.sh" powersave >/dev/null 2>&1

ui_start "$b1"
ui_prog 10
sleep 1
ui_text "$b2"; ui_prog 40; sleep 3
ui_text "$b3"; ui_prog 70; sleep 3
ui_text "Tools/rg353/$PAK_NAME.pak"; ui_prog 100; sleep 2

ui_final "$PAK_NAME: see $LOGS_PATH/$PAK_NAME.txt" 5
echo "=== $(date '+%F %T') $PAK_NAME done"
