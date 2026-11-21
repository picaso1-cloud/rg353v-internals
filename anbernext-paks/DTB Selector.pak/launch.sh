#!/bin/sh
# DTB Selector.pak — choose which panel device tree AnberNext boots.
#
# Why it edits a file and not the config:
#   /boot.scr hardcodes `load ... ${fdt_addr_r} rk3566-353v.dtb` and boots with
#   booti directly; /boot/extlinux/extlinux.conf (the fallback) also points at
#   /rk3566-353v.dtb. So the only change that works for BOTH paths is replacing
#   the contents of that one file. No config edit, nothing to rebuild.
#
# Safety:
#   - only a partition whose GPT name is NEXTBOOT on a device whose type is "SD"
#     is accepted; the eMMC (Android) is never a candidate;
#   - the write goes to rk3566-353v.dtb.new, is synced, then renamed over the
#     original, so a power cut leaves either the old or the new complete file;
#   - the two good trees travel with the pak in res/, so it can always put the
#     normal one back.
#
# Controls: D-pad Up/Down (or Left/Right) to choose, A to apply, B to exit.

set -u

PAK_DIR=$(cd "$(dirname "$0")" && pwd)
PAK_NAME=$(basename "$PAK_DIR" .pak)
: "${SDCARD_PATH:=/mnt/SDCARD}"
: "${SYSTEM_PATH:=$SDCARD_PATH/.system/rg353}"
: "${USERDATA_PATH:=$SDCARD_PATH/.userdata/rg353}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"

LOG="$LOGS_PATH/$PAK_NAME.txt"
mkdir -p "$LOGS_PATH" 2>/dev/null
exec >>"$LOG" 2>&1
echo "=== $(date '+%F %T') $PAK_NAME ==="

SHOW="$SYSTEM_PATH/bin/show2.elf"
LOGO="$SDCARD_PATH/.system/res/logo.png"
FIFO=/tmp/show2.fifo
MNT=/tmp/dtb-selector
RES="$PAK_DIR/res"
BOOT_FILE=rk3566-353v.dtb
ALT_FILE=rk3566-353v-notimingchange.dtb
UI_PID=""

find_gamepad() {
	for n in /sys/class/input/event*/device/name; do
		[ -r "$n" ] || continue
		if [ "$(cat "$n" 2>/dev/null)" = "retrogame_joypad" ]; then
			e=$(basename "$(dirname "$n")")
			echo "/dev/input/$e"
			return 0
		fi
	done
	return 1
}

find_bootpart() {
	for u in /sys/class/block/mmcblk*p*/uevent; do
		[ -f "$u" ] || continue
		grep -q '^PARTNAME=NEXTBOOT$' "$u" 2>/dev/null || continue
		part=$(sed -n 's/^DEVNAME=//p' "$u" 2>/dev/null | tr -d '\r')
		[ -n "$part" ] || continue
		disk=${part%p*}
		# never the eMMC (Android): only a card reader reports type "SD"
		[ "$(cat "/sys/block/$disk/device/type" 2>/dev/null)" = "SD" ] || continue
		echo "/dev/$part"
		return 0
	done
	return 1
}

# ---- UI ------------------------------------------------------------------

ui_start() {
	[ -x "$SHOW" ] || chmod 0755 "$SHOW" 2>/dev/null
	[ -x "$SHOW" ] && [ -f "$LOGO" ] || { echo "show2/logo missing"; return 0; }
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
ui_final() {
	ui_stop
	[ -x "$SHOW" ] && [ -f "$LOGO" ] && "$SHOW" --mode=simple --image="$LOGO" \
		--bgcolor=0x120c02 --fontcolor=0xf2a53a --text="$1" --timeout="${2:-4}" >/dev/null 2>&1
	return 0
}
cleanup() {
	ui_stop
	umount "$MNT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ---- helpers -------------------------------------------------------------

valid_dtb() {
	[ -f "$1" ] || return 1
	[ "$(wc -c <"$1" 2>/dev/null)" -gt 100000 ] || return 1
	[ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" = "d00dfeed" ]
}

label_of() {
	case "$1" in
		"$BOOT_FILE") echo "Normal (AnberNext default)" ;;
		"$ALT_FILE") echo "No timing change (panel re-init fix)" ;;
		*) echo "Unknown" ;;
	esac
}

