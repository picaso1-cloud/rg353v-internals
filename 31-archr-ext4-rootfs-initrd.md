# 31 — The ext4 rootfs needs the RG353V's own initramfs (build step)

**Date:** 2026-11-26 · **Branch:** `archr-patcher` · **Status:** fixed in the
build; the image now boots with the injection step.

## The problem the patcher could not see

The patcher replaces **p4** of the dArkOS base with the Arch-R rootfs. Two
details matter and both are invisible in an offline check:

| Partition | Before (dArkOS base) | After (our image) |
|---|---|---|
| p3 | FAT `dArkOS_Fat` — kernel, DTB, **dArkOS's uInitrd**, extlinux.conf | unchanged **except** the initramfs |
| p4 | **btrfs** `rootfs` | **ext4** `ARCHR_ROOT` |

The dArkOS initramfs is built for a btrfs rootfs:

```
$ ls scripts/local-premount/
btrfs          <-- only btrfs; no ext4 module in the initramfs
```

The Arch-R rootfs is ext4. The dArkOS init does `mount ${FSTYPE:+-t "$FSTYPE"}`
with no `rootfstype=` on the kernel cmdline, so it would auto-detect — the
kernel does have ext4 built in, so it *might* work. "Might" is not good enough
for the first boot of a new image.

The RG353V's own live initramfs (`rg353v-backup/live/uInitrd.live.latest`)
does not guess at all:

```sh
mount -t ext4 -o rw /dev/mmcblk1p4 /root     # -> switch_root /root /sbin/init
```

and that exact combination — **5.10.226 kernel + this initramfs + ext4 p4** —
is the one that booted on the device before.

## The fix

`archr-patcher/inject-initrd.sh` writes the live initramfs into p3 of the built
image and creates the `NORMAL` marker the initramfs looks for:

```sh
sudo bash archr-patcher/inject-initrd.sh downloads/archr-rg353v.img
```

It is a build step, not a device step: it runs on the image before the flash.

```
p3 after injection:
-rwxr-xr-x 23921077  uInitrd     <- the live dual-mode initramfs (23 MB)
-rwxr-xr-x        0  NORMAL      <- marker: boot p4 (the real Arch-R rootfs)
```

Without `NORMAL` the same initramfs stays in **live mode** (tmpfs root, Wi-Fi
and sshd on tty1, nothing from the card mounted) — that is the rescue path,
and it is how a failed boot is diagnosed without pulling the card.

## Order of the build steps

```sh
python3 main.py patch --image <arch-r.img> --device rg353v --out archr-rg353v.img --base <darkos.img>
sudo bash inject-initrd.sh archr-rg353v.img      # <-- this step
sudo python3 main.py flash --image archr-rg353v.img --target /dev/sdX
```

## Also fixed: the GPU blob

The profile pointed at a machine that did not have the port's preferred blob,
so the build fell back to dArkOS's `g29p1` build (fbdev-only). The profile now
points at the **g24p0 wayland-gbm** build:

```
libmali.so.1.9.0 -> Bifrost-"g24p0-00eac0"   (EGL_KHR_platform_gbm / wayland)
```

## Result of the 2026-11-26 build on this machine

| Item | Value |
|---|---|
| base | dArkOS RG353v **11072026** (local copy, p3 kernel `Image` = 33,761,288 B — the same kernel the proven card ran) |
| rootfs | Arch-R **v3.1.1** R36S original (20261125), 6,762,266,624 B |
| image | 8,053,063,680 B — exactly the card size |
| sha256 | `4c42e701b47daa0b1f27444ec60b8a5db27dfd685c21d6a72b47bee14b671273` |
| card | 7.5 GiB NCard, **read-back verified bit-for-bit** |

Hardware boot: pending (the card is flashed and verified offline).
