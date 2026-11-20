#!/bin/bash
# Replace dArkOS's /init with our tracer (keeps all their binaries/libs).
set -euo pipefail
IN="${1:?usage: $0 <uInitrd.orig> [out]}"
OUT="${2:-${IN%.orig}.ourtrace}"
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
gzip -dc "$IN" | ( cd "$W" && cpio -idm --quiet )
cp -a "$W/init" "$W/init.darkos"
install -m 0755 "$HERE/init-trace.sh"      "$W/init"
install -m 0755 "$HERE/s2-init-wrapper.sh" "$W/scripts/s2-init-wrapper.sh"
sh -n "$W/init"; sh -n "$W/scripts/s2-init-wrapper.sh"
find "$W" -exec touch -h -d '1970-01-01 00:00:00 UTC' {} +
( cd "$W" && find . -print0 | cpio --null -o -H newc --owner 0:0 --reproducible --quiet ) | gzip -9 > "$OUT"
gzip -t "$OUT"
echo "entries: $(zcat "$OUT" | cpio -it --quiet 2>/dev/null | wc -l)"
echo "init is ours: $(zcat "$OUT" | cpio -i --to-stdout ./init 2>/dev/null | head -2 | tail -1)"
echo "sha256 : $(sha256sum "$OUT" | cut -d' ' -f1)"
