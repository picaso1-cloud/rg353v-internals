#!/bin/sh
# patch-initramfs.sh — add a stage-1 boot trace to an AnberNext uInitrd.
#
#   sudo ./patch-initramfs.sh <original-uInitrd> <output-uInitrd>
#
# The patched init appends one line per stage to NEXTBOOT/boot-trace.txt:
#   stage1: partition /dev/mmcblkXpY
#   stage1: F check done
#   stage1: root mounted /dev/mmcblkXpZ
#   stage1: switch_root
#
# If the card is never written again, stage 1 never ran. If it stops after
# "root mounted", switch_root/nextui-init is the problem. This survives a black
# screen, which is the whole point.
set -eu

in=${1:?usage: patch-initramfs.sh <original-uInitrd> <output-uInitrd>}
out=${2:?usage: patch-initramfs.sh <original-uInitrd> <output-uInitrd>}

work=$(mktemp -d /tmp/anbernext-initrd.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root"

( cd "$work/root" && zcat "$in" | cpio -idm --quiet )

python3 - "$work/root/init" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
reps = [
('''bootpart="$(wait_partition NEXTBOOT)"
if [ -n "$bootpart" ] && rgsplash held $BTN_MODE 1500; then''',
'''bootpart="$(wait_partition NEXTBOOT)"

# boot trace: prove how far stage 1 got, even with a black screen
trace() {
	[ -n "${bootpart:-}" ] || return 0
	if mount -t vfat -o rw "$bootpart" /bootpart 2>/dev/null; then
		printf 'stage1: %s\\n' "$*" >>/bootpart/boot-trace.txt 2>/dev/null
		sync
		umount /bootpart 2>/dev/null
	fi
}
trace "partition ${bootpart:-none}"

if [ -n "$bootpart" ] && rgsplash held $BTN_MODE 1500; then'''),
('''        rgsplash show /screens/boot-android.ppm''',
'''        trace "F held -> android"
        rgsplash show /screens/boot-android.ppm'''),
('''fi

phrase
rgsplash bar 18''',
'''fi

trace "F check done"

phrase
rgsplash bar 18'''),
('''rgsplash bar 28''',
'''trace "root mounted ${root:-none}"
rgsplash bar 28'''),
('''exec switch_root /newroot /sbin/nextui-init''',
'''trace "switch_root"
exec switch_root /newroot /sbin/nextui-init'''),
]
for old, new in reps:
    n = s.count(old)
    assert n == 1, f"expected 1 match, found {n}: {old[:50]!r}"
    s = s.replace(old, new)
open(p, 'w').write(s)
print("patched init:", p)
PY

chmod 0755 "$work/root/init"
( cd "$work/root" && find . -print0 | cpio --null -o -H newc --owner root:root 2>/dev/null | gzip -9 ) >"$out"
gzip -t "$out"
echo "wrote $out ($(stat -c %s "$out") bytes)"
