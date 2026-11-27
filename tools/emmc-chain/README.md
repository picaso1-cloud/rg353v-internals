# tools/emmc-chain — the RG353V dual-boot boot-chain patch

The RG353V's BootROM boots the **eMMC** first; the card's own bootloader is
never executed while Android is installed. The way to add "boot Linux from
TF1" without wiping Android is to replace the compiled-in `bootcmd` in the
eMMC's u-boot FIT.

`patch-uboot.py` does exactly that, in place and with the FIT sha256 records
recomputed. It is verified to reproduce the image that is running on the
device byte-for-byte.

## Usage

```sh
# 1. extract the u-boot partition (4 MiB at 8 MiB) from the backup
dd if=emmc-first16MiB-20261127.img of=uboot.img bs=1M skip=8 count=4

# 2. the dual-boot script (single line, no NULs)
cat > bootcmd.txt <<'EOF'
if test -e mmc 1:3 /extlinux/extlinux.conf; then mw.b 0x60000000 0x31; save mmc 1:3 0x60000000 s1 2; setenv kernel_addr_r 0x2000000; sysboot mmc 1:3 any 0xc00000 /extlinux/extlinux.conf; mw.b 0x60000000 0x32; save mmc 1:3 0x60000000 s2 2; setenv kernel_addr_r 0x00280000; fi; boot_fit; boot_android mmc 0
EOF

# 3. patch + validate
./patch-uboot.py --input uboot.img --bootcmd-file bootcmd.txt \
                 --output uboot-patched.img --verify

# 4. write back (from Android with root, or any booted Linux)
dd if=uboot-patched.img of=/dev/mmcblk0 bs=1M seek=8 conv=fsync

# 5. rollback
dd if=emmc-first16MiB-20261127.img of=/dev/mmcblk0 bs=1M conv=fsync
```

## What the script asserts

* 4 MiB input, FIT magic at 0x0 and 0x200000 (the two copies)
* the `bootcmd` slot is found and the new script fits (5 467 B on the stock build)
* the old sha256 is found **exactly once** in each FIT FDT
* only the bootcmd bytes + the two 32-byte hash records change

`--verify` prints the new hash records via `dumpimage -l`.

## Notes

* The card's own u-boot has a **different layout** (`bootcmd` at `0xbb820`,
  value 88 B, u-boot data at `0xe0`/`0x11f628`) — see
  `34-emmc-dualboot-chain.md` §6. Do not use this script unmodified on it.
* LBA 40 (`0x28`) is used as a scratch/probe sector by the earlier diagnostic;
  it is free space (GPT ends at 33, the idblock starts at 64).
* If the patch is ever wrong, the 16 MiB backup restores everything.
