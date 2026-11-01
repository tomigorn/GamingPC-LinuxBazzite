# Harry Potter 6 & 7 (DVD, Lutris)

*Half-Blood Prince* (2009) and *Deathly Hallows: Part 1* (2010), installed from the original DVDs with the Lutris "DVD + Chip-Biscuit wrapper" scripts by [legluondunet](https://github.com/legluondunet/MyLittleLutrisScripts). Both run through `umu-run` (Proton outside Steam).

| | Half-Blood Prince | Deathly Hallows 1 |
|---|---|---|
| Prefix | `~/Games/harry-potter-and-the-half-blood-prince` (3.1 GB) | `~/Games/harry-potter-and-the-deathly-hallows-part-1` (4.8 GB) |
| Exe | `.../Harry Potter and the Half Blood Prince/pc/hp6.exe` | `.../Harry Potter and the Deathly Hallows(TM) - Part 1/pc/hp7.exe` |
| Wrapper | `hphbpfix60fps` (60 fps fix) | `hp7fixOriginalFOV` (FOV fix) |
| FPS limit | 59 | 60 |
| vkBasalt | CAS sharpening | SMAA + CAS sharpening |
| Audio sink | default (DTS 7.1) | **`movie_eq`** (dialogue was too thin on the DTS sink) |

Copies of every file below are in [`config/`](../config/home/bazzite/), at the same paths.

## Install

1. Lutris → search the game → the *DVD + Chip-Biscuit wrapper* installer → insert the disc when asked.
2. **Deathly Hallows only:** the DVD installs into `Harry Potter and the Deathly Hallows(TM) - Part 1`, but the script expects the name without `(TM)`. The installer's own step adds a symlink without it. If the game won't start, check that the symlink exists in `drive_c/Program Files (x86)/Electronic Arts/`, and that the Lutris `exe:` points at the `(TM)` folder.
3. Apply the tweaks below. The Lutris YAMLs have backups of their state before the tweaks (`*.bak-original`, `*.bak-before-visuals`).

## What the installer does vs. what was changed by hand

All of it was done on this Linux install (HBP installed 2026-08-22, tweaked the next night; DH installed and tweaked 2026-10-05).

| Change | By |
|---|---|
| official game patch, wrapper (`d3d9.dll` + `d3d9.ini`: 60 fps fix for HBP, FOV fix for DH), `d3d9: n,b` override, HBP registry defaults for resolution and LOD | Lutris installer |
| Lutris `exe:` repointed to the `…Hallows(TM) - Part 1` folder (DH) | hand |
| `d3d9.ini`: `UsePrimaryMonitor` 0 → 1 (both) | hand |
| `d3d9.ini`: resolution 1600×900 → 2560×1440 (HBP) | hand |
| `dxvk.conf`, vkBasalt, MangoHud, sync options off, `PULSE_SINK` (DH) | hand |

`pc/maps/*.cmap` are controller maps the game writes itself when an Xbox controller is connected, not a tweak.

## Tweaks

All in the game's Lutris config (`~/.local/share/lutris/games/<slug>-<id>.yml`, *Configure → System options → Environment variables*):

```yaml
system:
  env:
    DXVK_CONFIG_FILE: <prefix>/.../pc/dxvk.conf        # d3d9.samplerAnisotropy = 16
    ENABLE_VKBASALT: '1'
    VKBASALT_CONFIG_FILE: ~/.config/vkBasalt/<hp6: vkBasalt.conf | hp7: hp7.conf>
    MANGOHUD: '1'
    MANGOHUD_CONFIGFILE: ~/.config/MangoHud/<hp6|hp7>.conf
    PROTON_NO_ESYNC: '1'
    PROTON_NO_FSYNC: '1'
    PROTON_NO_NTSYNC: '1'        # hp7 only
    PULSE_SINK: movie_eq         # hp7 only
wine:
  esync: false
  fsync: false
  overrides:
    d3d9: n,b                    # load the wrapper's d3d9.dll
  show_debug: -all
```

| File | What it does |
|---|---|
| `pc/dxvk.conf` | 16× anisotropic filtering |
| `pc/d3d9.ini` | the wrapper's settings: FPS limit, borderless fullscreen on the primary monitor, ignore focus loss. HBP also forces 2560×1440 and FOV level 1 |
| `~/.config/vkBasalt/*.conf` | sharpening (CAS 0.4), hp7 also SMAA anti-aliasing. `Home` toggles it |
| `~/.config/MangoHud/hp6.conf`, `hp7.conf` | overlay: FPS, frametime, GPU/CPU load and temps. `Right Shift + F12` toggles it |

ESYNC/FSYNC/NTSYNC are switched off in both. The reason wasn't written down at the time. Re-test with them on before copying this to another game.
