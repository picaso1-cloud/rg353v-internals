# 18 — Arch-R (`archr-linux/Arch-R`) upstream analysis + RK3566 device profile

**Created:** 2026-11-20 · **Evidence:** repository contents read directly
(README, `Makefile`, `projects/ArchR/options`, `projects/ArchR/devices/RK3326/*`,
`projects/ArchR/config.xml`, `projects/ArchR/bootloader/mkimage`,
`packages/linux/package.mk`) plus ROCKNIX `next` for the RK3566 reference
values. **Nothing built or booted yet.**

## What it is

> "Arch Linux gaming distribution for handheld devices." Genuine **Arch Linux
> ARM** userland (pacman, systemd, signed repos: stable/next/dev) on top of an
> image pipeline that **descends from LibreELEC → JELOS → ROCKNIX**.

That lineage is the single most important fact for us: **Arch-R's build system
is the same one that produces ROCKNIX**, which already has a working RK3566
target. We are not inventing a port method — we are moving an existing RK3566
device definition from a glibc/read-only distribution into an Arch userland.

## Current coverage (upstream, main branch)

| SoC | Device profiles | Boards |
|---|---|---|
| **RK3326** | `devices/RK3326/` | R36S (+clones), R33S, Odroid Go Advance/Super, RG351V/M, GameForce Chi, MagicX XU10, RGB10 — 15 DTBs in `config.xml` |

That is **all**. No RK3566, no RK3399, no Unisoc/T618. (ROCKNIX-inherited
strings like `RK3566-Generic` in `bootloader/mkimage` are leftovers, not a
working profile.)

## Why it is still the right base for the RG353V

| Feature | What it gives us |
|---|---|
| Arch Linux ARM + pacman + signed repos | Rolling packages, no reflash for userland updates |
| Built-in updater (`archr-update`, ES menu) that also syncs kernel/DTBs | Kernel updates without rebuilding the card |
| `MALI_FAMILY` / `GRAPHIC_DRIVERS="mali panfrost"` / `VULKAN="vulkan-loader"` | panfrost **and** panvk are already first-class options |
| Mainline kernel (`packages/linux` → 6.15.6), `KERNEL_TARGET=Image`, `DTC_FLAGS=-@` | Overlays supported; matches RG353V's mainline DT |
| Board DTB + **panel overlay** separation (`config.xml` → `fdt`/`fdtdir`) | Exactly the model the RG353V needs (v1 0x3052 / v2 0x3821 panels) |
| `bootloader/mkimage` writes u-boot at **sector 64** | Same Rockchip convention as dArkOS/ROCKNIX |

## Anatomy of a device profile (RK3326 is the template)

```
projects/ArchR/
  config.xml                      # <SOC> → subdevice → list of DTBs + fdt_type
  devices/RK3326/
    options                       # CPU, part table, cmdline, u-boot, Mali, Vulkan, drivers
    linux/linux.aarch64.conf      # kernel .config (18x KB, full defconfig)
    linux/dts/                    # board DTBs shipped in the image
    bootloader/                   # boot.scr / u-boot payloads
    packages/                     # device-only packages
    patches/                      # kernel/u-boot patches
Makefile                          # one target per SOC: RK3326: ... ; world: RK3326
```

Build: `make docker-image-build` once, then `make docker-RK3326` → `target/*.img`.

Image layout: `p1 FAT32 ARCHR` (kernel, DTBs, overlays, boot.scr) ·
`p2 ext4 ARCHR_ROOT` · `p3 ext4 STORAGE` (+ `ARCHR_ROMS` exFAT on ≥32 GB cards).

Boot flow: u-boot (SARADC board detect) → `extlinux.conf` → kernel + DTB +
overlay → initramfs resolves root **by label** → systemd → `archr-autostart` →
EmulationStation.

## Work required: add `devices/RK3566`

### 1. `projects/ArchR/devices/RK3566/options`

