# DTB Selector.pak

Small AnberNext tool to switch the **panel device tree** the card boots, without
editing configs or rebuilding anything.

```
Tools/rg353/DTB Selector.pak/
├── launch.sh
├── pak.json
└── res/
    ├── rk3566-353v.dtb                  normal (AnberNext default)
    └── rk3566-353v-notimingchange.dtb   alternate panel timing
```

## Why it swaps a file instead of editing the boot config

The primary boot path is `boot.scr`, a compiled U-Boot script. It hardcodes:

```
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} rk3566-353v.dtb
...
booti ${kernel_addr_c} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
```

The extlinux fallback (`boot/extlinux/extlinux.conf`) also points at
`FDT /rk3566-353v.dtb`. Both paths use the **same filename**, so the selector
replaces the contents of `rk3566-353v.dtb` and leaves every config untouched.
That also means there is nothing to break if a future AnberNext update rewrites
`extlinux.conf`.

## What it does

1. finds the partition whose GPT name is `NEXTBOOT` **on an SD card** (the eMMC
   is never a candidate — same rule `nextui-init` uses);
2. mounts it read-write and compares the current `rk3566-353v.dtb` with the two
   curated trees in `res/`, so it knows what is active;
3. shows a two-entry menu; Up/Down (or Left/Right) chooses, **A/Start** applies,
   **B/Select** exits;
4. writes the chosen tree to `rk3566-353v.dtb.new`, `sync`s, then renames it over
   `rk3566-353v.dtb` (a power cut leaves the old or the new complete file, never
   a half-written one);
5. writes `dtb-selected.txt` on NEXTBOOT (choice, panel ID, time) and asks the
   launcher to reboot via `/tmp/reboot`.

Nothing is written to the games card or the eMMC.

## Install

```sh
cd rg353v-internals/anbernext-paks
./install-pak.sh /media/$USER/NEXTUI "DTB Selector.pak"
# or ship dist/DTB.Selector.pak.zip and unzip it into Tools/rg353/
```

Boot → Tools → **DTB Selector**.

## Which entry to use

| Entry | When |
|---|---|
| **Normal (default)** | the tree AnberNext ships and booted on this unit |
| **No timing change (panel re-init fix)** | try only if the panel fails to initialize on a warm reboot (black screen while the system is clearly running) |

The alternate changes the panel init sequence and `timing0` (see
`../anbernext-boot/README.md` for the exact property diff). It is the same tree
retrotiv ships as `rk3566-353v-notimingchange.dtb`, not something we generated.

## If the screen stays black after choosing the alternate

The pak cannot help without a display, but recovery is a file copy on a PC:

1. power off, put TF1 in the reader;
2. open the `NEXTBOOT` partition;
3. copy `Tools/rg353/DTB Selector.pak/res/rk3566-353v.dtb` over
   `NEXTBOOT/rk3566-353v.dtb` (or use `anbernext-boot/rk3566-353v.dtb`);
4. `sync`, eject, boot.

The two files are also archived in `rg353v-internals/anbernext-boot/`:

```
996e4cf1b2fc11f0c63938727ad334b760c547dafc7808fd0b84c289dcf1f057  rk3566-353v.dtb
011e38504e6408902a79493f9b96d4e1ff20a8203a3777b46c6077f10f30d84f  rk3566-353v-notimingchange.dtb
```

## Notes

* The selector reads the gamepad by name (`retrogame_joypad`) from
  `/dev/input/event*`, so it does not depend on a fixed event number.
* It accepts A (**304**) or Start (**315**) to apply, B (**305**) or Select
  (**314**) to exit; D-pad codes 544–547 navigate.
* SDL/DRM is not involved: the UI is `show2.elf` in daemon mode, the same
  presenter the AnberNext updater uses.
* Logs: `.userdata/rg353/logs/DTB Selector.txt`.
