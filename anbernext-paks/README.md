# Writing paks for AnberNext (RG353V)

AnberNext v3.26 is a NextUI derivative (MinUI lineage) with a custom "NeonDrive"
theme. Everything you can add to it — a tool, a file manager, a scraper, a music
player, an emulator — is a **pak**. This document is what we learned by taking the
shipped image apart (partitions, `nextui-init`, `nextui.elf`, the two stores).

The good news: a pak needs **no compiler, no SDK and no rebuild of the firmware**.
A folder with a `launch.sh` is a complete app.

---

## 1. Who runs what (the boot chain)

```
p1/p2  4 MiB   FIT loader (ATF/OP-TEE/U-Boot)      <- the eMMC bootloader hands off here
p3     99 MiB  NEXTBOOT   Image, rk3566-353v.dtb, uInitrd, boot.scr, android.go/no/req
p4    768 MiB  NEXTROOT   Debian 13 (trixie), ext4 — this is the Linux system
p5    1.5 GiB  NEXTUI     FAT32 — .system, .userdata, Tools, Emus, Roms, Saves (the "card")
```

At boot, `NEXTROOT` runs `/usr/sbin/nextui-init` as **PID 1**. There is **no systemd
and no udev** on this card. `nextui-init`:

1. mounts proc/sys/dev, tmpfs on `/tmp` and `/run`;
2. finds the partition whose GPT name is `NEXTUI` on an **SD** device (never eMMC)
   and mounts it read-write at `/mnt/SDCARD`;
3. mounts the second card (TF2) read-only, with only `Music`, `Saves` and
   `.userdata/shared` bind-mounted read-write;
4. writes a boot report to `NEXTUI/relatorio-rg353v.txt`;
5. runs `.system/rg353/paks/MinUI.pak/launch.sh`.

`MinUI.pak/launch.sh` is the app runtime. It exports the environment, starts the
background daemons (`keymon.elf`, `batmon.elf`, `audiomon.elf`, Wi-Fi/Bluetooth
when enabled) and then loops:

```
nextui.elf            <- the menu; draws, reads input, returns
  writes /tmp/next    <- the command you picked, e.g. '/mnt/SDCARD/Tools/rg353/X.pak/launch.sh'
  exits
launch.sh evals it    <- your app owns the device now
  deletes /tmp/next
nextui.elf            <- menu comes back
```

**Consequence:** a pak is not a plugin loaded into the launcher. It is an ordinary
process that inherits a prepared environment, takes over the screen, and returns
when it exits. Anything that runs on Linux aarch64 can be a pak.

---

## 2. Where an app lives

```
/mnt/SDCARD/Tools/rg353/<Name>.pak/launch.sh     tool, appears under Tools
/mnt/SDCARD/Emus/rg353/<TAG>.pak/launch.sh       emulator, bound to Roms/<system> (<TAG>)
```

* The menu label is the folder name **without `.pak`**.
* The platform folder for this device is **`rg353`**.
* Nothing else is scanned. Do **not** put paks in `.system/` — the OTA updater
  replaces that folder.
* `launch.sh` must be executable (`0755`). On FAT32 the mount gives files `0755`
  anyway, but if you ship binaries, `chmod 0755` them from `launch.sh` to be safe
  (the AnberNext updater does exactly this for its bundled busybox/show2).

Verified detail: **`nextui.elf` never reads `pak.json`** (zero occurrences in the
binary). `pak.json` exists only for the stores. The menu works from the folder name.

Three paks are special-cased in the launcher: `Settings.pak` (runs `settings.elf`),
`Pak Store.pak` and `AnberTunes.pak` (resident music player). Avoid those names.

---

## 3. The environment a pak inherits

| Variable | Value on this device | Use |
|---|---|---|
| `PLATFORM` | `rg353` | platform folder name |
| `DEVICE` | *(unset here; one device per card)* | exact model on shared platforms |
| `SDCARD_PATH` | `/mnt/SDCARD` | the FAT32 NEXTUI card |
| `SYSTEM_PATH` | `$SDCARD_PATH/.system/rg353` | cores, bin, shaders, etc. |
| `USERDATA_PATH` | `$SDCARD_PATH/.userdata/rg353` | settings, save states, per-pak data |
| `LOGS_PATH` | `$USERDATA_PATH/logs` | **put your log here** |
| `BIOS_PATH` | `$SDCARD_PATH/Bios` | |
| `ROMS_PATH` | `$SDCARD_PATH/Roms` | |
| `SAVES_PATH` | `$SDCARD_PATH/Saves` | may be TF2's folder, bind-mounted |
| `CHEATS_PATH` | `$SDCARD_PATH/Cheats` | |
| `CORES_PATH` | `$SYSTEM_PATH/cores` | libretro cores |
| `SHARED_USERDATA_PATH` | `$SDCARD_PATH/.userdata/shared` | recents, save states |
| `HOOKS_PATH` | `$USERDATA_PATH/.hooks` | boot/pre/post hook scripts |
| `HOME` | `$USERDATA_PATH` | |