Values below are taken from **ROCKNIX `next` → `devices/RK3566/options`**
(the configuration proven to run on this exact board family), mapped onto the
field names Arch-R uses:

```
TARGET_CPU="cortex-a55"
TARGET_CPU_FLAGS="+crc+crypto+fp+simd+rcpc"
PARTITION_TABLE="gpt"
HW_CPU="Rockchip RK3566"
KERNEL_TARGET="Image"
EXTRA_CMDLINE="quiet console=ttyS2,1500000 console=tty0 loglevel=7 vt.global_cursor_default=0"
BOOTLOADER="u-boot"
UBOOT_FIRMWARE="rkbin atf"
ATF_PLATFORM="rk3568"
MALI_FAMILY="bifrost-g52"
GRAPHIC_DRIVERS="mali panfrost"
VULKAN="vulkan-loader"
DISPLAYSERVER="wl"
WINDOWMANAGER="swaywm-env"
ADDITIONAL_DRIVERS="mali-bifrost"
DEBUG_TTY="/dev/ttyS2"
ZRAM_COMPRESSION_ALGO="lz4"
```

(`loglevel=7` instead of ROCKNIX's quiet default: during bring-up we want the
panel console — see `17-archr-bringup-plan.md`, S1.)

### 2. `projects/ArchR/devices/RK3566/linux/linux.aarch64.conf`

**Do not start from the RK3326 config.** Take the **ROCKNIX RK3566 kernel
config** as the base — it is the only config known to drive this board's panel,
touch, joypad, audio, Wi-Fi and panfrost. Then:

- `CONFIG_ARCH_ROCKCHIP=y`, `CONFIG_ARM64_ROCKCHIP_DT=y`
- `CONFIG_DRM_PANFROST=y`, `CONFIG_DRM_ROCKCHIP=y`, DSI/panel drivers for
  `newvision,nv3051d` (v1) and `elida,kd35t133` (v2)
- `CONFIG_ROCKCHIP_IODOMAIN`, `CONFIG_PHY_ROCKCHIP_*`, `CONFIG_TYPEC_*`,
  `CONFIG_MMC_SDHCI_OF_DWCMSHC`, `CONFIG_RK8XX_*` regulators/RTC
- shrink to Arch-R's package set if needed (kernel modules land in the rootfs)

### 3. Device trees + `config.xml`

Add an `RK3566` section mirroring ROCKNIX's `Generic` subdevice, but limited to
what we own first:

```xml
<RK3566 dtb_prefix="rockchip">
  <rg353v mkimage_options="dtb,extlinux,uboot" fdt_type="fdtdir" fdt="device_trees">
    <file>rk3566-anbernic-rg353v</file>
    <file>rk3566-anbernic-rg353vs</file>
    <file>rk3566-anbernic-rg353p</file>
    <file>rk3566-anbernic-rg353ps</file>
  </rg353v>
</RK3566>
```

(`fdtdir` + u-boot `$fdtfile` is the ROCKNIX style; alternatively `fdt_type="fdt"`
with one explicit DT — the dArkOS style, and the safer one for S1–S3.)

### 4. `Makefile`

Add the target (pattern is mechanical):

```make
world: RK3326 RK3566

RK3566:
	unset DEVICE_ROOT
	PROJECT=ArchR DEVICE=RK3566 ARCH=aarch64 ./scripts/build_distro
```

(Arch-R's RK3326 target builds both `ARCH=arm` and `ARCH=aarch64`; we only need
aarch64.)

### 5. Package gaps (must be ported from ROCKNIX, same licence family)

`packages/virtual/` in Arch-R has **no `atf`, no `rkbin`, no `u-boot` for
Rockchip**. RK3566 needs, at minimum:

- `rkbin` (DDR init binaries + `bl31`/`bl32` inputs for RK3566/RK3568)
- `atf` with `ATF_PLATFORM=rk3568`
- `u-boot` built as the Rockchip FIT (`u-boot-rockchip.bin` / `uboot.bin`)

