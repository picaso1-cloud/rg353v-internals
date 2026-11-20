# Anbernic RG353V — Internals (GammaOS)

Documentation of the **Anbernic RG353V** handheld running **GammaOS_Lite_v1.5**
(NotGrey's LineageOS-derived Android firmware for Rockchip RK3566 handhelds),
compiled from live hardware probing. Goal: understand how everything is wired,
how to optimize it, how to upgrade its Android version, and how to regenerate
the OS build at any time.

> **Cross-device context:** see `MASTER-PLAN.md` (three-device strategy),
> `SHARED-KNOWLEDGE.md` (reusable findings), `docs/DECISIONS.md`,
> `docs/RE-METHOD.md`. This repo is the RG353V slice of the platform.

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
| [11-arkos-side.md](11-arkos-side.md) | ArkOS side: survey, PS2-on-Linux verdict, optimization notes |
| [12-ps2-linux-investigation.md](12-ps2-linux-investigation.md) | ARMSX2 on ArkOS: full investigation, why it cannot display, ROCKNIX path |
| [13-archr-rk3566-plan.md](13-archr-rk3566-plan.md) | Modern Linux / Arch-R for RK3566: feasibility + revised staged plan |
| [14-rocknix-image-analysis.md](14-rocknix-image-analysis.md) | ROCKNIX Generic image offline teardown: boot chain, glibc/Mesa/kernel, ARMSX2 preinstall, Android/eMMC boot blocker |
| [15-darkos-migration.md](15-darkos-migration.md) | ArkOS → dArkOS migration record, RG353V boot-flow research, ROCKNIX wipe-Android requirement, hybridA–D results |
| [16-gpu-vulkan-panvk-status.md](16-gpu-vulkan-panvk-status.md) | GPU/Vulkan status: vendor blob vs panfrost/panvk, hybrid experiments, Rockchip partition-GUID finding |
| [17-archr-bringup-plan.md](17-archr-bringup-plan.md) | **Current plan** — ground-up Arch bring-up on the proven dArkOS chain: S0–S5, one variable per boot, panel console first |
| [18-archr-upstream-analysis.md](18-archr-upstream-analysis.md) | **Arch-R upstream** (`archr-linux/Arch-R`): what it is, RK3566 device-profile files to add, package gaps, transplant rule |
| [docs/ARCHIVE.md](docs/ARCHIVE.md) | Index of closed tracks/dead ends (ROCKNIX, hybridA–D) with evidence pointers — nothing deleted |
| [19-s1-initramfs.md](19-s1-initramfs.md) | **S1 executed**: patched initramfs (banner + dmesg + `S1-LOG.txt` to boot FAT), artifacts and install/revert scripts in `tools/s1/` |
| [20-emmc-chainload-bridge.md](20-emmc-chainload-bridge.md) | **GarlicOS-style eMMC chain-load** on RK3566: what it buys (independent boot path), what it does not (no ROCKNIX gate bypass), decisive unknowns (fastboot boot, kexec), E0–E4 ladder |
| [21-boot-chain-verified.md](21-boot-chain-verified.md) | **Boot chain verified on hardware** (S1 log + SSH): extlinux read but `root=` forced, dArkOS initramfs hardcodes `/dev/mmcblk1p4`, no kexec, mali kbase built-in |
| [22-s2-arch-rootfs.md](22-s2-arch-rootfs.md) | **S2 built**: Arch-R rootfs + dArkOS 5.10.226 modules/firmware on p4; write/revert scripts in `tools/s2/` |

## Status

- ✅ Full hardware/firmware survey (live probing)
- ✅ Wireless adb fixed and made persistent (Magisk autostart)
- ⏳ Optimization pass (governors/GPU/zram/debloat)
- ⏳ Android upgrade test (GammaOSNext / Android 14)
- ⏳ Regeneration procedure validation (build from upstream sources)
- ✅ ArkOS surveyed; PS2-on-Linux blocked by the display stack (documented)
- ✅ ROCKNIX image analysed offline (correct Generic variant, verified)
- ❌ ROCKNIX on RG353V hardware: **closed 2026-11-20** — 4/4 variants land on Android; the eMMC boot chain gates the TF1 card (see doc 15)
- 🚧 Arch bring-up: **active plan in doc 17**, starts at S1 (custom initramfs banner on the working dArkOS card — no reflash)
