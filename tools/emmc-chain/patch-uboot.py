#!/usr/bin/env python3
"""
Patch the RG353V stock (Anbernic 2023) eMMC u-boot FIT default environment.

Why: the eMMC boot chain owns the boot (the BootROM is eMMC-first), so the
only way to add "boot Linux from TF1" while keeping Android installed is to
replace the compiled-in `bootcmd` inside the u-boot payload of the FIT.

The FIT is uncompressed and has no signature — only per-image sha256 records,
which the SPL verifies. This tool replaces the `bootcmd` value in place (same
byte length, space padded) and rewrites the sha256 record of the `uboot`
image in the FIT FDT, for **both** FIT copies (8 MiB and 10 MiB).

Usage:
    patch-uboot.py --input uboot.img --bootcmd-file bootcmd.txt \
                   --output uboot-patched.img [--verify]

    dd if=emmc-first16MiB.img of=uboot.img bs=1M skip=8 count=4
    dd if=uboot-patched.img of=/dev/mmcblk0 bs=1M seek=8 conv=fsync

Layout verified against the RG353V's stock eMMC (`U-Boot 2017.09`,
Jan 08 2023); the script asserts everything and fails loudly on a different
build instead of writing garbage. See 34-emmc-dualboot-chain.md.
"""
import argparse
import hashlib
import struct
import subprocess
import sys

FIT_BASES = (0x0, 0x200000)     # 8 MiB and 10 MiB inside the 4 MiB partition
FIT_MAGIC = b"\xd0\x0d\xfe\xed"
UBOOT_POS = 0x1000              # /images/uboot data-position
UBOOT_SIZE = 0x12ef58           # /images/uboot data-size
TAG = len(b"bootcmd=")


def be32(b, off):
    return struct.unpack(">I", b[off:off + 4])[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--bootcmd-file", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--verify", action="store_true")
    a = ap.parse_args()

    img = bytearray(open(a.input, "rb").read())
    if len(img) != 4 * 1024 * 1024:
        raise SystemExit(f"{a.input}: expected a 4 MiB u-boot partition image")

    script = open(a.bootcmd_file, "rb").read().strip()
    if not script or b"\x00" in script or b"\n" in script:
        raise SystemExit("bootcmd must be one non-empty line without NULs")

    for base in FIT_BASES:
        if img[base:base + 4] != FIT_MAGIC:
            raise SystemExit(f"copy at 0x{base:x} is not a FIT")
        fdt_size = be32(img, base + 4)

        var = img.find(b"bootcmd=", base)
        if var < 0:
            raise SystemExit(f"bootcmd not found at 0x{base:x}")
        end = img.find(b"\x00", var)
        slot = end - var - TAG
        if len(script) > slot:
            raise SystemExit(
                f"script is {len(script)} B; this build only has {slot} B at "
                f"0x{base:x}"
            )

        old = hashlib.sha256(
            img[base + UBOOT_POS:base + UBOOT_POS + UBOOT_SIZE]
        ).digest()

        img[var + TAG:end] = script + b" " * (slot - len(script))

        new = hashlib.sha256(
            img[base + UBOOT_POS:base + UBOOT_POS + UBOOT_SIZE]
        ).digest()

        pos = img.find(old, base, base + fdt_size)
        if pos < 0:
            raise SystemExit(f"sha256 record not found in FDT at 0x{base:x} "
                             f"(wrong build/layout?)")
        if img.find(old, pos + 1, base + fdt_size) >= 0:
            raise SystemExit(f"sha256 record not unique at 0x{base:x}")
        img[pos:pos + 32] = new

        print(f"  copy 0x{base:x}: slot {slot} B, "
              f"sha256 {old.hex()[:12]} -> {new.hex()[:12]}")

    open(a.output, "wb").write(img)
    print(f"written {a.output} ({len(img)} B)")

    if a.verify:
        try:
            out = subprocess.run(["dumpimage", "-l", a.output],
                                 capture_output=True, text=True, check=True).stdout
            print("\n".join(l for l in out.splitlines()
                            if "Image 0" in l or "Hash value" in l))
        except (OSError, subprocess.CalledProcessError):
            print("  (dumpimage unavailable; hash records were recomputed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
