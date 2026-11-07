# 05 — Optimization plan

Baseline at survey: 2 GB RAM, soc 52.5 °C / gpu 47.8 °C (idle-charge),
/ 152 packages, `/data` 83% used, schedutil + simple_ondemand + dmc_ondemand,
GPU max 800 MHz (top OPP reachable), zram 1.5 GB.

## Levers, ordered by value

### 1. RAM & background management (2 GB is tight)
- zram already 1.5 GB ✓ (good default on this RAM).
- Trim **GammaOS_Lite preinstalled fat** (frontend extras, duplicated
  launchers): audit `pm list packages -3`, remove unused ones (`pm uninstall
  --user 0 <pkg>` — reversible by factory reset; true uninstall needs /data
  wipe or Magisk module).
- Background janitor (same concept as RGB10 Max 2): a Magisk script that runs
  `am kill-all` periodically and force-stops heavy unused apps — worth adding
  once real usage patterns are known.

### 2. GPU & DRAM latency
- GPU: `simple_ondemand` + full 800 MHz OPP available ✓ — nothing to unlock,
  unlike RGB10 Max 2. Optional: `performance` governor during gaming
  (thermals permitting), or `min_freq` floor (e.g. 400 MHz) to kill ramp lag.
- **DMC (`dmc_ondemand`) is the interesting one**: DRAM frequency scaling adds
  latency spikes. Pinning DMC at a higher floor (or `performance` during
  gaming) can smooth frame pacing — measure before/after with a stream.

### 3. CPU
- `schedutil` is right for battery; a `min_freq` floor (816 MHz) during
  gaming helps consistency; full `performance` only if thermals allow
  (soc already 52 °C idle-charge).

### 4. Storage
- `/data` was 83% used → debloat frees space; eMMC is fast enough.
- f2fs/ext4 choice is fixed by the vendor image (no action).

### 5. Input latency
- GammaOS `retrogame_joypad` polling — check
  `/sys/devices/platform/singleadc-joypad/` for a `poll_interval` style node;
  reducing ADC poll interval improves stick response at slight CPU cost.
- `touch_joypad` (pad→touch emulator) is heavy if unused — consider disabling
  its service if you never need touch emulation.

### 6. Debloat list (candidates to audit, not blind-remove)
- Launcher3 overlays/duplicates, unused GammaOS extras, Chromecast-ish and
  print services, any preinstalled store/updater.
- `pm list packages -s | sort` diff against a minimal gaming set.

### 7. Thermal
- soc 52 °C at idle-charge is fine; real gaming loads need measurement
  (`soc-thermal` trip points live in the DTBO). If it throttles, the first
  lever is the GPU governor, not the CPU.

## Measurement harness (to be built)

- Streaming latency: Moonlight session + network RTT logs.
- Frame pacing: `dumpsys gfxinfo com.<game>` frame time histogram.
- Thermals under load: thermal zones polled every 5 s during a fixed
  benchmark scene.
- RAM pressure: MemAvailable + psi (pressure stall info) during a heavy game.

## Non-goals

- Kernel rebuild (4.19.232 prebuilt works; rebuild only if a driver fix
  demands it — then use the GammaOS-RK3566 kernel source, not upstream).
- Verified boot re-lock (stays orange/unlocked).
