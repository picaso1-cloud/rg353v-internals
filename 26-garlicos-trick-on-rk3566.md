# 26 — Could the GarlicOS trick unlock mainline here? (no — but one part is useful)

**Date:** 2026-11-21 · **Short answer:** the trick does not bypass the eMMC
bootloader and cannot reach a mainline kernel. One variant of it *is* valuable as
a rescue path that keeps Android intact.

## What the GarlicOS trick actually does (RG405 / Unisoc)

1. keep the **stock, signature-verified boot chain** running,
2. replace only the **ramdisk** inside `vendor_boot`,
3. re-sign the metadata with a key the bootloader accepts (`avbtool` testkey +
   Unisoc `DHTB` wrapper),
4. the ramdisk mounts an f2fs rootfs from SD and `chroot`s into it.

It works because it *uses* the trusted chain instead of replacing it. The kernel
stays the **vendor** kernel (Android 5.4 on T618).

## Mapping to the RG353V (RK3566, GammaOS on eMMC)

The RK3566 equivalent is: patch the ramdisk of the eMMC `boot` (or `recovery`)
image so the Android BSP kernel mounts our SD rootfs. Our unit is **unlocked**
(`verifiedbootstate=orange`), so no re-signing dance is required — a modified
`boot.img`/`recovery.img` can be flashed directly, and Maskrom/`rkdeveloptool`
can recover a bad write.

**But it does not give mainline:**

| Requirement | Status |
|---|---|
| Boot chain still runs the eMMC bootloader | yes — that is the point of the trick |
| Kernel | **still the Android 5.10 BSP kernel** |
| Mainline via chaining | needs `kexec` — we verified `# CONFIG_KEXEC is not set` in the Android kernel |
| Panfrost / panvk | needs mainline DRM, i.e. a mainline kernel |

So it is **a second route to the same 5.10 kernel** we already boot via dArkOS.
It cannot lift the eMMC bootloader gate, which is what blocks ROCKNIX.

## The useful variant: a rescue in the RECOVERY partition

Instead of `boot`, patch **`recovery`**:

- Android keeps booting normally (default path untouched),
- holding **power + volume down** boots our **Linux RAM rescue** on the Android
  kernel (no SD boot chain needed at all),
- restoring is trivial: Android still boots, so the original `recovery.img` can be
  flashed back from inside Android (`dd` / Magisk shell) — no PC, no Maskrom.

Value: this is the **missing safety net for kernel experiments**. Today a bad
`/Image` on the SD locks us out until the card is pulled; with a recovery-partition
rescue, the eMMC path always yields a working Linux that can rewrite the card.

It still does **not** produce mainline/panfrost — it just makes experiments
recoverable.

## Decision matrix (updated)

| Goal | Path | Android kept? |
|---|---|---|
| Arch userland, current 5.10 | dArkOS loader + ArchR (done) | ✅ |
| Mainline + panfrost | wipe/zero eMMC bootloader area, then ROCKNIX | ❌ bootloader area must go |
| Kernel experiments without card pulls | **recovery-partition Linux rescue** | ✅ |
| andr36oid on RG353V (planned) | Android eMMC must stay — unaffected by all of the above | ✅ |

**Conclusion:** keep Android. Use the recovery-partition rescue if we want to
continue kernel experiments; otherwise the working ArchR-on-5.10 is the ceiling.
