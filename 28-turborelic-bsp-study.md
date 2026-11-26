# 28 — TurboRelic RG353V BSP study (kernel/drivers/features guide)

**Date:** 2026-11-26 · **Source:** `bomba5/turborelic-public` (cloned to
`/home/souhail/Anbernic/downloads/turborelic/`).

TurboRelic is the only from-scratch Yocto distro for the RG353V. It boots a
**mainline 6.15.11 kernel** on the RG353V — the only proven mainline kernel for
this device. This is the reference for patching the Arch-R kernel to get
panfrost/panvk (Vulkan) working.

## Kernel

- **Version:** mainline **6.15.11** (`linux-mainline_6.15.bb`)
- **DTB:** `rockchip/rk3566-anbernic-rg353v.dtb` (mainline)
- **U-Boot:** mainline **2025.01** (`u-boot-mainline`)
- **Mesa:** `mesa-megadriver` (panfrost) — `MACHINE_ESSENTIAL_EXTRA_RDEPENDS += "mesa-megadriver"`
- **Tune:** `cortexa55`, `-march=armv8.2-a -mtune=cortex-a55`
- **MACHINE_FEATURES:** `apm usbhost usbgadget screen alsa wifi bluetooth ext2 gpu opengl panfrost`
- **Image type:** `wic.gz` (ext4 wic)

## Kernel patches (7)

| Patch | File | Purpose |
|---|---|---|
| 0001 | `0001-rg353v-sdmmc2-cap-25MHz-for-wifi.patch` | Cap sdmmc2 to 25 MHz (SDR25) — the board has SDIO signal-integrity issues at 50 MHz (SDR50), causing rtw88 `-ETIMEDOUT` (-110). Removes `sd-uhs-sdr50`, sets `max-frequency = <25000000>`. |
| 0002 | `0002-rtw88-sdio-mdelay-before-probe.patch` | Add 500 ms delay before rtw88 SDIO probe — the RTL8821CS SDIO WiFi and Bluetooth UART race during probe; the delay lets the UART finish first. |
| 0003 | `0003-drm-panel-st7703-fix-rg353v2-init.patch` | Fix ST7703 panel init for RG353V-V2 — correct two init params (`SETVCOM` 0x92 0x92 → 0x7f 0x7f, `SETPOWER_EXT` 0x25 0x22 → 0x26 0x62). |
| 0004 | `0004-power-rk817-rename-battery-charger.patch` | Rename battery/charger supply names from `rk817-battery`/`rk817-charger` to `battery`/`charger` (standard names for userspace tools). |
| 0006 | `0006-arm64-dts-rgxx3-sdmmc1-card-detect-delay.patch` | Add 800 ms `card-detect-delay` to sdmmc1 (external TF card slot) to avoid false card-detect events. |
| 0007 | `0007-arm64-dts-rk3566-add-1992mhz-cpu-opp.patch` | Add 1992 MHz CPU OPP with turbo-mode flag for Cortex-A55. |

(Note: there is no 0005 — the numbering skips it.)

## Kernel cfg files (11)

| File | Features |
|---|---|
| `audio.cfg` | RK817 PMIC codec + I2S1 + HDMI audio; ALSA loopback (for web UI streaming). `CONFIG_SND_SOC_ROCKCHIP_I2S=y`, `CONFIG_SND_SOC_RK817=y`, `CONFIG_SND_SOC_HDMI_CODEC=y`, `CONFIG_SND_SOC_SIMPLE_AMPLIFIER=y`, `CONFIG_DRM_DW_HDMI_I2S_AUDIO=y`, `CONFIG_SND_ALOOP=m`. |
| `bluetooth.cfg` | RTL8821CS HCI UART serdev (H5/Three-wire). BT must init before WiFi SDIO probe. `CONFIG_BT_HCIUART_SERDEV=y`, `CONFIG_BT_HCIUART_RTL=y`. |
| `debug.cfg` | `CONFIG_DYNAMIC_DEBUG=y` (per-callsite dev_dbg control). |
| `display.cfg` | DRM + fbcon + fbdev client (matches Batocera 6.15.11). `CONFIG_DRM=y`, `CONFIG_DRM_FBDEV_EMULATION=y`, `CONFIG_DRM_CLIENT_DEFAULT_FBDEV=y`, `CONFIG_FRAMEBUFFER_CONSOLE=y`, `CONFIG_DRM_ROCKCHIP=y`, `CONFIG_ROCKCHIP_DW_MIPI_DSI=y`, `CONFIG_DRM_DW_MIPI_DSI=y`, `CONFIG_PHY_ROCKCHIP_INNO_DSIDPHY=y`, `CONFIG_BACKLIGHT_CLASS_DEVICE=y`, `CONFIG_BACKLIGHT_PWM=y`, `CONFIG_DRM_PANEL_SITRONIX_ST7703=y` (built-in), `CONFIG_DRM_PANEL_NEWVISION_NV3051D=m` (module), `CONFIG_DRM_PANFROST=m` (module). |
| `gamepad.cfg` | Mainline `adc-joystick` driver (not singleadc-joypad). `CONFIG_INPUT_JOYSTICK=y`, `CONFIG_INPUT_JOYDEV=y`, `CONFIG_JOYSTICK_ADC=y`, `CONFIG_MULTIPLEXER=y`, `CONFIG_MUX_GPIO=y`, `CONFIG_IIO_MUX=y`, `CONFIG_INPUT_UINPUT=y`. |
| `input.cfg` | Touchscreen (Hynitron CST340) — **disabled** (phantom touch events). |
| `performance.cfg` | CPU freq scaling (schedutil + performance), CPU boost, DevFreq governors (simple_ondemand/performance/powersave), Rockchip DDR bandwidth scaling, thermal management. |
| `touch.cfg` | Hynitron CST340 — **disabled** (ghost input in ES). |
| `usb-serial.cfg` | USB gadget serial (CDC ACM) for kernel log access over USB-C OTG. `CONFIG_USB_G_SERIAL=y`, `CONFIG_USB_DWC3_DUAL_ROLE=y`, `CONFIG_USB_DWC3_OF_SIMPLE=y`. |
| `v4l2.cfg` | V4L2 stateless hardware video decode (Hantro H.264, RkVDEC H.265/HEVC/VP9). For FFmpeg V4L2 Request API hwaccels (Moonlight). `CONFIG_MEDIA_SUPPORT=y`, `CONFIG_VIDEO_HANTRO=m`, `CONFIG_VIDEO_HANTRO_ROCKCHIP=y`, `CONFIG_VIDEO_ROCKCHIP_VDEC=y`. |
| `wifi.cfg` | RTL8821CS SDIO (rtw88). `CONFIG_RTW88=m`, `CONFIG_RTW88_8821CS=m`. |

