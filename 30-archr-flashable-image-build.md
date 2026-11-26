# 30 — Building the flashable Arch-R RG353V image (real run log)

Date: 2026-11-26
Branch: `archr-patcher`
Tool: `archr-patcher/` (see `29-archr-patcher.md`)

This is the runbook + troubleshooting log for producing an SD-ready Arch-R
image for the RG353V from the dArkOS base. It records every failure hit during
the first real (non-mocked) run and the fix applied, so the build is
reproducible after a session crash.

---

## Inputs

| Artifact | Path | Size |
|---|---|---|
| Arch-R R36S v3.1.1 image | `downloads/ArchR-R36S.aarch64-20261125-original.img` | 6,762,266,624 B |
| dArkOS RG353v v11192026 image | `downloads/darkos-rg353v/dArkOS_RG353v_trixie_11192026.img` | 8,053,063,680 B |
| Mali-G52 GPU blob (from dArkOS p4) | `downloads/darkos-rg353v/gpu/libmali-bifrost-g52-g29p1.so` | 59,865,008 B |
| Mali hook (from dArkOS p4) | `downloads/darkos-rg353v/gpu/libmali-hook.so.1.9.0` | 72,624 B |

### Where the GPU blob came from
The port's preferred blob (`libmali-bifrost-g52-g24p0-wayland-gbm.so`) is **not
on this server**. The dArkOS rootfs ships `libmali-bifrost-g52-g29p1.so` +
`libmali-hook.so.1.9.0`. Verified the g29p1 build supports Wayland/GBM
(`EGL_KHR_platform_gbm`, `EGL_KHR_platform_wayland`, `wayland` in strings), so
it is a usable substitute. Extracted read-only from dArkOS p4 (btrfs) at
`/mnt/darkos-p4/usr/lib/aarch64-linux-gnu/`.

If you have the g24p0 wayland-gbm build, point `gpu_blob`/`gpu_hook` at it.

---

## Command

```bash
cd rg353v-internals/archr-patcher
python3 main.py patch \
  --image  /path/ArchR-R36S.aarch64-20261125-original.img \
  --device rg353v \
  --out    /path/archr-rg353v.img \
  --base   /path/dArkOS_RG353v_trixie_11192026.img
```

(`--base` is required unless the dArkOS image can be auto-fetched.)

---

## What the tool does

1. Parse Arch-R partitions, pick rootfs = **largest partition** (p2, ext4,
   6.0 GiB).
2. `dd` that partition out to `<out>.rootfs`.
3. Run `tools/archr-port/apply.sh` on it (loop-mount, patch, unmount).
4. Parse dArkOS partitions, rootfs = p4 (15,208,047 sectors = 7.78 GB).
5. `e2fsck -fy` + `resize2fs` the ported rootfs to the p4 size.
6. Copy dArkOS base → `<out>` (this preserves p1/p2 boot chain + p3 kernel).
7. Overwrite p4 in `<out>` with the ported rootfs (Python I/O, **not** `dd`).
8. Remove `<out>.rootfs`.

Result: dArkOS boot chain + kernel + DTB + initramfs + extlinux.conf, with the
ported Arch-R ext4 rootfs in p4.

---

## Bugs found and fixed (this run)

### 1. `apply.sh` path resolution (`patch.py`)
`repo_root` went up 2 dirs from the profile, but the profile sits at
`<repo>/archr-patcher/profiles/rg353v.yaml` and `apply.sh` is at `<repo>/tools/…`.
→ went up **3** dirs.

### 2. `/etc/systemd/system` missing in Arch-R v3.1.1 (`tools/archr-port/apply.sh`)
Arch-R v3.1.1 keeps units only in `/usr/lib/systemd/system/`; the port's step 4
writes into `/etc/systemd/system/` which did not exist.
→ added `mkdir -p "$R/etc/systemd/system"` right after mount. Safe on older
images too.

### 3. `apply.sh` exited 1 on success (`tools/archr-port/apply.sh`)
The script ends with `set -euo pipefail` and a trailing
`[[ "$SAFE" = 1 ]] && echo …`. When `SAFE=0` that test is the last command and
returns 1, so the whole script "failed" after doing all 8 steps.
→ replaced with an `if … then … fi` block + explicit `exit 0`.

### 4. `resize2fs` refused dirty fs (`patch.py`)
The port leaves the fs dirty; `resize2fs` aborts.
→ run `e2fsck -f -y <rootfs>` first (`-y` because there is no terminal).

