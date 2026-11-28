# PROJECT STATUS — Handhelds (compaction checkpoint)

**Date:** 2026-11-12 · **Purpose:** complete cross-project state so context can
be compacted and work resumed from this file alone. Mirrored in the device repos.

> **Start here:** `MASTER-PLAN.md` (goals, shared architecture, roadmap) ·
> `SHARED-KNOWLEDGE.md` (reusable findings) · `docs/DECISIONS.md` ·
> `docs/RE-METHOD.md` · per-device repos below.

---

## Session recap — 2026-11-28 — RG353V Linux track is feature-complete

**The RG353V is done on the Linux side.** ROCKNIX 20261101 (kernel 7.2.11)
boots from TF1 through the patched eMMC chain, the v2 panel is fixed, and
Panfrost/PanVK are validated. The record: `34` (chain), `35` (panel), `36`
(mainline validation + GPU A/B), `37` (tuning/resources).

### Verified on hardware (2026-11-27 → 28)
- **Dual-boot:** card in → Linux, card out → Android; no Android partition
  was ever wiped. The card's own bootloader was restored to a safe fallback
  and the eMMC patch is a documented tool (`tools/emmc-chain/`).
- **Panel:** `anbernic,rg353v-panel-v2` → `panel-sitronix-st7703`, 640×480@60;
  the residual flicker was power/retention, gone after a long power-off.
- **GPU:** Panfrost (GLES 3.1, `glmark2` 613) and PanVK (Vulkan 1.0.354,
  `vkmark` 628) behind `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`; libmali for
  comparison: GLES 3.2 / 577, Vulkan 1.3.276 / 747. The driver is global.
- **Remote:** Wi-Fi (iwd) + SSH persist via `system.cfg` (`ssh.enabled`,
  `wifi.enabled`), `sshd.conf` `SSH_ARGS`, `/storage/.cache/ssh` keys.

### Tuning applied
- **zram 512 MB lz4 + `vm.swappiness=100`** via `rocknix-memory-manager`
  (`/storage/.config/swap.conf`, applied by the service at boot).
- Idle governors left at `ondemand` / `simple_ondemand`: `runemu.sh` already
  switches to `performance` for every game and restores on exit, so pinning
  it only heats the menu (measured: 143 → 184 MB, 16.9 → 24.5 % CPU, 45 → 55 °C).
- ES weight analysed: 143–184 MB / 16–24 % CPU, driven by the theme's
  **video previews** (`showVideoAtDelay=10`); "close ES when RAM is tight" is
  only safe as **freeze** (games are `StopPropagatedFrom=essway.service`).
- Undervolt overlays exist but are **not applied** by our chain (stock
  `sysboot` ignores `/overlays`); merge with `fdtoverlay` if wanted.

### Next
1. Optional: ES video previews off, freeze-ES-during-game watchdog, undervolt.
2. **Android refresh:** evaluate **GammaOS Next / andr36oid** on the latest
   Android releases for the RG353V, using the eMMC 16 MiB backup + the
   card-based `dd` restore path as the rollback net (docs `33`, `34`).

---

## Session recap — 2026-11-27 (evening) — MAINLINE + DUAL-BOOT WORKING

**The mainline phase is unblocked and validated on the RG353V.** ROCKNIX
20261101 (kernel **7.2.11**) boots from TF1 with the **eMMC Android left
installed and bootable**; card out → Android. The eMMC boot chain was patched
so it hands off to the card's extlinux, and the v2 panel was fixed. Full
records: `34-emmc-dualboot-chain.md`, `35-rg353v-panel-v2-fix.md`,
`36-rocknix-mainline-validation.md`; tool: `tools/emmc-chain/`.

### The boot-chain answer (why the wiki says "wipe Android")
- The BootROM is **eMMC-first**: the card's own u-boot never runs while Android
  is installed. Proof: replacing the card's own `bootcmd` with `reset` still
  booted Android.
- The stock eMMC u-boot FIT (8 MiB, duplicate at 10 MiB, uncompressed, sha256
  per image, no signature) has a **5 467-byte default `bootcmd`** at
  `0xbfc50`. It was replaced (same length + hash records recomputed) with:
  *find `/extlinux/extlinux.conf` on TF1 p3 → write marker → set
  `kernel_addr_r=0x2000000` → `sysboot` → marker → fall back to
  `boot_fit; boot_android mmc 0`*.
- Two traps found on the way: this u-boot needs a **leading `/`** in
  `test -e mmc 1:3 …`, and `rkimgtest` checks **LBA 64 (RKNS)**, not a
  "resource partition".
- Reversible: the 16 MiB eMMC backup restores everything; Android data was
  never touched.

### The display answer
- The DTB shipped the **v1** panel (`newvision,nv3051d`); this unit is **v2**
  (`anbernic,rg353v-panel-v2` → `panel-sitronix-st7703`). One `fdtput` on
  `/flash/device_trees/rk3566-anbernic-rg353v.dtb` fixed it (original kept as
  `.orig`). The image also shipped the wrong DTB in extlinux
  (`powkiddy-x55` → `anbernic-rg353v`).
- The flicker/"shadow" that followed was **not** the driver (Android did it
  too, PWM is 40 kHz, no DSI errors): a long power-off + charge cleared it.

### GPU validated
- `gpu.driver=panfrost` → Panfrost binds (`Mali-G52 r1 MC1`), GLES 3.1 Mesa
  26.2.4; `glmark2` **613**.
- PanVK (Vulkan 1.0.354) works behind `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`
  (`vkmark` **628**); `mali.json` is a 0-byte file in panfrost mode.
- SSH/Wi-Fi were disabled by settings (`ssh.enabled=0`, `wifi.enabled=0`) —
  enabling them in `system.cfg` (plus the `sshd.conf` `SSH_ARGS` file and the
  `/storage/.cache/ssh` host keys) is the persistent fix.

### Open
- A/B benchmark libmali vs panfrost; a real dual-boot selector (button or
  marker) instead of card presence; the ARCH-R-userland-on-7.2 "merge"
  decision; package the chain patch (done) and document the panel/boot
  work upstream (ROCKNIX quirks).

---

## Session recap — 2026-11-27 (day) — Arch-R verified

**The image boots on hardware and works.** Buttons, volume, Wi-Fi (with the
Settings page), the TF2 ROM card and the touch panel are all verified on the
device. The full record is `32-update-regressions-and-fixes.md`.

### The five causes behind "it booted, then went black"
1. **The PI2 futex.** libpulse's `pa_threaded_mainloop` asks for
   `PTHREAD_PRIO_INHERIT`; glibc 2.40 answers with `FUTEX_LOCK_PI2`, a syscall
   that needs **Linux 5.14** — the 5.10 BSP kernel answers `ENOSYS`, glibc
   aborts ("The futex facility returned an unexpected error code."). Every
   pulse client died: the launcher (black screen), `archr-levels` (the volume
   daemon) and with it `input_sense` (every button).
   **Fix:** `tools/archr-port/pi2_compat.c` — a 2 KB, libc-free preload shim
   that answers the request with `PTHREAD_PRIO_NONE`. Verified: volume
   75→77→79→77, launcher stable, pulse sink 64%.
2. **The package update reverted the port's patches** (`SDL_AUDIODRIVER=alsa`
   in `archr-launcher-session`, the `rewrite_config` fix in
   `/etc/profile.d/001-functions`) because those files belong to the archr /
   archr-launcher packages. **Fix:** `rg353v-port-doctor` + a pacman hook
   (`99-rg353v-port.hook`) + `rg353v-port.service` (runs at boot too).
