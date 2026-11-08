# 05 — Optimization plan

Baseline at survey: 2 GB RAM, soc 52.5 °C / gpu 47.8 °C (idle-charge),
/ 152 packages, `/data` 83% used, schedutil + simple_ondemand + dmc_ondemand,
GPU max 800 MHz (top OPP reachable), zram 1.5 GB.

## Levers, ordered by value (with measured results)

### 1. GPU & DRAM latency — DEPLOYED
- GPU: `simple_ondemand` + full 200–800 MHz OPP ✓ nothing to unlock.
- **GPU `min_freq` writes are silently ignored while the GPU is
  runtime-suspended** (verified: echo succeeds, value reverts) — no GPU floor
  possible this way; `simple_ondemand` ramps 200→800 MHz on load anyway.
- **DMC (DRAM) floor WORKS and is the real lever**: idle drops to 324 MHz;
  `echo 780000000 > /sys/class/devfreq/dmc/min_freq` pins it — kills the
  DRAM-latency spikes that cause frame pacing hitches.

### 2. Scripts deployed (Magisk-rooted, on-demand)
- `/data/local/tmp/gamemode` — CPU floor 816 MHz + DMC floor 780 MHz
- `/data/local/tmp/gamemode-off` — back to 408 MHz / 324 MHz
- `/data/adb/service.d/janitor.sh` — boot script (root): background janitor
  (`am kill-all` every 60 s) + keeps wireless adb (`:5555`) enabled.
- Run via root adb: `su -c /data/local/tmp/gamemode`

### 3. CPU
- GammaOS default governor is **`interactive`** (their performance choice).
- `schedutil` was on the RGB10 Max 2; interactive already biases high — leave.

### 4. Storage
- The 18 GB in /data is USER content (ADM downloads 7 GB incl. Valve/Steam
  data 2.2 GB, GTA SA 2.6 GB, apps 4 GB) — not bloat. Clean ADM if stale.
- GammaOS_Lite package count: 152 — already lean; no debloat pass needed.

### 5. Thermal
- soc 35 °C / gpu 34 °C idle (not charging) — cool. Gaming loads TBD.

## Measurement harness (to be built)

- Streaming latency: Moonlight session + network RTT logs.
- Frame pacing: `dumpsys gfxinfo com.<game>` frame time histogram.
- Thermals under load: thermal zones polled every 5 s during a fixed benchmark.
- RAM pressure: MemAvailable + psi during a heavy game.

## Non-goals

- Kernel rebuild (4.19.232 prebuilt + vendor mali_kbase module; rebuild only
  if a driver fix demands it).
- Verified boot re-lock (stays orange/unlocked).

## Deployed (2026-11-08) — verified live

- `/data/local/tmp/gamemode` / `gamemode-off`: CPU floor 816 MHz + DMC floor
  780 MHz (GPU floor impossible — devfreq ignores min writes while the GPU is
  runtime-suspended; simple_ondemand ramps 200→800 automatically).
  Requires `su -c`. Both directions verified.
- `/data/adb/service.d/janitor.sh`: `am kill-all` every 60 s + wireless adb
  enabler (replaces the separate adb-wifi.sh).
- Debloat: NOT needed — GammaOS_Lite is lean (152 packages); the 18 GB in
  /data is user content (ADM downloads 7 GB, Valve 2.2 GB, GTA SA 2.6 GB).
- Storage note: if the ADM downloads are stale, clearing them frees 7 GB.
