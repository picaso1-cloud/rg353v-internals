#!/usr/bin/env python3
"""Copy aarch64 shared-library dependencies of given binaries into a live tree."""
import os
import re
import shutil
import subprocess
import sys

SRC_ROOT = "/mnt/da"
DEST_LIB = sys.argv[1]
BINARIES = sys.argv[2:]

SEARCH_DIRS = [
    f"{SRC_ROOT}/usr/lib/aarch64-linux-gnu",
    f"{SRC_ROOT}/lib/aarch64-linux-gnu",
    f"{SRC_ROOT}/usr/lib",
    f"{SRC_ROOT}/lib",
]


def needed(path):
    try:
        out = subprocess.run(["readelf", "-d", path], capture_output=True, text=True).stdout
    except Exception:
        return []
    return re.findall(r"Shared library: \[(.*?)\]", out)


def find(lib):
    for d in SEARCH_DIRS:
        p = os.path.join(d, lib)
        if os.path.exists(p):
            return p
    return None


seen = set()
queue = list(BINARIES)
while queue:
    cur = queue.pop()
    for lib in needed(cur):
        if lib in seen:
            continue
        seen.add(lib)
        src = find(lib)
        if not src:
            print("MISSING", lib)
            continue
        dst = os.path.join(DEST_LIB, lib)
        if not os.path.exists(dst):
            shutil.copyfile(os.path.realpath(src), dst)
            print("copied", lib)
        queue.append(dst)

print("total libs:", len(seen))
