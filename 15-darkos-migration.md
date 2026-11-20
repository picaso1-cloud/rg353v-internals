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

---

## 2026-11-20 — RESEARCH RESOLVES THE MYSTERY: boot flow + the wipe-Android requirement

**Sources:** RK3566 Boot Sequence docs (cnblogs/zxdplay), Pine64 forum
(Rockchip BootROM TRM behavior), **ROCKNIX wiki — RG353 P/M/V/VS device page**.

### The actual RG353V boot flow (RK3566)

1. BootROM → loads **uboot SPL from eMMC FIRST** (fixed order: eMMC, then SD).
   With GammaOS on eMMC, this is **GammaOS's SPL**.
2. The SPL searches for **u-boot: SD first, then eMMC** — it loads a u-boot
   FIT from the SD card **only if the FIT format is one it accepts**.
3. That u-boot searches **extlinux.conf + kernel: SD first**, then eMMC, USB.

### Why ArkOS/dArkOS boot but ROCKNIX doesn't

- ArkOS & dArkOS FITs (`ArkOS-style`, `ATF/OP-TEE/U-Boot/MCU`) are
  **accepted by the GammaOS SPL** (shared BSP lineage) → SD u-boot runs →
  their extlinux on SD → Linux boots.
- ROCKNIX's FIT (`bl31 TF-A` structure) is **not loadable by the GammaOS
  SPL** → no usable SD u-boot → SPL continues the eMMC chain → **Android**.
  Observed on every ROCKNIX attempt (original, hybridA, hybridB).

### The documented requirement (ROCKNIX wiki, RG353 P/M/V page)

> **"P/M/V Users: You will need to wipe the Android partition to boot into
> ROCKNIX."** (via ADB; warning: removes Android from eMMC completely)

ROCKNIX on an RG353 **P/M/V** (2 GB, eMMC models) is **only supported with
Android wiped from eMMC**. Also documented: "eMMC models with legacy
bootloader is not supported"; v1 (0x3052) and v2 (0x3821) panels both
supported once booting.

### Undocumented-but-consistent detail

The RG353V BootROM/eMMC-SPL chain has **no user-facing boot-order setting**
(confirmed by community docs for this device family: a card that "lands on
the vendor interface is either not in the boot slot or is booting with the
wrong device tree"). Changing the primary boot medium = installing the OS to
eMMC (unofficial, brick-risk, unnecessary for card-based setups).

### Decision matrix (RG353V Linux)

| Option | Android on eMMC | Modern kernel/drivers | Effort |
|---|---|---|---|
| **dArkOS v11072026 (current)** | **kept (dual-boot via card)** | Debian Trixie, BSP 5.10 kernel, **Vulkan 1.3 blob** | done ✅ |
| ROCKNIX 20261101 | **must wipe Android (ADB)** | mainline 7.2.11 + panfrost/panvk | needs eMMC wipe + backup first |
| ArkOS 07/31/2025 update | kept | no development anymore | n/a |
| Arch port | depends on design | own kernel choice | scaffold |

---

## 2026-11-20 — hybridD result: ROCKNIX track CLOSED

**Hardware result:** hybridD also boots straight to Android. That is 4/4
ROCKNIX-based images rejected (original, hybridA, hybridB, hybridC, hybridD —
hybridC was superseded before testing, so 4 tested).

### What was matched in hybridD (verified byte-exact, laptop-side)

| Region | dArkOS (boots) | hybridD | Status |
|---|---|---|---|
| p1 `uboot` @ 8 MiB (FIT: ATF×6 + U-Boot) | `4cee0306…` | `4cee0306…` | **identical** |
| p2 `resource` @ 12 MiB (RKNS) | `4004bb43…` | `4004bb43…` | **identical** |
| GPT types/names/disk GUID | Rockchip `A60B…`/`D46E…` | same | identical |
| p3 name + fs label | `dArkOS_Fat` | `dArkOS_Fat` | identical |
| **0–8 MiB (idbloader `RKNS` @ 32 KiB)** | `d1a362f7…` | `c10dcabc…` | **DIFFERS** |

So the last uncontrolled variable is the **idbloader region** (DDR init + SPL,
32 KiB … 8 MiB). Everything from 8 MiB onward was dArkOS's, byte for byte.

### Conclusion (final for this cycle)

- Without serial console we cannot see whether the eMMC SPL, the SD SPL, or
  dArkOS u-boot is the stage that gives up. Each new card variant was a guess
  in the dark, and all of them cost a flash + a device round-trip.
- The documented supported path for ROCKNIX on RG353 **P/M/V** remains "wipe
  the Android partition from the eMMC" (ROCKNIX wiki). That is the only
  *known-good* ROCKNIX configuration, and it destroys GammaOS Android unless an
  eMMC backup is taken first.
- **Decision: stop flashing ROCKNIX variants.** dArkOS v11072026 is the RG353V
  Linux baseline. Further Linux work moves to the ground-up bring-up plan in
  `17-archr-bringup-plan.md`, which changes **one variable per boot** on top of
  the proven dArkOS chain.

### Method lesson (recorded so it is not repeated)

Four variables were changed at once across the hybrid series (loader bytes,
partition numbering, partition type GUIDs/names, kernel+dtb+cmdline). Every
failure was therefore un-attributable. A port must instead hold the working
chain fixed and move one layer at a time, with a visible output at each stage.