This is the biggest unknown and the only part with real porting effort. It is
also **optional for the first boots** — we can boot Arch-R's kernel + rootfs
with dArkOS's proven loader (below).

## The boot-chain rule for *our* unit (non-negotiable)

Every ROCKNIX-based image failed on this RG353V because of the loader, not the
userland (doc `15`). Therefore:

> **Build the Arch-R image, then transplant its userland onto the proven dArkOS
> partition scheme for the first boots.** Do not judge Arch-R by whether its own
> u-boot boots here.

| dArkOS partition (proven) | Arch-R content |
|---|---|
| p1 `uboot` @ 8 MiB, p2 `resource` @ 12 MiB, idbloader @ 32 KiB | **kept byte-identical** |
| p3 `dArkOS_Fat` vfat @ 16 MiB | Arch-R `/Image` + `/rk3566-353v.dtb` + `extlinux.conf` with explicit `FDT` and `root=LABEL=ARCHR_ROOT` |
| p4 ext4 (was btrfs ROOTFS) | Arch-R `ARCHR_ROOT` ext4 |
| p5 exfat `/roms` | kept |

Then S4 (own loader) becomes an *optional* upgrade instead of a prerequisite for
seeing Arch on screen.

## Milestones (map to `17-archr-bringup-plan.md`)

| # | Milestone | Acceptance |
|---|---|---|
| M0 | Clone Arch-R, add `devices/RK3566/options`, get `scripts/build_distro` to accept `DEVICE=RK3566` | build starts, fetches kernel |
| M1 | Kernel + DTBs only (`make package` on linux / manual build) | `Image` + `rk3566-anbernic-rg353v.dtb` produced |
| M2 | Arch-R rootfs built (`ARCHR_ROOT` ext4) | mounts, `pacman -Q` sane |
| M3 | **Transplant card** (table above) → boot on device | Arch boot messages / login / ES on the panel |
| M4 | Own loader (rkbin + atf + u-boot FIT) | boot without dArkOS's loader — *or* accept keeping it |

## Risks

- **u-boot gate** (high): M4 may simply fail like every ROCKNIX image. Mitigation:
  M3 does not need it; keeping dArkOS as the loader is a legitimate end state.
- **Kernel config drift** (medium): start from ROCKNIX's config, not a defconfig.
- **Panel** (low): v2 = 0x3821; mainline handles both, but verify at M3.
- **Input** (medium): RG353V uses `gpio-keys` + `adc-joystick`/vendor joypad —
  confirm mapping at M3.
- **Wi-Fi** (medium): RG353V uses a Rockchip/AIC-class module; `ADDITIONAL_DRIVERS`
  + firmware needed (verify exact chip from dArkOS's `lsmod`/`dmesg` when the
  card is back in the laptop).
- **Time/disk** (high): ~40 GB and hours per full image build; build kernel
  first, image last.

## Next action

`git clone --filter=blob:none https://github.com/archr-linux/Arch-R` → add
`devices/RK3566/options` + `config.xml` entry → confirm the build system picks
the device up (`DEVICE=RK3566 ./scripts/build_distro` dry start). No device
time required.

---

## Reuse from our other device repos (checked on GitHub 2026-11-20)

We already own the two pieces Arch-R considers its "architecture". Do not
rebuild them:

