# 32 — What a package update broke, and the five fixes that came out of it

**Date:** 2026-11-26/27 · **Scope:** the `archr-patcher` image and
`tools/archr-port/` · **State:** all verified on the device

The unit booted, ARCH-R came up, and then `pacman -Su` was run. Three reboots
later the screen was black, the volume keys did nothing, and the Wi-Fi page in
Settings was empty. Every one of those had its own cause. This is the record,
so the next update does not repeat them.

---

## 1. The PI2 futex: why every pulse client died on the 5.10 kernel

**Symptom.** The launcher drew one frame and aborted:

```
archr-launcher-session[3366]: archr-launcher: first frame 557 ms (5 system rows)
archr-launcher-session[3366]: The futex facility returned an unexpected error code.
archr-launcher-session[2774]: 3366 Aborted (core dumped) "$launcher"
```

`archr-levels` (the volume daemon) died the same way, and with it
`input_sense`, and with that every button.

**The trace** (strace + gdb on the device):

```
futex(0x3bf4660, 0x18d /* FUTEX_LOCK_PI2 */, NULL) = -1 ENOSYS

Thread 2 "threaded-ml" received signal SIGABRT
#7  pa_mutex_lock () from /usr/lib/pulseaudio/libpulsecommon-17.0.so
#8  ?? () from /usr/lib/libpulse.so.0
```

**The chain.**

1. libpulse's `pa_threaded_mainloop` creates its lock with
   `pthread_mutexattr_setprotocol(PTHREAD_PRIO_INHERIT)`
   (`pthread_mutexattr_setprotocol@plt` is imported by
   `libpulsecommon-17.0.so`).
2. glibc ≥ 2.34 answers a priority-inherit mutex with the **PI2** protocol:
   `FUTEX_LOCK_PI2` (op 0x8d | PRIVATE | CLOCK_REALTIME).
3. `FUTEX_LOCK_PI2` was added in **Linux 5.14**. The RG353V runs the dArkOS
   **5.10** BSP kernel, which answers **ENOSYS**.
4. glibc's futex wrapper treats any unexpected errno as fatal →
   `futex_fatal_error()` → `abort()`.

**Fix.** `tools/archr-port/pi2_compat.c` — a 2 KB shim that answers the
priority-inherit request with `PTHREAD_PRIO_NONE`. The attribute is left at the
default `pthread_mutexattr_init` set, so nothing is forwarded and the shim has
**no libc dependency**:

```
clang --target=aarch64-linux-gnu -fPIC -shared -nostdlib -O2 -o pi2_compat.so pi2_compat.c
```

It joins `fchmodat2_compat.so` in `/etc/ld.so.preload`.

Verified on the device: `archr-levels` stable, `volume +2` → 77 → 79 → `-2` →
77, pulse sink at 64%, launcher no longer crashes.

### The workaround that was already there

