"""Flash the patched image to a target device."""

import subprocess


def flash(image, target):
    """Write the image to the target device using ``dd``.

    ``target`` is a block device (e.g. ``/dev/sdX``). The caller must ensure the
    device is the correct one and that it is safe to overwrite.
    """
    subprocess.run(
        ["dd", "if=" + image, "of=" + target, "bs=4M", "conv=fsync"],
        check=True,
    )
