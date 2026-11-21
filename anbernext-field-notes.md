# AnberNext field notes (RG353V)

Collected on the running v3.26 card, 2026-11-21.

## Where the evidence lives

| What | Path on the NEXTUI partition |
|---|---|
| boot report, rewritten every boot | `relatorio-rg353v.txt` |
| launcher log (menu start/exit, pak runs) | `.userdata/rg353/logs/launch.txt` |
| menu's own stdout/stderr | `.userdata/rg353/logs/nextui.txt` |
| kernel snapshot | `.userdata/rg353/logs/kernel-live.txt` |
| battery/CPU/top samples (~2 s) | `.userdata/rg353/logs/power-live.txt` |
| button events | `.userdata/rg353/logs/neondrive-keys.log` |
| per-pak logs | `.userdata/rg353/logs/<Pak>.txt` |
| crash dump from the previous session | `.userdata/rg353/logs/*.prev.txt` |
| firmware status | `.system/rg353/anbernext-version.txt` |

If `relatorio-rg353v.txt` was not rewritten, the machine never reached stage 2
of `nextui-init` — look at power, not at software.

## Black screen on 2026-11-21: empty battery, not a firmware fault

Timeline (UTC, from `launch.txt` / `power-live.txt`):

```
20:16:51  boot, battery 3440 mV, gauge 38 %, discharging -640 mA
20:22     Pak Store running, paks being installed
20:31:54  last clean menu exit
20:34:56  store downloading (curl), gauge 2 %
20:35:11  last log line — system stopped (no clean shutdown)
```

* No boot report after the 20:16 boot → the following power-on never reached Linux.
* FAT dirty bit + a truncated `cheats.zip.tmp` → the card was cut mid-write.
* The gauge was optimistic: **3.44 V at "38 %"** is a nearly empty cell under
  load. 38 % → 2 % in 19 min at ~500 mA is only ~160 mAh, impossible for a
  healthy 3.2 Ah pack. Expect a worn cell or an uncalibrated gauge.

Fix: charge 30–60 min with the device off (5 V/2 A), then hold Power ~10 s and
boot. If it still stays black **while charging**, the panel init is suspect —
`p3/boot/extlinux/extlinux.conf` line 3 can be switched from
`FDT /rk3566-353v.dtb` to `FDT /rk3566-353v-notimingchange.dtb` (retrotiv ships
that variant for panels that dislike timing changes). Not needed unless the
battery is ruled out.

## 2026-11-21 second incident: black screen on every boot

Different from the empty-battery one: after a full charge the device still showed
nothing, and **no new boot report or logs were written to the card at all**. That
puts the failure before stage 2 (`nextui-init`).

Byte comparison with the pristine image:

* p1, p2, p3 (every boot file), p4 (ext4 clean) and p5 matched the image;
* only the gap between the 32 KiB Rockchip FIT and p1 (sectors 64–16383) differed.

The difference was a **`DVKR` runtime state block at offset `0x380000`**, which the
bootloader writes (zeros in the pristine image). A power cut mid-write can leave
it inconsistent and the loader never reaches the kernel. Fixed by rewriting
sectors 64–16383 from the pristine image; the old block is saved as
`rg353v-backup/anbernext-loader-state-20261121.bin`.

If this recurs, the same 8 MiB rewrite is the fix. To diagnose a black screen
without pulling the card, see `anbernext-rescue/`: stage-1 trace on p3, a TCP
rescue shell, backlight logging/self-heal, and a stay-alive guard.

## Pak-Plaza runs as `my355` on purpose

`Tools/rg353/Pak-Plaza.pak/launch-brick.sh` sets `STORE_PLATFORM=my355`: the
Miyoo Flip has the same RK3566 + Mali-G52, and the upstream store has no rg353
profile. It installs into `Tools/my355` / `Emus/my355`, then moves each pak to
`Tools/rg353` / `Emus/rg353` and copies `bin/my355` → `bin/rg353` (and the same
for `lib/`, `resources/`). That is why `.userdata/my355/` exists — not a bug.
A store self-update replaces `Pak-Plaza.pak/pak-store` with the newer upstream
binary and keeps the Pak-Plaza launcher/catalog.

## Gotcha: a pak zip must have its contents at the root

`Cheat Manager` installed as
`Tools/rg353/Cheat Manager.pak/Cheat Manager.pak/launch.sh` — invisible to the
menu, because the release zip wrapped everything in a folder. The menu only
looks for `Tools/rg353/<Name>.pak/launch.sh`. Flattened by hand on 2026-11-21.

## Space

The NEXTUI partition is only 1.5 GB (p5). After ~15 paks it was at 75 %
(399 MB free). `Porty McPortface` alone is 431 MB, `Netplay` 123 MB,
`Swap` 120 MB. The 5.1 GB `ROMS` partition (p6) is separate and does not help.

## Housekeeping done

* `.userdata` + boot report backed up to
  `rg353v-backup/anbernext-userdata-20261121/` (15 MB).
* FAT dirty bit cleared and the truncated temp file fixed with `fsck.fat -a`.
* `Cheat Manager.pak` nesting flattened.