3. **iwd was masked**, but the launcher's Settings page and `wifictl` speak
   iwd — the network list came up empty. With the `SaeDisable=...,8821cs`
   quirk iwd associates and scans fine, so iwd is unmasked/enabled, the DHCP
   unit waits for iwd, and wpa_supplicant is the fallback only. The `.psk`
   files must live in `/storage/.cache/iwd/` (the `/var/lib/iwd` bridge).
4. **The TF2 card** carries the ArkOS layout (system folders at the card
   root, 221 GB / 86k files) but roms2 pointed at `<card>/roms` (empty).
   **Fix:** `rg353v-roms2.sh` + `rg353v-roms2.service` — 5 → 130 systems.
5. **The touch panel works but had no pointer.** 830 events on a tap
   (cst3xx, ABS_MT, 0..639 × 0..479) — note TurboRelic reports
   IRQs-without-events on mainline/Batocera, so this is BSP-driver specific.
   libinput gives the seat no pointer, so the UI and the emulators that take
   a mouse could not use it. **Fix:** `rg353v-touch-mouse.py` +
   `rg353v-touch-mouse.service` — a **relative** pointer on `/dev/uinput`
   (this vendor kernel: `UI_SET_*BIT` takes the value not a pointer,
   `input_id` is first in `uinput_user_dev`, and the absmin/absmax arrays are
   ignored → an absolute device gets 0..0 and libinput drops it).
   Verified: libinput `Capabilities: pointer`, sway has a pointer, tap =
   BTN_LEFT + REL_X/REL_Y.

### The image is reproducible again (2026-11-27, final)
`archr-patcher` builds a complete card in one command, and the image was
rebuilt + verified offline after every fix above:

```sh
sudo python3 main.py patch --image ArchR-R36S…original.img --device rg353v \
     --out archr-rg353v.img --base dArkOS_RG353v_trixie_11072026.img
sudo python3 main.py flash --image archr-rg353v.img --target /dev/sdX
```

`downloads/archr-rg353v.img` 8,053,063,680 B,
sha256 `5aab8587…1c89526`. Verified in the image: SDL_AUDIODRIVER=alsa, the
gate `chmod`, the hook with 10 `Target` lines, both preload shims, 8 port
units, 4 port scripts, 8821cs.ko + firmware, iwd's SAE quirk + 2 profiles,
the PPSSPP mapping, `/storage/bios`, the roms2 unit; p3 has the dual-mode
initramfs, NORMAL and both DTBs at 25 MHz.

The updater path is verified too: `pacman -Su` installed archr 85 /
archr-launcher 0bd6f0a / system-utils 15, the hook ran as 6/6 and the doctor
re-applied both patches.

### Known issue, deferred: the PSP left stick is inverted
Both axes, in PPSSPP only. The packaged RK3566 `controls.ini` (all four
analog bindings) is seeded now — PPSSPP had been writing its own defaults
because `start_ppsspp.sh` only copies `/usr/config/ppsspp` when
`/storage/.config/ppsspp` does not exist yet. Still inverted after the
seed, so the leads are: the kernel reports the axes in the opposite sign on
this unit (RetroArch/dArkOS configs both use the standard `up = -Y`,
`left = -X`, doc 09 says no invert props are needed) or PPSSPP's SDL axis
mapping. Deciding test: `evtest /dev/input/event4` while the stick is pushed
up — ABS_Y negative = kernel fine, PPSSPP to fix; positive = invert the
four axis entries (RetroArch autoconfig + PPSSPP controls.ini).

### Two more, found on the first day of real use
- **Every game quit immediately.** `archr-launcher-session` makes a FIFO per
  game with `mkfifo -m 0600`. coreutils issues the **fchmodat2 syscall
  inline** (not through a symbol, so the preload shim cannot catch it) →
  ENOSYS → `mkfifo: cannot set permissions … Function not implemented` → the
  `|| exit 1` takes the whole session down → systemd restarts it → back to the
  menu. The port now does `mkfifo "$gate" && chmod 0600 "$gate"` (chmod goes
  through fchmodat, which the shim handles).
- **Wi-Fi flapped and the Settings page stuck on "connecting".** Power save
  was on: this SDIO RTL8821CS drops the link every ~30 s with it on
  (`connected → disconnected → autoconnect`), and the launcher's page blocks
  while it waits. `rg353v-wifi-powersave.service` turns it off once wlan0 is
  up; no drops in the following minutes.

### Also fixed
- `rg353v-kernel-overlays.service` had an **ordering cycle** that made systemd
  delete the tmpfiles jobs: no `/var/run`, no `/run/archr` → sway could not
  make `/run/sway/sway-daemon.conf` (the UI restart-looped) and nothing could
  write `/var/cache`. The unit now runs in `multi-user.target`.
- `sshd-s2`: `/var/lib/sshd` → `/storage/.cache/ssh` did not exist on a fresh
  card, so ssh-keygen could not save the host keys (no SSH at all). The unit
  creates it.
- The Wi-Fi SDIO bus (`sdmmc2` / `fe000000`) is capped to **25 MHz** in the
  DTB (TurboRelic's fix; the board's SDIO breaks above it).