# returns the EV_KEY code on a press; 1 on anything else
read_key() {
	dev=$1
	set -- $(dd if="$dev" bs=24 count=1 2>/dev/null | od -An -tu2)
	[ -n "${9:-}" ] || { sleep 0.2; return 1; }
	[ "$9" = "1" ] || return 1        # EV_KEY
	[ "${11:-0}" = "1" ] || return 1  # value 1 = press, not release/repeat
	printf '%s\n' "${10:-}"
}

# ---- main ----------------------------------------------------------------

EV=$(find_gamepad) || {
	echo "no retrogame_joypad found"
	ui_start "Gamepad not found."
	sleep 4
	exit 1
}
echo "gamepad: $EV"

BOOTPART=$(find_bootpart) || {
	echo "no NEXTBOOT partition on an SD card"
	ui_start "NEXTBOOT partition not found. Nothing changed."
	sleep 6
	exit 1
}
echo "boot partition: $BOOTPART"

mkdir -p "$MNT" 2>/dev/null
umount "$MNT" 2>/dev/null || true

ui_start "DTB Selector: mounting NEXTBOOT..."

if ! mount -t vfat -o rw,noatime "$BOOTPART" "$MNT" 2>/dev/null; then
	echo "mount failed"
	ui_final "Cannot mount NEXTBOOT (read-only card?). Nothing changed." 6
	exit 1
fi

current=unknown
if cmp -s "$MNT/$BOOT_FILE" "$RES/$BOOT_FILE"; then
	current=$BOOT_FILE
elif cmp -s "$MNT/$BOOT_FILE" "$RES/$ALT_FILE"; then
	current=$ALT_FILE
fi
PANEL=$(dmesg 2>/dev/null | sed -n 's/.*panel id: //p' | head -1)
echo "current=$current panel=${PANEL:-unknown}"

sel=0
[ "$current" = "$ALT_FILE" ] && sel=1

render() {
	if [ "$sel" = 0 ]; then name=$BOOT_FILE; else name=$ALT_FILE; fi
	lbl=$(label_of "$name")
	act=""
	[ "$current" = "$name" ] && act="  [active]"
	ui_text "Apply: $lbl$act    A=select  B=exit"
	ui_prog $((sel * 100))
}

apply() {
	name=$1
	lbl=$(label_of "$name")
	if [ "$current" = "$name" ]; then
		ui_text "Already using $lbl.  B=exit"
		return 0
	fi
	if ! valid_dtb "$RES/$name"; then
		echo "invalid source $RES/$name"
		ui_text "Source DTB invalid. Nothing written.  B=exit"
		return 0
	fi
	echo "writing $name"
	ui_text "Writing $lbl ... do not power off"
	ui_prog 50
	rm -f "$MNT/$BOOT_FILE.new" 2>/dev/null
	if cp "$RES/$name" "$MNT/$BOOT_FILE.new" 2>/dev/null &&
	   sync &&
	   mv -f "$MNT/$BOOT_FILE.new" "$MNT/$BOOT_FILE" 2>/dev/null; then
		sync
		printf 'selected=%s\npanel=%s\nat=%s\n' "$name" "${PANEL:-unknown}" "$(date '+%F %T')" \
			>"$MNT/dtb-selected.txt" 2>/dev/null
		sync
		umount "$MNT" 2>/dev/null || true
		current=$name
		echo "applied $name; asking the launcher to reboot"
		ui_final "Saved: $lbl. Rebooting..." 3
		touch /tmp/reboot
		exit 0
	fi
	rm -f "$MNT/$BOOT_FILE.new" 2>/dev/null
	echo "write failed"
	ui_text "Write failed. Nothing changed.  B=exit"
}

render
while :; do
	code=$(read_key "$EV") || continue
	case "$code" in
		544|546|545|547) sel=$((1 - sel)); render ;;
		304|315)  # A, or Start
			if [ "$sel" = 0 ]; then apply "$BOOT_FILE"; else apply "$ALT_FILE"; fi
			;;
		305|314)  # B, or Select
			echo "cancelled by user"
			break
			;;
	esac
done
