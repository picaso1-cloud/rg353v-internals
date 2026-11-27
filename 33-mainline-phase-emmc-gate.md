# 33 — Mainline + Panfrost/PanVK: the plan, and the eMMC gate

**Date:** 2026-11-27 · **State:** ROCKNIX card built and verified; the eMMC
step pending · **Goal:** run a **mainline kernel** with **Panfrost/PanVK**
(Vulkan) instead of the dArkOS 5.10 BSP kernel

Docs 25 and 28 established the wall: the eMMC's **legacy dual-boot
bootloader** runs first, only accepts the ArkOS/dArkOS FIT, and rejects both
mainline u-boot and a raw mainline `Image`. ROCKNIX's own wiki says it plainly:

> "eMMC models with legacy bootloader is not supported." … **"P/M/V Users —
> You will need to wipe the Android partition to boot into ROCKNIX."**
>
> Kernel: **Mainline Linux** · GPU: libmali (GLES 3.2) **& Panfrost
> (GL 3.1/GLES 3.1)** · Sway · "L1+SELECT+B — **Touchscreen toggle**"

So mainline is reachable, but only after the eMMC boot chain is out of the way.

---

## The eMMC, measured (not guessed)

`mmcblk0` = the eMMC, 14 GPT partitions, **Android/GammaOS**:

```
LBA 64 … 8191   32 KiB … 4 MiB   idbloader/SPL ("RKNS" at 32 KiB)   ← the gate
p1  security      @4 MiB  4 MB
p2  uboot         @8 MiB  4 MB   FIT (d0 0d fe ed)
p3  trust         @12 MiB
p4  misc          @16 MiB
p5  dtbo          @20 MiB
p6  vbmeta        @24 MiB
p7  boot          @25 MiB        49 MB
p8  recovery      @74 MiB        96 MB
p9  backup        @170 MiB      384 MB
p10 cache         @554 MiB      384 MB
p11 metadata      @938 MiB       16 MB
p12 baseparameter @954 MiB        1 MB
p13 super         @955 MiB     5426 MB   (Android's dynamic partitions)
p14 userdata      @6381 MiB  23438 MB    f2fs
```

**What we zero:** exactly **LBA 64–8191** (32 KiB–4 MiB) — the SPL. The GPT
(LBA 0–63) and every Android partition stay untouched, so Android is only
missing its boot chain, not its data.

**Backup (done):** `rg353v-backup/emmc/emmc-first16MiB-20261127.img`, 16 MB,
sha256 `f69a4bc63d61eb4eaa013ecdd48c57e9bce4d65888b61ad355eea52d3588b716`,
verified to contain "RKNS" at 32 KiB.

**Restore:** write those 16 MiB back (`dd … of=/dev/mmcblk0`) — from ROCKNIX
(its SPL boots, see below) or through Maskrom.

---

## The ROCKNIX card (built)

`ROCKNIX-RK3566.aarch64-20261101-Specific.img.gz` (sha256 verified
`0e0b73a0…76931`), flashed to the 250 GB test card.

- Its **SPL at 32 KiB is present** ("RKNS") — this is what the BootROM runs
  once the eMMC's is gone, and what makes the card itself the recovery boot.
- `device_trees/rk3566-anbernic-rg353v.dtb` is shipped. `extlinux.conf` names
  the X55 DTB, but the Anbernic u-boot replaces it by **ADC board detection
  (RG353V = 695)** and DSI panel probing, per doc 25.
- The card is a **counterfeit** ("limbo", 52.39 GB real of 250 GB claimed),
  confirmed by `f3probe`. It is used for this test only, and the image + data
  stay inside the real area:
  - `system` (ROCKNIX, FAT) 2 GB @16 MiB
  - `storage` (ext4) **20 GB**
  - `fence` 30.4 GB — a dummy partition that ends at the **real** LBA
    109 878 238, so ROCKNIX's first-boot resize cannot grow into the fake
    tail (which would wrap and corrupt the real data).
  - The GPT was rebuilt from a 52.39 GB sparse file for the same reason (the
    backup GPT sits at the real end, not the fake one).

---

## Recovery paths, in order

1. **ROCKNIX's own SPL.** With the eMMC's SPL zeroed the BootROM falls through
   to the SD, which has a valid SPL — a working Linux to restore the eMMC from.
2. **Maskrom + rkdeveloptool** (`rkdeveloptool` 1.32 installed on the laptop).
   Hold the maskrom/recovery key while applying power/USB, then
   `rkdeveloptool ld` must list `Maskrom`, and
   `rkdeveloptool wl 0 emmc-first16MiB-20261127.img` writes the backup back
   (sector 0 = LBA 0). **Test this entry BEFORE zeroing anything.**

---

## Steps

1. **S1 — boot the ROCKNIX card with the eMMC untouched.** Expect Android: it
   confirms the gate and proves the card is readable (zero risk).
2. **S2 — zero LBA 64–8191** on the eMMC and reboot.
3. **S3 — ROCKNIX boots.** Verify: the panel (v2 = the `0x3821` one), the
   touch (L1+SELECT+B toggles it), buttons, Wi-Fi, then the GPU:
   `vulkaninfo --summary` (PanVK?), `glxinfo -B` (Panfrost GL 3.1?), and a game.
4. **S4 — restore Android** when done: write the 16 MiB back, clear the SD.

## Open risks

- ROCKNIX's kernel/DTB might not bring up this unit's panel → a black screen
  with no serial console and no network yet. Mitigation: the eMMC backup +
  Maskrom, and step 1 proves the card is readable.
- The test card is counterfeit: fine for a 2–20 GB test, not for a library.