Emulator paks also get the ROM as `$1`, and the tag from the folder name.

Logs are the only debugging channel: NextUI switches to a full-screen SDL app, so
stdout is invisible. Convention:

```sh
LOG="$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOG" 2>&1
```

On a PC that file is `NEXTUI/.userdata/rg353/logs/<Name>.txt`. The launcher's own
log is `nextui.txt` in the same folder.

---

## 4. What you can use at runtime

**Present:** busybox, Debian 13 userland, `curl`, `evtest`, `amixer`, `iw`,
`wpa_cli`, `rfkill`, `tar`, `gzip`, `python3` **no**, `node` **no**, `git` **no**,
`unzip` **no** (busybox has `tar`; the updater ships its own busybox).

**Helper binaries in `.system/rg353/bin/`:**

| Tool | What it does |
|---|---|
| `show2.elf` | full-screen image + text + progress UI (SDL2). The simplest GUI available to a shell pak |
| `governor.sh` | `auto` / `performance` / `powersave` |
| `syncsettings.elf` | restores brightness/volume after a standalone program changed them |
| `minarch.elf` | the libretro frontend (emulator paks) |
| `gametimectl.elf` | play-time tracking |

**In `/usr/local/bin/`:** `with-padxbox` (presents the built-in pad as an Xbox 360
controller for paks ported from the Brick), `standalone-run` (wraps PPSSPP/Flycast/
DraStic/Mupen64Plus with the dArkOS environment), `rgsplash`.

### show2.elf — the shell pak's UI

```
show2.elf --mode=simple   --image=<png> [--text="..."] [--timeout=N]
show2.elf --mode=progress --image=<png> [--text="..."] [--progress=0..100]
show2.elf --mode=daemon   --image=<png> --bgcolor=0x1a1205 --fontcolor=0xf2a53a
```

Daemon mode creates `/tmp/show2.fifo` (hard-coded) and accepts line commands:

```sh
printf 'TEXT:Downloading...\n'  > /tmp/show2.fifo
printf 'PROGRESS:42\n'          > /tmp/show2.fifo
printf 'QUIT\n'                 > /tmp/show2.fifo
```

Only one show2 instance at a time — `/tmp/show2.fifo` is global.

### Hooks (run without writing a pak)

`$USERDATA_PATH/.hooks/boot.d/*.sh` runs at boot, `pre-launch.d` / `post-launch.d`
around every launch. Suffix `.sync.sh` to run synchronously. See
`.system/rg353/bin/run_hooks.sh`.

---

## 5. Three ways to build an app

### A. Shell only (start here)

Zero toolchain, instant iteration. Perfect for file operations, downloads,
backups, system info, launching other binaries. See `template/System Info.pak/`.

