# 03 — Drivers

## GPU

| Item | Value |
|---|---|
| GPU | Mali-G52 (Bifrost, 1 core configuration per RK3566) |
| Kernel driver | **`mali_kbase.ko`** (vendor Bifrost driver, loaded from `/vendor/lib/modules/`) |
| Userspace | vendor blob, reports **OpenGL ES 3.2**, `v1.g7p1-01bet0.…` |
| Devfreq node | `/sys/class/devfreq/fde60000.gpu` |
| Governor | `simple_ondemand` |
| Freq table | 200 / 300 / 400 / 600 / 700 / **800 MHz** |
| Current policy | max capped at **800 MHz** (top OPP reachable — no cap to lift, unlike RGB10 Max 2) |

Tuning lever: switch governor to `performance` while gaming (more heat), or
raise `min_freq` for latency; verify thermals first (soc 52 °C at idle-charge).

## Video decode

- `fdf80200.rkvdec` devfreq node present — **RK VDEC hardware decoder**
  (H.264/HEVC/VP9 blocks on RK3566). Moonlight/Sunshine and video playback can
  hardware-decode; the decoder has its own frequency scaling.

## Input drivers

| Device | Driver/platform | Notes |
|---|---|---|
| `retrogame_joypad` | `singleadc-joypad` platform driver (GammaOS) | game pad via single ADC + mux; GammaOS-specific source |
| `touch_joypad` | GammaOS | joypad→touch emulator input device |
| `adc-keys` | Rockchip ADC keys | volume up/down |
| `gpio-keys` | standard | hard buttons (KEY_BACK, KEY_MEDIA …) |
| `rk805 pwrkey` | RK817/RK809 PMIC | power button |

## Wireless

- Wi-Fi/BT: Realtek SDIO combo (RG353V hardware), driver
  `v5.12.0-8-g39bbb8dd2.20201015_COEX20200730-5151` (Realtek 5.12 tree with
  COEX patch set), firmware `v24.8`. Interfaces: `wlan0`, `p2p0`.

## Power

| Block | Driver | Node |
|---|---|---|
| PMIC | RK817 (family) | regulator + codec + charger |
| Fuel gauge | **cw-bat** (Coslight CW201x) | `/sys/class/power_supply/cw-bat` |
| Charger | RK817 charger | `/sys/class/power_supply/{ac,usb,battery}` |
| Power key | rk805 pwrkey | event1 |

## Audio

- Card 0: `rockchip,hdmi` (HDMI audio)
- Card 1: **`rockchip,rk817-codec`** (speaker + headphone)
- RK3566 audio pipeline: I2S → RK817 codec; HDMI audio via the DSC/HDMI block.

## Other devfreq devices

| Node | Role | Governor |
|---|---|---|
| `dmc` | DRAM controller frequency | `dmc_ondemand` (latency lever) |
| `fde60000.gpu` | Mali-G52 | `simple_ondemand` |
| `fdf80200.rkvdec` | video decoder | (check per load) |

## Kernel modules present

`/vendor/lib/modules/` carries 7 modules including `mali_kbase.ko` — the GPU
is NOT in-tree in this kernel; it loads as a vendor module. Keep this in mind
for kernel rebuilds: the module and kernel must match.
