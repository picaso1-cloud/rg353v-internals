# 07 — Regenerating the firmware (build, flash, backup, restore)

The goal: be able to rebuild/restore the device's OS at any time, from
documented pieces.

## Flash anatomy (how GammaOS gets onto the device)

RK3566 devices flash via Rockchip **Loader/Maskrom mode** using
`rkdeveloptool` (CLI) or **RKDevTool** (GUI, Windows):

1. Boot into **Loader mode**: power off → hold volume-... on GammaOS devices
   usually: with the device ON, `adb reboot loader`, or use Maskrom
   (short/hold while powering) if the loader is unreachable.
2. `rkdeveloptool ld` → device listed in Loader/Maskrom.
3. `rkdeveloptool boot <miniloader/loader blob>` if in Maskrom (the GammaOS
   release provides the loader).
4. Flash partitions individually:

```
rkdeveloptool wl 0x0   <uboot.img>          # or flash via rkdeveloptool ul
rkdeveloptool w 0x0    trust.img            # partition offsets per the GPT below
rkdeveloptool w 0x...  boot.img
rkdeveloptool w 0x...  dtbo.img
rkdeveloptool w 0x...  vbmeta.img
rkdeveloptool w 0x...  super.img
rkdeveloptool w 0x...  userdata.img         # optional
```

5. `rkdeveloptool reset`.

Partition order (from `/dev/block/by-name`, GPT on eMMC): security, uboot,
trust, misc, dtbo, vbmeta, boot, recovery, backup, cache, metadata,
baseparameter, **super**, userdata. The firmware release's flasher script
contains the exact offsets — archive it with the images.

## Regenerating from upstream sources

Pieces to assemble a GammaOS build:

1. **Vendor BSP + kernel**: TheGammaSqueeze/GammaOS-RK3566 (kernel prebuilt +
   vendor images + device pack).
2. **GSI**: Pixel 3a sargo Android 12 GSI (GammaOS v1.5) — or the GammaOSNext
   Android 14 / LineageOS 21 GSI (GammaOSNextDistribution-14).
3. **Assembler**: GammaOS distribution scripts (pack super.img from
   system/vendor/odm via lpmake, sign vbmeta with verification disabled, emit
   the flasher + images).

Archive list to keep for regeneration:

- the exact firmware zip used (contains GSI + vendor + loader + flasher)
- Magisk-patched `boot.img` (or the recipe: patch_boot + vbmeta disable flags)
- `/data/adb/service.d/` scripts (adb-wifi, future tuning)
- userdata backup tar (apps + data + tailscale auth)

## Backup / restore (device state)

Full-state backup over root adb (before any upgrade):

```sh
# boot + vbmeta + dtbo images
for P in boot vbmeta dtbo uboot trust super; do
  su -c "dd if=/dev/block/by-name/$P of=/data/local/tmp/$P.img" 
done
adb pull /data/local/tmp/<P>.img .
# userdata (apps+data; excludes caches)
su -c "tar cf /data/local/tmp/ud.tar --exclude='data/app/*/*.cache' -C /data ."
adb pull /data/local/tmp/ud.tar .
```

Restore = flash the partition images back + extract ud.tar onto a freshly
formatted userdata, then re-flash Magisk into boot.

## Current state archived

- GammaOS_Lite_v1.5 as-received survey data: `survey/` (this repo).
- The device currently runs the as-received firmware + the adb-wifi Magisk
  script + (planned) tuning scripts. Nothing irreversible done — any flash
  can return it to stock.
