# 15 — ArkOS → dArkOS migration (RG353V TF1 card, 2026-11-20)

**Outcome: dArkOS v11072026 boots ✅ — RG353V Linux baseline is now dArkOS.**
ROCKNIX 20261101 was flashed first with a verified-correct procedure and
**failed to boot on this unit**; dArkOS's own boot chain works.

## Why we migrated

- ArkOS archived 2025-12-30; final image 02/09/2025, final OTA 07/31/2025.
- **dArkOS is the official successor** (same author, christianhaitian):
  **Debian 13 Trixie** base (ArkOS was Ubuntu 19.10), btrfs rootfs, active
  releases. Latest at migration time: **v11072026** (published 2026-11-14).

## The migration journey (evidence-driven)

1. **ArkOS card diagnosis:** card healthy (fsck clean, UUIDs match, boot files
   valid); 31 boots logged; ES ran 4 h on 2026-11-13, then unclean power-off
   corrupted `imagecache.db` → quarantined it (fix attempt 1 — did not clear
   the symptom; symptom reclassified as "device skips SD → eMMC Android").
2. **STORAGE expansion fix:** dArkOS/ROCKNIX first-boot expansion had never
   completed; expanded manually (56.2 GiB) — did not clear the symptom either.
3. **ROCKNIX 20261101 test:** flashed byte-verified (readback = image SHA)
   → device still skipped the SD card. Flash procedure proven correct;
   failure is in the OS build (see `16-gpu-vulkan-panvk-status.md` for the
   boot-chain comparison).
4. **dArkOS v11072026 flashed by user → BOOTS ✅.**

## Boot-chain root cause (raw-byte comparison, laptop)

| Region (sectors) | dArkOS vs ROCKNIX |
|---|---|
| 64–8191 (idbloader: RKNS hdr + DDR blob + SPL) | ❌ different |
| 8192–16383 + 16384–32767 (u-boot FIT regions) | ❌ different |
| IDB header @ sector 64 | identical except one byte: 0x0073 = `6c` (dArkOS DDR blob = 108 sectors) vs `74` (ROCKNIX = 116 sectors) |
| u-boot FIT content @ 8 MiB | dArkOS: `FIT Image with ATF/OP-TEE/U-Boot/MCU` — ROCKNIX: `FIT image for U-Boot with bl31 (TF-A)` |

This unit **accepts dArkOS's loader (DDR init + full trusted chain) and
rejects ROCKNIX's generic chain** → BootROM falls through to eMMC Android.
The ROCKNIX flash procedure itself was NOT the problem (byte-for-byte vs the
official image). **Fix candidate if ROCKNIX is ever wanted:** splice dArkOS's
loader region (sectors 64→32768) onto a ROCKNIX card keeping ROCKNIX
partitions — two splice hybrids already built (see `rg353v-backup/images/`).

## dArkOS internals (from the 11072026 RG353v image)

- Partition layout: `uboot` 4 M raw (sector 16384) · `resource` 4 M raw ·
  `dArkOS_Fat` 99 M fat32 (Image, uInitrd, `rk3566-353v.dtb`,
  `rk3566-353v-notimingchange.dtb`, extlinux, expandtoexfat.sh) ·
  `rootfs` **btrfs** 7.4 G (label ROOTFS, zstd:1) · p5 fat16 79 M
  (expands → exfat for /roms on first boot).
- Kernel **5.10.226** (Rockchip BSP line — vendor `CONFIG_MALI_BIFROST=y`
  built-in; no panfrost/panthor).
- RG353V-specific DTBs including the **notimingchange** panel variant —
  likely why display works on this v2-panel unit.
- Vulkan: `/usr/share/vulkan/icd.d/rk_vk.json` →
  `libmali-bifrost-g52-g29p1.so`, **api_version 1.3.276**, 440 exported
  `vk*` symbols → **Vulkan 1.3 on the G52 via the vendor blob** (see
  `16-gpu-vulkan-panvk-status.md`).
- First boot expands p5 → exfat `/roms` (bios/saves/roms go there —
  ArkOS-style layout).

## Card notes (58.2 G "SD16G" TF1 card)

- **Fails writes beyond ~24 GB** (kernel-logged I/O error @ sector 50,376,960,
  card dropped off bus during our expansion test). It wedged once (that's why
  boots skipped the SD) — a clean re-flash recovered it.
- ROCKNIX was first attempted here with STORAGE capped at 20 GiB + a dead-zone
  wall partition; still no boot (loader-level rejection, not storage).
- dArkOS footprint (7.4 G rootfs + ~1 G data) **fits the healthy zone** with
  headroom; ROMs live on TF2.
- Do not grow the data partition past ~20 GB on this card.

## Status / next steps

- ✅ dArkOS v11072026 boots on the TF1 card (in device, running).
- BIOS set (11 M) + saves staged for push: `rg353v-backup/payload-bios-saves/`.
- Enable SSH/Samba on dArkOS → push bios to `/roms/bios`, wire TF2 roms.
- Follow-up: report ROCKNIX 20261101 RG353V boot failure upstream
  (github.com/ROCKNIX/distribution) with this boot-chain comparison.
