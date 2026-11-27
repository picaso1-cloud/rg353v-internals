# 35 — RG353V panel v2: the black/white lines and the DTB fix

**Date:** 2026-11-27 · **Status:** verified on hardware · **Scope:** RG353V
panel variants under mainline ROCKNIX.

---

## 1. Symptom

With the dual-boot chain fixed, ROCKNIX's kernel started (SSH reachable, WiFi
up, D-pad moving the UI) but the panel showed **vertical black/white lines** —
a panel that gets a DSI clock but no valid init sequence.

## 2. Root cause: the DTB declared the wrong panel

ROCKNIX's `rk3566-anbernic-rg353v.dtb` declares **only the v1 panel**:

```
dsi@fe060000 {
    panel@0 {
        compatible = "anbernic,rg353p-panel", "newvision,nv3051d";
        …
    };
};
```

and the kernel bound the matching driver:

```
panel-newvision-nv3051d fe060000.dsi.0: Looking up vdd-supply …
```

This unit is **v2**. The vendor (Android/dArkOS) DT proves both variants exist
and are selected by a panel ID read over DSI:

| node | compatible | id |
|---|---|---|
| `panel@0` | `aoly,sl008pa21y1285-b00` | `0x3052` |
| `panel@1` | `elida,kd35t133` | `0x3821` |

ROCKNIX's kernel ships the v2 driver — the alias is visible in
`modules.builtin.modinfo`:

```
panel_sitronix_st7703.alias=of:N*T*Canbernic,rg353v-panel-v2
```

So the hardware wants `anbernic,rg353v-panel-v2` → `panel-sitronix-st7703`.

## 3. The fix (one property, on the boot partition)

```sh
# on the laptop
cp rk3566-anbernic-rg353v.dtb rk353v-v2.dtb
fdtput -t s rk353v-v2.dtb /dsi@fe060000/panel@0 compatible \
        "anbernic,rg353v-panel-v2"
fdtget rk353v-v2.dtb /dsi@fe060000/panel@0 compatible   # verify

# on the device /flash is mounted ro
mount -o remount,rw /flash
cp -f /flash/device_trees/rk3566-anbernic-rg353v.dtb \
      /flash/device_trees/rk3566-anbernic-rg353v.dtb.orig
cp /tmp/rk353v-v2.dtb /flash/device_trees/rk3566-anbernic-rg353v.dtb
sync
mount -o remount,ro /flash
reboot
```

The original file stays as `.orig` next to it; the extlinux entry
(`/extlinux/extlinux.conf` → `FDT /device_trees/rk3566-anbernic-rg353v.dtb`)
needs no change.

## 4. Verification

```
panel-sitronix-st7703 fe060000.dsi.0: 640x480@60 24bpp dsi 4dl - ready
/sys/class/drm/card0-DSI-1/status: connected
/sys/class/drm/card0-DSI-1/modes : 640x480
```

GLES then reports `Mali-G52 r1 MC1 (Panfrost)` (see
`36-rocknix-mainline-validation.md`).

## 5. A second bug in the image: the wrong DTB in extlinux

The ROCKNIX image as flashed pointed the boot entry at
`rk3566-powkiddy-x55.dtb`. It must be the RG353V tree:

```
LABEL ROCKNIX
  LINUX /KERNEL
  FDT /device_trees/rk3566-anbernic-rg353v.dtb
  APPEND boot=LABEL=ROCKNIX disk=LABEL=STORAGE quiet …
```

## 6. The flicker / "shadow" afterwards (not the driver)

After the panel came up there was still a flicker and a faint ghost of the
earlier black/white pattern. Evidence:

| Observation | Conclusion |
|---|---|
| Android (vendor `panel-simple-dsi`) flickered the same way | not the OS driver |
| backlight PWM = `0x61a8` ns = **40 kHz** in both ROCKNIX and vendor DTBs | not PWM flicker |
| no DSI errors, no VOP underruns, `dclk_vop1` steady at 24.15 MHz | not the link |
| battery was **3.66 V / 44 %** at the time | rail sag candidate |
| a long power-off (+ full charge) removed it | retention/rail, not software |

So: a real power-off (and charge) is the first thing to try; if it survives a
full off at 100 %, the panel/FPC is the suspect, not the kernel.

## 7. Notes for the other units

* A **v1** unit keeps the original DTB (`anbernic,rg353p-panel` + `nv3051d`).
* A v2 unit needs the property above (or, better, a DTB that carries both
  nodes plus an ID-based selection — upstreamable idea).
* The vendor `panel-simple-dsi` node also carries the full
  `panel-init-sequence`; mainline drivers use their own sequences, which is
  why changing the `compatible` is the correct (and sufficient) fix.
