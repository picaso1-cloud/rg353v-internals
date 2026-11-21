# AnberNext boot artifacts — RG353V / RK3566

A known-good, hardware-verified boot set extracted from a working AnberNext v3.26
card, kept so other projects (ArchR port, andr36oid, experiments) can reuse the
device tree instead of reverse-engineering the panel again.

## Provenance

| | |
|---|---|
| Extracted | 2026-11-21, from TF1 partition 3 (`NEXTBOOT`, 99 MB FAT32) |
| Firmware | AnberNext v3.26 "NeonDrive", image dated 2026-11-18, artifacts built 2026-10-28 |
| Kernel | `5.10.226` (Rockchip vendor BSP), model `Anbernic RG353V/VS` |
| Compatible | `anbernic,rg353v`, `rockchip,rk3566` |
| Source project | https://github.com/retrotiv/AnberNext |
| Licensing | device tree derived from the Rockchip/Anbernic BSP (GPL-2.0); credit retrotiv/AnberNext |
| Verified on | our RG353V, panel ID `38 21`, `elida,kd35t133` |

Everything here was taken from a card that boots, lights the panel, and drives
Wi-Fi (`rtl8821cs`), the joypad and audio on this exact unit. It is the same DTB
AnberNext ships and runs.

## Files

| File | Purpose |
|---|---|
| `rk3566-353v.dtb` | **the one AnberNext boots** (also in `extlinux.conf`) |
| `rk3566-353v-notimingchange.dtb` | alternate panel timing/init, for panels that dislike warm re-init |
| `*.dts` | decompiled source of each DTB (`dtc -I dtb -O dts -s`) |
| `overlays/undervolt.{light,medium,maximum}.dtbo` + `.dts` | optional CPU OPP voltage reductions |
| `extlinux/extlinux.conf` | the boot entry (kernel, DTB, cmdline) |
| `boot.scr` | U-Boot script: Android dual-boot check, then falls back to extlinux |
| `android.go` / `android.no` / `android.req` | the dual-boot handshake files (contents: `go` / `no`) |
| `SHA256SUMS` | verify with `sha256sum -c SHA256SUMS` |

The 33 MB kernel `Image` and 1.3 MB `uInitrd` are **not** in git; they live in
`rg353v-backup/boot/anbernext-v3.26/` next to a copy of this set.

## Hardware map in the DTB

| Block | Node / compatible |
|---|---|
| Panel | `elida,kd35t133`, `simple-panel-dsi`, 4 DSI lanes, 640×480, id bytes `[30 52]` |
| DSI controller | `rockchip,rk3568-mipi-dsi` |
| Backlight | `pwm-backlight` |
| GPU | `arm,mali-bifrost` at `fde60000.gpu` |
| Storage | `rockchip,rk3568-dwcmshc` (eMMC, 8-bit), SD controllers |
| Wi-Fi/BT | `wlan-platdata` (SDIO, `keep_wifi_power_on`), `realtek,rtl8821cs-bt` |
| Gamepad | `singleadc-joypad` (shows up as `retrogame_joypad`) |
| Audio | `rockchip,rk817-codec`, headset detect via `rk-headset` |
| PMIC / battery | `rockchip,rk817`, `rk817,battery`, `rk817,charger` |
| Thermal | `soc-thermal`, `gpu-thermal` zones |

### Why this DTB matters (panel trap)

The mainline DTB we already had, `rg353v-backup/rocknix-kernel/rk3566-anbernic-rg353v.dtb`,
targets **`anbernic,rg353p-panel` / `newvision,nv3051d`** — a different panel.
Dropping it on a `kd35t133` unit gives a black screen. This vendor DTB is the one
that matches our hardware; keep it as the reference for the panel node and the
init sequence.

## The two variants

Both have the same panel compatible, `native-mode` points at `timing0` in both.

