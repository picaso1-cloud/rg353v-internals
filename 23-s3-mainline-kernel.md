# 23 — S3: mainline kernel (ROCKNIX 7.2.11) on the S2 rootfs

**Date:** 2026-11-21 · **Status:** payload staged, card write pending

## Why this exact kernel

- It is the **only kernel proven to run on this RG353V board family**: mainline
  7.2.11, `panfrost` + `rtw88_8821cs` for our exact Wi-Fi chip, RK3566 DTB.
- It removes the S2 ABI problem: Arch-R's userland is built for **Linux 6.10+**
  (busybox is `for GNU/Linux 6.10.0`), and 5.10 makes `chmod` return `ENOSYS`.
  7.2.11 is newer than the ABI the userland expects.
- `ext4` is **built into** this kernel (no `ext4.ko` in its module set), so our
  tracer initramfs can still mount p4 before any module is loaded.

## What is staged

`~/Andr36oid/rg353v-backup/rocknix-kernel/` (extracted from the official image):

| File | Size |
|---|---|
| `KERNEL` | 30 MB (arm64 Image, `Linux version 7.2.11`) |
| `rk3566-anbernic-rg353v.dtb` | 122 KB |
| `7.2.11/` | 17 MB, 288 modules incl. `panfrost.ko`, `rtw88_8821cs.ko`, `modules.dep` |
| `firmware/` | 43 MB (incl. `rtw88/rtw8821c_fw.bin`) |

## Swap

```bash
sudo tools/s3/install-kernel.sh --device /dev/mmcblk0
# revert: sudo tools/s3/install-kernel.sh --device /dev/mmcblk0 --revert
```

- p4: modules `7.2.11` + firmware, `modules-load.d/rtw88.conf`
- p3: `/Image` ← ROCKNIX `KERNEL`, `/rk3566-353v.dtb` ← ROCKNIX DTB
- backups kept once: `/Image.darkos-5.10`, `/rk3566-353v.dtb.darkos`
- the loader, `extlinux.conf`, `/uInitrd` (tracer) are **unchanged**

## What must keep working

| Layer | Expectation |
|---|---|
| u-boot | loads `/Image` (booti) — same as any Image |
| tracer initramfs | mounts p4 (ext4 built-in), applies `/sbin/init` wrapper, `switch_root` |
| systemd | ArchR on 7.2.11 → no more `chmod ENOSYS` |
| Wi-Fi | `rtw88_8821cs` + `rtw8821c_fw.bin` → same SSID/IP path as S2 |
| display | mainline `rockchip-drm` + panel driver from the ROCKNIX DTB |

## Failure modes

- **No Wi-Fi** → dashboard also absent; pull card, read `/BOOT-TRACE.txt`
  (tracer) and `/s2-BOOTLOG.txt` (if systemd got that far).
- **Panic at mount** → ext4 is built-in, so this would point at the DTB or the
  tracer; revert is one flag.
