# ARCHIVE — closed tracks, dead ends, and where the evidence lives

Nothing here is deleted: the device **is** the archive. This index exists so a
future session does not re-run a known-negative experiment.

**Rule:** an entry is only archived when the hardware answered it. Every entry
links to the document that holds the raw evidence.

## Closed (hardware answered)

| Track | Verdict | Evidence |
|---|---|---|
| **ROCKNIX on RG353V (20261101 Generic image)** | ❌ does not boot — lands on eMMC Android | `14-rocknix-image-analysis.md`, `15-darkos-migration.md` |
| **hybridA** (ROCKNIX image + dArkOS loader bytes) | ❌ Android | `16-gpu-vulkan-panvk-status.md` |
| **hybridB** (dArkOS exact loader + ROCKNIX partitions) | ❌ Android | `16-…` |
| **hybridC** (dArkOS partition numbering + explicit FDT) | ❌ Android (superseded by D before testing, D failed) | `15-…` final section |
| **hybridD** (dArkOS loader + dArkOS-identical GPT/type GUIDs/labels) | ❌ Android — 4/4 ROCKNIX variants rejected | `15-…` final section (md5 table: p1/p2 identical, idbloader region differs) |
| **Wipe-eMMC-Android → ROCKNIX** | 🚫 rejected by decision (destroys GammaOS; needs eMMC backup first) | `15-…` decision matrix |
| **ArkOS imagecache corruption** | 🟡 quarantined, card retired from service | `15-…` |
| **58.2 GB `SD16G` card beyond ~24 GB** | ❌ write failures — capacity capped in all layouts | `15-…` |

## Superseded (kept for reference)

| Document | Superseded by | Note |
|---|---|---|
| `13-archr-rk3566-plan.md` | `17-archr-bringup-plan.md` + `18-archr-upstream-analysis.md` | 13 holds the feasibility research and the ROCKNIX stack inventory |
| ROCKNIX image as a *distro candidate* | Arch-R | Still a **parts source**: kernel config, panfrost/panvk Mesa layout, u-boot RK3566 board code |
| `12-ps2-linux-investigation.md` | — | Conclusion stands; ARMSX2-on-Linux needs a modern GPU stack (Arch-R/panvk is the current hope) |

## Do not repeat

1. Flashing another distribution into TF1 to "see if it boots". The gate is the
   eMMC boot chain; a new userland changes nothing.
2. Laptop-side mount/`blkid` checks after a long write. Hash + one device boot.
3. Multi-variable card layouts. One layer per boot (`17-…`).
