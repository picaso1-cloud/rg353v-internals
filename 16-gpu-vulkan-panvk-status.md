# 16 — GPU / Vulkan status on the RG353V (G52): vendor blob vs panvk/panfrost

Question (2026-11-20): can the RG353V get **Vulkan (panvk/panfrost)** and
updated drivers on dArkOS / ROCKNIX / a future Arch port?

## Hardware

RG353V GPU = **Mali-G52 MP2** (Bifrost family, 2nd-gen, r8p0-class). Vulkan
options for Bifrost G52:

1. **ARM vendor blob** (`libmali` Bifrost with Vulkan) — what Rockchip BSPs ship
2. **Mesa panvk** — open-source Vulkan driver for Bifrost/Valhall, runs on the
   **mainline panfrost kernel driver** (needs kernel ≥ 5.9-ish; realistic use
   from 6.x; best from 6.12+/7.x)

## dArkOS v11072026 (current OS): vendor Vulkan 1.3 — COMPLETE ✅

| Piece | Finding |
|---|---|
| Kernel | 5.10.226 Rockchip BSP — `CONFIG_MALI_BIFROST=y` (+DEVFREQ, GATOR) built-in |
| Userspace | `libmali-bifrost-g52-g29p1.so` (in `/usr/lib/aarch64-linux-gnu/`) — **440 exported `vk*` symbols**, "ARM vulkan DRM display" strings |
| ICD | `/usr/share/vulkan/icd.d/rk_vk.json` → **api_version 1.3.276** |
| Mesa | Debian Trixie Mesa present but the G52 GL path is the same libmali blob (no panfrost_dri needed) |

**Test on device:** `vulkaninfo --summary` / `vkcube` (install
`vulkan-tools`) — expect "Mali-G52" via the vendor ICD.
**Caveats:** vendor libmali Vulkan = limited feature set (no
geometry/tessellation, GLES-leaning); some libretro Vulkan cores may work,
others not. It is still real hardware Vulkan 1.3.

## PanVK / Panfrost (open-source) on the RG353V

- **Mainline support exists**: `rk3566-anbernic-rg353v.dts` is upstream;
  panel drivers `nv3051d` (v1) + `elida,kd35t133` (v2) upstream; panfrost
  G52 GL is proven on rk3566 boards (Quartz64 family).
- **PanVK on G52**: Bifrost support in Mesa panvk (experimental tier) since
  Mesa 23.2, improving in 24.x/25.x/26.x. Requires the **mainline panfrost
  kernel driver** — the dArkOS 5.10 BSP kernel does **not** ship it, so
  **panvk is not available on dArkOS as-is**.
- **ROCKNIX 20261101 ships the full open-source stack**: kernel **7.2.11**
  with `panfrost.ko`, Mesa with `panfrost_dri.so` (GL),
  `libvulkan_panfrost.so` + `panfrost_icd.aarch64.json` (Vulkan) and
  `00-panvk-defaults.conf` — **but ROCKNIX 20261101 does not boot on this
  unit** (loader rejection, see `15-darkos-migration.md`).

## The bridge: splice hybrids (built, untested)

`rg353v-backup/images/`:
- `hybridA-dArkOS-idbloader_ROCKNIX.img.gz` — dArkOS idbloader (sectors
  64–8191: proven DDR init + SPL) spliced over ROCKNIX (whose u-boot FIT at
  8 MiB is untouched; SPL convention = u-boot @ 8 MiB on both).
- `hybridB-dArkOS-fullloader_ROCKNIX.img.gz` — dArkOS loader region
  (sectors 64–32767: idbloader + dArkOS u-boot FIT + resource) spliced;
  dArkOS u-boot would then need to find ROCKNIX's `extlinux.conf` in the
  vfat (ArkOS-lineage u-boot scans extlinux — plausible).

Flash either to TF1 (Etcher-free: `gunzip` → `dd`), test, and:
- **If hybrid boots → ROCKNIX becomes viable on this unit**, bringing
  kernel 7.2.11 + panfrost + panvk-era Mesa = the open-source Vulkan path.
  Report the working splice upstream (ROCKNIX issue: "RG353V v2 0x3821 panel
  unit fails with 20261101 Generic idbloader; dArkOS idbloader works").
- **If not** → the incompatibility is deeper than the loader (then dArkOS
  stays, and panvk waits for a mainline-kernel dArkOS variant or the Arch
  port below).

## Arch port relevance (`13-archr-rk3566-plan.md`)

An Arch(-R-style) RK3566 port would inherit exactly this decision: **boot
chain** (dArkOS/ArkOS loader = safe) + **kernel choice**:
- vendor BSP 5.10/6.1 → libmali blob, no panvk
- mainline 6.12+/7.x → panfrost GL + panvk Vulkan (open path), needs RG353V
  panel DTB care (v1 0x3052 / v2 0x3821)

## Bottom line

| Path | Vulkan | Status on this unit |
|---|---|---|
| dArkOS + vendor blob | **Vulkan 1.3 (limited)** | ✅ shipped, test with vulkaninfo |
| ROCKNIX + panfrost/panvk | Vulkan (open, experimental) | ❌ doesn't boot; splice hybrids built |
| Arch port (future) | depends on kernel choice | scaffold only (`13-archr-rk3566-plan.md`) |

## hybridD — the Rockchip-GUID discovery (2026-11-20, flashed, testing)

Comparing the GPT of the **working dArkOS card** vs every failing ROCKNIX-based
card exposed the missing piece: Rockchip vendor partition types/names.

| | dArkOS (boots) | all ROCKNIX variants (failed) |
|---|---|---|
| p1 | type `A60B0000-0000-4C7E-8000-015E00004DB7` name "uboot" | generic Linux type |
| p2 | type `D46E0000-0000-457F-8000-220D000030DB` name "resource" | generic Linux type |
| p3 | name/fs-label "dArkOS_Fat" | "system"/"ROCKNIX" |

hybridD = dArkOS loader + **dArkOS-identical GPT** (same types, names, disk
GUID `31AAB98C…`) + ROCKNIX kernel/dtb under both naming schemes + explicit
`FDT` + 20 GiB STORAGE + fs label `dArkOS_Fat` (`boot=LABEL=dArkOS_Fat`) —
flashed and byte-verified (cmp, 0 diffs). Testing on device.

**Process lesson:** stop laptop-side re-verification loops once `cmp` passes —
hand the card to the device; a device boot is the only meaningful test.
