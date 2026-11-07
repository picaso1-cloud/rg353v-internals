# 01 — Hardware

## SoC & memory

- **RK3566**: 4× Cortex-A55. CPU freq table: `408000 600000 816000 1104000 1416000 1608000 1800000` kHz.
- Governor: `schedutil`. Thermal at idle-ish load: soc 52.5 °C, gpu 47.8 °C, battery 18.8 °C.
- **2 GB LP4X** RAM (per the board DT model string "LP4X").
- DMC (DRAM controller) has its own devfreq governor: `dmc_ondemand` — DRAM frequency scales with load; a tuning lever for latency vs power.

## Panel

- 3.5″ **640×480 @60 Hz** MIPI-DSI, `rotation 0` — the panel is **landscape-native**;
  no SF orientation hacks, no handoff bugs. Density 160 (213 dpi).
- DSI controllers present: `dsi@fe060000` (used) + `dsi@fe070000` (HDMI/second DSI path on RK3566).
- Brightness range: min 0.0, max 1.0, default 0.3976 (kernel default brightness curve exposed straight through Android).
- Panel driver/compatible lives in the **dtbo** (`/dev/block/by-name/dtbo`) — GammaOS selects the panel
  by board variant; the RG353V DT node set includes `dsi@fe060000` + panel node (probe deeper via
  `find /proc/device-tree -name '*panel*'` from root shell).

## Input

Input devices (from `/proc/bus/input/devices`):

| Device | Node | Role |
|---|---|---|
| `gpio-moount_adc` | event0 | ADC mux control node (dmcfreq-linked) |
| `rk805 pwrkey` | event1 | power button (rk805 = part of the RK817/RK809 PMIC family) |
| `adc-keys` | event2 | volume keys (ADC ladder) |
| `gpio-keys` | event3 | hard buttons (KEY_BACK, KEY_MEDIA seen; volume in adc-keys) |
| **`retrogame_joypad`** | event4 | **the game pad**: platform device `singleadc-joypad` — ONE ADC channel + mux design (same architecture family as the RGB10 Max 2's amux), GammaOS's own driver |
| `touch_joypad` | event5 | GammaOS's **joypad→touch emulator** (lets games/apps requiring touch be driven from the pad) |

- Sticks are analog through the single-ADC mux; GammaOS's `retrogame_joypad` also exposes
  the pad as a mouse-capable device (BTN_MOUSE family seen on event3) — the mouse mode
  exists here natively in the driver stack.
- RG353V hardware: hall-effect-style compact sticks (confirm polarity/calibration via
  `/proc/device-tree` joystick nodes if recalibration is ever needed).

## Audio

- Two ALSA cards:
  - `rockchip,hdmi` (HDMI audio out)
  - **`rockchip,rk817-codec`** — the PMIC's built-in codec drives the speaker/headphone jack.
- Same RK817 audio block as the RGB10 Max 2 — the audio path (and its quirks) is family-shared.

## Battery / charging

- Fuel gauge: **cw-bat** (Coslight CW2015/2017 class), charger via RK817.
- Live sample: 4.161 V, +146 mA charging current scale, 91% level, USB-powered charging.
- `/sys/class/power_supply/{ac,battery,cw-bat,usb}` all present.

## Wireless

- Wi-Fi: Realtek SDIO combo (driver string `v5.12.0-8-g39bbb8dd2.20201015_COEX20200730-5151` →
  RTL8852BS/BT family), dual-band capable, `wlan0` + `p2p0`.
- Bluetooth: same combo module.

## Storage

- 32 GB eMMC: `mmcblk0` + `mmcblk0boot0/1` (i.e. eMMC with hardware boot partitions —
  u-boot may live in `mmcblk0boot0` or in the `uboot` GPT partition; both paths exist).
- `/data` (userdata, p14): 22 GB, was 83% used at survey time (GammaOS ships with a
  full frontend set preinstalled — debloat frees space).
- Dynamic partitions live in `super` (p13): system + vendor + odm.
