# 27 — dArkOS RG353V kernel + boot chain study

**Date:** 2026-11-26 · **Source:** dArkOS v11172026 (`dArkOS_RG353v_trixie_11192026.img`,
SHA-verified download from `christianhaitian/dArkOS` release v11172026).

This is the working Linux baseline for the RG353V. The Arch-R port
(`tools/archr-port/`) runs on this kernel. The patcher tool
(`archr-patcher/`) uses this image as its base and replaces only the rootfs
(p4).

## Kernel

- **Version:** `5.10.226` (dArkOS BSP kernel, built with Linaro GCC 6.3-2017.05)
  ```
  Linux version 5.10.226 (dev@devbox) (aarch64-linux-gnu-gcc (Linaro GCC 6.3-2017.05) 6.3.1 20170404, GNU ld (Linaro_Binutils-2017.05) 2.27.0.20161019) #1 SMP Thu Nov 19 01:25:04 EST 2026
  ```
- **SoC:** RK3566 (Mali-G52).
- **GPU driver:** vendor libmali (kbase). The Arch-R port installs the Mali-G52
  blob (`g29p1-12eac0`) as `libmali.so.1.9.0` (see `tools/archr-port/README.md`).
  **No panfrost / no panvk** on this kernel — Vulkan is vendor-only.
- **ABI note:** glibc 2.40 (Arch-R rootfs) needs the `fchmodat2_compat.so` shim
  because the 5.10 kernel lacks the `fchmodat2` syscall (Linux 6.6+). The shim is
  in `tools/archr-port/fchmodat2_compat.so`, loaded via `/etc/ld.so.preload`.

## Device tree

- **File:** `rk3566-353v.dtb` (173,234 bytes).
- **Model:** `Anbernic RG353V/VS`
- **Compatible:** `anbernic,rg353v`, `rockchip,rk3566`
- **Panel:** `elida,kd35t133` v2 (panel id `0x3821`), PWM backlight 0-255.
- **Also present:** `rk3566-353v-notimingchange.dtb` (variant).
- **Overlays:** `overlays/undervolt.{light,medium,maximum}.dtbo` (GPU/CPU undervolt).

## Boot chain

The RG353V eMMC bootloader gates SD boot: only the dArkOS boot chain is accepted
(ROCKNIX's chain is rejected — see `15-darkos-migration.md`). The boot chain is
the first 16 MiB of the image (unpartitioned region + p1 + p2):

| Region | Offset | Size | Contents |
|---|---|---|---|
| unpartitioned | 0 | 8 MiB | idbloader + SPL + ATF + OP-TEE + U-Boot (Rockchip boot chain) |
| p1 | 8 MiB | 4 MiB | `FIT Image with ATF/OP-TEE/U-Boot/MCU` (main bootloader) |
| p2 | 12 MiB | 4 MiB | MCU firmware + battery bitmaps + `rk-kernel.dtb` + DDR params |

The dArkOS chain is "RG353V-tuned DDR init" (vs ROCKNIX's generic RK3566 chain).
**The patcher must preserve this entire 16 MiB region from the dArkOS image.**

## Boot partition (p3, FAT, 99 MiB)

| File | Size | Purpose |
|---|---|---|
| `Image` | 33,761,288 | kernel (5.10.226) |
| `rk3566-353v.dtb` | 173,234 | device tree |
| `rk3566-353v-notimingchange.dtb` | 173,218 | DTB variant |
| `uInitrd` | 11,854,685 | initramfs (dual-mode) |
| `extlinux/extlinux.conf` | 275 | boot config |
| `overlays/undervolt.{light,medium,maximum}.dtbo` | 604 each | undervolt overlays |
| `expandtoexfat.sh` | 5,573 | first-boot partition expansion |
| `firstboot.sh` | 53 | runs expandtoexfat.sh |
| `fstab.exfat` | 276 | initramfs fstab |

### extlinux.conf

```
LABEL ArkOS
  LINUX /Image
  FDT /rk3566-353v.dtb
  APPEND root=/dev/mmcblk1p4 initrd=/uInitrd rootwait rw fsck.repair=yes quiet splash vt.global_cursor_default=0 net.ifnames=0 console=tty1 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60
```

The root is `/dev/mmcblk1p4` (the rootfs partition). The kernel auto-detects the
filesystem type, so the rootfs can be ext4 (Arch-R) even though the dArkOS
default is btrfs.

## Partition layout

| Partition | Start | End | Sectors | Size | Type |
|---|---|---|---|---|---|
| p1 | 16384 | 24575 | 8192 | 4M | bootloader |
| p2 | 24576 | 32767 | 8192 | 4M | bootloader |
| p3 | 32768 | 235519 | 202752 | 99M | FAT (boot) |
| p4 | 237568 | 15445614 | 15208047 | 7.3G | rootfs (btrfs) |
| p5 | 15446016 | 15608046 | 162031 | 79.1M | exfat (easyroms) |

Disk: 7.5 GiB (8,053,063,680 bytes), GPT.

## Key differences from the TurboRelic mainline kernel (see `28-turborelic-bsp-study.md`)

| Aspect | dArkOS (5.10.226) | TurboRelic (6.15.11) |
|---|---|---|
| Kernel | Android BSP 5.10.226 | mainline 6.15.11 |
| GPU driver | vendor libmali (kbase) | panfrost (mesa-megadriver) |
| Vulkan | vendor only (no panvk) | panvk (experimental) |
| Boot chain | dArkOS FIT (accepted by eMMC bootloader) | mainline u-boot 2025.01 (needs dArkOS idbloader) |
| DTB | `rk3566-353v.dtb` (dArkOS) | `rk3566-anbernic-rg353v.dtb` (mainline) |
| Wi-Fi | rtl8821cs (kernel) | rtw88 (kernel, with mdelay patch) |
| Gamepad | singleadc-joypad | singleadc-joypad + gamepad-merge daemon |
| Status on RG353V | **boots** (proven) | **boots** (proven, Yocto distro) |

## Patching implications for the patcher tool

- The patcher uses the **dArkOS image as the base** (boot chain + p3 are correct).
- It replaces **only p4** (rootfs) with the ported Arch-R rootfs.
- The ported Arch-R rootfs is ext4; the dArkOS initramfs + kernel can mount it
  (proven by the existing working port).
- The 16 MiB boot-chain region must be preserved byte-for-byte from dArkOS.