- The dArkOS **5.10.226 modules + firmware** are installed into the
  kernel-overlay tree (the Arch-R image is an RK3326 one: `kernel-overlays-setup`
  normally runs from ARCH-R's busybox init, which our initramfs replaces).
- `archr-patcher patch` now prepares the boot partition itself (dual-mode
  initramfs + 25 MHz cap); `prepare` is a subcommand for an already-patched
  image.

### Device state (verified 2026-11-27)
Boots ArchR 20261125 on the dArkOS 5.10.226 kernel; launcher/sway/archr-levels/
input/iwd/dhcp all active; 0 futex aborts and 0 launcher crashes this boot;
130 systems with games from TF2; volume and all 20 buttons verified on the
hardware; touch drives a pointer. The only failed unit is
`proc-sys-fs-binfmt_misc.mount` (this kernel has no binfmt_misc — harmless).

**Next:** a clean image rebuild + flash with every fix baked in (the card is
already correct from the live session), and the PanVK / mainline-kernel phase
(`28-turborelic-bsp-study.md`).

---

## Session recap — 2026-11-26

### Arch-R RG353V patcher/flasher tool (Phase 1)
- **Built** `archr-patcher/` — a reusable tool that downloads the latest
  Arch-R release, patches it for the RG353V, and produces an SD-ready image.
  It uses the **dArkOS image as the base** (boot chain p1/p2 + p3 kernel/DTB/
  initramfs) and replaces only **p4 (rootfs)** with the ported Arch-R rootfs.
- **Interface:** `fetch` / `patch` / `flash` subcommands; YAML device profiles
  (`profiles/rg353v.yaml`).
- **Offline tests passing** (`archr-patcher/tests/test_patch.py`, 4 tests) —
  synthetic MBR + GPT images, port/resize mocked.
- **Studied** the dArkOS 5.10.226 kernel + boot chain (`27-darkos-kernel-study.md`)
  and the TurboRelic mainline 6.15 BSP (`28-turborelic-bsp-study.md`) — the
  reference for the later PanVK/Vulkan + mainline-kernel phase.
- **Image built + verified offline (2026-11-26 21:13):**
  `downloads/archr-rg353v.img`, 8,053,063,680 B (== dArkOS base),
  sha256 `c8891017…72ae565`. GPT intact (5 parts), p4 = ext4 `ARCHR_ROOT`
  (1,900,544 × 4K), `NAME="ArchR"`, `HW_DEVICE="RK3566"`, g29p1 Mali blob +
  hook installed, `default.target→archr.target`, custom units enabled. **Ready
  to flash.** Full run log + 7 bugs found/fixed: `30-archr-flashable-image-build.md`.
- **Still not verified on hardware:** the full patch → flash → boot cycle. The
  port itself is proven (`tools/archr-port/`); the patcher's image assembly
  (resize + write to p4) is now verified at the image level only.
  Key open risk: dArkOS p4 is **btrfs** but Arch-R rootfs is **ext4** — the
  dArkOS initramfs/kernel must mount ext4 for the image to boot.
- **Fixes applied to the port during the real run** (`tools/archr-port/apply.sh`):
  `mkdir -p /etc/systemd/system` (missing in Arch-R v3.1.1) and replace the
  trailing `[[ … ]] && echo` with `if…fi; exit 0` (it exited 1 on success).
- **Next (Phase 2):** PanVK Vulkan for Mali-G52, TurboRelic mainline kernel,
  and the RG405V GarlicOS profile.

### Repos pushed
`rg353v-internals` (27–29, `archr-patcher/`), `archr-patcher` tool.

---

## Session recap — 2026-11-21

**Full resume sheet: `rg353v-internals/HANDOFF-2026-11-21.md`.**

### RG353V — ArchR is running, mainline is blocked by the loader
- **Working:** ArchR 20261113 (Arch Linux ARM) on dArkOS **5.10.226**, TF1 p4, Wi-Fi `CPE-C391`
  → **192.168.0.198**, `ssh root@192.168.0.198` (pw `ark`), panel dashboard, vendor Vulkan 1.3.276.
- **S1** (initramfs banner/log) ✅ · **S2** (our rootfs on their kernel) ✅ · **S3** (mainline kernel) ❌:
  ROCKNIX 7.2.11 `Image` never reaches `init` on a clean card (likely ATF/PSCI mismatch; needs UART).
- **Root cause of the ROCKNIX wall (sourced):** the eMMC legacy bootloader gates SD boot; official wiki
  requires wiping Android. **Decision: keep Android** (needed for the andr36oid port) → ArchR-on-5.10 is the ceiling.
- **New infrastructure:** RAM-only **live system** + **dual-mode boot** (`/NORMAL` on p3) — rootfs work and
  recovery now happen over SSH with the card free. No more card pulls for userspace work.
- **Corruption lessons:** hard power-offs corrupted ext4+FAT; only `poweroff`/`reboot`; keep p3 half-free;
  `chmod` fails in Arch (6.10 ABI on 5.10) → use `python3 os.chmod`.
- **Docs 17–26** written and pushed; `archr-device-kit` published; workspace consolidated under
  `~/Andr36oid` with compatibility symlinks.

### Repos pushed
`rg353v-internals` (17–26, HANDOFF), `rg405v-internals` (19, ARCHIVE),
`rgb10max2-internals` (12, Arch-R note), `archr-device-kit` (published).

---

## Session recap — 2026-11-20

### Workspace consolidation (single-root rule)
All device data moved under `~/Andr36oid/` — `rg353v-backup`, `rg405v-backup`,
`rg405v-gammaos`, `rg405v-apks`, `rgb10max2-archr`, `toolchains`. Old `~/<name>`
paths are now **symlinks** (no docs/scripts broken). See `WORKSPACE.md`.

### Arch-R found already attempted (RGB10 Max 2)
`~/Andr36oid/rgb10max2-archr/` holds a **2026-11-15/16 Arch-R port attempt**:
4 device changes (board DTB, ADC range in `clone_boot.ini`, Wi-Fi RK817 OTG
latch quirk, audio quirk), 40 GB of **patched release images**, and a build that
**fails at `cmake:host`** (4 attempts). Recorded in
`rgb10max2-internals/12-archr-port-2026-11.md`. Method adopted for the RG353V
Arch port: patch a released image, don't build one.

### RG353V
ROCKNIX track **closed** (4/4 variants → Android; hybridD's only unmatched
region is the 0–8 MiB idbloader). Arch bring-up plan is now `17-…` (S0–S5, one
variable per boot) + `18-…` (Arch-R `devices/RK3566` profile analysis).
Next: S1 = custom `/uInitrd` banner on the working dArkOS card.

### RG405V
GarlicOS 2.0 bootloader analysed (`19-…`): patch stock `vendor_boot` ramdisk +
`DHTB`-signed `vbmeta`, boot an f2fs rootfs from exFAT SD with the **vendor**
kernel via `chroot`. Bootloader problem solved; Arch port = f2fs rootfs + init.

### Repos pushed
`rg353v-internals` (docs 17, 18, ARCHIVE), `rg405v-internals` (doc 19, ARCHIVE),
`rgb10max2-internals` (docs 12 + Arch-R note).

---

## Session recap — 2026-11-12

### RG405V
- **PS2 custom GPU driver WORKING:** **MaliSX2 0.4.1** on **Mali-G52 MP2**
  via a **patched ARMSX2 Nightly 20261111** + **Renderer = Vulkan**.
  **Capcom vs. SNK 2** booted through the memory-card format to the title /
  VS-ranking screen. Emulog: `driver is malisx2`,
  `GS: Classic renderer active (renderer=Vulkan)`.
- **Two traps:** (1) ARMSX2 hides the MaliSX2 page on G52 because
  `isMaliSX2Supported()` is false; the driver itself supports G52
  experimentally. (2) `Auto` renderer picks **OpenGL** on G52; you must select
  **Vulkan** or the custom driver is never used.
- **Patch/build:** `rg405v-internals/tools/patches/armsx2-malisx2-g52/`;
  full reproduction + other-emulator matrix:
  `rg405v-internals/10-emulator-gpu-drivers.md`.
- Patched nightly SHA-256 `76924c41…`; MaliSX2 0.4.1 `feb44fcb…`; both on the
  SD card `Drivers/` and in the customisation backup.
- **Customisation backup:** `/home/souhail/rg405v-backup/custom-2026-11-12/`
  (service.d, mousemode/hidpad/dpadkeys/usbmode/perfmode, Panel APK, Daijishō
  data, settings, drivers, `MANIFEST.sha256`, restore README).
- **Unbricker:** downloaded/verified (2,549,946,021 bytes, SHA-256
  `9212eec4…`, `7z t` OK). GammaOS RG405V package also local. Recovery
  decision tree: `rg405v-internals/RECOVERY.md`.
- **Wi-Fi:** verified; Settings dialog dismisses on Connect by design; the join
  completes. `sprd-wlan` kernel log flood split into its own capture
  (`tools/rg405v-log.sh`, 4 MiB logd buffers).
- **Display:** **640x480 is the native RG405V panel** (official 4" IPS spec);
  the earlier RG505-panel theory was wrong. Do not change `wm size`.
- **SD card:** ROMs SNES/NeoGeo/NDS/PS2/PSX/OpenBOR/N64/PSP + BIOS + APKs +
  Drivers; **89 GB used / 28 GB free** (117 GB exFAT).
- **PS2 test status:** CvS2 verified; Metal Slug Anthology, Grandia II,
  GTA/Crash still to test. OSD FPS was off.

### Linux / GPU track — PARKED (2026-11-12)

- **RG405V Linux is feasible but parked.** Board is `ums512-1h10` (same as
  `rg-rotate` mainline 7.1). Blockers: PanVK G52 = Vulkan 1.3 **experimental**
  (non-conformant, gated); MaliSX2 Linux needs **kbase** and is **ARMSX2-only**;
  Mesa kmsro ↔ sprd-drm unproven; dual-boot needs custom U-Boot/SPL.
- **No eMMC/U-Boot/SPL writes were made.** Android/GammaOS stays the daily
  driver. ADR-011 + `rg405v-internals/15-linux-gpu-parking-and-references.md`
  hold the resume triggers and the reference review.

### AI optimization layer — reviewed, assist-only (2026-11-12)

- **Needle 3 runs on the RG405V** (android-arm64 4.1.0, 20 L): 2.0–2.4 s,
  ~76 MB, 8/10 curated prompts; 8 layers is 1/10 and disqualified; confidence
  on correct calls 0.38–0.88, so it cannot be the only gate.
- **Verdict:** keep the shadow/replay discipline, build a deterministic session
  table first, use AI offline on the watchdog logs, and allow the on-device
  model only as an on-demand 5-tool assistant. No resident daemon, no
  auto-debloat/zram/freezer/FSR. ADR-012, doc 17, `tools/cactus-bench/`.

### ROM hub
- **Transcend merge COMPLETE:** 11 systems, **190.9 GiB added**; hub
  **802 GB used / 131 GB free**. PSX CHD set (533 CHDs, 50.9 GiB) deliberately
  deferred (would take the drive to ~92% full). `pokemini` skipped (duplicate
  of `pcfx`); `steam/wiiu/xbox/windows` empty.
- `chkdsk /f` on Windows still recommended after the `ntfsfix` that made the
  volume writable.

### RGB10 Max 2
- Port **v0.1.0** released and hardware-verified (earlier).
- No changes this session.

### RG353V
- Unchanged; docs only.

---

## Devices & access

| Device | SoC | OS | Access |
|---|---|---|---|
| **Powkiddy RGB10 Max 2** | RK3326, 1 GB | **andr36oid port v0.1.0** (Android 11) on a 7.5 GiB NCard | Booted and verified 2026-11-11; `adb connect <ip>:5555` (port 5555 via diag.sh); root daemon `/data/local/tmp/cmd.in` |
| **Anbernic RG353V** | RK3566, 2 GB | **GammaOS_Lite_v1.5** (Android 12, eMMC) + **ArkOS** (TF1) + ROMs (TF2) | Android: wireless adb `192.168.1.148:5555` (Magisk). ArkOS: `ssh ark@192.168.1.148`, password `ark`. Both currently offline |
| **Anbernic RG405V** | Unisoc T618, **Mali-G52 MP2**, 4 GB | **GammaOS Next v1.1 Lite** (Android 14), bootloader unlocked, Magisk 29.0 (app 30.6), no GApps; 4" IPS **640x480 native** | **USB ADB** `79783730379533`; Wi-Fi verified. **PS2: MaliSX2 0.4.1 works on G52** via patched ARMSX2 Nightly + Vulkan (CvS2 verified). Backup + unbricker done (see `rg405v-internals/10-emulator-gpu-drivers.md`) |

Host: `/home/souhail/Andr36oid` workspace. Devices are on `192.168.x` networks
that change between sessions — re-scan if connect fails.

---

## Current state — 2026-11-11 (session recap)

### RGB10 Max 2 — andr36oid port **published (v0.1.0) and verified on hardware**

- Repo: **`picaso1-cloud/rgb10max2-andr36oid`** (public) ·
  release **`v0.1.0`**: image (1.6 GB xz / 4.8 GB raw) + 5 Go flasher binaries.
- **Verified**: boots, setup wizard, **Wi-Fi + BT from battery**, both sticks
  click (**L3/R3**), **L3+R3 mouse chord** works.
- **Two boot blockers found and fixed** (documented in the repo README):
  1. The DTB must be compiled with **`dtc -@`**; without `__symbols__` the boot
     applies overlays and fails with a **"system failure"** message. Correct DTB
     sha256 `8fa4e522…` (byte-identical to the proven working card).
  2. `boot.ini` needs `usbcore.autosuspend=-1` in `bootrootfs`,
     `androidboot.sf_orientation=ORIENTATION_270` on the `android` variable, and
     the pre-kernel PMIC OTG poke `i2c mw 0x20 0xb4 0x47 1` before **both**
     `booti` branches.
- The BOOT rebuild must copy the **whole** base BOOT tree (a whitelist dropped
  `Image/`, battery bitmaps, etc.).
- **Card** (correction): the port used the **7.5 GiB “NCard”** from the start;
  the **128 GB “SD16G” was not inserted this session**. NCard: full read
  52.9 MB/s, fsck clean, backup at
  `rgb10max2-andr36oid/build/backups/NCard-2026-11-11.img` (sha `90bbd779…`).
- Flasher: Go tool, write + **SHA-256 read-back**; tested on the NCard (OK).
  Removing the card mid-write aborts the image (reflash needed).

### RG405V — GammaOS Next v1.1 Lite, mods applied, healthy

- Android 14 / LineageOS 21, bootloader unlocked, Magisk 26.1 (app 29.0), no GApps.
- Health: no crashes/ANRs; `performance_mode=stock` (idle 614 MHz / GPU 384 MHz,
  ~39 °C); the only oddity is a cosmetic D-state load average (~6).
- Mods: **mouse mode** (L1+R1+Select; right stick pointer, left scroll,
  A=left/B=right, configurable), USB mode switcher, **USB HID gamepad**
  (`stop usb-hal-1-1` needed; self-restore watchdog), **andr36oid Panel** APK;
  Magisk `service.d` autostart for mouse + adb-wifi.
- **D-pad is native** in Android Settings (Tab bridge retired: it caused 2-row
  jumps because the hat already moved one row).
- Touchscreen: a latched Goodix needs a **cold power-off** (reboot is not
  enough); screen-off grabs the touch node for gestures (looks dead to getevent).
- SD: the 128 GB card was f3-validated earlier (0 errors, 5.7 GB ROM test set);
  it is not in use in this session.
- **Tailscale**: never in the image (only `/data`, untouched); repo history
  scrubbed of tailnet IPs/hostnames. No auth state anywhere in the repo.

---

## Goals (clarified 2026-11-08)

- **RGB10 Max 2 (weakest, reference implementation):** two OS cards swapped in
  its single slot — one **andr36oid Android** (upgrade to the newest *feasible*
  Android), one **bleeding-edge Linux** (shared core, emulator-first, optimized).
- **RG353V:** same **shared Linux core** on TF1 (patched for RK3566) while the
  eMMC keeps Android; TF2 = ROMs. Later: automated image builder/SD flasher for
  the community.
- **RG405V (most powerful):** Android-only focus — **GammaOS Next (13/14)** plus
  the andr36oid layer (speed controls, USB modes, launcher, remote play).
- **Cross-cutting:** reuse rockchip/PMIC/input/perf/streaming/build techniques
  across devices; document with `seen`/`inferred`/`unknown` evidence tags.
  Full detail: `MASTER-PLAN.md`.

---

## Project 1 — RGB10 Max 2: andr36oid port  ✅ feature-complete (rebuild pending)

**Production state:** v31 DTB + v32 service, validated on hardware. The test SD
card later **died** (unstable reads; BOOT FAT corrupted) — hence the rebuild
kit. Console currently has no working card.

### Done (all hardware-verified)
- **Wi-Fi from battery every cold boot**: rk817 PMIC-side latch via raw i2c
  `0xB4=0x47` (`rk817tool`). Latch survives warm reboots, resets on cold off.
- **Charging + Wi-Fi simultaneously** (stock parity): stock topology — OTG phy
  port **disabled**, dwc2 phyless with `phys` kept (defer timing), `dc_det`
  intact. Verified `+869 mA` charging with `wlan0` up.
- **Boot black screen fixed** (v27): auto sleep/wake cycle after bootanim
  (SF/HWC never enables the CRTC; DPMS cycle fixes it). Screen comes up alone.
- **L3/R3 fix** (v29): stick pushes emit BTN_THUMBL/THUMBR (317/318).
- **Right-stick remap** (v30/v31): `amux-channel-mapping = <1 0 2 3>` +
  `invert-absrx` (no invert-absry) — mouse mode cursor and emulator stick
  correct (the board muxes right-X on ch0/ch1 differently than the R36S; the
  stock `abs_*_channel` props are inert in this kernel).
- **Mouse mode**: toggle = **Select+Start** (hold ~1 s), pointer = right stick;
  props `pointer_stick=right`, `invert_ry=false`, `pointer_invert_x=false`.
- **Performance (v28)**: swappiness 100, SD readahead 512, iostats off, GPU max
  600 MHz (unlocked from 520), UI animations 0.5, background janitor (am
  kill-all every 40 s + force-stop thorium/vlc), `gamemode` script
  (CPU floor 1.008 GHz). RAM available 369→442 MB.
- **Remote play (v32)**: Tailscale (CLI daemon, tailnet `the console`
  `100.x.x.x`, autostart + keep-alive in service) + Moonlight v12.1
  (preinstalled) + Sunshine on PC. Service v32 runnable on any card.
- **Docs**: `PORT-REPORT.md`, `device-work/kernel/VALIDATION.md` (v9→v32),
  `FIRMWARE-GUIDE.md`, `OS-RESEARCH.md`, repo **rgb10max2-internals**.
- **ROCKNIX RK3326 port analysis** (2026-11-08, offline): the board identifies
  as **ODROID-GO Super class** (`hwrev=v10-go3`, ADC 85); ROCKNIX's
  `RK3326-a` image auto-selects `rk3326-odroid-go3.dtb`, which already matches
  the panel (kd50t048a, 2 lanes), RK817 charger, sticks and d-pad/face pins.
  Extra buttons need a Max 2 DTS; Wi-Fi hub power is the main risk. Plan:
  `rgb10max2-internals/11-rocknix-rk3326-port.md`.

### Next actions (ordered)
1. **Android card — new SD**: flash `dist/andr36oid-rgb10max2-master.img`
   (md5 `618f948d7055af948c362ff593433924`) → extend userdata to fill the card
   → restore `dist/userdata-full.tar` (apps/data/wifi) → restore
   `dist/essentials.tgz` (tailscale auth into `/data/local/tmp/ts/state/`) →
   boot → verify: Wi-Fi + charging + mouse mode + tailscale (`100.x.x.x`)
   + Moonlight hosts.
2. **Linux card (new goal)**: flash **ROCKNIX RK3326-a** (`dist/ROCKNIX-RK3326-a.img.gz`,
   SHA-256 `4e96c257…02ce`) to an A2 card, then apply the validated key overlay
   (`rgb10max2-internals/dts/apply-rocknix-max2.sh /dev/sdX1`). The Max 2 is
   OGS-class; the OGS DTB boots it. Test panel/input/Wi-Fi/charging; remaining
   work = Wi-Fi hub power + stick axis check + upstream DTS/quirk. Full plan:
   `rgb10max2-internals/11-rocknix-rk3326-port.md`. Two cards, swapped.
3. Gameplay test of GPU 600 MHz + `gamemode` → keep or revert.
4. **Android upgrade research**: newest *feasible* Android (11 → 12/13 GSI on
   the RK3326 BSP); do not touch the stable card without a proven rollback.
5. Optional: kernel patch for honest battery icon while latched; deeper
   performance measurement.

### Known limits (by design)
- Cable ADB/USB device modes: phy port disabled for charging (documented trade-off).
- Battery icon may read “charging” while latched (self-sensing; % is honest).

### Artifacts (`/home/souhail/Andr36oid/dist/`)
- `andr36oid-rgb10max2-master.img` (4.7 GB, md5 618f948d…) — CLEAN rebuild from
  official base, verified (mtools).
- `andr36oid-rgb10max2-v26.img` — older working image (v26-era).
- `andr36oid-rgb10max2-clone.img` — clone of the DYING card (do not use).
- `userdata-full.tar` (1.5 GB) — full /data snapshot (apps+data+wifi).
- `essentials.tgz` (1.6 KB) — tailscale auth (`ts/state/tailscaled.state`).
- `andr36oid-20261024-1750-rk3326.img.xz` — official base release.
- `ROCKNIX-RK3326-a.img.gz` (+ raw `.img`) — shared Linux core, Max 2/OGS
  class; SHA-256 `4e96c2574e7856f9c35963cd8aba1c1ba40a87694b8676f42b8bb2e5efaa02ce`.
- `rgb10max2-internals/dts/rk3326-rgb10max2-keys-overlay.dts` (+ `.dtbo`,
  `apply-rocknix-max2.sh`) — validated key remap for ROCKNIX.
- Builders: `image-patcher/build-rgb10max2-image.sh` (mtools BOOT rebuild),
  `image-patcher/migrate-console-state.sh`.

---

## Project 2 — RG353V: GammaOS study + optimization  ✅ deployed

### Done
- Full study: hardware, GammaOS structure (Android 12 sargo GSI on RK3566 BSP,
  dynamic partitions, Magisk), drivers, **kernel+DTB decompiled** (`survey/boot.dts`),
  comparisons vs the RGB10 Max 2 pain list.
- **Wireless adb** root cause (adbd USB-only) + fix + **Magisk persistence**
  (`/data/adb/service.d/janitor.sh` sets `service.adb.tcp.port 5555`).
- **Optimization deployed**: `/data/local/tmp/gamemode` (CPU floor 816 MHz +
  DMC floor 780 MHz; GPU min not settable — devfreq ignores while suspended),
  `gamemode-off`, janitor (`am kill-all` every 60 s).
- PS2 on Android already works for the user (AetherSX2/ARMSX2 APK).
- Upgrade path studied: **GammaOSNext does NOT support the RG353 series**
  (deprecated GammaOS-RK3566 v1.5.1 is current); SDDiskTool recovery model +
  safest procedures documented.

### Next actions
1. **Linux core on TF1** (Project 4): flash ROCKNIX Generic, then port the
   andr36oid L3 layer (perf/janitor/Tailscale/Moonlight/input).
2. (Optional) deploy Moonlight + Tailscale on GammaOS for parity with the Max 2.
3. Android ceiling: GammaOS 12 is stable; a 13/14 GSI is an experiment only
   after a proven eMMC backup + rollback.

---

## Project 3 — RG353V: ArkOS → dArkOS  ✅ running (migrated 2026-11-20)

### 2026-11-19 card diagnosis (ArkOS TF1 card failed to boot — "stuck on splash")

Card inspected read-only on laptop (58.2 GiB, ArkOS rk3566 layout: p1/p2
bootloaders, p3 BOOT 100 M vfat, p4 ext4 root 10.4 G, p5 EASYROMS exfat 47.8 G):

- **Card is healthy**: ext4 fsck clean, boot-chain files valid, rootfs UUID
  matches extlinux, kernel `Image` Feb 2025 (≈ the 02/09/2025 release, the
  last ArkOS image ever published).
- **31 boots logged**, 3 in the last week; the last full boot (2026-11-13
  19:35) reached **network + audio + EmulationStation started**, and
  `imagecache.db` was still being written at 23:30 — the device **worked for
  ~4 h that evening**, then died/removed uncleanly (BOOT vfat dirty bit + a
  `System Volume Information` dir = Windows also touched the card after).
- **Root cause (hypothesis, high confidence): ES crash-loop from
  `imagecache.db` corrupted by that unclean shutdown** — EmulationStation
  starts (service OK) but dies reading the corrupt cache → screen frozen on
  splash → "stuck on splash". No `es_log.txt` was written (crash too early).
- **Fix applied:** ES config backed up to
  `rg353v-backup/arkos-card/ark-emulationstation-config.tar.gz`;
  `imagecache.db` quarantined as `imagecache.db.corrupt`; ES will rebuild it.
- Backups taken: `boot-p3.img` (100 M), `easyroms-content.tar.gz` (671 M —
  all EASYROMS content incl. bios 11 M + configs).
- Only cosmetic service failures noted (503 vibration script, rc.local
  odroidgo2-joypad echo — both present during working boots; not the cause).

### ArkOS ecosystem status (researched 2026-11-19)

- christianhaitian/ArkOS **archived 2025-12-30**; final image = **02/09/2025**
  (MD5 `F8EDEC54…`), final OTA update = **v2.0 07/31/2025** (PPSSPP 1.19.3,
  RA 1.20.0, PortMaster fix — fetchable, repo `main` frozen).
- **dArkOS is the successor** (same author): github.com/christianhaitian/dArkOS.
- OTA mechanism: `Update.sh` → `ArkOSUpdate.sh` from repo `main` (frozen final
  state) → per-device payload. Reference copy saved:
  `rg353v-backup/arkos-card/ArkOSUpdate-final.sh`.

### Next actions
1. ~~Test card in RG353V~~ — **user reports still stuck on splash after the
   imagecache fix** (2026-11-20). Root cause of the ES crash not identified;
   moved to the OS-level upgrade instead.
2. **ROCKNIX migration DONE on the ArkOS card (2026-11-20):**
   - Data preserved: `easyroms-content.tar.gz` (bios 11 M + saves + configs)
     and `ark-emulationstation-config.tar.gz` — the only data parts on the card.
   - User declined further ArkOS backups; partial full-card image deleted.
   - Flashed **ROCKNIX-RK3566 20261101 Generic** (SHA256-verified download,
     `b573c965…` gz) to the card — write 34.2 MB/s fsync'd, readback verified
     byte-for-byte. Resulting layout: 2 GiB `ROCKNIX` vfat + 32 MiB `STORAGE`
     ext4 (auto-expands to the full 58 GiB on first boot).
   - **FINAL STATE (2026-11-20):** card re-flashed clean + **STORAGE capped at
     20 GiB** + third "unused" partition (36.2 GiB, no filesystem) walling off
     the dead zone — ROCKNIX's auto-expander can no longer grow into it
     (storage fs already fills its partition; the expander's only growth target
     is the dummy partition = table-only no-op). fsck clean, mount-tested.
     **Superseded same evening:** ROCKNIX still failed to boot on-device —
     **dArkOS v11072026 installed instead, booting ✅** (see OUTCOME below).
   - **Root cause chain (final):** card fails writes beyond ~24 GB →
     ROCKNIX first-boot storage expansion hung the device (user saw frozen
     splash, pulled power) → wedged card state made subsequent boots skip the
     SD entirely (BootROM fallback to eMMC Android). Re-flash + 20 GiB cap +
     dead-zone wall resolves all three.
   - **TF2 (ROMs card) untouched** — ROCKNIX firmware-only on TF1 per plan;
     after first boot: enable SSH/Samba → copy bios set (11 M, in
     `easyroms-content.tar.gz`) into `STORAGE/bios` → map TF2 roms folders.
   - **Boot failure root cause found (2026-11-20): interrupted first-boot
     storage expansion.** The card diff vs pristine image proved the device
     DID boot ROCKNIX (STORAGE ext4 metadata modified, boot files intact).
     The first-boot resize started, the screen looked frozen, power was pulled
     — leaving `STORAGE` at 32 MiB with the expansion never retried (flag
     consumed) → every boot stuck at the same stage.
   - **Fix applied: manual expansion** — `sfdisk -N2 ",+"` grew p2 to fill the
     card (GPT backup relocated), `e2fsck -f -y` clean, `resize2fs` grew the
     fs to 14,738,939 blocks (**56.2 GiB**), final fsck clean, mount-tested.
     **→ User test 2026-11-20: STILL failed — device skipped the SD entirely
     and booted eMMC Android.** Storage was never the (only) problem.
   - Card health extra datapoint: sustained sequential reads collapse
     44 → 9 MB/s on this old card (abandoned full-backup dd log).
   - **OUTCOME (2026-11-20 evening): ROCKNIX abandoned — dArkOS flashed by
     user, BOOTS ✅.** User downloaded **dArkOS v11072026** (latest release,
     Debian 13 Trixie base, RG353V-specific image, published 2026-11-14),
     flashed it onto the same TF1 card → device boots to the frontend.
     Decompressed image (7.5 GB, MD5 `acb3f2b0…`) + .7z parts kept in
     `rg353v-backup/images/`.
   - **Boot-chain root cause (raw-byte comparison, laptop):** dArkOS vs
     ROCKNIX idbloader + u-boot regions differ entirely. dArkOS @ 8 MiB:
     `FIT Image with ATF/OP-TEE/U-Boot/MCU` (full trusted chain, RG353V-tuned
     DDR init); ROCKNIX @ 8 MiB: `FIT image for U-Boot with bl31 (TF-A)`
     (generic RK3566 chain). This unit accepts dArkOS's chain and rejects
     ROCKNIX's — **the ROCKNIX flash procedure itself was verified correct
     (byte-for-byte vs official image); the incompatibility is in ROCKNIX's
     boot-chain build for this unit.** If ROCKNIX is ever wanted here: splice
     dArkOS's loader region (sectors 64→32768) keeping ROCKNIX partitions
     — experimental.
   - Worth reporting upstream: ROCKNIX 20261101 Generic fails to boot on
     RG353V (data point for their RK3566 build).
   - **RG353V Linux baseline = dArkOS v11072026** (successor of ArkOS, active
     releases, Debian Trixie). Mirror saves to TF2/hub.
   - Full-card dd abandoned mid-way (card read speed collapses 44→9 MB/s on
     sustained reads — this old card is on its way out; do not reuse for new
     libraries).
3. Mid-term: evaluate **dArkOS** for RG353V vs staying on ROCKNIX (active
   monthly releases; 20261101 = latest). Keep saves mirrored to TF2/hub.

---

## Project 4 — Modern Linux for RK3566/RG353V (ROCKNIX)  📚 documented (no action planned)

**Key finding (2026-11-08)**: ROCKNIX's RK3566 **Generic** image already provides
the modern stack the "Arch-R" idea was after — glibc **2.44**, Mesa **26.2.4**
(panfrost + panvk), kernel **7.2.11**, **sway**, EmulationStation — and ships
**ARMSX2 preinstalled**. Building a new Arch-R RK3566 port is therefore
**optional** (only for pacman/rolling packages), not needed for performance.

**Offline Stage 1 completed** (`14-rocknix-image-analysis.md`):
- Correct image identified: `Generic`, *not* `Specific` (RG353V is in the
  Generic list; Specific is X55/X35S/RG DS). Downloaded + SHA-256 verified
  (`b573c965…c775`); wrong image deleted.
- Boot chain captured: idbloader `RKNS` @ 32 KiB, SPL DT @ 0x36EC0
  (SD-first order), U-Boot 2026.01 @ 8 MiB, FAT @ 16 MiB with `FDTDIR`,
  KERNEL 7.2.11 (embedded LZO initramfs), SYSTEM squashfs, STORAGE ext4.
- U-Boot Anbernic board code: SARADC detection (RG353V = 695) + panel ID
  detection (0x3052 = v1 nv3051d, 0x3821 = v2). **This unit is v2** (GammaOS
  DTB active panel ID 0x3821).
- Userland verified: glibc 2.44, Mesa 26.2.4, sway kiosk, ES, ARMSX2
  (`/usr/share/armsx2-sa/armsx2-qt` + `start_armsx2.sh`), RG353V quirks
  (`/usr/lib/autostart/quirks/devices/Anbernic RG353V`).

### Boot model (corrected, verified behavior)
The RG353V has **two OS modes and two SD slots**:
- **TF1** = OS card → **boot priority**; a bootable TF1 card (Linux or Android)
  boots directly.
- **eMMC** = built-in OS (GammaOS Android) → boots only when TF1 has no bootable
  OS card.
- **TF2** = ROMs/media card only (never boots).

**2026-11-20 — this model is now qualified by hardware evidence.** Four
ROCKNIX-based cards (original image, and three hybrids carrying dArkOS's exact
u-boot FIT + dArkOS-identical GPT) all landed on Android, while dArkOS and
ArkOS boot from the same slot. The eMMC boot chain therefore gates what a TF1
card may load; ROCKNIX's documented "wipe the Android partition on P/M/V" is
real for this unit, not a caveat. **The ROCKNIX track is closed** —
see `15-darkos-migration.md` (final section) and the replacement plan
`17-archr-bringup-plan.md`.

### Stages
0. ~~Validate by flashing ROCKNIX~~ — **closed 2026-11-20**: ROCKNIX does not
   boot on this unit (4/4 variants → Android).
1. Capture boot chain — **done offline**; dArkOS's chain is now the reference
   implementation.
2. **Staged bring-up** — the replacement plan: keep the proven dArkOS chain and
   replace one layer per boot (initramfs → rootfs → kernel → loader), with a
   visible output on the panel at every step.
3. Distribution polish — ES frontend, controls, audio, Wi-Fi, TF2 ROMs, OTA.

**Decision (2026-11-20):** stop distro-flashing experiments. Proceed with
`17-archr-bringup-plan.md`, starting at **S1** (custom initramfs banner on the
working dArkOS card — one file, no reflash).

Full plan: `17-archr-bringup-plan.md` (current) · `13-archr-rk3566-plan.md`
(background) · analysis: `14-rocknix-image-analysis.md`.

---

## Project 5 — RG405V: newest Android + andr36oid layer  ✅ GammaOS Next v1.1 Lite running

**Device (verified live 2026-11-08 → 2026-11-11):** Unisoc T618, 4 GB,
**116.5 GB eMMC**, 4″ **480×640 portrait** panel (UI 640×480 landscape),
**128 GB microSD ROM library** (103 GB used). Now running **GammaOS Next v1.1
Lite** = Android **14 / LineageOS 21** (`lineage_arm64_bvN-userdebug
AP2A.240905.003`), model `TrebleDroid vanilla`, **no GApps**, **Magisk 29.0**,
SELinux Permissive, bootloader **unlocked** (`flash.locked=0`,
`verifiedbootstate=orange`). Stock was Android 12 V1.23 (38 Google packages).
Full stock profile: `rg405v-internals/02-recon-results.md`.

- **Access:** USB ADB serial `79783730379533`; fastboot/fastbootd work.
  Wireless ADB port changes after reboot.
- **Bootloader unlocked 2026-11-11** with Linux `unisoc-unlock` (token + RSA
  signature → `flashing unlock_bootloader`). Traps: 60 s confirmation window
  (timeout still applies the unlock; retry says `can not been unlocked
  repeatly`), OEM-unlock toggle not required, post-wipe USB debugging off /
  MTP `1782:4001`. Runbook:
  `rg405v-internals/07-bootloader-unlock-lock-unbrick.md`.
- **Flash (2026-11-11, done):** archive 2,425,892,864 B, `7z t` → OK (86 files);
  `adb reboot fastboot` → fastbootd (`is-userspace: yes`); `FlashPartitions.sh`
  exit 0, **0 failures** (both slots + logical `system`/`vendor`; system sparse
  transfer 175 s, ~6 min total); `EraseUserData.sh` 59.9 s. First boot: ADB in
  40 s, `boot_completed` ~2 min. Details: `03-gammaos-next-plan.md` §6.
- **Post-flash validated:** `/data` 110 GB (1.1 GB used), `wm size` 640×480,
  no `com.google.android.gms`/Play Store, Magisk 29.0 present, GammaOS apps
  (`gammapad` running, shader control, analog calibrator, joystick LED).
- **Next steps:** device setup wizard → Magisk finish-install (adb shell still
  uid 2000, no `su`) → new microSD + ROM library → reinstall Daijishō/emulators
  → port andr36oid L3 layer.
- **Linux (new, 2026-11-20):** GarlicOS 2.0's bootloader proves the practical
  route — patch the stock **`vendor_boot` ramdisk + `vbmeta`** (avbtool test
  key, Unisoc `DHTB` wrapper), install via APK, then boot an **f2fs rootfs image
  from exFAT SD** with the *vendor* kernel and `chroot`. No bootloader porting,
  Android untouched, reversible. That is the boot half of our Arch port on this
  device (GPU via vendor GL / MaliSX2, **no panfrost**). Mechanism + plan:
  `rg405v-internals/19-garlicos-bootloader-analysis.md`.
- **Rollback:** GammaOS RG405V unbricker
  (`RG405V_UNBRICKER_SPD_Upgrade_Tool_R26.21.2801.7z`, 2,549,946,021 bytes,
  Windows `UpgradeDownload.exe`) — **downloaded/verified 2026-11-12**
  (SHA-256 `9212eec4…`, `7z t` OK); the SPD rollback itself is not yet
  exercised.
- **Historical (stock era, wiped):** Daijishō 1.5.0 + 32 platforms, Droidify
  0.7.8, Shizuku-Next 14.0.33, and the 2026-11-08 performance tuning
  (`rg405v-internals/06-optimization.md`) — all lost in the wipe; redo on
  GammaOS Next.
- **Kernel/DT deep dive (stock era):** kernel **5.4.161** BSP, full running DTS
  via sysfs, 152 modules / 282 loaded. Hardware: SC2730 PMIC, **AW32257
  charger**, SC2730 FGU/Type-C/vibrator, generic MIPI **480×640** panel,
  **Goodix GT9xx** touch, `retrogame_joypad` (singleadc), **SC2355 SDIO**
  WiFi/BT/GNSS, **Mali-G52 Gondul** 384–850 MHz. Artifacts:
  `rg405v-internals/recon/20261108/`, doc `05-kernel-drivers-deep-dive.md`.

---

## Repositories & upstream

| Repo | State |
|---|---|
| `picaso1-cloud/rgb10max2-internals` | RGB10 Max 2 knowledge base (10 docs + artifacts) |
| `picaso1-cloud/rg353v-internals` | RG353V knowledge base (15 docs + survey incl. ROCKNIX teardown) |
| `picaso1-cloud/rg405v-internals` | RG405V knowledge base (recon results + GammaOS Next plan + shared docs) |
| `andr36oid/andr36oid_sdflasher` PR **#2** (`picaso1-cloud:rgb10max2-port`) | open, mergeable, head **`649dee6`** — docs + DTS + service + builder |
| Shared docs (mirrored) | `MASTER-PLAN.md`, `SHARED-KNOWLEDGE.md`, `PROJECT-STATUS.md`, `REFERENCES.md`, `docs/DECISIONS.md`, `docs/RE-METHOD.md` |
| Local workspace | `/home/souhail/Andr36oid` — PORT-REPORT, VALIDATION, device-work, image-patcher, dist |

GitHub token: fine-grained, `picaso1-cloud` (push via explicit URL form;
never stored in files). PRs can't be created cross-repo with this token (user
opened #2 manually).

---

## Decisions — resolved and open

**Resolved (user, 2026-11-08):**
- ✅ **Linux core = ROCKNIX** (ADR-001).
- ✅ **RGB10 Max 2 = two cards swapped** in the single slot (ADR-004).
- ✅ **Android = stable first, experiments on separate media** (ADR-005).
- ✅ **RG405V = stock Android 12, not rooted**, ADB available (ADR-002).
- ✅ **RG405V = Android-first**; Linux investigation-only (ADR-006).

**Open:**
1. **RGB10 Max 2 card purchase:** size/class → flash master + migrate state.
2. **RG405V — stay stock (user decision 2026-11-08).** Revisit later if a newer
   Android is wanted; the GammaOS Next Lite plan + Windows unbricker path are
   ready. No backup/flash performed.
3. **Community release timing:** after Phase 2 or Phase 3? (ADR-007)
4. **Max 2 Linux acceptance:** which emulator/streaming set and numbers define
   "done".
5. **Priority order:** RGB10 rebuild → shared Linux core (ROCKNIX Max 2 port +
   RG353V TF1) → RG405V backup/unlock/GammaOS Next → community builder/flasher.

---

## Latest session update (2026-11-08, post-checkpoint)

- **Goals clarified across all three devices** (RGB10 Max 2 / RG353V / RG405V):
  Android + Linux strategy, shared core, cross-device reuse. Written as
  `MASTER-PLAN.md`, `SHARED-KNOWLEDGE.md`, `docs/DECISIONS.md`,
  `docs/RE-METHOD.md`, and a new `rg405v-internals/` knowledge base.
- Read `PROJECT-STATUS.md`, resumed Project 4.
- Discovered the downloaded ROCKNIX image was the **wrong variant** (`Specific`);
  downloaded the correct **Generic** image, verified SHA-256, deleted the wrong one.
- Completed the offline ROCKNIX teardown (`14-rocknix-image-analysis.md`):
  boot chain, SPL DT (SD-first), U-Boot board/panel detection, glibc/Mesa/kernel,
  ARMSX2 preinstall, RG353V quirks.
- Documented the boot model correctly: **TF1 = OS card (boot priority), eMMC =
  fallback Android, TF2 = ROMs only**; no eMMC wipe needed for a TF1 ROCKNIX
  experiment. (Corrected an earlier overstatement based on an unverified wiki
  caveat.)
- Corrected the panel claim: unit is **v2** (ID 0x3821); mainline/u-boot/kernel
  support both v1 (0x3052) and v2.
- No hardware was touched; all devices remain offline/not surveyed.
- **RG353V hardware remains deferred** (documentation-only for now); the new
  master plan defines what to do when it resumes.
- **Decisions confirmed (user):** Linux core = **ROCKNIX**; Max 2 = **two cards
  swapped**; Android = **stable first, experiments separate**; RG405V =
  **stock Android 12, not rooted**.
- **ROCKNIX RK3326-a analysed offline** (SHA-256 `4e96c257…02ce`): kernel 7.1.2,
  glibc 2.44, Mesa 26.2.4, no ARMSX2; `boot.scr` maps the Max 2's ADC 85 to
  `rk3326-odroid-go3.dtb`; the go3 DTB already has every Max 2 button pin, only
  the key codes differ. **Validated a DT overlay** that remaps all keys
  (`rgb10max2-internals/dts/`, `apply-rocknix-max2.sh`). Wi-Fi driver + firmware
  present; hub power and stick axes remain hardware tests.
- **Added `REFERENCES.md`** (curated sources) — includes the user-provided
  [`Zaruber/ohmyanbernic`](https://github.com/Zaruber/ohmyanbernic) Termux
  no-root dashboard (useful for unrooted RG405V recon/telemetry).
- **RG405V recon completed live** (wireless ADB, read-only): stock **Android 12
  V1.23**, T618, kernel 5.4.161, 116.5 GB eMMC / 77 A/B partitions, 4″
  480×640 portrait panel (UI 640×480), full gamepad + Goodix touch, SC2355
  5 GHz Wi-Fi, zram 2.14 GB, 38 Google packages, bootloader locked / no usable
  root, SELinux Permissive. ROM library (103 GB) is on the 128 GB microSD.
  Data: `rg405v-internals/02-recon-results.md`.
- **GammaOS Next plan written** (`rg405v-internals/03-gammaos-next-plan.md`):
  Android 14 Lite, fresh install, unlock via `unisoc-unlock`/subut-rehost,
  fastbootd flash, mandatory data erase, RG405V unbricker as rollback gate.
  **Nothing flashed.**
- **User decision: RG405V stays stock for now** — no unlock, no backup, no
  device changes. Plan + Windows unbricker path recorded for later.
- **RG405V user-space setup (no root):** installed **Daijishō 1.5.0** (32
  platforms imported), **Droidify 0.7.8** (F-Droid client), **Shizuku-Next
  14.0.33** (running, UID 2000/shell). Prepared official APKs for Cromite,
  Fennec, PPSSPP 1.20.4, RetroArch 1.22.2, Flycast 2.7, Azahar 2126.2.
  Chrome left untouched (no Google account; Play/Aurora needed).
- **Deep kernel/DT probe:** pulled `/proc/config.gz`, reconstructed the full
  running DTS from `/sys/firmware/devicetree/base`, captured `dmesg`, lsmod,
  module params, firmware and sysfs power/thermal/display/input. Documented
  SC2730 PMIC, AW32257 charger, SC2730 FGU/Type-C, Goodix GT9xx, SC2355 WiFi,
  Mali-G52. Shizuku = shell UID, no extra privilege over ADB.
- **Clean boot log captured (USB ADB):** with Wi-Fi/BT off, `dmesg` was pulled at
  **uptime 7.65 s** from `[0.000000]` — **9,686 lines**. Full probe timeline:
  SC2730 @0.47 s, mmc/eMMC/SD @0.8–0.96 s, Goodix GT9xx @0.91 s, joypad deferred
  (`-517`), Mali-Gondul @3.46 s, charger-manager/AW32257/FGU/Type-C @3.68–3.76 s,
  SC2355 WiFi @3.94 s, DSI `480x640@60` @6.2 s. Artifacts:
  `recon/20261108/dmesg-clean-boot.txt`, `boot-probes-key.txt`; analysis in
  `05-kernel-drivers-deep-dive.md` §8.
- **Shizuku-Next stops on reboot**; restart via the app's pairing flow when
  needed (it was running before the reboot).
- **Performance tuning applied (no root):** Daijishō set as default home,
  animations 0.5×, Doze exemptions for Daijishō + 16 emulator/tool packages,
  AOT compile (`cmd package compile -m speed -f`) for 17 apps (all Success),
  safe debloat of 6 Google packages. Reversible; details in
  `rg405v-internals/06-optimization.md`.
- **Next:** Daijishō ROM paths + default browser, install FOSS apps from
  Droidify, update emulators; Max 2 waits for an A2 card.

---

## Quick reference

```sh
# RGB10 Max 2
adb connect <ip>:5555
adb shell 'cat > /data/local/tmp/cmd.in << "EOF"\n{ ... } > /data/local/tmp/cmd.out 2>&1\nchmod 666 /data/local/tmp/cmd.out\nEOF'
# tailscale (on device)
TS=/data/local/tmp/ts/tailscale; SK=--socket=/data/local/tmp/ts/tailscaled.sock
$TS $SK status ; $TS $SK ip -4

# RG353V GammaOS
adb -s <serial|ip:5555> shell ; su -c '/data/local/tmp/gamemode'
# RG353V ArkOS
sshpass -p ark ssh ark@<ip>   # sudo with same password
systemctl {stop,start} emulationstation
```

## Session history highlights (for context)

- RGB10 Max 2: v9→v32 iterations; the four big discoveries: rk817 latch,
  stock-topology charging (phy port), CRTC handoff black screen, right-stick
  mux remap. Test card died → clean rebuild kit + mtools BOOT pipeline.
- RG353V: GammaOS = GSI+vendor; wireless adb persistence; gamemode/janitor;
  ARMSX2-on-ArkOS blocked by display stack (full record); ROCKNIX identified as
  the modern path; Arch-R port plan written.
