# 09 — Kernel & device tree analysis (vs the RGB10 Max 2 lessons)

Decompiled sources: `survey/boot.dts` (the boot DTB, 155k lines decompiled),
`survey/dtbo-overlay.dts` (the 623-byte DTBO = boot-args extension + reboot-mode
magic numbers only), `survey/boot-unpacked/` (kernel/ramdisk/dtb from boot.img).

The DTB lives **inside boot.img** (Android 12 boot v2/v3 style); the dtbo
partition carries only board deltas. GammaOS selects `dtbo_idx=0` at boot.

## The RGB10 Max 2 pain list — how this device compares

| RGB10 Max 2 lesson (weeks of work) | RG353V / GammaOS reality |
|---|---|
| Stick pushes were generic TRIGGER_HAPPY codes, had to remap | **Factory-correct**: sw17 = `0x13d` (BTN_THUMBL/L3), sw16 = `0x13e` (BTN_THUMBR/R3) as GPIO buttons |
| Right-stick mux channels swapped (amux ch0=RX, ch1=RY reverse of R36S) | Same **single-ADC + mux** architecture (`singleadc-joypad`, amux count 4, ADC channel 3, mux GPIOs on gpio3 pins 13/14/15) — but GammaOS's own driver ships with **analog stick calibration fixed** ("tighter controls" is an official GammaOS feature) |
| No invert/channel props needed | Axis tuning per axis: `abs_{x,y,rx,ry}-{p,n}-tuning = <245>`; poll interval **10 ms** |
| Charger DC-detect broke charging when disabled | RK817 charger node with `dc_det_adc = <0>` (ADC-based DC detect, not GPIO); charging params: max input current 1500 mA, charge current 2000 mA, charge voltage 4250 mV |
| Panel rotation/orientation hacks (ORIENTATION_270) | Panel is **landscape-native, rotation 0** — nothing to fight |
| Panel variant selection | TWO panel nodes with hardware-ID detection: `aoly,sl008pa21y1285-b00` (8″ variant) and **`elida,kd35t133` (the RG353V 3.5″, status okay)** — `id`/`id-reg` bytes read back at probe |
| PMIC quirks (RK817 OTG rail latch) | RK817 again (charger node present) but **no latch misbehavior** observed — GammaOS ships on this hardware at scale |
| Battery gauge | Different IC: **Cellwise CW2015** at I2C 0x62 (not Coslight cw-bat... the power_supply name `cw-bat` comes from the Cellwise driver `cw2015`) |
| Dead second panel left enabled | Two panel nodes coexist; panel@1 (kd35t133) is the active one for this variant |
| Display handoff black-screen bug | Not reproduced here (different DRM path + landscape-native panel) — validate on a cold-boot cycle anyway |

## Key nodes documented

- **singleadc-joypad**: `io-channels = <&saradc 3>`, `amux-count = <4>`,
  mux GPIOs en/a/b, per-axis tuning 245, `poll-interval = <10>` (ms) —
  the poll interval is the input-latency lever (see 05).
- **Buttons** (all GPIO, on gpio3/gpio1 banks): DPAD-UP/DOWN/LEFT/RIGHT,
  A/B/X/Y, SELECT/START, TL/TR (L1/R1), TL2/TR2 (L2/R2), THUMBL/THUMBR.
- **Reboot modes** (dtbo): magic numbers for normal/charge/fastboot/
  bootloader/recovery — fastboot = recovery-mode magic (`0x5242c303`).
- **USB**: `usbdrd` dwc3, `dr_mode = "otg"` (dual-role; the OTG port is a real
  data port here), plus a second `dr_mode = "host"` controller.
- **GPU OPPs**: full OPP table with per-bin voltages (`opp-microvolt-L0/L1/L2`
  — Samsung binning), 200 MHz → 800 MHz.
- **Wi-Fi**: SDIO with `sdio_pwrseq` + `vcc_wifi` regulator nodes (Realtek
  combo; power sequencing in DT).
- **LEDs**: `gpio-leds` node present.

## Kernel source status

- Kernel = prebuilt **4.19.232 #176** (Jan 2023). The singleadc-joypad driver
  source is **not** in TheGammaSqueeze's public repos (they ship distribution
  binaries; GammaOS-RK3566 is now deprecated in favor of **GammaOS Core**,
  Android TV 13, and GammaOSNext, Android 14).
- The driver family is public elsewhere (RG351/RGB10 community kernels share
  the singleadc-joypad + odroidgo3-joypad lineage), so behavior can be
  cross-referenced even without GammaOS's exact source.
- Any kernel change on this device means rebuilding 4.19 with GammaOS's
  kernel config against the mali_kbase vendor module — only do this if a
  driver fix demands it (05/06 cover the alternatives).

## Firmware facts

- boot.img: 49.5 MB = kernel 32 MB + ramdisk 1.4 MB + dtb 127 KB + second
  (Rockchip resource image) 3 MB.
- dtbo: one 559-byte overlay (boot-args extension
  `androidboot.boot_devices=fe310000.sdhci,fe330000.nandc` + reboot-mode
  magics) — **not** a panel/joystick source.
- Verified boot state: **orange** (unlocked); vbmeta partition present.
