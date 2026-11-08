# 10 — Emulation limits & browser (WASM) gaming

Covers both handhelds: **RGB10 Max 2** (RK3326, 1.3 GHz, 1 GB) and
**RG353V** (RK3566, 1.8 GHz, 2 GB).

## Native emulation limits

| System | RGB10 Max 2 (1 GB) | RG353V (2 GB) |
|---|---|---|
| NES / SNES / GB·GBC / Genesis / PCE | ✅ perfect | ✅ perfect |
| GBA | ✅ perfect | ✅ perfect (+ higher res filters) |
| Arcade (FBNeo classics) | ✅ good | ✅ good |
| PSX (DuckStation) | ✅ good (tight RAM) | ✅ good |
| N64 (mupen64plus) | ⚠️ moderate, many games OK | ✅ good |
| Dreamcast (Flycast) | ⚠️ playable w/ settings | ✅ good |
| NDS (drastic) | ✅ good (ARM-native) | ✅ good |
| PSP (PPSSPP) | ⚠️ 1× res, lighter titles | ✅ good, some 2× res |
| Saturn | ⚠️ marginal | ⚠️ moderate |
| GameCube / Wii (Dolphin) | ❌ | ❌ (CPU-bound; A55 can't) |
| PS2 (AetherSX2) | ❌ | ❌ (needs SD845-class) |
| 3DS (Citra) | ❌ (RAM wall) | ⚠️ marginal at best |

Hard walls: **CPU** (4×A55 regardless of clock) and **RAM** (1 GB on the RGB10
Max 2 kills anything memory-hungry). GPU matters less for 2D/low-res 3D cores.

## Browser (WASM) gaming — e.g. ported2browser.com class

Two very different categories live behind "browser game":

### 1. True WASM ports (native code compiled to WebAssembly)
Examples: Diablo (devilutionX web), Doom/Quake/Quake III (WebGL), Duke Nukem 3D,
Fallout-class engine ports, 2D engines.
- WASM runs at ~70-80 % of native speed on the same core; **WebGL2 is
  supported** by both GPUs (Mali-G31/G52, GLES 3.2).
- **RG353V: ✅ good** — Firefox is preinstalled; 2 GB RAM + 1.8 GHz handles
  most true-WASM ports. Use Chrome or Firefox, request desktop site, one tab
  only. The pad works via the **HTML5 Gamepad API** (Android exposes it as a
  standard gamepad) — and GammaOS's `touch_joypad` covers touch-only pages.
- **RGB10 Max 2: ⚠️ marginal** — 1.3 GHz is enough for 2D-era ports, but the
  **1 GB RAM is the wall** (browser + WASM heap + GPU buffers). Close
  everything; use the joypad **mouse mode** (Select+Start chord, built in
  v26+) for pointer-style games.

### 2. In-browser PC emulation (v86 / WASM x86 / DOS-in-browser)
Examples: full Windows 3.1/95/98 in the browser, DOS PCs, or "big game"
sites that actually run an x86 VM per tab (some AoE2/RA2-class pages).
- The browser emulates a whole PC at **~10-20 % of native** speed. On 4×A55
  handhelds this is **not usable for real gaming** — this is the hard wall,
  on both devices.

### 3. JS console emulators in the browser (EmulatorJS etc.)
- Works, but strictly worse than the native RetroArch/standalone emulators
  already on both devices. No reason to use it for console games.

## Practical setup

| | RGB10 Max 2 | RG353V |
|---|---|---|
| Browser | check installed (Chromium-based preferred) | **Firefox** (preinstalled) or Chrome |
| Controls | HTML5 Gamepad API (native) + mouse mode chord | HTML5 Gamepad API + `touch_joypad` |
| Resolution note | 640×480 page in landscape | same panel class, landscape-native |
| Keep in mind | close all apps first (1 GB) | game mode script available |

## Bottom line

- **RG353V**: browser WASM gaming is genuinely usable for true-WASM ports of
  90s PC classics (Diablo/Quake/2D engines). Emulated-PC pages are not.
- **RGB10 Max 2**: possible for light ports with everything else closed; the
  1 GB RAM ceiling is the limit.
- Console emulation belongs to the **native** emulators (RetroArch/drastic/
  PPSSPP/Flycast/DuckStation) — the browser adds value only for the
  true-WASM PC-game ports.
