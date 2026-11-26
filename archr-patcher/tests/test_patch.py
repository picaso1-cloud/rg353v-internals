"""Offline tests for the patcher.

These tests build small synthetic images (an MBR "Arch-R-like" image and a GPT
"dArkOS-like" image) and verify the partition parsing and the patch logic. The
port application and filesystem resize are mocked so the tests run offline and
fast without a real rootfs or GPU blob.
"""

import os
import subprocess
import sys
import tempfile
from unittest import mock

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import patch
from patch import Partition, find_rootfs, parse_partitions, patch as patch_fn


def _make_image(path, label, sizes):
    """Create a synthetic image with the given partition sizes (in sectors).

    The image is sized to fit all partitions plus the GPT backup header
    (34 sectors) and the first-partition offset (2048 sectors).
    """
    total = sum(sizes) + 2048 + 34 + 4096
    size_bytes = total * 512
    with open(path, "wb") as f:
        f.truncate(size_bytes)
    lines = [f"label: {label}", "unit: sectors", ""]
    for s in sizes:
        lines.append(f",{s}")
    script = "\n".join(lines)
    subprocess.run(["sfdisk", path], input=script, text=True, check=True)
    return path


def _write_pattern(path, partition, value=0xAB):
    """Write a single-byte pattern into a partition using dd."""
    data = bytes([value]) * (partition.size * 512)
    with open(path, "r+b") as f:
        f.seek(partition.start * 512)
        f.write(data)


def test_parse_partitions_mbr(tmp_path):
    img = tmp_path / "archr.img"
    _make_image(str(img), "dos", [1024, 100000, 1024])
    parts = parse_partitions(str(img))
    assert len(parts) == 3
    # The rootfs is the largest partition (index 2).
    assert parts[1].size == 100000
    assert parts[0].size == 1024
    assert parts[2].size == 1024


def test_parse_partitions_gpt(tmp_path):
    img = tmp_path / "darkos.img"
    _make_image(str(img), "gpt", [1024, 1024, 1024, 100000, 1024])
    parts = parse_partitions(str(img))
    assert len(parts) == 5
    # The rootfs is the largest partition (index 4).
    assert parts[3].size == 100000


def test_find_rootfs():
    parts = [
        Partition(index=1, start=0, size=100, type="83", name="p1"),
        Partition(index=2, start=100, size=100000, type="83", name="rootfs"),
        Partition(index=3, start=100100, size=100, type="83", name="p3"),
    ]
    assert find_rootfs(parts).index == 2


def test_patch_replaces_rootfs(tmp_path):
    # Arch-R-like MBR image: p2 is the rootfs (largest).
    archr = tmp_path / "archr.img"
    _make_image(str(archr), "dos", [1024, 100000, 1024])
    archr_parts = parse_partitions(str(archr))
    archr_rootfs = find_rootfs(archr_parts)
    _write_pattern(str(archr), archr_rootfs, value=0xAB)

    # dArkOS-like GPT image: p4 is the rootfs (largest).
    darkos = tmp_path / "darkos.img"
    _make_image(str(darkos), "gpt", [1024, 1024, 1024, 100000, 1024])
    darkos_parts = parse_partitions(str(darkos))
    darkos_rootfs = find_rootfs(darkos_parts)

    out = tmp_path / "out.img"
    profile = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "profiles", "rg353v.yaml")

    with mock.patch.object(patch, "apply_port") as mock_port, \
         mock.patch.object(patch, "resize_rootfs") as mock_resize:
        result = patch_fn(str(archr), profile, str(out), base=str(darkos))

    assert result == str(out)
    assert os.path.exists(str(out))
    mock_port.assert_called_once()
    mock_resize.assert_called_once()

    # The output p4 should contain the data pattern from the Arch-R rootfs.
    # The output image is a copy of the base image with p4 replaced, so p4 is
    # at the same location as in the base image.
    with open(str(out), "r+b") as f:
        f.seek(darkos_rootfs.start * 512)
        sample = f.read(1024)
    assert sample == bytes([0xAB]) * 1024
