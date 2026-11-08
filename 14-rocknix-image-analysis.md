# 14 — ROCKNIX RK3566 image: offline analysis (Stage 1)

Offline teardown of the **correct** ROCKNIX image for the RG353V, done without
hardware. This supersedes the earlier assumption that the `Specific` image was
the right one, and corrects two claims in `13-archr-rk3566-plan.md`.

**Date:** 2026-11-08 · **Image:** `ROCKNIX-RK3566.aarch64-20261101-Generic.img.gz`

---

## TL;DR

> **Decision (2026-11-08): documentation-only for now.** No card is being
> flashed and no device will be modified. This document is the reference for a
> future ROCKNIX experiment; the hardware steps remain valid but unexecuted.

1. **Wrong image was downloaded first.** The RG353V is in the **Generic**
   RK3566 image; `Specific` is only for Powkiddy X55/X35S and Anbernic RG DS
   (plus RG DS Plus). Generic has been downloaded and checksum-verified.
2. **ROCKNIX is already the modern stack** the "Arch-R" idea was meant to get:
   glibc **2.44**, Mesa **26.2.4** (panfrost + panvk Vulkan), kernel **7.2.11**,
   **sway** compositor, EmulationStation. No Arch-R port is needed for the
   "make everything smoother" goal.
3. **ARMSX2 is preinstalled** (`/usr/share/armsx2-sa/armsx2-qt` +
   `/usr/bin/start_armsx2.sh`), with PS2 BIOS/savestate plumbing. The PS2 games
   already on the ArkOS SD (`/roms2/ps2`) can be used directly.
4. **Boot model (verified device behavior, corrected 2026-11-08):** the RG353V
   has **two OS modes and two SD slots**:
   - **TF1** = OS card. A bootable card in TF1 has **boot priority**; the
     console boots it directly (Linux *or* Android on TF1).
   - **eMMC** = the built-in OS (currently GammaOS Android); it boots only when
     there is no bootable OS card in TF1.
   - **TF2** = ROMs/media card only (no OS boot).

   So ROCKNIX on a TF1 card should boot directly, **with GammaOS Android left
   untouched on the eMMC**. Removing the TF1 card boots Android again. The
   ROCKNIX wiki note ("wipe Android on P/M/V") is a caveat for some
   units/bootloader revisions — **not** the normal behavior of this unit, and
   not verified here. It is a fallback only if the TF1 boot actually fails.
5. **Panel variant is v2 on this unit** (ID `0x3821`), which ROCKNIX's u-boot
   auto-detects and the kernel supports. The vendor GammaOS DTB's active panel
   node is `elida,kd35t133` at 640×480 — not the earlier "elida = the only
   panel" reading.

---

## 1. Image identity (verified)

| Item | Value |
|---|---|
| Release | `20261101` (ROCKNIX `next`) |
| File | `ROCKNIX-RK3566.aarch64-20261101-Generic.img.gz` |
| Compressed size | 1,428,514,539 B (1.33 GiB) |
| SHA-256 (gz) | `b573c9656d85bca5fa1aba038aac6cfabd92345d28a55cd74725cc98c618c775` |
| Raw image | 2,198,863,872 B (2.05 GiB) |
| MD5 (raw) | `6419f3081571cefeb00df8b0a82d58e8` |

The earlier `Specific` image was deleted from `dist/` to avoid flashing the
wrong one. The two images share the **same KERNEL and SYSTEM** (identical
`KERNEL.md5`/`SYSTEM.md5`); only the bootloader and `extlinux.conf` differ.

### Partition layout (GPT)

| # | Start | Size | FS/Label | Role |
|---|---|---|---|---|
| — | sector 0 | 16 MiB | raw | Rockchip idbloader + U-Boot |
| 1 | 32768 (16 MiB) | 2 GiB | FAT32 `ROCKNIX` | `KERNEL`, `SYSTEM`, `device_trees/`, `extlinux/`, `overlays/` |
| 2 | 4227072 | 32 MiB | ext4 `STORAGE` | grows to fill the card on first boot (`.please_resize_me`) |

---

## 2. Boot chain (Stage 1 capture)

| Offset | Component | Notes |
|---|---|---|
| `0x8000` (32 KiB) | `idbloader.img` | `RKNS` magic; TPL (DDR init) + SPL |
| `0x36EC0` (224,960) | **embedded SPL device tree** | extracted to `survey/rocknix/spl-rk3566.dtb` |
| `0x800000` (8 MiB) | `u-boot.itb` | **U-Boot 2026.01** (Nov 01 2026) |
| 16 MiB | FAT `ROCKNIX` | extlinux boot |

