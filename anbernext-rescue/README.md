# AnberNext rescue kit — black screen without pulling the card

Built on 2026-11-21 after the RG353V stopped showing anything at all (no splash,
no new logs on the card) even after a full charge.

## What was actually wrong

The card was compared byte-for-byte with the pristine `anbernext-v3.26-rg353v.img`:

| Region | Result |
|---|---|
| p1 (`uboot`), p2 (`resource`), p3 (`NEXTBOOT`, every boot file) | **identical** |
| p4 (`NEXTROOT`) ext4 | clean (`e2fsck -fn`: 0 errors) |
| p5 (`NEXTUI`) FAT | clean (after the earlier dirty-bit repair) |
| loader gap, sectors 64–16383 (`0x8000`–`0x7FFFFF`) | **differs** |

The only difference was a small runtime state block at **`0x380000`**, magic
`DVKR`, written by the bootloader into the gap between the 32 KiB Rockchip FIT
and partition 1. The pristine image has zeros there. A power cut mid-write (the
device died at 2 % during a store download) can leave that block inconsistent,
after which the loader never reaches the kernel/initramfs — exactly the symptom:
black screen and nothing written to `relatorio-rg353v.txt`.

Fix applied: rewrote sectors 64–16383 from the pristine image. The old block is
saved in `rg353v-backup/anbernext-loader-state-20261121.bin` (8 MiB) for
forensics.

```
dd if=anbernext-v3.26-rg353v.img of=/dev/mmcblk0 bs=512 skip=64 seek=64 \
   count=16320 conv=notrunc,fsync
```

This does **not** touch the GPT or any partition, and `android.*` on p3 stays as
shipped (`android.req = no`).

## What this kit adds

1. **Stage-1 trace** (patched `uInitrd`): after each step the init appends to
   `NEXTBOOT/boot-trace.txt`. No trace = the kernel/initramfs never ran. Trace
   ending at `root mounted` = switch_root/`nextui-init` problem.
2. **Rescue shell** (`rescue-shell`, static aarch64, Go): TCP **2323**, password
   **`ark`**, gives `/bin/sh` on the rootfs even with a dead display.
3. **Boot hook** (`50-rescue.sh`): logs DRM/backlight/dmesg to
   `.userdata/rg353/logs/rescue.txt`, forces `bl_power=0` if something left the
   panel off, waits for Wi-Fi, starts the shell.
4. **Stay-alive guard**: `MinUI.pak/launch.sh` normally powers off after three
   quick menu crashes. With the marker `.userdata/rg353/rescue-mode` present it
   retries forever instead, so the rescue shell survives.

## Use

```sh
# on the laptop, once the device is on the LAN
printf 'ark\n' | nc <device-ip> 2323
# or: telnet <device-ip> 2323
```

The shell starts before the menu and binds `0.0.0.0:2323`; it is reachable as
soon as `wlan0` has an address.

## Revert (when done)

On the NEXTUI partition, remove:

* `.userdata/rg353/.hooks/boot.d/50-rescue.sh`
* `.userdata/rg353/rescue-shell`
* `.userdata/rg353/rescue-mode`
* restore `.system/rg353/paks/MinUI.pak/launch.sh` from
  `.userdata/rg353/launch.sh.pre-rescue`

On NEXTBOOT, restore the stock initramfs by mounting p3 read-write and copying
the stock file back over `uInitrd`:

```sh
cp rg353v-backup/boot/anbernext-v3.26/uInitrd /media/NEXTBOOT/uInitrd
sync
```

`patch-initramfs.sh` regenerates the traced one from that stock file at any
time, so nothing here is one-way.

## Notes

* The rescue shell has **no encryption** and one shared password. Treat it as a
  bench/debug tool, not something to leave on a device you carry around.
* The password is in `main.go`; rebuild with `./build.sh`.
* The boot hook runs from `MinUI.pak/launch.sh` via `run_hooks.sh boot.d`; it
  returns immediately and detaches the slow parts so the menu is not delayed.
* `boot-trace.txt` grows by 4 lines per boot; delete it freely.