| property (timing0) | `rk3566-353v` (used) | `-notimingchange` |
|---|---|---|
| `clock-frequency` | `0x2fae1a8` (49,996,200) | `0x2faf080` (50,000,000) |
| `hback-porch` | 450 | 80 |
| `hfront-porch` | 458 | 40 |
| `hsync-len` | 70 | 2 |
| `vback-porch` | 13 | 28 |
| `vfront-porch` | 17 | 18 |
| `vsync-len` | 5 | 2 |

`timing1` is nearly identical between them (only `hfront-porch` 458 → 450).
The `panel-init-sequence` also differs in the `ff 02` bank (gamma/power
registers), and the alt DTB drops `dynamic-power-coefficient` from `rkvdec`.
That is the whole difference (verified property-by-property).

AnberNext boots the **normal** variant. Switch only if the panel fails to
re-initialize on a warm reboot (black screen after reboot, while the system is
clearly running). To switch on this card, edit `boot/extlinux/extlinux.conf`:

```
FDT /rk3566-353v.dtb   →   FDT /rk3566-353v-notimingchange.dtb
```

## CPU undervolt overlays (optional, not applied by AnberNext)

They target `cpu0-opp-table`; the base DTB exports `__symbols__`, so they can be
applied. `extlinux.conf` and `boot.scr` in v3.26 do **not** reference them.

| MHz | base mV | light | medium | maximum |
|---|---|---|---|---|
| 408 | 825 | 800 | 775 | 760 |
| 600 | 825 | 800 | 800 | 775 |
| 816 | 825 | 800 | 800 | 790 |
| 1104 | 825 | 800 | 800 | 800 |
| 1416 | 900 | 850 | 850 | 825 |
| 1608 | 975 | 900 | 900 | 850 |
| 1800 | 1050 | 950 | 925 | 875 |
| 1992 | 1150 | 1000 | 950 | 900 |

Use them with `fdtoverlays` in extlinux (if the U-Boot supports it), or merge
offline:

```sh
fdtoverlay -i rk3566-353v.dtb -o merged.dtb overlays/undervolt.light.dtbo
```

`maximum` at 1.992 GHz / 900 mV is aggressive: validate stability per unit.

## Android dual-boot behaviour

The markers are two plain bytes:

* `android.go` = `go`
* `android.no` = `no`
* `android.req` = `no` (default)

`boot.scr` does: if `android.req` equals `android.go` (F was held at power-on and
the initramfs wrote `go`), write `android.no` back over `android.req` (one-shot),
then run `boot_android mmc 0`. Nothing on the eMMC is written. If Android fails
to start it falls through to `extlinux.conf` and boots AnberNext.

## Reusing it in another project

1. Pick the variant (start with `rk3566-353v.dtb`).
2. **Match the kernel.** This is a vendor 5.10 tree. It assumes the vendor
   bindings/drivers: `panel-simple` with `elida,kd35t133`, Rockchip DSI, `rk817`,
   `singleadc-joypad`, the Mali Bifrost node. It works with AnberNext/dArkOS 5.10
   kernels. For a mainline kernel, use a mainline DTS (and a panel driver for
   `kd35t133`, which may not exist upstream) — do not just drop this binary in.
3. Put the DTB where that project's bootloader expects it: replace the file and
   keep the name, or update the config (`FDT` line in extlinux, or the DTB
   component of a FIT image).
4. If the panel stays dark but the system is up, try the other variant. Read the
   panel ID from the kernel log (`panel id: 38 21`) to know which batch you have.
5. Keep `boot.scr` + the three `android.*` files if you need the hold-F-to-Android
   behaviour; drop them for a card that should never start Android.
6. Credit retrotiv/AnberNext and the Rockchip/Anbernic BSP in derived work.

## Verify / regenerate

```sh
sha256sum -c SHA256SUMS
dtc -I dtb -O dts -s rk3566-353v.dtb > check.dts     # readable source
fdtdump rk3566-353v.dtb | head                        # header sanity
./extract.sh /dev/mmcblk0 ./out                       # re-extract from a card/image
```

The `.dts` files here are decompiled with `-s` (sorted, phandle-renumbered):
recompiling them yields an equivalent DTB, not a byte-identical one. Use the
`.dtb` files when you need the exact shipped binary.
