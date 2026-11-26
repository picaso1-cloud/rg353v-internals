"""Download the latest Arch-R / dArkOS firmware images.

The patcher needs two images:
  * the Arch-R image (provides the rootfs, p2)
  * the dArkOS image (provides the boot chain p1/p2 + p3 kernel/DTB/initramfs)

Both are downloaded from GitHub releases and cached on disk so they are not
re-downloaded on every run.
"""

import os
import re
import shutil
import subprocess
import tempfile
import urllib.request

# GitHub repos that host the firmware images.
REPOS = {
    "arch-r": "archr-linux/Arch-R",
    "darkos": "christianhaitian/dArkOS",
}

# Asset name patterns (regex) for each firmware.
ASSET_PATTERNS = {
    # The R36S "original" image (the clone image is for K36 clones).
    "arch-r": re.compile(r"^ArchR-R36S\.aarch64-\d+-original\.img\.gz$"),
    # The RG353V image is split into 7z parts: <name>.img.7z.001, .002, ...
    "darkos": re.compile(r"^dArkOS_RG353v_trixie_\d+\.img\.7z\.\d+$"),
}


def _github_release(repo, version):
    """Return the release dict for a repo/version (or the latest release)."""
    if version == "latest":
        url = f"https://api.github.com/repos/{repo}/releases/latest"
    else:
        url = f"https://api.github.com/repos/{repo}/releases/tags/{version}"
    with urllib.request.urlopen(url, timeout=60) as resp:
        import json
        return json.load(resp)


def _download(url, dest):
    """Download url to dest, skipping if dest already exists and is non-empty."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return
    tmp = dest + ".part"
    with urllib.request.urlopen(url, timeout=300) as resp, open(tmp, "wb") as f:
        shutil.copyfileobj(resp, f)
    os.replace(tmp, dest)


def _cache_dir():
    return os.environ.get("ARCHR_PATCHER_CACHE", os.path.join(os.path.expanduser("~"), ".cache", "archr-patcher"))


def fetch(firmware, version, out):
    """Download the firmware image to `out`. Returns the path to the image.

    `firmware` is one of the keys in REPOS. `version` is a tag or "latest".
    """
    repo = REPOS[firmware]
    pattern = ASSET_PATTERNS[firmware]
    release = _github_release(repo, version)
    assets = release.get("assets", [])

    if firmware == "arch-r":
        match = [a for a in assets if pattern.match(a["name"])]
        if not match:
            raise RuntimeError(f"no Arch-R original image asset found in release {version}")
        asset = match[0]
        _download(asset["browser_download_url"], out)
        # Decompress .img.gz -> .img
        if out.endswith(".img.gz"):
            img = out[:-3]
            if not (os.path.exists(img) and os.path.getsize(img) > 0):
                subprocess.run(["gzip", "-d", out], check=True)
            return img
        return out

    if firmware == "darkos":
        matches = [a for a in assets if pattern.match(a["name"])]
        if not matches:
            raise RuntimeError(f"no dArkOS RG353V image parts found in release {version}")
        # Download all parts, combine, extract.
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        parts = []
        for a in sorted(matches, key=lambda x: x["name"]):
            part_path = os.path.join(os.path.dirname(out) or ".", a["name"])
            _download(a["browser_download_url"], part_path)
            parts.append(part_path)
        # Combine the 7z parts.
        combined = out + ".7z"
        if len(parts) == 1:
            shutil.copy2(parts[0], combined)
        else:
            # Concatenate the split parts into a single 7z archive.
            with open(combined, "wb") as f:
                for p in parts:
                    with open(p, "rb") as src:
                        shutil.copyfileobj(src, f)
        # Extract the .img from the 7z.
        if not (os.path.exists(out) and os.path.getsize(out) > 0):
            subprocess.run(["7z", "x", "-y", "-o", os.path.dirname(out) or ".", combined], check=True)
        # Clean up the parts and combined archive.
        for p in parts:
            if os.path.exists(p):
                os.remove(p)
        if os.path.exists(combined):
            os.remove(combined)
        return out

    raise ValueError(f"unknown firmware: {firmware}")
