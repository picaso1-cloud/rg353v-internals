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

---

## 2026-11-21 — 7.2.11 boots; panel white; logging upgraded

Timeline evidence from the card:

- `BOOT-TRACE.txt` at 20:42 → tracer ran **with the new kernel**, mounted p4,
  `switch_root` reached.
- `/s2-BOOTLOG.txt` at 20:46 (uptime 258 s) → `wlan0 … 192.168.0.198`, i.e. the
  system reached multi-user **and** network on 7.2.11.
- Panel: white with a black left edge → the DTB panel node was still wrong after
  the `elidA,kd35t133` switch (see below).

### Logging, upgraded (what "log the boot" can actually mean here)

| Stage | Captured by | Survives cold boot? |
|---|---|---|
| BootROM / SPL / u-boot | **only UART** (`earlycon` already passes `uart8250,mmio32,0xfe660000`) | needs a USB-TTL |
| kernel early (incl. panel/DRM probes) | `/s2-EARLY.txt` + `/boot/S2-EARLY.txt` — **full dmesg written at first userspace start** | yes |
| initramfs stage | `/BOOT-TRACE.txt` (tracer) | yes |
| systemd onwards | `/s2-BOOTLOG.txt` every 10 s, journal filtered of `archr-levels` spam | yes |

The previous log was useless for the panel because the journal window was 200
lines and `archr-levels` writes a `chmod` error every 1.6 s. The new early
capture dumps the **whole dmesg** once, plus DRM/backlight/panel-grep output.

### Panel: next test

ROCKNIX's DTB says `anbernic,rg353p-panel","newvision,nv3051d`; our unit is the
v2 panel that dArkOS drives as `elida,kd35t133`. ROCKNIX normally patches this
in **its own u-boot** from panel-ID detection — which we bypass by using
dArkOS's loader. The one-line compatible swap did not produce a picture, so the
next step is to check the early dmesg for the actual probe result (bound vs
failed to find panel) before patching timings or adding an overlay.