SPL DT (verified by decompile):

```
compatible = "anbernic,rg353p", "rockchip,rk3566";
model = "Anbernic RG353P";
chosen {
    u-boot,spl-boot-order = "/mmc@fe2b0000", "/mmc@fe310000";
};
```

`fe2b0000` = SDMMC0 (SD/TF slot), `fe310000` = SDHCI (eMMC) → **SPL order is
SD first, eMMC second**, which matches the verified TF1-priority boot model in
§4.

`extlinux/extlinux.conf` (Generic):

```
LABEL ROCKNIX
  LINUX /KERNEL
  FDTDIR /device_trees
  APPEND boot=LABEL=ROCKNIX disk=LABEL=STORAGE quiet console=ttyS2,1500000 \
         console=tty0 systemd.debug_shell=ttyS2
```

`FDTDIR` (not a fixed `FDT`) is the key Generic-image difference: U-Boot picks
the DTB at runtime from `device_trees/` after detecting the board.

### U-Boot board detection (Generic)

The Generic U-Boot is U-Boot's **Anbernic `rgxx3_rk3566` board code**, not the
Quartz64 generic build used by `Specific`. It detects the model and the panel
over SARADC/DSI ID and then loads the matching DTB:

| ADC | Model | DTB |
|---|---|---|
| 695 | **Anbernic RG353V / RG353VS** | `rk3566-anbernic-rg353v(s).dtb` |
| 517 | RG353M | `rk3566-anbernic-rg353p.dtb` |
| 860 | RG353P / RG353PS | `rk3566-anbernic-rg353p(s).dtb` |
| 383 | Powkiddy RGB30 | `rk3566-powkiddy-rgb30.dtb` |
| … | … | (16 DTBs present incl. RGB10 Max 3, RGB20 Pro, X55, X35S) |

Panel detection (DSI ID register):

| Panel ID | Compatible written into the DT | Variant |
|---|---|---|
| `0x3052` | `anbernic,rg353p-panel` + `newvision,nv3051d` | v1 |
| `0x3821` | `anbernic,rg353v-panel-v2` | v2 |

**This unit is v2** — the GammaOS vendor DTB has the active panel node
`panel@1` with `id = [38 21]` (0x3821) and `elida,kd35t133` at 640×480. The
ROCKNIX 7.2.11 kernel image contains all three compatibles
(`anbernic,rg353p-panel`, `anbernic,rg353v-panel-v2`, `elida,kd35t133`), so v2
is covered end-to-end. (Correction to doc 13: the vendor DTB also has
`panel@0` = `aoly,sl008pa21y1285-b00`, ID 0x3052; the two nodes are the v1/v2
variants, selected by ID.)

---

## 3. Userland inside SYSTEM (squashfs, zstd, 1.4 GB)

| Component | Version / path |
|---|---|
| glibc | **2.44** (`/usr/lib/libc.so.6`) |
| Mesa | **26.2.4** (`libgallium-26.2.4.so`, `panfrost_icd.aarch64.json`, `mali.json`) |
| Kernel | **7.2.11** (GCC 16.2.0), uncompressed arm64 `Image`, **embedded LZO initramfs** |
| Modules | 290 `.ko` under `/usr/lib/kernel-overlays/base/lib/modules/7.2.11`; `/usr/lib/modules` → `/run/kernel-overlays/modules` at runtime |
| Compositor | **sway** (kiosk config for ES; `xdg_wm_base` present — the thing weston 5 on ArkOS lacked) |
| Frontend | EmulationStation |
| PS2 | **ARMSX2 preinstalled**: `/usr/share/armsx2-sa/armsx2-qt` (17 MB) + `resources/`, `/usr/bin/start_armsx2.sh`, `cheevos_armsx2.sh`, PCSX2.ini templates |

`start_armsx2.sh` creates `/storage/.config/ARMSX2/`, `/storage/roms/bios/armsx2/`
and `/storage/roms/savestates/ps2/`, and reads EmulationStation per-game
settings (aspect ratio, filtering, FPS, EE cycle rate). No AppImage, no glibc
bundling, no compositor hacks — the whole `12-ps2-linux-investigation.md`
workaround chain is unnecessary on ROCKNIX.

### RG353V device quirks (shipped)

`/usr/lib/autostart/quirks/devices/Anbernic RG353V/`:

- `001-device_config`: `DEVICE_FAKE_JACKSENSE=true`,
  `DEVICE_HEADPHONE_DEV=/dev/input/by-path/platform-rk817-sound-event`,
  `DEVICE_HAS_TOUCHSCREEN=true`
