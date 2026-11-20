# 21 — Boot chain: verified on hardware (S1 log + live SSH)

**Date:** 2026-11-20 · **Method:** our S1 initramfs log (`S1-LOG.txt`) plus a
read-only SSH session on the running dArkOS. No guesses left in this document.

## The chain, as it actually runs

```
BootROM -> eMMC SPL -> SD u-boot FIT (dArkOS's)
   u-boot READS /extlinux/extlinux.conf
     loads /Image, /rk3566-353v.dtb, /uInitrd
     bootargs  = extlinux APPEND  (root= replaced, console= replaced, earlycon appended)
   kernel 5.10.226 (dArkOS)
     initramfs (uInitrd)  ->  mounts /dev/mmcblk1p4  <-- HARDCODED
       run-init -> systemd -> dArkOS
```

### Proof 1 — extlinux is read, but `root=` is not ours

| Token | extlinux.conf | actual cmdline |
|---|---|---|
| root | `root=/dev/mmcblk1p4` | `root=PARTUUID=614e0000-0000` |
| initrd | `initrd=/uInitrd` | *(consumed by the loader, absent)* |
| console | `console=tty1` | `console=console=ttyUSB0,115200` *(double prefix — dArkOS build bug)* |
| everything else | `rootwait rw fsck.repair=yes quiet splash vt.global_cursor_default=0 net.ifnames=0 plymouth.ignore-serial-consoles consoleblank=0 loglevel=5 video=HDMI-A-1:1280x720@60` | **identical, same order** |
| extra | — | `earlycon=uart8250,mmio32,0xfe660000` |

So: the loader reads `extlinux.conf`, but **overrides `root=`** with a value of
its own. `console=tty1` is also lost — our banner still appeared because it
writes to `/dev/tty1` explicitly.

### Proof 2 — the initramfs ignores `root=` completely

In the extracted `uInitrd`, `scripts/local` is patched so that the device is
hardcoded:

```sh
local_device_setup()
{
	local dev_id="/dev/mmcblk1p4"     # <- dArkOS patch; takes precedence over ROOT
	...
}
```

`blkid -t PARTUUID=614e0000-0000` finds nothing on the device, yet root mounts —
because the value is never used. **dArkOS always boots whatever is on TF1 p4.**

### Consequence for us

Any rootfs on TF1 partition 4 boots with dArkOS's kernel and initramfs.
That is what makes S2 a partition write instead of a loader project.

(The hybrids are *not* explained by this: they carried ROCKNIX's own kernel and
initramfs, so dArkOS's hardcoded root was never in play. The ROCKNIX track stays
closed.)

## Other verified facts from the same session

| Item | Value |
|---|---|
| Kernel | `5.10.226 #1 SMP` — Debian 13 (trixie), dArkOS |
| GPU | **mali kbase built into the kernel** (`mali fde60000.gpu: Kernel DDK version g25p0-00eac0`), no modules → panfrost/panvk impossible without a new kernel |
| Vulkan | vendor ICD only: `libmali-bifrost-g52-g29p1.so`, API 1.3.276 |
| kexec | `# CONFIG_KEXEC is not set`, `# CONFIG_KEXEC_FILE is not set` → the eMMC chain-load bridge (doc 20) cannot reach a mainline kernel |
| Debug UART | loader passes `earlycon=uart8250,mmio32,0xfe660000` → UART2 pads are live (115200/1500000 per the bootargs pair) |
| eMMC | `mmcblk0` 29.1 GB, **14 partitions** (+ `boot0`/`boot1` 4 MB each) |
| TF1 | `mmcblk1` (the 8 GB card) |
| TF2 | `mmcblk2` 233 GB vfat — the certified Samsung card, **ROMs; do not touch** |
| Panel | DSI connected (`card0-DSI-1`), backlight 77/255, model `Anbernic RG353V/VS` |
| `/roms` | 135 MB, 100 % full (8 GB card → expansion could not grow it) |

## Artifacts captured

- `~/Andr36oid/rg353v-backup/images/s1/S1-LOG.txt` — the full S1 boot log
- `~/Andr36oid/rg353v-backup/darkos-kernel/kernel-5.10.226.tar.gz`
  (modules + firmware + `Image` + dtb, 55 MB, sha256 `360b2774…a5c26`)
