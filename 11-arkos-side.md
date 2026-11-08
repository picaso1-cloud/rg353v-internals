# 11 — ArkOS side (dual-boot): survey, optimization, and the PS2 verdict

The RG353V dual-boots: **eMMC = Android/GammaOS**, **microSD (TF1) = ArkOS**.
SSH access: `ark@<ip>` password `ark` (sudo with same password). The ArkOS
kernel is 4.19.172 on an **Ubuntu 19.10 (Eoan)** rootfs — older than GammaOS's
kernel and glibc (2.30).

## Survey results

- ArkOS CPU governor: `ondemand` (ArkOS manages per-game governors itself).
- GPU: `simple_ondemand`, 200 MHz idle / 800 MHz max — same OPP table as GammaOS.
- DMC: present, `dmc_ondemand`, idle 324 MHz (same devfreq nodes as GammaOS).
- RAM: 2 GB, ~1.53 GB available at idle (leaner than Android).
- `amux`-style pad handled by GammaOS's driver stack here as well (ArkOS ships
  its own joypad handling via ES settings).

## PS2 on ArkOS — investigated, verdict: not possible

The Android/GammaOS side plays some PS2 games via **AetherSX2** (Android-only
emulator). For the Linux side we checked every avenue:

| Option | Result |
|---|---|
| PCSX2 ARM64 Linux builds | **Never published** — checked the entire PCSX2 release history: every Linux asset is x64-only |
| Play! (jpd002) | No current ARM64 Linux release assets |
| AetherSX2 | Android-only, no Linux build |
| Running x64 PCSX2 | Impossible (ARM CPU, no x86 translation layer worth using) |
| Even if an ARM64 build existed | The old Ubuntu 19.10 stack (glibc 2.30, Mesa 19.2-era panfrost without desktop GL 3.3) could not run PCSX2 (needs glibc ≥ 2.31 + GL 3.3) |

**Conclusion: PS2 emulation lives on the Android side (AetherSX2) only.**
Keep the dual-boot division: ArkOS = retro systems + Linux native games,
GammaOS = Android + PS2 + streaming. This is the sane split for this hardware.

## ArkOS optimization levers (what's actually tunable)

- ArkOS manages CPU governor itself per-game (`ondemand` at idle; switches to
  performance during emulation) — leave it; ArkOS's own scripts handle this
  better than manual overrides.
- DMC floor idea from GammaOS applies here too if a game stutters:
  `echo 780000000 > /sys/class/devfreq/dmc/min_freq` (as root) — revert with
  324000000. Test per-game; not persisted across reboots.
- `/data`-free / storage: ArkOS runs from the SD — card speed directly
  affects load times (same A2 advice as the rebuild guide).
- "Disable Remote Services.sh" in `/opt/system/` — ArkOS ships toggles for
  SSH/Samba; re-enable when remote work is needed (that's how we SSH'd in).

## Useful ArkOS notes

- SSH: `ark@<ip>` / `ark`, sudo with the same password.
- Remote services can be toggled from the ArkOS Options menu
  (`/opt/system/Enable Remote Services.sh`).
- SD-card TF1 = ArkOS OS + ROMs; TF2 slot = extra ROM storage (the README
  warning about TF2 during GammaOS installs applies to the Android side).
