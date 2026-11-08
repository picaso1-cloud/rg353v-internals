# 12 — PS2 on the Linux side: ARMSX2 investigation (full record)

Goal: run **ARMSX2** (the AetherSX2-derived PS2 emulator for ARM64, Linux
ARM64 AppImages published) on the RG353V's **ArkOS** Linux side, to complement
the Android/GammaOS AetherSX2 setup.

**Outcome: ARMSX2's binary and Qt stack fully start on ArkOS, but ArkOS's
graphics stack cannot host a Qt6 window.** The investigation below maps every
layer precisely so the conclusion is reproducible.

## What was proven to work (all live-tested)

1. **ARMSX2 extracts and runs** (Linux-arm64-4K-pages AppImage v2.9.2):
   `./AppImage --appimage-extract` → `squashfs-root/usr/bin/armsx2-qt`.
2. **glibc requirement 2.38+ / GLIBCXX 3.4.32 solved**: ArkOS has glibc 2.30.
   Bundling Ubuntu 24.04's `ld-linux-aarch64.so.2` + libc 2.39 + libstdc++ 14
   and launching through the bundled loader works:
   ```
   ld-linux-aarch64.so.1 --library-path <bundle>:<appimage-libs>:/lib/... \
       ./usr/bin/armsx2-qt
   ```
   (Never export LD_LIBRARY_PATH — it poisons system binaries.)
3. **FreeType 2.10+ solved**: `FT_Get_Paint` → bundle libfreetype 2.13.3.
4. **libwayland ≥ 1.20 solved**: `wl_proxy_marshal_flags` → bundle 1.22.
5. **Qt wayland plugin loads** against weston 5 (`zxdg_shell_v6` only) — but
   Qt6 requires stable `xdg_wm_base` → no window. This is the wall.
6. **weston 5.0 (preinstalled) runs on the DSI panel** (DRM backend, correct
   output, GL renderer fine).

## The display dead-ends (each tested)

| Path | Result |
|---|---|
| weston 5 + Qt wayland | No window: weston 5 exposes only `zxdg_shell_v6`, Qt6 needs `xdg_wm_base` |
| weston 5 + `--xwayland` + Qt xcb | Xwayland spawns, glamor falls back to SW (no `wl_drm`), then weston dies on a legacy VT signal (SIGUSR1) |
| sway 1.2 (installed from 19.10 repos) | Cannot get a VT/session from SSH; openvt VT allocation fights (VT-in-use / dealloc errors) |
| Xorg + fbdev driver | `FBDEV(0): mmap fbmem: Invalid argument` — **the ArkOS kernel's fb0 is unmappable** (also why weston's fbdev backend failed), with EmulationStation fully stopped and service inactive |
| Xorg + modesetting (DRM) | Not viable: requires glamor/GL; no Mali X11 GL in this stack |

## Root cause summary

ArkOS on this device is a **console-only OS** (EmulationStation on the fb with
no display server, old kernel 4.19.172, weston 5, no GL/Vulkan for desktop
apps). A modern Qt6 application needs either:
- a compositor with `xdg_wm_base` (weston ≥ 7 / wlroots-based sway/labwc), or
- a working X server with a mappable framebuffer (fbdev mmap broken, no Xorg
  GPU driver).

Neither exists on ArkOS. Every piece of ARMSX2 itself proved obtainable.

## The correct path: ROCKNIX

**ROCKNIX** (github.com/ROCKNIX/distribution) supports the **Anbernic RG353
family** (device quirks present for RG353M/RG353P; the V shares the family)
and is a modern mainline-kernel Linux with a current Mesa (panfrost GL 3.3+,
panvk Vulkan on G52) and modern Wayland compositors — exactly the stack
ARMSX2's Linux AppImage expects (glibc ≥ 2.38, `xdg_wm_base`, GL/Vulkan).

Plan when testing ROCKNIX (SD card, Android on eMMC untouched):
1. Flash the ROCKNIX RG353 image to a spare SD (same A2-card advice).
2. Boot ROCKNIX, SSH in, verify: `glibc --version` ≥ 2.38, `weston-screenshooter`
   / compositor with xdg_wm_base (`wayland-info | grep xdg_wm_base`), Mesa
   renderer.
3. Copy the ARMSX2 AppImage (no libc hacks needed), run it directly.
4. If it works: add to ES/GMenu2X as an app; PS2 on the Linux side done.
5. Rollback = remove the SD (Android on eMMC boots as before).

## Files kept for reproducibility

`survey/` contains the working launcher script (`run-armsx2.sh`) capturing the
whole ARMSX2-on-ArkOS attempt (glibc bundle launch, weston/xwayland/Xorg
variants) — a complete reference if ArkOS's stack ever changes.

Game/BIOS assets already on the ArkOS SD: `/roms2/ps2/*.iso` (GTA VCS, GTA SA,
NFS Underground, Crash Tag Team Racing, SNK Neogeo Collection, Twisted Metal)
and `/roms2/ps2/bios/SCPH30004R.bin` (+ scph39001.bin).
