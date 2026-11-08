# 06 — Android upgrade paths (study result)

Current: Android 12 (Pixel 3a sargo GSI) via GammaOS_Lite_v1.5.1 on the RK3566
vendor BSP, kernel 4.19.232, Magisk root.

## The headline finding

**GammaOSNext (Android 13/14) does NOT support the RG353 series.** The
supported list covers RG DS/DS Plus, RG Vita/Vita Pro, RG477x, RG556/557,
T618 devices (RG405/505), Retroid, AYANEO Pocket, etc. The RG353 line is not
even in the "PLANNED" section. The RK3566 RG353 line stays on the now
**deprecated GammaOS-RK3566 v1.5.1 (Android 12)** repo.

## How GammaOS flashing actually works (the safety model)

Three methods exist, and they make the device effectively brick-resistant:

1. **SD-card flasher (primary + recovery)**: SDDiskTool v1.69 (Windows) writes
   an "Upgrade Firmware" microSD → insert into **TF Slot 1** → boot → the
   device re-flashes its own eMMC. This is ALSO the un-brick path and the
   "back to Stock OS" path (flash Anbernic's stock image the same way).
2. **fastbootd**: upgrade from a working GammaOS install
   (`adb reboot fastboot` → fastboot flasher script) — dynamic partitions
   (system/vendor/odm inside `super`) update without touching the bootloader.
3. **fastboot**: alternate method if SDDiskTool is unavailable.

Notes: remove the TF2 card during install; do NOT use Win32DiskImager/Etcher
on the GammaOS img (it is a Rockchip update package, not a raw image).

## Ranked options for this device

| Option | Verdict |
|---|---|
| **Stay on GammaOS_Lite v1.5.1** (Android 12) | **Recommended today.** Stable, root, optimized, maintained-ish (deprecated = no updates, but also no churn) |
| GSI experiment (Android 13/14 arm64 GSI via fastbootd) | Possible research; the vendor is Android 12 — expect HWC/audio/sepolicy breakage; full backup + SD-flash rollback required |
| GammaOSNext | **Not available for RG353** — not released, not planned. Watch the supported-devices table |
| Stock Anbernic firmware | Possible via SD-flash; loses root/optimizations |

## The safest upgrade procedure (whenever trying anything)

0. **Backup everything (once, now — see 07)**: all partitions via root dd +
   the full userdata tar. Store on the PC AND another drive.
1. Archive the CURRENT working firmware zip (GammaOS_Lite v1.5.1 release for
   RG353V) + SDDiskTool — this is the guaranteed rollback.
2. Prepare the rollback SD card (stock OS image, "Upgrade Firmware" mode) and
   put it aside — with that card, any failed experiment is one boot away from
   recovery.
3. Only then experiment: fastbootd flash of a GSI/GammaOSNext-style package,
   keeping userdata untouched (wipe userdata only if the experiment wins).
4. Test matrix after any flash: boot, display, audio (speaker + jack + HDMI),
   wifi, both sticks + all buttons (incl. L3/R3), charging, sleep/wake,
   GPU renderer string (`dumpsys SurfaceFlinger | grep GLES`).
5. Rollback = the prepared SD card, boot, re-flash GammaOS_Lite, restore
   userdata backup, re-apply Magisk scripts (adb-wifi + janitor + gamemode).

## If GammaOSNext RG353 support ever appears

- Verify the release targets the RG353V specifically (V1 vs V2 displays are
  both handled by GammaOS's 60 Hz fix, but check the release notes).
- Follow the same safety procedure; userdata survives fastbootd upgrades only
  if the release doesn't reformat userdata — assume it does and restore from
  the backup.
