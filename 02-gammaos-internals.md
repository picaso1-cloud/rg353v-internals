# 02 — GammaOS internals (firmware structure)

GammaOS is **not** a from-scratch Android build: it is an Android **GSI**
(Generic System Image) + a Rockchip **vendor BSP** + GammaOS glue, assembled
into Rockchip-standard partitions. Understanding this split is the key to
upgrading and regenerating it.

## The split

| Layer | What | Provenance |
|---|---|---|
| **system** (in `super`, dm-0) | Pixel 3a **sargo GSI**, Android 12 `SP2A.220505.008` | Google/AOSP-derived GSI (Treble) |
| **vendor + odm** (dm-2/dm-4) | **RK3566 BSP**: HALs, GPU blob userspace (`mali_kbase.ko` kernel module loaded by init), wifi firmware, audio, sensors | Rockchip Android SDK / GammaOS device pack |
| **boot** (p7) | kernel 4.19.232 + ramdisk | GammaOS kernel prebuilt |
| **dtbo** (p5) | per-board overlays (panel, sticks) | GammaOS device pack |
| **Magisk** | root, systemless mirrors under `/sbin/.magisk/` | patched boot image at flash time |

This is why `ro.product.*` says **sargo/Pixel 3a**: the GSI's identity wins for
system-level props, while the vendor side carries RK3566 HALs. Treble makes
this combination legal; GammaOS's work is making the vendor side complete and
gaming-optimized (joypad driver, launcher hooks, GPU tuning).

## Partition map (GPT, eMMC 32 GB)

| Partition | Block | Role |
|---|---|---|
| security | p1 | factory/security data |
| uboot | p2 | u-boot (also `mmcblk0boot0/1` hardware partitions exist) |
| trust | p3 | ARM Trusted Firmware / BL31 |
| misc | p4 | bootloader messages / BCB |
| dtbo | p5 | device-tree overlays (board variants, panel) |
| vbmeta | p6 | verified-boot metadata (device is UNLOCKED: `verifiedbootstate=orange`) |
| boot | p7 | kernel + ramdisk |
| recovery | p8 | recovery |
| backup | p9 | Rockchip backup images |
| cache | p10 | cache |
| metadata | p11 | encryption metadata |
| baseparameter | p12 | Rockchip `baseparameter` image (screen config) |
| **super** | p13 | **dynamic partitions**: system (2.8G used) + vendor + odm |
| userdata | p14 | `/data` 22 GB |

Boot chain: **BootROM → `mmcblk0boot0`/`uboot` (u-boot) → `boot` (kernel 4.19.232)**
with `dtbo` applied per board, `vbmeta` in orange (unlocked) state. Kernel
cmdline (from `uboot`): `storagemedia=emmc`, `androidboot.dtbo_idx=0`,
`androidboot.verifiedbootstate=orange`, `console=ttyFIQ0`, plus the sargo GSI
boot props.

## Root & startup customization

- **Magisk** (shipped by GammaOS) — root via `su`, systemless modifications.
- Autostart hook: **`/data/adb/service.d/*.sh`** (Magisk late-start scripts run
  as root at boot) — the right place for: wireless-adb enabler, tailscaled,
  governor tuning, cleanup jobs.
- SELinux: permissive-capable (device runs unlocked; Magisk handles rules).

## Where the upstream pieces live

- **TheGammaSqueeze/GammaOS-RK3566** — the RK3566 firmware line (this device).
- **TheGammaSqueeze/GammaOSNext** + **GammaOSNextDistribution-14** — the newer
  **Android 14 / LineageOS 21** GSI distribution (upgrade path).
- **TheGammaSqueeze/GammaOSCore(Distribution)** — Android TV 13 based variant.
- The firmware zip = GSI image + vendor image + boot/dtbo/uboot/vbmeta + flasher
  (RKDevTool / rkdeveloptool loader) — regenerate = reassemble those.

## Why the input stack is special

GammaOS replaces the stock Rockchip joypad handling with
`retrogame_joypad` on a `singleadc-joypad` platform device (single ADC +
mux, like the RG351/RGB10 family design), plus `touch_joypad` — a
joypad→touch **emulator** input device that lets touch-only apps be driven
from the pad. Both are GammaOS-specific glue worth keeping across upgrades.
