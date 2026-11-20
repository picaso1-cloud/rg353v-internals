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

1. **sway on the vendor libmali G31 bookkeeping blob** — `gpudriver.log` said
   `libmali bound OK (card=1 bind=1 display=1)`, but the blob is named for a
   Mali-G31 while this SoC has a Mali-G52. If sway dies in EGL, the fallback is
   `WLR_RENDERER=pixman`; the proper fix is the RK3566 G52 wayland-gbm blob.
2. GPU devfreq node name (`fde60000.gpu`) — probed at boot by the quirk.
3. `archr-levels` brightness/volume scaling for the kd35t133 backlight.
4. Whether the launcher's hotkey = `system_hk` button 10 (F) works as expected.
