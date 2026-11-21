# ArchR port overlay for Anbernic RG353V/VS (RK3566)

Turns an ArchR **RK3326** rootfs into an RG353V system running on the
dArkOS 5.10 BSP kernel (the only kernel the eMMC legacy bootloader lets us
boot while Android stays installed).

## What it changes

| Area | Change | Why |
|---|---|---|
| Identity | `HW_DEVICE=RK3566` in `/etc/os-release` | ArchR picks platform quirks by this name; without it no RK3566 quirk runs |
| Platform quirks | new `quirks/platforms/RK3566/` | copied from RK3326, with the RK3566 GPU devfreq node (`fde60000.gpu`) and the RG353V mixer (`Playback Path`) |
| Device quirks | new `quirks/devices/Anbernic RG353V-VS/` | DT model is `Anbernic RG353V/VS`; `/etc/profile.d/002-autostart` turns `/` into `-` |
| Storage | `/storage` moved onto p4 | p5 is the 137 MB ArkOS `EASYROMS` partition; the image tried to mount it at `/storage` |
| Gamepad | es_input patch + `098-controller` + RetroArch udev cfg | `singleadc-joypad` "retrogame_joypad": buttons 0-12, D-pad 13-16, sticks axes 0-3; F/MODE = button 10 |
| Session | unmask `archr-autostart`, `archr-launcher-session`, `sway`, `archr-levels`, `archr-automount`; `default.target -> archr.target` | the real ArchR UI (sway + archr-launcher) instead of a bare console |
| Network/SSH | keep `wpa-wlan0` + `dhcp-wlan0` + `sshd-s2`; mask `iwd`, `connman`, stock `sshd` | one manager, one sshd, no races on wlan0/port 22 |
| Console | dashboard off, shell on tty2 | sway owns tty1; SSH is the primary fallback |

Deliberately **not** enabled: `sway.service` / `archr-launcher-session.service`.
`archr-autostart` starts them *after* it has written `095-sway` and the sway
config, which is the order ArchR expects.

## Use

```sh
# card in the laptop, TF1 = /dev/mmcblk0
sudo bash apply.sh /dev/mmcblk0
# back to console-only if the UI needs debugging
sudo bash revert.sh /dev/mmcblk0
```

Then make sure p3 has the `NORMAL` marker so the dual-mode initramfs boots p4:

```sh
sudo mount /dev/mmcblk0p3 /mnt && sudo touch /mnt/NORMAL && sync && sudo umount /mnt
```

## First-boot diagnostics (over SSH)

```sh
systemctl --failed
systemctl status archr-autostart sway archr-launcher-session archr-levels
cat /var/log/sway.log
cat /var/log/archr-launcher-session.log
cat /var/log/boot.log
journalctl -b -u sway -u archr-autostart -u archr-launcher-session --no-pager | tail -100
ls -l /dev/mali0 /dev/dri/
cat /proc/bus/input/devices | grep -A4 retrogame
amixer -c 0 controls | grep -i 'playback path'
```

The journal is persistent now (`/var/lib/journal`), so a failed boot keeps its
evidence across a reboot.

## Hardware facts used (from the on-card `rk3566-353v.dtb`)

- panel `elida,kd35t133` v2 (`panel id: 38 21`), PWM backlight 0-255
- audio `rockchip,multicodecs-card` + `rk817` codec, mux `Playback Path` = `SPK`/`HP`
- gamepad `singleadc-joypad` "retrogame_joypad", vendor `0x484b`, product `0x1101`
- buttons: volume up/down on `gpio-keys` (`KEY_VOLUMEUP/DOWN`)
- LEDs: `battery_full`, `battery_charging`, `low_power` (kernel triggers)
- thermal: `soc-thermal` (zone0), `gpu-thermal` (zone1)
- Wi-Fi `rtl8821cs` (vendor `8821cs` module), Bluetooth node disabled in this DT

## Known unknowns to verify on hardware

1. Whether the G52 DDK (`g29p1-12eac0`) hands sway a GBM EGL platform — if it
   still fails, add `MALI_PLATFORM=gbm` or fall back to `WLR_RENDERER=pixman`.
2. GPU devfreq node name (`fde60000.gpu`) — probed at boot by the quirk.
3. `archr-levels` brightness/volume scaling for the kd35t133 backlight.
4. Whether the launcher's hotkey = `system_hk` button 10 (F) works as expected.

## What the first boot taught us (2026-11-21 night)

Three boot cycles, ~70–90 s each, then the box went dark. The flight recorder
(`/storage/.cache/log/`, error reports in `/storage/.cache/error-reports/`)
named three independent bugs:

| Bug | Evidence | Fix |
|---|---|---|
| **G31 DDK on a G52 GPU** — sway crash-looped 11× in 70 s, each attempt poking a kernel that then locked | `sway.log`: "The DDK (built for 0x7000003) is not compatible with this Mali GPU … 0x7040002" | the Mali-**G52** blob from the dArkOS image (`g29p1-12eac0`, proven on this very kernel), installed as `libmali.so.1.9.0` |
| **rfkill soft-block resurrected every boot** — Wi-Fi never associated, `udhcpc: Network is down` | journal: `wpa_supplicant: rfkill: WLAN soft blocked`; poison file `/storage/.cache/rfkill/platform-fe000000.dwmmc:wlan` | delete the saved state, mask `systemd-rfkill.service`, unblock inside the `wpa-wlan0` wait loop |
| **`chmod` → ENOSYS** — `set_setting` failed, `archr-levels` core-dumped on loop | error reports: `exit: core-dump (status 6)`; journal: `chmod: changing permissions … Function not implemented` | coreutils uses `fchmodat2()` (Linux 6.6+); `rewrite_config` now copies modes with python3 (`fchmodat`, exists on 5.10) |

Also: this rootfs has **no `/var/log`** — everything lives in
`/storage/.cache/log/` (boot.log, sway.log, journal). Use
`read-p4-logs.sh` after a crash; it knows the real paths.

`apply.sh --safe` masks the UI so the boot cannot reach the GPU; start it over
SSH once the box is verified stable.

## TF2 ROMs/BIOS wiring (2026-11-21)

- `system.automount=1` — ArchR's own automount handles the second card:
  it skips the system disk by name and the eMMC via the
  `/sys/class/block/mmcblk0boot0` Android guard, then mounts TF2
  (`/dev/mmcblk2p1`, **FAT32**, 233 GB) at `/storage/games-external`
  and publishes `/run/archr/roms2 → /storage/games-external/roms`.
- `/storage/bios → /storage/games-external/bios` symlink (730 files) so
  every core finds BIOSes without copies.
- `archr-roms-migrate` stays masked (nothing must move the collection).
- The launcher lists TF2 systems natively via roms2; saves write back to
  the card (vfat rw, uid=0). Restarting `archr-automount` stacks duplicate
  mounts (cosmetic; a fresh boot mounts once).

## PortMaster / commander (file manager)

- **PortMaster was never installed** — the launcher's `Start PortMaster.sh`
  runs `/usr/bin/start_portmaster.sh`, which unpacks
  `/usr/config/PortMaster/release/PortMaster.zip` into
  `/storage/roms/ports/PortMaster` on first run. It failed silently in the
  fchmodat2 era (unzip cannot set permissions); with the shim it installs
  and runs, and its device report correctly says `RG353V/VS - ArchR`.
  Known upstream nit: it tees device_info to a path containing the model
  string `RG353V/VS` — the slash breaks the filename (cosmetic).
- **commander** (file manager, `/usr/bin/commander`) runs fine under sway;
  earlier failures were the same era.
