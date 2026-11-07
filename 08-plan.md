# 08 — Roadmap

## Phase 0 — study (done)
- Hardware + firmware survey complete (01–03).
- Wireless adb diagnosed + fixed + persisted (04).
- Root, TUN, and full adb access confirmed.

## Phase 1 — optimization (next)
1. Build the measurement harness (thermal logger, frame pacing, RAM pressure).
2. Baseline a real game/stream session (Moonlight once deployed).
3. Apply, one at a time, with measurement between each:
   - DMC floor/performance during gaming (frame pacing lever)
   - GPU min_freq floor
   - debloat pass (free /data space + RAM)
   - background janitor (Magisk service.d)
4. Lock the winners into `/data/adb/service.d/` scripts (documented in 05).

## Phase 2 — remote play (small, when wanted)
- Deploy tailscaled (same aarch64 binary family as RGB10 Max 2) + Magisk
  autostart; join the tailnet (login URL flow).
- Install Moonlight (v12.2) — NOT preinstalled on GammaOS_Lite.
- PC side: Sunshine (same as RGB10 Max 2 setup — see rgb10max2-internals/09).

## Phase 3 — Android upgrade (when Phase 1 is stable)
- Track GammaOSNext (Android 14 / LineageOS 21) releases for RK3566.
- Full backup (07), flash GammaOSNext vendor pack + GSI, re-apply:
  Magisk, adb-wifi script, tuning scripts, restore userdata.
- Validate: GPU/audio/wifi/input/mouse-mode parity, then re-baseline.

## Phase 4 — regeneration & contribution
- Assemble a regeneration archive (base firmware + GSI + Magisk boot + scripts
  + userdata backup + flash offsets) so the exact OS is re-creatable.
- Contribute upstream (TheGammaSqueeze) anything learned: input driver notes,
  tuning data, documentation fixes.

## Risks & rollbacks
- Every flash action is reversible via Loader-mode reflashing + the backups in
  07 — as long as backups exist BEFORE the change.
- The dying-SD-card lesson from RGB10 Max 2 applies: archive to more than one
  place.
