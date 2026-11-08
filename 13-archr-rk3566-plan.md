# 13 — Arch-R for the RG353V (RK3566): feasibility & plan

Question: build an **Arch-R style ROM** for the RG353V so the modern stack
(pacman, latest glibc/Mesa) makes everything smoother — including ARMSX2.

> **Update 2026-11-08 (see `14-rocknix-image-analysis.md`):** the ROCKNIX RK3566
> **Generic** image already *is* the modern stack (glibc 2.44, Mesa 26.2.4,
> panfrost/panvk, kernel 7.2.11, sway) and ships **ARMSX2 preinstalled**. A new
> Arch-R port is therefore **not required** for the performance goal; it would
> only buy `pacman`/rolling packaging. The real blocker is the Android/eMMC boot
> conflict, not missing board support.

## Why not just flash Arch-R

**Arch-R targets RK3326** (R36S/RG351/RGB10 family). The RG353V is **RK3566**.
The distro itself is not the hard part — **board support** is: kernel, u-boot,
DDR init, device tree, panel, input. Arch-R has no RK3566 board definitions.

## Why it is feasible anyway

| Piece | Status |
|---|---|
| **Mainline device tree** | ✅ upstream: `rk3566-anbernic-rg353v.dts` (+ rg353p/ps/vs/x shared dtsi) in torvalds/linux |
| **Mainline panel drivers** | ✅ `newvision/nv3051d` (v1, ID 0x3052) + `elida,kd35t133` (v2, ID 0x3821); ROCKNIX's 7.2.11 kernel handles both, u-boot auto-detects the panel ID |
| **Mainline GPU** | ✅ panfrost (GL 3.3+) / panvk Vulkan (G52) — ROCKNIX ships Mesa 26.2.4 |
| **RK3566 u-boot + DDR blobs** | ✅ ROCKNIX builds this (`ROCKNIX-RK3566` images); same LibreELEC→JELOS→ROCKNIX build-system lineage as Arch-R |
| **Kernel config for RK3566** | ✅ ROCKNIX 7.2.11 is the reference (embedded initramfs, modules in `/usr/lib/kernel-overlays`) |
| **Arch userland** | ⚠️ ROCKNIX already provides glibc 2.44 / Mesa 26.2.4 / sway; a pure Arch rootfs adds only pacman |

So an RK3566 Arch port = **Arch-R's build system + `projects/ArchR/devices/RK3566/`**
(board config: u-boot, kernel config, DTS selection, panel overlay), using
ROCKNIX's RK3566 boot chain as the reference implementation. **But it is now
optional**, not the recommended route to performance.

## Staged plan (de-risk first, then port)

### Stage 0 — validate the modern stack (hardware step, blocked on decision)
1. Flash the **Generic** image — `ROCKNIX-RK3566.aarch64-20261101-Generic.img.gz`
   — to a **spare SD** (TF1). RG353V is listed under *Generic*; the `Specific`
   image is only for Powkiddy X55/X35S and RG DS. **Do not** use `Specific`.
   Hashing and flashing recipe: `14-rocknix-image-analysis.md` §6.
2. **Boot prerequisite:** with Android on the eMMC, ROCKNIX does **not** boot
   from SD. Options: (A) try a legacy chainload (SD-only, keeps Android),
   (B) wipe the eMMC (destructive, documented), or (C) stay on GammaOS/ArkOS.
   Details: `14-rocknix-image-analysis.md` §4.
3. After boot, verify: panel + touch, audio, Wi-Fi, buttons/sticks, GL
   (`Mesa 26.2.4`, `wayland-info | grep xdg_wm_base`), glibc 2.44.
4. Run **ARMSX2 from EmulationStation** against the PS2 ISOs already on the
   ArkOS SD (`/roms2/ps2`, BIOS `SCPH30004R.bin`). No AppImage/libc hacks.

### Stage 1 — capture the RK3566 boot chain  ✅ mostly done offline
From the Generic image (verified):
- idbloader (`RKNS`) @ 32 KiB, SPL DT @ 0x36EC0 (SD-first boot order), U-Boot
  2026.01 @ 8 MiB, FAT @ 16 MiB (`extlinux` with `FDTDIR`), KERNEL 7.2.11,
  SYSTEM squashfs, STORAGE ext4.
- U-Boot Anbernic board code: SARADC model table (RG353V = 695), panel ID
  detection (0x3052 v1 / 0x3821 v2).
Still to capture on hardware: ArkOS `/boot` legacy files + eMMC bootloader
(read-only) to evaluate option A.

### Stage 2 — Arch userland on the proven boot chain (optional)
Only if pacman/Arch packaging is actually wanted. ROCKNIX's stack already
satisfies the "modern, smooth" goal; this stage has low marginal value.

### Stage 3 — the real Arch-R port (optional/upstreamable)
Fork archr-linux/Arch-R, add `projects/ArchR/devices/RK3566/`:
- bootloader package (rk3566 u-boot + rkbin DDR/TPL)
- kernel config derived from ROCKNIX's RK3566 config (mainline kernel)
- DTS: `rk3566-anbernic-rg353v.dts` + panel variant handling
- device scripts (SARADC board detection, boot config)
Validate against Stage 0/2 results, then propose upstream to archr-linux.
**Do this only for pacman/rolling-release value, not for speed.**

## Risks & mitigations

- **Android/eMMC boot conflict**: ROCKNIX needs either the eMMC wiped or a
  legacy chainload. Do not assume dual-boot parity with ArkOS.
- **Panel/backlight quirks**: mainline DTS + u-boot panel detection + kernel
  support all present. This unit is **v2** (ID 0x3821). GammaOS DTB
  (`survey/boot.dts`) is the cross-reference (two panel nodes: 0x3052 and 0x3821).
- **DDR/u-boot brick risk**: none for SD-only experiments; the eMMC is only at
  risk if option B (wipe) is chosen.
- **Card quality**: same A2 advice as the RGB10 Max 2 guide.
- **Time**: Stage 0 ~1 hour after the boot decision; Stage 1 done offline;
  Stage 2 a day; Stage 3 multi-day and optional.

## Current assets

- `dist/ROCKNIX-RK3566-Generic.img.gz` (+ raw `.img`, SHA-256 verified
  `b573c965…c775`, raw MD5 `6419f308…d58e8`).
- Offline analysis + extracted SPL DT: `14-rocknix-image-analysis.md`,
  `survey/rocknix/`.
- GammaOS DTB decompile + driver analysis: `survey/boot.dts`, `09-kernel-dtb.md`.
- ArkOS survey + PS2 assets list: `11-arkos-side.md`, `12-ps2-linux-investigation.md`.
- RG353V hardware map: `01-hardware.md`, `03-drivers.md`.

## Next action

**None for now (decision 2026-11-08: documentation-only, nothing to flash).**
When/if this is picked up again: decide the boot path (A/B/C in
`14-rocknix-image-analysis.md` §4). If A: boot ArkOS online and capture `/boot`
+ the eMMC bootloader read-only. Then flash the Generic image and run Stage-0
measurements.
