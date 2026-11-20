#!/bin/bash
# Build an initramfs that (a) shows the banner, (b) fixes /dev/console,
# (c) installs the S2 wrapper as the rootfs /sbin/init, then hands over.
#   build-debug-initramfs.sh <uInitrd.orig> [out]
set -euo pipefail
IN="${1:?usage: $0 <uInitrd.orig> [out]}"
OUT="${2:-${IN%.orig}.s2dbg}"
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
gzip -dc "$IN" | ( cd "$W" && cpio -idm --quiet )
install -m 0755 "$HERE/../s1/s1-banner.sh"   "$W/scripts/s1-banner.sh"
install -m 0755 "$HERE/s2-init-wrapper.sh"   "$W/scripts/s2-init-wrapper.sh"
python3 - "$W/init" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
devpts='mount -t devpts -o noexec,nosuid,gid=5,mode=0600 devpts /dev/pts || true\n'
if 'S1 bring-up banner' not in s:
    s=s.replace(devpts, devpts+'''
# --- S1 bring-up banner (archr-device-kit) ---
[ -x /scripts/s1-banner.sh ] && /scripts/s1-banner.sh || true
''',1)
anchor='exec run-init ${drop_caps} "${rootmnt}" "${init}" "$@"'
assert anchor in s, "run-init anchor not found"
shim='''# --- S2: make the rootfs handover visible ---
mkdir -p "${rootmnt}/dev"
[ -e "${rootmnt}/dev/console" ] || mknod -m 620 "${rootmnt}/dev/console" c 5 1 2>/dev/null || true
[ -e "${rootmnt}/dev/null" ]    || mknod -m 666 "${rootmnt}/dev/null"    c 1 3 2>/dev/null || true
if [ -x /scripts/s2-init-wrapper.sh ] && [ ! -e "${rootmnt}/s2-init-wrapper.installed" ]; then
	cp -a "${rootmnt}/sbin/init" "${rootmnt}/sbin/init.stock" 2>/dev/null || true
	rm -f "${rootmnt}/sbin/init"
	cp /scripts/s2-init-wrapper.sh "${rootmnt}/sbin/init"
	chmod 0755 "${rootmnt}/sbin/init"
	touch "${rootmnt}/s2-init-wrapper.installed"
fi

'''
s=s.replace(anchor, shim+anchor, 1)
open(p,'w').write(s)
print("init patched: banner + console + init wrapper install")
PY
find "$W" -exec touch -h -d '1970-01-01 00:00:00 UTC' {} +
( cd "$W" && find . -print0 | cpio --null -o -H newc --owner 0:0 --reproducible --quiet ) | gzip -9 > "$OUT"
gzip -t "$OUT"; sh -n "$W/init"; sh -n "$W/scripts/s2-init-wrapper.sh"
echo "entries: $(zcat "$OUT" | cpio -it --quiet 2>/dev/null | wc -l)"
echo "sha256 : $(sha256sum "$OUT" | cut -d' ' -f1)"
