# 37 — ROCKNIX tuning, resource stats and the ES question

**Date:** 2026-11-28 · **Status:** measured on hardware · **Scope:** RG353V,
ROCKNIX 20261101 (kernel 7.2.11), card boot through the eMMC chain (`34`),
panel v2 fixed (`35`).

---

## 1. Idle resource snapshot

| | |
|---|---|
| RAM | **310 MB used / 1962 MB**, 1651 MB available, buff/cache 532 MB, **no swap** |
| CPU | 4× Cortex-A55, OPPs `408/600/816/1104/1416/1608/1800 MHz`; all cores at **1800 MHz** while idling in ES; load 1.13; PSI `cpu some 3.1 %` |
| GPU | devfreq `200–800 MHz`, `simple_ondemand`, **200 MHz** idle |
| Thermal | cpu **45.5 °C**, gpu **41.9 °C** |
| Display | DSI-1 640×480, `dclk_vop1` 24.15 MHz |
| Storage | `/storage` 5.4 GB free; card write ≈ **13.6 MB/s** (the EE8QT card is the I/O limit) |

Top RAM: **emulationstation 143 MB** (16.9 % CPU), sway 53.6, systemd 19.3,
inputplumber 17.7, wireplumber 15.8, pipewire-pulse 13.2, resolved 12.1,
pipewire 11.4, NetworkManager 11.2, udevd 9.9.

## 2. What ROCKNIX exposes (and what it does automatically)

### CPU / GPU governors
* Setting: `system.cpugovernor` in `/storage/.config/system/configs/system.cfg`
  (`ondemand` default). `/etc/profile.d/099-freqfunctions` implements
  `performance` / `ondemand` / `schedutil` / `powersave` (CPU + DMC) and
  `gpu_performance_level` (`auto|default` → ondemand, else the given governor).
* Setting: `system.gpuperf` (global GPU governor override; games may override
  it per platform/ROM via the `gpuperf` key).
* **`runemu.sh` already switches to `performance` before every game** (line 14)
  and restores `system.cpugovernor` on exit — so pinning `performance`
  permanently only heats the **menu**. Measured: pinned → ES 184 MB / 24.5 %,
  cpu 55 °C, load 2.77 vs stock 143 MB / 16.9 %, 45.5 °C, 1.13.
  **Conclusion: keep `ondemand` (or `schedutil`) as the idle governor.**

### Memory: zram/swap (built in, off by default)
`rocknix-memory-manager` (service `rocknix-memory-manager.service`, config
`/storage/.config/swap.conf`) manages ZRAM + optional disk swap, with
`--zram-size [0|Auto|N%|MB]`, `--zram-algo zstd|lzo|lz4`, `--vm-*`, `--ksm`,
plus `rocknix-memory-recompress.timer`. Applied here:

```sh
rocknix-memory-manager --zram-size 512 --zram-algo lz4 --setup
# swap.conf: ZRAM_SIZE="512"  ZRAM_ALGO="lz4"
# -> /dev/zram0 512M lz4, swap prio 100, vm.swappiness=100,
#    watermark_scale_factor=10, compaction_proactiveness=10
```

This is persistent (service + swap.conf) and is the cheap insurance against
OOM in PS2/GC/Switch titles on 2 GB. Default was **no swap at all**.

### Services
`samba.enabled=0` out of the box. 24 services run at idle; the small ones
(`avahi`, `rpcbind`, `debug-shell`, `touchkeyboard`) are a few MB — the real
weight is ES. The rootfs is a **read-only squashfs**, so "disable" has to go
through the settings or `/storage/.config` (see §4).

### Undervolt overlays
`/flash/overlays/rk3566-undervolt-cpu-l1|l2|l3.dtbo` exist, but **our boot
chain does not apply dtbos**: the stock eMMC u-boot does a plain `sysboot` and
ignores `/overlays` (ROCKNIX's own u-boot would apply them). To use one, merge
it into the boot DTB:

```sh
fdtoverlay -i rk3566-anbernic-rg353v.dtb -o merged.dtb rk3566-undervolt-cpu-l1.dtbo
```

Do this last, and start with l1 — it trades stability for °C.

## 3. The ES question (the user's main complaint)

Facts measured:
* ES-DE is the only frontend in the image (no Pegasus/Attract); RetroArch
  1.22.2 and all the standalones are present.
* ES costs **143–184 MB and 16–24 % CPU** depending on **what it is showing**:
  the system theme has **`showVideoAtDelay=10`**, so a game list with video
  previews decodes video. That is the single biggest ES lever.
* The settings file is minimal (`LastSystem`, `ShowFlags`, `ShowTags`), so
  videos/animations are at their defaults.
* `boot=Emulationstation` exists in `system.cfg` but no consumer was found in
  the image; the frontend is started by `essway.service` →
  `/usr/bin/start_es.sh` → `emulationstation` (via PATH).

### If we keep ES
* Turn **video previews off** (ES UI setting or a theme without videos) — the
  cheapest big win.
* Or run RetroArch as the frontend: `/storage/bin/emulationstation` wrapper →
  `retroarch`, with `/storage/bin` prepended to PATH from
  `/storage/.config/profile.d/` (the rootfs is read-only, but `/etc/profile`
  sources `/storage/.config/profile.d/*`). Reversible by deleting two files.

### "Close ES when RAM is tight" — possible as **freeze**, not close
* Games run in `games.slice` via `systemd-run --scope … -p
  StopPropagatedFrom=essway.service`. **Stopping essway kills the game.**
* **Freezing** `essway.service` is safe (the game is in a separate cgroup): the
  menu's 16–24 % CPU goes to zero and its ~150–180 MB becomes cold pages that
  zram (swappiness 100) can reclaim under pressure.
* A watchdog can do it: poll for an active `game-*.scope`; `systemctl freeze
  essway.service` when one exists, `thaw` when it ends; log to
  `/storage/.cache/es-squeeze.log`. Started from `profile.d`, fully
  reversible. Not installed yet.

## 4. Persistence map (read-only rootfs)

| Thing | Where |
|---|---|
| settings | `/storage/.config/system/configs/system.cfg` (backup: `.bak2`) |
| zram/swap | `/storage/.config/swap.conf` + `rocknix-memory-manager.service` |
| session env/PATH | `/etc/profile` sources `/storage/.config/profile.d/*` |
| ES data | `/storage/.config/emulationstation/`, `/storage/.emulationstation/` |
| GPU/frontend choice | `gpu.driver`, `boot=` in `system.cfg` |

## 5. GPU A/B and the "limits" picture

Benchmarks (single sample, see `36` for the caveat):

| | libmali | Panfrost |
|---|---|---|
| GLES | 3.2 / 577 | 3.1 / **613** |
| Vulkan | **1.3.276 / 747** | 1.0.354 / 628 |

The driver is global (one kernel driver at a time) — no per-emulator switch
without a reboot. Keep **libmali** unless everything you run is GLES.

Thermals leave headroom (45–57 °C), the CPU is already at its top OPP
(1.8 GHz) and the GPU at 800 MHz; the remaining gains are **software**
(previews off, ES frozen during games, zram) rather than clocks.

## 6. Next

1. ES video previews off (measure the drop).
2. Freeze-ES-during-game watchdog (+ log).
3. Undervolt l1 (optional, after stability is confirmed).
4. RG353V is otherwise **feature-complete**: mainline kernel, v2 panel,
   Panfrost/PanVK, dual-boot with Android, Wi-Fi/SSH. The next project is the
   **Android refresh** — GammaOS Next / andr36oid on the latest releases —
   keeping the eMMC backup/rollback path (`33`, `34`).