### B. Go — static binary (what Game Manager does)

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o myapp .
```

A pure-Go static binary runs on this rootfs with no libraries. `launch.sh` just
`exec ./myapp`. This is the cheapest route to a real interactive app (you get
`os/exec`, HTTP, JSON, SQLite via pure-Go drivers, etc.). If you need input, read
`/dev/input/event*` (the pad is `retrogame_joypad`) or render yourself with a
framebuffer/SDL binding.

### C. C/C++ + SDL2

The runtime has SDL2 2.32, SDL2_image and SDL2_ttf in `/usr/lib/aarch64-linux-gnu`
(glibc 2.41; binaries built against glibc ≥ 2.17 load fine). Cross-compile with
`aarch64-linux-gnu-gcc` against a sysroot extracted from `NEXTROOT`, or use the
NextUI build container (`aarch64-nextui-linux-gnu`). This is what the menu itself
uses (`nextui.elf` → SDL2 + SDL2_image + SDL2_ttf, KMS/DRM).

---

## 6. Development loop

1. **Build** the pak folder (or `./build-pak.sh "template/System Info.pak"`).
2. **Install**: power off, card out, copy the `.pak` folder into
   `Tools/rg353/`, card back. Once you have a network pak installed (FTP/HTTP
   Filebrowser/SSH from Pak Store), you can drop zips over Wi-Fi instead.
3. **Boot**, open Tools, run it.
4. **Read the log** on a PC: `.userdata/rg353/logs/<Name>.txt`.
5. If the launcher itself misbehaves, read `relatorio-rg353v.txt` on the card root.

`./build-pak.sh` produces the exact artifact the stores expect (pak contents at the
zip root, dots instead of spaces in the asset name, plus a `.sha256`).

Gotchas learned from this image:

* FAT32: no symlinks, no POSIX permissions, case-insensitive. Keep paths short.
* Tools run at the **performance** governor by default; call
  `sh "$SYSTEM_PATH/bin/governor.sh" powersave` at the start of a light pak and
  the launcher resets it on exit.
* Never write to the eMMC (Android) — `nextui-init` deliberately never mounts it.
* TF2: `Roms`, `Bios`, `Collections` are read-only; only `Music`, `Saves` and
  `.userdata/shared` are writable. Don't design an app that needs more.
* No `unzip`: if your pak installs things, bundle busybox or use `tar`.

---

## 7. Packaging and publishing

### `pak.json` (store metadata; ignored by the menu)

Required by both stores:

```json
{
  "name": "System Info",
  "version": "v0.1.0",
  "type": "TOOL",
  "description": "One-paragraph description, shown in the store.",
  "author": "your name",
  "repo_url": "https://github.com/YOU/REPO",
  "release_filename": "System.Info.pak.zip",
  "platforms": ["rg353"]
}
```

Optional: `changelog` (map version → text), `screenshots` (paths inside the repo),
`banners` (device → path), `launch` (script name, default `launch.sh`).
Emulator paks set `name` to the ROM tag (e.g. `INTV`).

### Zip layout

The zip contains the **contents** of the pak folder, not the folder itself:

```
System Info.pak.zip
├── launch.sh
├── pak.json
└── res/...
```

The store creates `Tools/rg353/System Info.pak/` and extracts into it. The release
asset name replaces spaces with dots (`Game.Manager.pak.zip`,
`System.Info.pak.zip`) and must match `release_filename`.

### Publishing

* Tag the release `vX.Y.Z`, matching `version` in `pak.json`.
* **Pak Store** (community): open the new-pak issue form in
  `LoveRetro/nextui-pak-store` with the repo and display name.
* **Pak-Plaza** (AnberNext's own shelf): add an entry to `paks.json` in
  `retrotiv/Pak-Plaza` — no code, just JSON (`name`, `store`, `category`, `desc`,
  `author`, `source`, `availability`).
* Manual distribution works too: users unzip into `Tools/rg353/`.

### How the store actually works

Both `Pak Store.pak` and `Pak-Plaza.pak` are builds of the same Go app
(`LoveRetro/nextui-pak-store`, UI library "gabagool"). The flow is:

1. download the storefront JSON (`storefront.json`; Pak-Plaza generates it from
   `paks.json`) — 126 community entries + 4 experimental at v3.26;
2. each entry carries `id`, `repo_url`, `release_filename`, `platforms`,
   `categories`, `scripts`, `update_ignore`;
3. for an install/update it asks the GitHub API for the repo's **latest release**,
   downloads the asset named `release_filename`, verifies it, unzips into
   `Tools/<platform>/<name>.pak/`, and optionally runs `post_install` /
   `post_update` / `post_uninstall` scripts;
4. a local metadata DB tracks installs so updates show up, and an update can move
   a pak folder if its name changed (`previous_names`).

So the "app store" is just: **GitHub releases + a JSON catalog**. No server of
their own, no signing, no review pipeline beyond the catalog PR/issue.

### The firmware OTA (worth copying as a pattern)

`AnberNext Update.pak` updates the boot card from inside the device: it fetches
`retrotiv/AnberNext`'s latest release `update.tar`, checks `sha256`, and applies
only paths whose top-level folder is in the allowlist
`.system Tools Emus .tmp_update` — refusing absolute paths and `..`. Existing files
are backed up to `.anbernext/backup/<version>-<timestamp>` and replaced by
`mv` over the destination (so a running binary is not "text file busy"). It never
looks at the games card or the eMMC. That is why it is safe to let it update.

---

## 8. What is already installed on our card

Tools: `Pak Store`, `Pak-Plaza`, `AnberNext Update`, `AnberNext Rollback`,
`AnberTunes`, `Settings`, `Battery`, `Clock`, `Game Tracker`, `Input`,
`Disc Organizer`, plus `Atualizar NeonDrive` (legacy updater).

Emulators: 34 paks (PSP, DC, NDS, N64, …) over 6 shared libretro cores and the
standalone builds in `NEXTROOT/opt` (PPSSPP, Flycast, DraStic, Mupen64Plus).

That means the ecosystem is already coherent: firmware from retrotiv, paks from
the NextUI community, adapted for `rg353` by Pak-Plaza, updates via the OTA pak.

---

## 9. Ideas that fit this device well

* **Save backup / export** — zip `Saves/` to `Music/` or a USB drive (writable
  paths only).
* **ROM library QA** — find missing BIOS, duplicate ROMs, bad extensions, empty
  folders (read-only on TF2).
* **Cheat manager** — fetch `.cht`/`.ini` sets per core into `Cheats/`.
* **Screenshot gallery** — NextUI already writes screenshots; a viewer is a small
  SDL/Go app.
* **Network dashboard** — signal, IP, throughput, DNS (useful given the 8821cs
  quirks on this unit).
* **andr36oid bridge** — anything that needs Android should stay a separate
  Android-side app; paks cannot mount or talk to the eMMC by design.

---

## 10. Limits to keep in mind

* No systemd/udev: if you need a daemon, start it from `launch.sh` and clean it up
  on exit (`trap`).
* 2 GB RAM, no swap by default; avoid Electron-class runtimes.
* The launcher restarts after every pak — keep startup under ~1 s.
* Screen is 640×480, pad-only (no touch in NextUI): design for D-pad + A/B/X/Y,
  and check `Input.pak` for the button map.
* FAT32 timestamps are local/coarse; don't depend on them.