- `020-gpios`: `DEVICE_WIFI=5`, `DEVICE_LED=77`, `DEVICE_PWM_MOTOR=pwmchip1`,
  `DEVICE_JACK=86`; exports PWM and parks rumble off at boot
- `040-display`: brightness/contrast/saturation/hue via `drm_tool` (connector 133)
- `050-audio_path`: `ALSA_PRIMARY_CARD=1`, SPK/HP paths
- `info.d/001-panel`: `dmesg | grep panel` → `newvision` = v1, `sitronix` = v2

---

## 4. Boot model — two OS modes, two SD slots (verified behavior)

The RG353V boots like this:

| Slot / medium | Role | Boot priority |
|---|---|---|
| **TF1** (microSD, first slot) | OS card: Linux **or** Android | **First** — if a bootable OS card is present, it boots from it |
| **eMMC** (32 GB) | Built-in OS (currently GammaOS Android) | Fallback — boots only when TF1 has no bootable OS |
| **TF2** (microSD, second slot) | ROMs/media only | Never boots |

So the safe experiment is exactly the simple one:

1. Flash ROCKNIX **Generic** to a TF1 card.
2. Insert it in TF1 and power on → the console boots ROCKNIX.
3. Remove the TF1 card and power on → the console boots **GammaOS Android on
   the eMMC**, untouched.
4. TF2 keeps the ROM/BIOS card (e.g. `/roms2/ps2`), available to whichever OS is
   running — no need to reflash or wipe anything.

### Caveat (unverified on this unit)

The ROCKNIX wiki says P/M/V users must wipe the Android partition, and some
community reports match that on certain units/bootloader revisions. That does
**not** describe this device's normal TF1-priority behavior and has **not** been
observed here. Treat it as a fallback **only if** a TF1 ROCKNIX card actually
fails to boot; the first thing to check then is whether the card is bootable and
correctly flashed, not the eMMC.

### If a TF1 boot ever fails

| Fallback | What it means |
|---|---|
| Re-check the card | Correct Generic image, verified hash, proper `dd` + `sync`, good A2 card |
| Verify the panel/DTB | U-Boot should pick `rk3566-anbernic-rg353v.dtb`; v2 panel = ID 0x3821 |
| Last resort: eMMC wipe | Destructive, documented by ROCKNIX; requires a GammaOS/SDDiskTool restore card to get Android back. Not planned. |

For the record, an optional R&D path (legacy chainload) was considered earlier;
it is **not needed** under the verified TF1-priority model and is not part of the
plan.

---

## 5. Consequence for the "Arch-R for RK3566" plan

**Building Arch-R for RK3566 is no longer the shortest path to the goal.**

- The user's goal was "a modern stack so everything is smoother, including
  ARMSX2". ROCKNIX already delivers glibc 2.44, Mesa 26.2.4, panfrost/panvk,
  sway, kernel 7.2.11 — i.e. the *outcome* of an Arch-R port.
- Arch-R's value would be `pacman`/rolling packages, not performance. That is a
  much smaller (and optional) benefit, and it still needs the same RK3566 board
  work.
- Therefore: **Stage 0/1 = validate/use ROCKNIX**. Only pursue a custom Arch-R
  RK3566 port if the user specifically wants pacman/Arch packaging.

Revised stage view:

| Stage | Old plan | Revised |
|---|---|---|
| 0 | flash Specific, validate | flash **Generic**, validate; first decide A/B/C (§4) |
| 1 | capture boot chain | **done offline** (this doc) + finish the ArkOS legacy-capture (§4) on hardware |
| 2 | Arch rootfs hybrid | optional/unnecessary |
| 3 | upstream Arch-R RK3566 port | optional, only for pacman/rolling; not for speed |

---

## 6. Flash recipe (when a card and a decision are available)

```sh
cd dist
sha256sum -c <<'EOF'
b573c9656d85bca5fa1aba038aac6cfabd92345d28a55cd74725cc98c618c775  ROCKNIX-RK3566.aarch64-20261101-Generic.img.gz
EOF
gzip -dk ROCKNIX-RK3566.aarch64-20261101-Generic.img.gz
# triple-check the device before writing:
lsblk
sudo dd if=ROCKNIX-RK3566-Generic.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

First boot expands `STORAGE` to fill the card. Keep the card A2/quality class
(same advice as the RGB10 Max 2 guide). Put the card in **TF1**; Android on the
eMMC is untouched and boots again when the TF1 card is removed. Keep ROMs/BIOS
on the **TF2** card.
