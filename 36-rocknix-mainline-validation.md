# 36 — ROCKNIX mainline on the RG353V: remote access, Panfrost/PanVK, numbers

**Date:** 2026-11-27 · **Status:** verified on hardware · **Device:** RG353V,
eMMC GammaOS Android kept, ROCKNIX 20261101 on TF1 through the patched eMMC
chain (`34-emmc-dualboot-chain.md`).

---

## 1. Result

| Item | Value |
|---|---|
| OS | ROCKNIX `20261101`, kernel **7.2.11** aarch64 |
| Boot | eMMC u-boot → SD `sysboot` → ROCKNIX (card in) / Android (card out) |
| Panel | `panel-sitronix-st7703`, 640×480@60, 4-lane (`35`) |
| GPU (GL) | Panfrost, `Mali-G52 r1 MC1`, **OpenGL ES 3.1 Mesa 26.2.4** |
| GPU (VK) | PanVK, Vulkan **1.0.354**, `vkmark` **628** |
| `glmark2` | **613** (offscreen, panfrost) |
| Remote | Wi-Fi (iwd) + SSH `root` — both persisted in `system.cfg` |

---

## 2. Remote access (SSH/Wi-Fi) — why it looked "down"

The image ships both **disabled**, and the daemons *delete* the enable file at
every boot, which is why a hand-created `sshd.conf` disappeared:

```
/storage/.config/system/configs/system.cfg
  ssh.enabled=0        →  no sshd
  wifi.enabled=0       →  no radio
```

The units:

```
sshd.socket    ConditionKernelCommandLine=|ssh
               ConditionPathExists=|/storage/.cache/services/sshd.conf
               ListenStream=22  Accept=yes
sshd.service   Requires=sshd.socket (same conditions)
sshd@.service  EnvironmentFile=-/storage/.cache/services/sshd.conf
               ExecStart=-/usr/sbin/sshd -i $SSH_ARGS
sshd-keygen    mkdir -p /storage/.cache/ssh ; ssh-keygen -A
```

Host keys live in **`/storage/.cache/ssh/`**; `/etc/shadow` is a symlink to
**`/storage/.cache/shadow`** and `root` is locked (`*`) on a fresh image.

### Fix (all on the card, persistent)

```
system.cfg          ssh.enabled=1
                    wifi.enabled=1
/storage/.cache/services/sshd.conf
  SSH_ARGS=-h /storage/.cache/ssh/ssh_host_ed25519_key -h /storage/.cache/ssh/ssh_host_rsa_key
extlinux APPEND     … ssh                 (belt-and-braces: ConditionKernelCommandLine)
/storage/.cache/shadow
  root:$6$…                 (set a known password, e.g. `rocknix`)
```

Wi-Fi: ROCKNIX runs **iwd** with `STATE_DIRECTORY=/storage/.cache/iwd`
(`Environment=` in `iwd.service`). Seeding `<SSID>.psk` there is enough:

```
[Security]
Passphrase=…
[Settings]
AutoConnect=true
```

After a successful WPA3 (SAE) handshake iwd rewrites the file with
`SAE-PT-Group19/20` entries and `.known_network.freq` appears — a handy
"it really connected" indicator, visible from the card alone.

`sshd_config`: `PermitRootLogin yes`, `StrictModes no`, host keys as above.

---

## 3. GPU: libmali → Panfrost/PanVK

ROCKNIX ships **both** stacks and a setting:

```
/storage/.config/system/configs/system.cfg
  gpu.driver=libmali      # default: Mali blob (kbase), GLES/Vulkan blob
  gpu.driver=panfrost     # Mesa Panfrost + experimental PanVK
```

Switching and rebooting gives:

```
fde60000.gpu -> panfrost
panfrost fde60000.gpu: mali-g52 id 0x7402 … Initialized panfrost 1.6.0
/dev/dri/card1  /dev/dri/renderD128            # card0 stays the display VOP
/usr/lib/dri/panfrost_dri.so
```

### The PanVK gate

`/usr/lib/vulkan/icd.d/mali.json` is a **0-byte file** in panfrost mode (the
loader reports *Invalid JSON*), and panvk refuses to run unless:

```sh
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 \
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json \
vulkaninfo --summary
```

```
deviceName = Mali-G52 r1 MC1
driverName = panvk          driverInfo = Mesa 26.2.4
apiVersion = 1.0.354
WARNING: panvk is not a conformant Vulkan implementation, testing use only.
```

ROCKNIX's own quirk does this for the UI service
(`/usr/lib/autostart/quirks/platforms/RK3566/090-ui_service` →
`/storage/.config/profile.d/090-ui_service`: `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`,
`DISABLE_WSI_LAYER=1`); an SSH session must set it explicitly.

### Benchmarks

```sh
# GLES (Panfrost), offscreen
XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1 \
  glmark2-es2-wayland --off-screen
#   GL_RENDERER: Mali-G52 r1 MC1 (Panfrost)
#   GL_VERSION : OpenGL ES 3.1 Mesa 26.2.4
#   glmark2 Score: 613

# Vulkan (PanVK)
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 \
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json \
XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1 vkmark
#   vkmark Score: 628
```

The Wayland socket is `wayland-1` under `/run/0-runtime-dir` (the ES process
env has the exact pair; do not guess `wayland-0`).

---

## 4. Resource snapshot (idle, 67 % battery)

| | |
|---|---|
| CPU | 4× Cortex-A55, OPPs `408/600/816/1104/1416/1608/1800 MHz`, governor `ondemand` |
| GPU | devfreq `200–800 MHz`, `simple_ondemand` |
| Thermal | cpu 41.9 °C, gpu 38.9 °C |
| RAM | 1962 MB total, 345 MB used |
| Storage | `/storage` 5.5 G (430 M used), `/flash` 2.0 G (1.3 G used) |
| Display | DSI-1 640×480, `dclk_vop1` 24.15 MHz |

---

## 5. Next steps

1. **Baseline A/B**: `gpu.driver=libmali` → same two benchmarks, compare with
   the panfrost numbers above, then pick the default.
2. **Tuning**: `schedutil`/`performance`, undervolt overlays
   (`rk3566-undervolt-cpu-l1..l3`, GPU), GPU `simple_ondemand` thresholds.
3. **Dual-boot selector**: button at power-on or a marker file, instead of
   "card presence".
4. **The merge decision**: ROCKNIX-only, ARCH-R userland on this 7.2 kernel,
   or two cards on one chain.
5. Clean the stale `WLR_DRM_AFBC_ALT_PRIMARY=1` from the running UI env (it is
   the libmali branch; harmless but shouldn't apply to panfrost).

---

## 6. Reproduce in 5 commands

```sh
S=root@<device>
ssh $S 'sed -i "s/^gpu.driver=.*/gpu.driver=panfrost/" /storage/.config/system/configs/system.cfg; reboot'
ssh $S 'grep . /sys/bus/platform/devices/fde60000.gpu/driver 2>/dev/null; ls /dev/dri/'
ssh $S 'dmesg | grep panfrost | tail -3'
ssh $S 'XDG_RUNTIME_DIR=/var/run/0-runtime-dir WAYLAND_DISPLAY=wayland-1 glmark2-es2-wayland --off-screen | tail -3'
ssh $S 'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.aarch64.json vulkaninfo --summary | grep -E "deviceName|driverName"'
```
