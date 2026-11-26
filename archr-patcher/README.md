# archr-patcher

Download the latest Arch-R release, patch it for the Anbernic RG353V (RK3566),
and produce an SD-ready image.

## How it works

The patcher uses the **dArkOS image as the base** (it has the correct boot chain
p1/p2 + p3 kernel/DTB/initramfs/extlinux.conf that boots on the RG353V) and
replaces only **p4 (rootfs)** with the ported Arch-R rootfs. This matches the
existing working port in [`tools/archr-port/`](../tools/archr-port/).

- **Arch-R image** → provides the rootfs (p2, ext4).
- **dArkOS image** → provides the boot chain (p1/p2) + kernel/DTB/initramfs (p3).
- **Port** → applied to the Arch-R rootfs via `tools/archr-port/apply.sh`.

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
given (it is cached in `~/.cache/archr-patcher/`).

## Requirements

- Python 3.10+
- `sfdisk`, `dd`, `losetup`, `resize2fs`, `mount`, `7z` (util-linux, coreutils, e2fsprogs, p7zip)
- The Mali-G52 GPU blob and hook (see below)
- Root for the `patch` and `flash` steps (mounting, dd, resize2fs)

## GPU blob

The port installs the Mali-G52 vendor driver. The blob and hook must be available
at the paths in `profiles/rg353v.yaml` (or override with the `GPU_BLOB` /
`GPU_HOOK` environment variables):

```
GPU_BLOB=/path/to/libmali-bifrost-g52-g24p0-wayland-gbm.so
GPU_HOOK=/path/to/libmali-hook-g24p0.so.1.9.0
```

See [`tools/archr-port/README.md`](../tools/archr-port/README.md) for details.

## Device profiles

Each device has a profile in `profiles/`. The RG353V profile is
[`profiles/rg353v.yaml`](profiles/rg353v.yaml). To add a new device (e.g.
RG405V), create `profiles/<device>.yaml` with the appropriate base firmware,
kernel, and port script.

## Tests

```bash
python3 -m pytest tests/ -v
```

The tests build small synthetic images and verify the partition parsing and the
patch logic (with the port application and filesystem resize mocked).
