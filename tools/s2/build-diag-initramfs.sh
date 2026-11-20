#!/bin/bash
# Build a diagnostic initramfs (banner + rootfs/chroot report, then stop).
#   build-diag-initramfs.sh <uInitrd.orig> [out]
set -euo pipefail
IN="${1:?usage: $0 <uInitrd.orig> [out]}"
OUT="${2:-${IN%.orig}.s2diag}"
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
gzip -dc "$IN" | ( cd "$W" && cpio -idm --quiet )
install -m 0755 "$HERE/../s1/s1-banner.sh" "$W/scripts/s1-banner.sh"
install -m 0755 "$HERE/s2-diag.sh"        "$W/scripts/s2-diag.sh"
python3 - "$W/init" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
anchor = "mount -t devpts -o noexec,nosuid,gid=5,mode=0600 devpts /dev/pts || true\n"
if anchor not in s: raise SystemExit("anchor not found")
ins = anchor + """
# --- S2 diagnostics (archr-device-kit) ---
[ -x /scripts/s1-banner.sh ] && /scripts/s1-banner.sh || true
[ -x /scripts/s2-diag.sh ] && /scripts/s2-diag.sh
# (s2-diag never returns: it stops for inspection)
"""
open(p, "w").write(s.replace(anchor, ins, 1))
print("init patched for diagnostics")
PY
find "$W" -exec touch -h -d '1970-01-01 00:00:00 UTC' {} +
( cd "$W" && find . -print0 | cpio --null -o -H newc --owner 0:0 --reproducible --quiet ) | gzip -9 > "$OUT"
gzip -t "$OUT"; sh -n "$W/init"; sh -n "$W/scripts/s2-diag.sh"
echo "entries: $(zcat "$OUT" | cpio -it --quiet 2>/dev/null | wc -l)"
echo "sha256 : $(sha256sum "$OUT" | cut -d' ' -f1)"
