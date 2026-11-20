#!/bin/bash
# Build an S1 initramfs from a dArkOS (or any Debian-style) uInitrd.
#
#   patch-initramfs.sh <uInitrd.orig> [out]
#
# Inserts exactly two things: /scripts/s1-banner.sh and a guarded call to it in
# /init after /dev exists. Reproducible: same input -> same output bytes.
set -euo pipefail
IN="${1:?usage: patch-initramfs.sh <uInitrd.orig> [out]}"
OUT="${2:-${IN%.orig}.s1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BANNER="$HERE/s1-banner.sh"
[ -f "$IN" ] || { echo "missing $IN"; exit 1; }
[ -f "$BANNER" ] || { echo "missing $BANNER"; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
gzip -dc "$IN" | ( cd "$W" && cpio -idm --quiet )
[ -f "$W/init" ] || { echo "no /init in $IN"; exit 1; }

install -m 0755 "$BANNER" "$W/scripts/s1-banner.sh"

python3 - "$W/init" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = "S1 bring-up banner (archr-device-kit)"
if marker in s:
    print("init already patched")
    raise SystemExit(0)
anchor = "mount -t devpts -o noexec,nosuid,gid=5,mode=0600 devpts /dev/pts || true\n"
if anchor not in s:
    raise SystemExit("anchor not found — unexpected initramfs layout")
ins = anchor + """
# --- S1 bring-up banner (archr-device-kit) ---------------------------------
# Runs after /dev exists, before root mounting. Always returns 0.
[ -x /scripts/s1-banner.sh ] && /scripts/s1-banner.sh || true
# --------------------------------------------------------------------------
"""
open(p, "w").write(s.replace(anchor, ins, 1))
print("init patched")
PY

# Normalise timestamps so the build is byte-for-byte reproducible.
find "$W" -exec touch -h -d '1970-01-01 00:00:00 UTC' {} +
( cd "$W" && find . -print0 \
  | cpio --null -o -H newc --owner 0:0 --reproducible --quiet ) \
  | gzip -9 > "$OUT"

gzip -t "$OUT"
sh -n "$W/init"
sh -n "$W/scripts/s1-banner.sh"
printf 'entries: %s\n' "$(zcat "$OUT" | cpio -it --quiet 2>/dev/null | wc -l)"
printf 'sha256 : %s\n' "$(sha256sum "$OUT" | cut -d' ' -f1)"
printf 'output : %s\n' "$OUT"