The port had patched `SDL_AUDIODRIVER=pulseaudio` → `alsa` in
`archr-launcher-session` for exactly this reason ("the SDL2 pulse backend
aborts with pipewire-pulse"). The package upgrade put the upstream line back,
which is why **the launcher** broke before the shim existed. The shim fixes the
underlying problem; the ALSA patch stays as belt and braces.

---

## 2. The update itself reverted the port's patches

`pacman -Su` upgraded `archr` 72→83, `archr-launcher` dd53f4b→6ffbcd5,
`archr-joypad`, `autostart`, `quirks`, `bash`, `lib32`, `linux`, `portmaster`,
`ppsspp-arch`, and installed `openssl11` + `SDL3`.

Two files the port patches are **owned by those packages**, so the upgrade
restored the upstream versions:

| File | Port's patch | Consequence of the revert |
|---|---|---|
| `/usr/bin/archr-launcher-session` | `SDL_AUDIODRIVER=alsa` | the launcher aborts in its pulse backend → black screen |
| `/etc/profile.d/001-functions` | `rewrite_config` via python3 (coreutils' chmod uses `fchmodat2`, Linux 6.6+) | every `set_setting` fails on 5.10 |

**Fix.** `/usr/local/bin/rg353v-port-doctor`, run by a pacman hook
(`/etc/pacman.d/hooks/99-rg353v-port.hook`, triggered by archr,
archr-launcher, archr-joypad, autostart, quirks, system-utils, archr-hotkey,
powerstate, sleep, retroarch) **and at every boot**
(`rg353v-port.service`).

The doctor repairs:

- `SDL_AUDIODRIVER=alsa`
- the `rewrite_config` fix in `001-functions`
- both preload shims in `/etc/ld.so.preload`
- iwd unmasked/enabled, wpa_supplicant disabled (one manager per interface)
- `dhcp-wlan0` waits for iwd instead of pulling wpa_supplicant in
- the touch bridge enabled
- the controller mapping, `/storage/bios`, the TF2 ROM folders
- it warns (does not guess) about missing quirks and units

It is also the first thing to run by hand when something looks wrong after an
update: `sudo /usr/local/bin/rg353v-port-doctor`, log in
`/tmp/rg353v-port-doctor.log`.

---

## 3. iwd, not wpa_supplicant: the Settings page needs it

**Symptom.** The launcher's network page stayed empty.

```
dbus-daemon: Activation via systemd failed for unit 'iwd.service': Unit iwd.service is masked.
archr-launcher: Wi-Fi: wifictl: exit status: 1;      (every 10 s)
```

The page and `wifictl` speak iwd's D-Bus API. The port had masked iwd ("it
scanned but never issued a connect on this vendor driver") and ran
wpa_supplicant instead, so the connection worked but the UI could not see it.

**Why iwd works now.** The `SaeDisable=...,8821cs` quirk in `/etc/iwd/main.conf`
(the 8821cs vendor driver advertises SAE but never delivers the external-auth
events, so iwd hung instead of falling back to WPA2). With it, iwd associates
on its own: after a reboot it connected to a saved profile and its scan lists
every nearby network.

**Fix.** iwd unmasked + enabled; `dhcp-wlan0.service` is `After=iwd.service`
with no `Wants=wpa-wlan0`; wpa_supplicant stays installed as a fallback, not
enabled.

**The provisioned networks** have to live in `/storage/.cache/iwd/`, not
`/var/lib/iwd/`: the latter is a tmpfiles bridge (`L+ /var/lib/iwd →
/storage/.cache/iwd`), so `.psk` files written into the image are lost when the
bridge takes over. That is exactly what had happened.

```
iwctl station wlan0 get-networks →
  > Tenda_ED9470_5G   psk  ****      HOME-NETWORK           psk  ****
    Fibre_MarocTelecom_2.4G psk **** La_Fibre_dOrange_9318   psk  ****
```

---

## 4. The TF2 card keeps its ROM folders at the card root

**Symptom.** The launcher listed 5 systems, the second card looked "not
detected".

The card was mounted (221 GB, 86 067 files), but ARCH-R publishes
`/run/archr/roms2 → <card>/roms`, and this card carries the **ArkOS layout**:
`psx/`, `snes/`, `gba/`, `dreamcast/` sit at the **card root** next to `bios/`
and `AnberNext/`, while `<card>/roms` held only the empty folders ARCH-R had
created for itself.

**Fix.** `rg353v-roms2.service` → `rg353v-roms2.sh`: use `<card>/roms` when it
really holds games, the card root when it does not but the root does, and
nothing is copied — only the symlink moves. 5 → **130 systems with content**;
the launcher lists 31 rows and indexes the ROMs.

---

## 5. The touch panel as a pointer

**The panel works.** `Hynitron cst3xx Touchscreen` (i2c 2-001a), multitouch
(`ABS_MT_SLOT/POSITION_X/POSITION_Y/TRACKING_ID`, `BTN_TOUCH`), axes 0..639 ×
0..479 — the panel resolution, so a position maps 1:1 to the screen. A capture
on a tap produced 830 events.

Note that the TurboRelic author reports the opposite on mainline 6.15 and
Batocera: *"touchscreen interrupts fire but no input events arrive. CST340
controller. Same issue on Batocera and stock Anbernic firmware."* On the
dArkOS 5.10 BSP kernel with its cst3xx driver the events do arrive — that is
the difference the bridge below relies on.

**The gap.** libinput/wlroots expose the panel as a *touch* device only, so the
seat had **no pointer**: the launcher could not be tapped and the emulators that
take a mouse (Draxcast, melonDS through RetroArch's touchscreen driver) never
saw the finger.

**Fix.** `rg353v-touch-mouse.py` (systemd unit `rg353v-touch-mouse.service`)
reads the panel and writes a pointer to `/dev/uinput`.

Three things about the vendor kernel's uinput are worth writing down:

1. The `UI_SET_*BIT` ioctls take the bit **value** as the argument, not a
   pointer to it. Passing a pointer is taken for a huge bit number → `EINVAL`.
2. `struct uinput_user_dev` keeps `struct input_id` **first** in this kernel
   (with the upstream name-first order the device comes out called
   "ouch Panel" — the name copied from offset 8).
3. The kernel **ignores the absmin/absmax arrays** of that struct: a virtual
   absolute device comes out with a 0..0 range and libinput drops it. Probed
   the whole struct; no offset produces a range.

So the bridge emits a **relative** pointer (REL_X/REL_Y + BTN_LEFT), which needs
no range at all. Verified: libinput `Capabilities: pointer`, sway
`"type": "pointer"`, and a tap produces `BTN_LEFT 1/0` plus `REL_X/REL_Y`.

### For DS games

- **Draxcast** (the standalone NDS emulator) takes the mouse, so the pointer is
  the stylus.
- **melonDS through RetroArch** uses RetroArch's touchscreen input driver, which
  reads the pointer position, so the same bridge feeds it.
- The bridge maps finger motion 1:1 (it forwards the panel deltas), so a drag
  along the DS touch screen moves the stylus along it.

---

## What the flasher does now

`archr-patcher` produces a ready-to-flash image in one command:

```sh
sudo python3 main.py patch --image <arch-r.img> --device rg353v \
     --out archr-rg353v.img --base <darkos.img>
```

`patch` now also runs `prepare-boot.sh` (a `prepare` subcommand exists for an
image that was already patched):

- injects the RG353V's dual-mode initramfs (the dArkOS one is btrfs-only and
  the Arch-R rootfs is ext4 — the port's `uInitrd.live`);
- writes the `NORMAL` marker so the initramfs boots the real rootfs;
- caps the Wi-Fi SDIO bus (`sdmmc2` / `fe000000`) to **25 MHz** (TurboRelic's
  fix: this board's SDIO signal integrity breaks above it and the probe hangs
  the kernel).

Then `main.py flash --image ... --target /dev/sdX`, which is a plain `dd`.
