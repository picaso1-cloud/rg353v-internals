"""Patch an Arch-R image for the RG353V.

The strategy: use the dArkOS image as the base (it has the correct boot chain
p1/p2 + p3 kernel/DTB/initramfs/extlinux.conf) and replace only p4 (rootfs) with
the ported Arch-R rootfs. This matches the existing working port
(``tools/archr-port/apply.sh``).

Steps:
  1. Parse the Arch-R image's partition table; find the rootfs (largest partition).
  2. Extract the rootfs to a file.
  3. Apply the port (run ``tools/archr-port/apply.sh`` on the rootfs file).
  4. Parse the dArkOS base image's partition table; find its rootfs (p4).
  5. Resize the ported rootfs to the dArkOS p4 size.
  6. Copy the dArkOS base image to the output and write the rootfs into p4.
"""

import os
import re
import shutil
import subprocess
from dataclasses import dataclass

import yaml


@dataclass
class Partition:
    index: int
    start: int  # sector
    size: int   # sectors
    type: str
    name: str = ""


def parse_partitions(image):
    """Parse the partition table of an image using ``sfdisk -d``.

    Returns a list of :class:`Partition` in disk order.
    """
    out = subprocess.check_output(["sfdisk", "-d", image], text=True)
    partitions = []
    for line in out.splitlines():
        m = re.match(r"^\S+ : start=\s*(\d+), size=\s*(\d+), type=(\S+)", line)
        if not m:
            continue
        start, size, ptype = int(m.group(1)), int(m.group(2)), m.group(3)
        name = ""
        nm = re.search(r'name="([^"]*)"', line)
        if nm:
            name = nm.group(1)
        partitions.append(
            Partition(index=len(partitions) + 1, start=start, size=size, type=ptype, name=name)
        )
    return partitions


def find_rootfs(partitions):
    """The rootfs is the largest partition."""
    return max(partitions, key=lambda p: p.size)


def extract_rootfs(image, partition, out):
    """Extract a partition to a file using ``dd``."""
    subprocess.run(
        ["dd", "if=" + image, "of=" + out, "bs=512",
         f"skip={partition.start}", f"count={partition.size}"],
        check=True,
    )


def apply_port(rootfs_file, profile, repo_root):
    """Run the port script (``apply.sh``) on the rootfs file.

    The GPU blob / hook paths come from the profile (or the environment).
    """
    apply_sh = profile["rootfs_port"]
    if not os.path.isabs(apply_sh):
        apply_sh = os.path.join(repo_root, apply_sh)
    env = os.environ.copy()
    if profile.get("gpu_blob"):
        env["GPU_BLOB"] = profile["gpu_blob"]
    if profile.get("gpu_hook"):
        env["GPU_HOOK"] = profile["gpu_hook"]
    subprocess.run(["bash", apply_sh, rootfs_file], env=env, check=True)


def resize_rootfs(rootfs_file, target_size_bytes):
    """Grow the ext4 rootfs to target_size_bytes.

    resize2fs takes a size in *filesystem* blocks, so a raw block count is
    ambiguous (1K vs 4K). Pass a ``K`` (1024-byte) suffix so it is explicit;
    the result is <= target_size_bytes and still fits the partition.
    """
    # resize2fs refuses to resize a dirty filesystem; clean it first.
    # -f forces a check, -y assumes yes to repairs (no terminal in CI/patcher).
    subprocess.run(["e2fsck", "-f", "-y", rootfs_file], check=True)
    subprocess.run(
        ["resize2fs", rootfs_file, f"{target_size_bytes // 1024}K"], check=True
    )


def write_rootfs(base_image, partition, rootfs_file):
    """Write the rootfs file into the base image's partition.

    Uses Python I/O (not ``dd``) because ``dd`` truncates the output file to
    the last sector written, which would corrupt the GPT backup header.
    """
    with open(base_image, "r+b") as out, open(rootfs_file, "rb") as src:
        out.seek(partition.start * 512)
        while True:
            chunk = src.read(1024 * 1024)  # 1 MiB chunks
            if not chunk:
                break
            out.write(chunk)


def load_profile(profile):
    """Load the profile YAML. Returns the profile dict."""
    if os.path.isdir(profile):
        profile = os.path.join(profile, "rg353v.yaml")
    with open(profile) as f:
        return yaml.safe_load(f)


def patch(image, profile, out, base=None):
    """Apply the profile to the Arch-R image. Returns the output path.

    ``image`` is the Arch-R image. ``profile`` is the profile path (or a device
    name that maps to ``profiles/<name>.yaml``). ``out`` is the output image
    path. ``base`` is the dArkOS base image path; if not given it is looked up
    in the profile or downloaded.
    """
    profile_dict = load_profile(profile)
    # Profile lives at <repo>/archr-patcher/profiles/<name>.yaml; the port
    # script path is relative to <repo> (e.g. tools/archr-port/apply.sh).
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(profile))))

    # Determine the dArkOS base image.
    if base is None:
        base = profile_dict.get("base_image")
    if base is None:
        import fetch
        cache = fetch._cache_dir()
        os.makedirs(cache, exist_ok=True)
        base = fetch.fetch(
            profile_dict["base_firmware"],
            profile_dict.get("base_version", "latest"),
            os.path.join(cache, "darkos-base.img"),
        )

    # 1. Find the Arch-R rootfs partition.
    archr_parts = parse_partitions(image)
    archr_rootfs = find_rootfs(archr_parts)

    # 2. Extract the rootfs.
    rootfs_file = out + ".rootfs"
    extract_rootfs(image, archr_rootfs, rootfs_file)

    # 3. Apply the port.
    apply_port(rootfs_file, profile_dict, repo_root)

    # 4. Find the dArkOS base rootfs partition.
    darkos_parts = parse_partitions(base)
    darkos_rootfs = find_rootfs(darkos_parts)

    # 5. Resize the ported rootfs to the dArkOS p4 size.
    target_size = darkos_rootfs.size * 512
    resize_rootfs(rootfs_file, target_size)

    # 6. Copy the base image to the output.
    shutil.copy2(base, out)

    # 7. Write the rootfs into the base image's p4.
    write_rootfs(out, darkos_rootfs, rootfs_file)

    # 8. Clean up.
    os.remove(rootfs_file)
    return out