| Our asset | Repo / path | What it gives this port |
|---|---|---|
| **ROCKNIX→device port methodology** (board auto-detect via ADC/HWREV, overlay-only iteration, no image rebuild) | `rgb10max2-internals/11-rocknix-rk3326-port.md` | The exact template for RG353V: ROCKNIX's RK3566 u-boot already maps SARADC **695 → RG353V**; the same "boot.scr/ADC → fdtfile" mechanism Arch-R uses on RK3326 |
| **Bootable-overlay installer** (backs up `extlinux.conf`, adds `FDTOVERLAYS`, revertible) | `rgb10max2-internals/dts/apply-rocknix-max2.sh` + `dts/rk3326-rgb10max2-keys-overlay.dts` | Direct model for a `rk3566-rg353v-panel.dtbo` + apply script; same one-file iteration discipline as plan S1 |
| **DTB→panel-overlay converter** (Go, ships base DTBs for R36S/EE/SoY, extracts panel/audio/LED/PMIC wiring from a stock DTB) | `andr36oid_sdflasher/internal/dtbconv/` (`bases/SOURCES.txt`, `convert.go`) | This is functionally **Arch-R's online overlay generator**. For RG353V: feed it the stock dArkOS/Android panel node (v1 `0x3052` / v2 `0x3821`) and emit `mipi-panel.dtbo` — no hand-written panel timings |
| **RK3326 hard-won detail: A/B swap, joypad codes, rk817 OTG latch, panel lanes** | `rgb10max2-internals/11-rocknix-rk3326-port.md` §2–§4 | RK3566 is a different SoC but the *class* of problems (button codes, PMIC rails, panel lane count) and the fix technique (overlay `linux,code`, DT regulator) are identical |
| **Card flashing tool (Go + Android app, catalog/update aware)** | `andr36oid_sdflasher` | Candidate flasher for Arch-R images later; `internal/dtbconv` is the immediately useful part |

### Consequence for the work plan

- **Do not write a panel node by hand.** Generate the overlay with `dtbconv`
  from the stock DTB, exactly as Arch-R does for RK3326 boards.
- **Do not invent board detection.** Reuse ROCKNIX's RK3566 u-boot SARADC table
  (already validated for this unit: **695**), which is what Arch-R's `boot.scr`
  equivalent needs.
- **Iteration stays at one file** (`/Image`, a `.dtb`, or a `.dtbo`), never a
  full 40 GB rebuild — the Max 2 doc proved that workflow on RK3326 hardware.

### Repo housekeeping

Superseded material is indexed (not deleted) in
[`docs/ARCHIVE.md`](docs/ARCHIVE.md).

---

## Prior art in our own workspace (found 2026-11-20)

Arch-R was **already cloned and attempted** on the RGB10 Max 2 — the workspace
was sitting outside the project root (`~/rgb10max2-archr`, now
`~/Andr36oid/rgb10max2-archr/`, with a compatibility symlink). It is recorded in
`rgb10max2-internals/12-archr-port-2026-11.md`. What it changes for us:

| Lesson | Consequence for the RG353V port |
|---|---|
| `make docker-RK3326` **fails at `cmake:host`** (four attempts) | Do **not** start with a full image build. Assume the build chain needs work first; budget for it only at M4 |
| Device work was delivered by **patching a released image** (`make-rgb10max2-image.sh`, `make-rgb10max2-overlay-image.sh`) | Adopt the same for M3: patch the official Arch-R image with our kernel/DTB/overlay/quirks instead of building |
| Device hacks live in `packages/hardware/quirks/devices/<Device>/NNN-*` | RG353V fixes go there (panel, joypad, rails), not into a hand-edited rootfs |
| Board detection = **ADC range in `boot.ini`** (`clone_boot.ini` 60–110) | Same scheme on RK3566: ROCKNIX's SARADC table already has RG353V = **695** |
| "Driver present" ≠ "hardware powered" (RK817 OTG latch for Wi-Fi) | Check regulators/rails first when something is silent on RK3566 |
| Separate `…-DEBUGPROBE.img` variant with its own key | Cheap pattern for instrumented bring-up images — reuse at S3 |

**Workspace rule (2026-11-20):** all device data now lives under
`~/Andr36oid/` (`rg353v-backup`, `rg405v-backup`, `rg405v-gammaos`,
`rg405v-apks`, `rgb10max2-archr`, `toolchains`); the old `~/<name>` paths are
symlinks, so existing documents and scripts keep working.