## U-Boot patches (1)

| Patch | File | Purpose |
|---|---|---|
| 0001 | `0001-board-rockchip-Fix-panel-detection-and-DTB-path.patch` | Mainline A-TF doesn't enable the VO power domain like the BSP A-TF did, so panel detection crashes (reboot loop). Set the VO domain on + memory barrier before panel detection. Also remove `rockchip/` prefix from `DTB_DIR` to match Batocera's boot partition layout. |

## Gamepad-merge daemon

`recipes-gaming/gamepad-merge/gamepad-merge/gamepad-merge.c` (120+ lines of C):
- The mainline kernel exposes the RG353V controls as **separate** input devices:
  - `adc-joystick` — ABS_X, ABS_Y, ABS_RX, ABS_RY (analog sticks)
  - `gpio-keys-control` — BTN_SOUTH/EAST/NORTH/WEST, DPAD, shoulders, thumbsticks
  - `adc-keys` — BTN_MODE (function/hotkey button)
  - `rk805-pwrkey` — KEY_POWER (power button)
- The daemon grabs all four, creates a single **"RG353V Gamepad"** uinput device,
  and forwards events so RetroArch/SDL2 see one unified gamepad.
- **Power button behavior:** short press (<1s) = toggle screen DPMS (off/on);
  long press (>=1s) = open ES quit menu via HTTP API.
- Copies absinfo from the real adc-joystick device (min=15, max=1023, flat=32,
  fuzz=32) rather than hardcoding.

## Comparison: dArkOS 5.10 vs TurboRelic 6.15

| Aspect | dArkOS (5.10.226) | TurboRelic (6.15.11) |
|---|---|---|
| Kernel | Android BSP 5.10.226 | mainline 6.15.11 |
| GPU driver | vendor libmali (kbase) | panfrost (mesa-megadriver) |
| Vulkan | vendor only (no panvk) | panvk (experimental) |
| Boot chain | dArkOS FIT (accepted by eMMC bootloader) | mainline u-boot 2025.01 (needs dArkOS idbloader) |
| DTB | `rk3566-353v.dtb` (dArkOS) | `rk3566-anbernic-rg353v.dtb` (mainline) |
| Wi-Fi | rtl8821cs (kernel) | rtw88 (kernel, + 25 MHz cap + 500 ms delay) |
| Gamepad | singleadc-joypad | adc-joystick (mainline) + gamepad-merge daemon |
| Display | fbcon (dArkOS) | fbcon + fbdev client (matches Batocera) |
| USB serial | — | USB gadget serial (CDC ACM) |
| Video decode | — | V4L2 (Hantro + RkVDEC) |
| Status on RG353V | **boots** (proven) | **boots** (proven, Yocto distro) |

## Key takeaways for patching the Arch-R kernel

1. **The mainline kernel works on the RG353V** (TurboRelic proves it). The key
   patches are the WiFi ones (25 MHz cap + 500 ms delay) and the panel init fix.
2. **Panfrost is the GPU driver** for the mainline kernel (not libmali). This is
   what enables panvk (Vulkan).
3. **The u-boot patch is critical** — mainline A-TF doesn't enable the VO power
   domain, so panel detection crashes without it.
4. **The gamepad-merge daemon** is needed because the mainline kernel exposes
   the controls as separate devices.
5. **The boot chain is the hard part** — the mainline u-boot needs the dArkOS
   idbloader to be accepted by the eMMC bootloader.
