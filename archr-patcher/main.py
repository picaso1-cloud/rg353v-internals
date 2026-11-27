#!/usr/bin/env python3
"""archr-patcher — download, patch, and flash Arch-R for the Anbernic RG353V.

Usage:
  archr-patcher fetch --firmware arch-r --version latest --out ./archr.img
  archr-patcher patch --image ./archr.img --device rg353v --out ./archr-rg353v.img
  archr-patcher flash --image ./archr-rg353v.img --target /dev/sdX
"""

import argparse
import os
import sys

import fetch
import flash
import patch

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    parser = argparse.ArgumentParser(
        description="Download, patch, and flash Arch-R for the Anbernic RG353V."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_fetch = sub.add_parser("fetch", help="Download a firmware image")
    p_fetch.add_argument("--firmware", required=True, choices=["arch-r", "darkos"])
    p_fetch.add_argument("--version", default="latest")
    p_fetch.add_argument("--out", required=True)

    p_patch = sub.add_parser("patch", help="Patch an Arch-R image for the RG353V")
    p_patch.add_argument("--image", required=True)
    p_patch.add_argument("--device", required=True)
    p_patch.add_argument("--out", required=True)
    p_patch.add_argument("--base", default=None, help="dArkOS base image path")
    p_patch.add_argument(
        "--no-prepare-boot",
        action="store_true",
        help="skip the boot partition prep (initramfs + the 25 MHz SDIO cap)",
    )

    p_prepare = sub.add_parser(
        "prepare", help="Only prepare the boot partition of an image"
    )
    p_prepare.add_argument("--image", required=True)

    p_flash = sub.add_parser("flash", help="Flash the image to a target device")
    p_flash.add_argument("--image", required=True)
    p_flash.add_argument("--target", required=True)

    args = parser.parse_args()

    if args.command == "fetch":
        out = fetch.fetch(args.firmware, args.version, args.out)
        print(f"fetched: {out}")
    elif args.command == "patch":
        profile = os.path.join(HERE, "profiles", f"{args.device}.yaml")
        out = patch.patch(
            args.image,
            profile,
            args.out,
            base=args.base,
            prepare=not args.no_prepare_boot,
        )
        print(f"patched: {out}")
    elif args.command == "prepare":
        patch.prepare_boot(args.image)
        print(f"prepared: {args.image}")
    elif args.command == "flash":
        flash.flash(args.image, args.target)
        print(f"flashed: {args.target}")


if __name__ == "__main__":
    main()
