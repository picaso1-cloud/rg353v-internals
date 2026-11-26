# 29 — Arch-R RG353V patcher/flasher tool

**Date:** 2026-11-26 · **Location:** `archr-patcher/`

A reusable tool that downloads the latest Arch-R release, patches it for the
RG353V (RK3566), and produces an SD-ready image. It is the automation of the
manual workflow in [`tools/archr-port/`](tools/archr-port/).

## Why

Every time a new Arch-R release comes out, the manual workflow is:
1. Download the Arch-R image.
2. Extract the rootfs (p4).
3. Apply the port (`tools/archr-port/apply.sh`).
4. Flash the rootfs to p4 (the dArkOS boot chain + p3 stay as-is).

The patcher automates steps 1–4 and produces a complete image that can be
flashed to a fresh SD card.

## How it works

The patcher uses the **dArkOS image as the base** (it has the correct boot chain
p1/p2 + p3 kernel/DTB/initramfs/extlinux.conf that boots on the RG353V) and
replaces only **p4 (rootfs)** with the ported Arch-R rootfs.

- **Arch-R image** → provides the rootfs (p2, ext4, "ARCHR_ROOT").
- **dArkOS image** → provides the boot chain (p1/p2) + kernel/DTB/initramfs (p3).
- **Port** → applied to the Arch-R rootfs via `tools/archr-port/apply.sh`.

### Partition layouts

**Arch-R (R36S, MBR):**
| Partition | Start | Size | Type |
|---|---|---|---|
| p1 | 32768 | 524288 | FAT32 (boot, "ARCHR") |
| p2 | 557056 | 12582912 | ext4 (rootfs, "ARCHR_ROOT") |
| p3 | 13139968 | 65536 | ext4 (storage, "STORAGE") |

**dArkOS (RG353V, GPT):**
| Partition | Start | Size | Type | Name |
|---|---|---|---|---|
| p1 | 16384 | 8192 | bootloader | uboot |
| p2 | 24576 | 8192 | bootloader | resource |
| p3 | 32768 | 202752 | FAT (boot) | dArkOS_Fat |
| p4 | 237568 | 15208047 | rootfs (btrfs) | rootfs |
| p5 | 15446016 | 162031 | exfat (easyroms) | 4 |

The patcher identifies the rootfs as the **largest partition** in each image.

## Usage

```bash
# 1. Download the latest Arch-R image (R36S original)
python3 main.py fetch --firmware arch-r --version latest --out ./archr.img

# 2. Download the dArkOS image (the base)
python3 main.py fetch --firmware darkos --version latest --out ./darkos.img

# 3. Patch the Arch-R image for the RG353V
python3 main.py patch --image ./archr.img --device rg353v --out ./archr-rg353v.img --base ./darkos.img

# 4. Flash to the SD card
sudo python3 main.py flash --image ./archr-rg353v.img --target /dev/sdX
```

The `patch` step downloads the dArkOS image automatically if `--base` is not
given (cached in `~/.cache/archr-patcher/`).

## Architecture

- `main.py` — CLI entry point (`fetch`, `patch`, `flash` subcommands).
- `fetch.py` — downloads the Arch-R / dArkOS images from GitHub releases.
- `patch.py` — parses partition tables, extracts the rootfs, applies the port,
  resizes, and writes the rootfs into the base image's p4.
- `flash.py` — writes the image to the target device.
- `profiles/rg353v.yaml` — the RG353V device profile.
- `tests/test_patch.py` — offline tests (synthetic images, mocked port/resize).

## Device profiles

Each device has a profile in `profiles/`. The RG353V profile is
[`profiles/rg353v.yaml`](profiles/rg353v.yaml). To add a new device (e.g.
RG405V), create `profiles/<device>.yaml` with the appropriate base firmware,
kernel, and port script.

## GPU blob

The port installs the Mali-G52 vendor driver. The blob and hook must be available
at the paths in `profiles/rg353v.yaml` (or override with the `GPU_BLOB` /
`GPU_HOOK` environment variables). See [`tools/archr-port/README.md`](tools/archr-port/README.md).

## Tests

```bash
python3 -m pytest tests/ -v
```

The tests build small synthetic images (MBR + GPT) and verify the partition
parsing and the patch logic (with the port application and filesystem resize
mocked).

## Status

- **Done:** tool implemented, offline tests passing.
- **Not yet verified on hardware:** the full patch → flash → boot cycle. The
  port itself is proven (see `tools/archr-port/`), but the patcher's image
  assembly (resize + write to p4) needs a hardware test.
