# Anbernic RG353V — Internals (GammaOS)

Documentation of the **Anbernic RG353V** handheld running **GammaOS_Lite_v1.5**
(NotGrey's LineageOS-derived Android firmware for Rockchip RK3566 handhelds),
compiled from live hardware probing. Goal: understand how everything is wired,
how to optimize it, how to upgrade its Android version, and how to regenerate
the OS build at any time.

## Device identity (as probed)

| Item | Value |
|---|---|
| SoC | **Rockchip RK3566** (4× Cortex-A55, 408 MHz – **1.8 GHz**) |
| PMIC | **RK817** (also the audio codec — same PMIC family as RGB10 Max 2) |
| RAM | **2 GB LP4X** (`MemTotal` 2,004,080 kB) |
| Storage | 32 GB eMMC (`/dev/block/mmcblk0`, `mmcblk0boot0/1` hardware partitions) |
| Firmware | **GammaOS_Lite_v1.5** (`ro.lineage.version=GammaOS_v1.5`, LineageOS-derived) |
| Android | **12** (`SP2A.220505.008`), **Pixel 3a (sargo) GSI** as system |
| Kernel | **4.19.232** aarch64, `#176 SMP PREEMPT Jan 8 2023` (GammaOS prebuilt) |
| Root | **Magisk** (`/sbin/su`, `u:r:magisk:s0`) |
| Bootloader | Unlocked (verified boot state = orange) |
| GPU | **Mali-G52** (Bifrost), vendor `mali_kbase.ko`, OpenGL ES 3.2 |
| Panel | 3.5″ **640×480 @60** DSI, **landscape-native** (`rotation 0` — no orientation hacks needed) |
| Wi-Fi | Realtek (SDIO), driver `v5.12.0-8-g39bbb8dd2.20201015_COEX20200730-5151` |
| Battery IC | **cw-bat** (Coslight CW201x fuel gauge) + RK817 charger |
| Network identity | wlan0 `192.168.1.148/24`, adb serial `76d3d33d36bf336` |

## Contents

| File | What's in it |
|---|---|
| [01-hardware.md](01-hardware.md) | Panel, input stack, audio, Wi-Fi/BT, battery/charging, thermal, storage |
| [02-gammaos-internals.md](02-gammaos-internals.md) | Partition map, GSI/vendor split, boot chain, Magisk, dynamic partitions |
| [03-drivers.md](03-drivers.md) | Driver inventory: mali_kbase, rkvdec, singleadc-joypad, RK817, cw-bat, wifi |
| [04-wireless-adb.md](04-wireless-adb.md) | Why wireless adb fails out of the box + the persistent fix |
| [05-optimization.md](05-optimization.md) | Every tuning lever: governors, GPU freq, zram, debloat, thermals |
| [06-android-upgrade.md](06-android-upgrade.md) | Upgrade paths: GammaOSNext (Android 14), GSI strategy, constraints |
| [07-rebuild-firmware.md](07-rebuild-firmware.md) | Regenerating the OS: upstream sources, flash procedures, backup/restore |
| [08-plan.md](08-plan.md) | Roadmap: study → optimize → upgrade → regenerate |
| [09-kernel-dtb.md](09-kernel-dtb.md) | DTB decompiled: joystick/panel/charger/USB/GPU nodes vs the RGB10 Max 2 pain list |
| [10-emulation-and-webasm.md](10-emulation-and-webasm.md) | Emulation limits both devices + browser WASM gaming verdicts |

## Status

- ✅ Full hardware/firmware survey (live probing)
- ✅ Wireless adb fixed and made persistent (Magisk autostart)
- ⏳ Optimization pass (governors/GPU/zram/debloat)
- ⏳ Android upgrade test (GammaOSNext / Android 14)
- ⏳ Regeneration procedure validation (build from upstream sources)
| [11-arkos-side.md](11-arkos-side.md) | ArkOS dual-boot side: survey, PS2 verdict (not possible on Linux), optimization notes |
| [12-ps2-linux-investigation.md](12-ps2-linux-investigation.md) | ARMSX2 on ArkOS: full investigation, why it cannot display, ROCKNIX path |
| [13-archr-rk3566-plan.md](13-archr-rk3566-plan.md) | Arch-R (RK3566) port feasibility: mainline DTS exists, staged plan (ROCKNIX validation → Arch hybrid → upstream port) |
