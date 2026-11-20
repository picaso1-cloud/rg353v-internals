# S2 rootfs overlay — Wi-Fi + SSH + no boot loop

Copy over the rootfs (p4), then enable the units (or pre-create the symlinks):

    cp -a . /path/to/p4/
    cd /path/to/p4/etc/systemd/system
    for u in wpa-wlan0 dhcp-wlan0 sshd-s2; do
      ln -sf /etc/systemd/system/$u.service multi-user.target.wants/$u.service
    done
    for u in archr-autostart archr-launcher-session sway; do
      ln -sf /dev/null $u.service        # mask the sway restart loop
    done

External files needed (not in this repo):
- `/usr/local/wpa/wpa_supplicant` + `/usr/local/wpa/lib/{libnl-3,libnl-genl-3,libnl-route-3}.so.200*`, `libpcsclite.so.1`
  — copied from the dArkOS image (`/usr/sbin/wpa_supplicant`, Debian 13 aarch64).
  Arch-R ships connman but no wpa_supplicant; all other NEEDED libs exist in Arch.

Wi-Fi: RTL8821CS, vendor module `8821cs` from the bundled dArkOS 5.10.226 module
set, firmware `rtw88/rtw8821c_fw.bin` present.

SSH: `root` / `ark` (also `ark`/`ark` if that user exists).