### 5. `resize2fs` size unit bug → 31 GB rootfs (`patch.py`)
`resize2fs <file> <N>` interprets `N` as **filesystem blocks** (4K here), not
1K blocks. Passing `bytes//1024` made the fs 4× too large (31 GB), which then
made the output image balloon to ~28 GB.
→ pass an explicit unit: `resize2fs <file> f"{bytes//1024}K"`. Correct result:
`1,900,544 × 4K = 7.78 GB`, which fits p4 exactly.

### 6. `dd` truncated the output image (`patch.py`)
`dd of=<image> seek=<p4start> count=<p4size>` **truncates** `<image>` to the last
sector written (verified: a 1000-sector file becomes 600 sectors after writing
sectors 500–599). That destroyed the GPT backup header, and `sfdisk` then read
the image as a bare DOS table.
→ replaced `dd` with Python file I/O (`open(..., "r+b")`, `seek`, chunked
`write`). Python does not truncate.

### 7. Stale loop device after a killed run
A timed-out run left `/dev/loop17` attached to a deleted rootfs file.
→ `losetup -d /dev/loop17` before re-running. Also: run the patcher detached
(`nohup … &`) so a tool timeout cannot kill it mid-write.

---

## Gotchas / notes

- The patcher must **not** run under a short tool timeout: extract (~45 s) +
  port (~60 s) + fsck/resize + 8 GB copy + 7.8 GB p4 write is several minutes.
  Use `nohup … > patch.log 2>&1 &` and poll the log.
- dArkOS p4 is **btrfs**, Arch-R rootfs is **ext4**. The dArkOS initramfs/kernel
  must mount ext4 for this to boot — *unverified on hardware*.
- Boot chain integrity relies on reusing dArkOS p1/p2 (uboot/resource) and p3
  (Image, rk3566-353v.dtb, uInitrd, extlinux.conf) byte-for-byte; only p4 is
  replaced.

---

## Verification (offline, after a successful run)

```bash
# 1. GPT intact (should print a gpt label with 5 partitions, not "label: dos")
sfdisk -d archr-rg353v.img

# 2. output size == dArkOS base size (8,053,063,680)
stat -c '%s' archr-rg353v.img

# 3. ext4 inside p4 mounts and looks like Arch-R
LOOP=$(losetup -f --show -o $((237568*512)) archr-rg353v.img); \
  mount -o ro "$LOOP" /mnt/check; \
  grep -E '^(NAME|PRETTY_NAME|OS_NAME)=' /mnt/check/etc/os-release; \
  ls /mnt/check/usr/lib/systemd/system/archr.target; \
  umount /mnt/check; losetup -d "$LOOP"
```

Success criteria: `label: gpt` with `uboot/resource/dArkOS_Fat/rootfs/…`
partitions, output exactly 8,053,063,680 bytes, p4 mounts, `NAME="ArchR"`,
`archr.target` present, and the ported units exist under
`/usr/lib/systemd/system/`.

---

## Result — image built and verified (2026-11-26 21:13)

Built **`downloads/archr-rg353v.img`**:

- size: `8,053,063,680` bytes (identical to the dArkOS base)
- sha256: `c88910176367ef165d5f62fe6340d3689f48eb24c93d5320554701c6472ae565`
- partition table: `label: gpt`, 5 partitions, GPT backup header intact
  (`uboot`, `resource`, `dArkOS_Fat`, `rootfs` p4 @ sector 237568, `4`)
- p4 filesystem: ext4, `ARCHR_ROOT`, 1,900,544 × 4K blocks (~7.78 GB)
- `/etc/os-release`: `NAME="ArchR"`, `HW_DEVICE="RK3566"`
- GPU blob installed as `libmali.so.1.9.0` (`Bifrost-"g29p1-12eac0"`) +
  `libmali-hook.so.1.9.0`; `libmali-bifrost-g31-g24p0-wayland-gbm.so` symlink
- `default.target -> /usr/lib/systemd/system/archr.target`
- units enabled under `/etc/systemd/system/multi-user.target.wants/`:
  `archr-levels`, `dhcp-wlan0`, `headphones`, `input`, `rg353v-flightrec`,
  `sshd-s2`, `wpa-wlan0`; `getty@tty2`; masks for connman/iwd/sshd/etc.
- `/etc/fstab` has no separate `/storage` mount (storage is on the rootfs)

Image is **ready to flash**. Hardware boot is still unverified.


---

## Next: flash

The `.img` is written to the SD card raw (it is a full disk image):

```bash
sudo python3 main.py flash --image ./archr-rg353v.img --target /dev/sdX
```

Then boot the RG353V, SSH in, and capture logs
(`journalctl -b`, `dmesg`, GPU/EGL smoke test). Hardware verification is
**pending**.
