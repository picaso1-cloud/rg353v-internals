# 06 — Android upgrade paths

Current: Android 12 (Pixel 3a sargo GSI) on RK3566 vendor BSP, kernel 4.19.
The vendor BSP (HALs) decides which Android versions are possible — the GSI
side upgrades more freely.

## Path 1 (recommended): GammaOSNext — Android 14

**TheGammaSqueeze/GammaOSNext** + **GammaOSNextDistribution-14** = official
upgrade line: **Android 14, LineageOS 21 based GSI**, same distribution model
(GSI + RK3566 vendor pack), tailored for handheld gaming consoles including
RK3566 devices.

- Same flash procedure as GammaOS (vendor pack + GSI into super, boot, dtbo,
  vbmeta, uboot).
- The RK3566 vendor pack gets updated for 14 — HALs (graphics, audio, sensors,
  wifi) are maintained upstream; the GSI side is replaceable.
- Data migration: treat as a new install; use the backup-restore procedure
  (07) — Magisk must be re-flashed into the new boot image.

## Path 2: newer GSI on the existing vendor (Android 13/14 GSIs)

Because the system is a Treble GSI, **any compatible arm64 A/B GSI can be
tested** against the existing vendor:

1. Backup (07).
2. Fastboot/bootloader: flash GSI to `system` (inside `super` — resize
   dynamic partitions or flash via fastbootd).
3. Boot; expect breakage areas: HWC (display), audio policy, Keymaster,
   sepolicy — the classic GSI pain points.
4. Rollback = reflash the previous GSI (keep it archived).

Requirements/constraints:
- Vendor is Android 12 BSP → Android 13/14 GSIs need vendorsepolicy additions
  (VINTF compat). GammaOSNext solves this by shipping ITS OWN vendor updates —
  prefer Path 1 unless experimenting.
- Screen 640×480 landscape-native works in any GSI (no rotation hacks needed).

## Path 3: andr36oid-style LineageOS port (research, not near-term)

The RGB10 Max 2 project ran andr36oid (LineageOS 18.1) built from a
device-specific kernel+vendor. A true LineageOS port for RK3566 = GammaOS's
kernel/vendor reused with LineageOS build system — GammaOSNext already IS
LineageOS 21-based, which fulfills this goal; a separate port would duplicate
TheGammaSqueeze's work. Contribute upstream instead (device tree fixes,
feature patches) — that IS the port.

## Kernel upgrade notes

- Kernel 4.19.232 is GammaOS's prebuilt. Newer Android needs newer kernel for
  some HALs (e.g. wifi interfaces) — GammaOSNext ships a matching kernel.
- GPU: `mali_kbase.ko` vendor module must match the kernel build exactly.

## What to check before any upgrade

1. Full backup of the current state (07) — including Magisk-patched boot.
2. The exact target's flashing method (RKDevTool / rkdeveloptool loader mode).
3. After upgrade: wireless adb fix (04) needs re-applying if Magisk scripts
   are wiped (re-run after re-flashing Magisk).
