# RG353V firmware — how it is composed and rebuilt

Three independent parts. Only the third is device-specific; the rootfs is
**stock ArchR** with the port applied by `apply.sh`.

| Part | Where | Contents |
|---|---|---|
| **Boot chain** | TF1 p3, FAT `dArkOS_Fat` | dArkOS 5.10.226 `Image`, `rk3566-353v.dtb`, dual-mode `uInitrd`, `extlinux/extlinux.conf`, `NORMAL` marker |
| **Rootfs** | TF1 p4, ext4 `ARCHR_ROOT` | **ArchR 20261113** (Arch Linux ARM) + this port |
| **Games/BIOS** | TF2, FAT32 | `roms/` (178 systems) + `bios/` (730 files), mounted at `/storage/games-external`, BIOS via symlink |

The eMMC (Android/GammaOS) is **never touched**. The dArkOS bootloader reads
p3 and boots the 5.10 kernel; everything else is ArchR.

## Rebuild the rootfs from the original image

```sh
# 1. start from the original ArchR image (never boot this one directly —
#    it is an RK3326 build with the wrong GPU blob and no device quirks)
cp rg353v-backup/arch-rootfs/archr-rootfs.img \
   rg353v-backup/images/archr-rg353v-port.img

# 2. apply the port (idempotent; works on a card `p4` or on an image file)
cd rg353v-internals/tools/archr-port
sudo bash apply.sh /path/to/archr-rg353v-port.img

# 3. flash it to p4 (card in the laptop, TF1 = /dev/mmcblk0)
sudo dd if=/path/to/archr-rg353v-port.img of=/dev/mmcblk0p4 bs=4M conv=fsync
```

p3 files come from `rg353v-backup/darkos-kernel/` (kernel + dtb) and
`rg353v-backup/live/uInitrd.live` (dual-mode initramfs); `extlinux.conf`
boots `Image` + `rk3566-353v.dtb` + `uInitrd`.

## What apply.sh changes (all proven on hardware)

| Area | Change |
|---|---|
| identity | `HW_DEVICE=RK3566` in os-release → ArchR runs RK3566 quirks |
| quirks | `platforms/RK3566`, `devices/Anbernic RG353V-VS` (audio mux, thermals, jack polarity, model string with `/`→`-`) |
| GPU | Mali-G52 **wayland-gbm** blob (`g24p0` DDK) + hook. The G31 blob is rejected (different GPU id) and a g29p1 build is fbdev-only (no Wayland EGL) |
| ABI shim | `fchmodat2_compat.so` via `/etc/ld.so.preload` — glibc 2.40's `fchmodat()` needs the fchmodat2 syscall (Linux 6.6+); without it every settings write fails and the session/launcher abort |
| audio | SDL apps use **ALSA** (SDL2 pulse backend aborts against pipewire-pulse); mixer `Playback Path` SPK/HP, jack watch via rk-headset |
| Wi-Fi | `wpa_supplicant` (shipped) + udhcpc, `wifi.enabled=1` (else 099-networkservices rfkill-blocks the radio), `systemd-rfkill` masked |
| storage | `/storage` on the rootfs + `rg353v-storage-bind.service` (ArchR services require a mountpoint); corrected `mountpoint` (BusyBox misreports self-binds) |
| zram | `/storage/.config/swap.conf` → 1536 MB zstd (memory-manager now runs) |
| TF2 | `system.automount=1`; eMMC guarded by the `mmcblk0boot0` check; BIOS symlink |
| session | `default.target → archr.target`; sway + archr-launcher unmasked; connman/iwd/stock sshd masked |

## Expected result after flash

- boot ≈ 20 s to multi-user, launcher in ≈ 45 s
- Wi-Fi auto-connects (`CPE-C391`, DHCP)
- 0 failed units; zram 1536 MB; ~97 % idle at the launcher
- TF2 systems visible; BIOS resolves; PortMaster self-installs on first use
- SSH always available: `root@<ip>` / `ark`

## Known nits (not blockers)

1. `pacman -Q`/`archr-update` warn because the image ships no pacman DB
   (upstream `pacman-image-db.tar.gz` seeding is a follow-up).
2. PortMaster's device report tees to a path containing the model string
   `RG353V/VS` — the slash breaks one filename (cosmetic).
3. Launcher cover warnings for `.svg` images (its loader is raster-only).
4. Restarting `archr-automount` by hand stacks duplicate mounts (a boot mounts once).
