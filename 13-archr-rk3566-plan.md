# 13 — Arch-R for the RG353V (RK3566): feasibility & plan

Question: build an **Arch-R style ROM** for the RG353V so the modern stack
(pacman, latest glibc/Mesa) makes everything smoother — including ARMSX2.

## Why not just flash Arch-R

**Arch-R targets RK3326** (R36S/RG351/RGB10 family). The RG353V is **RK3566**.
The distro itself is not the hard part — **board support** is: kernel, u-boot,
DDR init, device tree, panel, input. Arch-R has no RK3566 board definitions.

## Why it is feasible anyway

| Piece | Status |
|---|---|
| **Mainline device tree** | ✅ upstream: `rk3566-anbernic-rg353v.dts` (+ rg353p/ps/vs/x shared dtsi) in torvalds/linux |
| **Mainline panel driver** | ✅ `panel-elida-kd35t133.c` (the RG353V's panel, seen in GammaOS's DTB) |
| **Mainline GPU** | ✅ panfrost (GL 3.3+) / panvk Vulkan (G52) in modern Mesa |
| **RK3566 u-boot + DDR blobs** | ✅ ROCKNIX builds this (`ROCKNIX-RK3566` images); same LibreELEC→JELOS→ROCKNIX build-system lineage as Arch-R |
| **Kernel config for RK3566** | ✅ ROCKNIX's config is the reference |
| **Arch userland** | ✅ Arch Linux ARM (alarm) generic aarch64 tarball |

So an RK3566 Arch port = **Arch-R's build system + `projects/ArchR/devices/RK3566/`
(board config: u-boot, kernel config, DTS selection, panel overlay)**, using
ROCKNIX's RK3566 boot chain as the reference implementation.

## Staged plan (de-risk first, then port)

### Stage 0 — validate the modern stack (immediate)
1. Flash `ROCKNIX-RK3566...Specific.img.gz` to a **spare SD** (TF1).
   The Android/GammaOS eMMC stays untouched (dual-boot preserved).
2. Boot ROCKNIX; verify: panel + touch, audio, Wi-Fi, buttons/sticks,
   GL renderer (`Mesa` version, `wayland-info | grep xdg_wm_base`), glibc ≥ 2.38.
3. Run the ARMSX2 AppImage directly (no libc hacks needed if glibc is new
   enough) → test the PS2 ISOs already on the other SD/ROM partition.
   This answers "will everything be smoother?" with measurements before any
   porting work.

### Stage 1 — capture the RK3566 boot chain
From the ROCKNIX image: u-boot + DDR blobs, kernel image/config, DTBs,
firmware blobs, partition layout, boot scripts. Document each piece
(offsets, filenames, cmdline).

### Stage 2 — Arch userland on the proven boot chain (hybrid)
SD image = ROCKNIX boot partition (kernel/uboot/dtb) + **Arch Linux ARM
rootfs** (systemd, pacman, mesa panfrost/panvk, pipewire/alsa, EmulationStation
or GMenu2X). Kernel modules copied from ROCKNIX into the Arch rootfs's
`/lib/modules`. This gives the Arch experience with zero kernel work.

### Stage 3 — the real Arch-R port (upstreamable)
Fork archr-linux/Arch-R, add `projects/ArchR/devices/RK3566/`:
- bootloader package (rk3566 u-boot + rkbin DDR/TPL)
- kernel config derived from ROCKNIX's RK3566 config (mainline kernel)
- DTS: `rk3566-anbernic-rg353v.dts` + panel overlay generation
- device scripts (board detection, boot config)
Validate against Stage 0/2 results, then propose upstream to archr-linux.

## Risks & mitigations

- **Panel/backlight quirks**: mainline DTS + panel driver already upstream;
  GammaOS's DTB (decompiled in `survey/boot.dts`) is the cross-reference
  (panel `elida,kd35t133`, DSI-1, 640×480@60).
- **DDR/u-boot brick risk**: none — the eMMC Android side is untouched when
  booting Linux from SD; the SD can be reflashed at will.
- **Card quality**: same A2 advice as the RGB10 Max 2 guide.
- **Time**: Stage 0 is ~1 hour; Stage 2 a day; Stage 3 is a multi-day project
  suitable for upstream collaboration.

## Current assets

- `dist/ROCKNIX-RK3566-Specific.img.gz` (1.36 GB, downloaded 2026-11-08).
- GammaOS DTB decompile + driver analysis: `survey/boot.dts`, `09-kernel-dtb.md`.
- ArkOS survey + PS2 assets list: `11-arkos-side.md`, `12-ps2-linux-investigation.md`.
- RG353V hardware map: `01-hardware.md`, `03-drivers.md`.

## Next action

Get a spare microSD → flash ROCKNIX → Stage 0 measurements. Then decide
hybrid (Stage 2) vs full Arch-R port (Stage 3).
