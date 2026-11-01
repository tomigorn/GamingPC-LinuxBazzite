# Games

What's installed on `bazzite-prime` and what each game needs to run well. A game gets its own page only when it needs something.

| Game | Store | Runs with | Tweaks |
|---|---|---|---|
| Crimson Desert Enhanced | Steam | Proton Experimental (forced) | KWin rule forces its window onto the first screen (`~/.config/kwinrulesrc`) |
| HELLDIVERS 2 | Steam | Steam default | — |
| Rock of Ages 2 | Steam | Steam default | — |
| Super Battle Golf | Steam | Steam default | — |
| Level Devil | Steam | Steam default | — |
| A Normal Train Game | Steam | Steam default | — |
| Harry Potter and the Half-Blood Prince | DVD, Lutris | umu-run | [Harry Potter 6 & 7](harry-potter-6-7.md) |
| Harry Potter and the Deathly Hallows: Part 1 | DVD, Lutris | umu-run | [Harry Potter 6 & 7](harry-potter-6-7.md) |

## Where things are

| What | Where |
|---|---|
| Steam library | `~/.local/share/Steam/steamapps` (one library, on the system disk) |
| Lutris games | prefixes in `~/Games/<slug>`, configs in `~/.local/share/lutris/games/*.yml` |
| Extra Proton versions | GE-Proton 11-5/11-6/11-7, UMU-Proton 10.0-4, managed with **ProtonPlus** |
| Per-game Proton in Steam | game → Properties → Compatibility (stored in `~/.local/share/Steam/config/config.vdf`, `CompatToolMapping`) |
| Start-menu entries | `~/.local/share/applications/<game>.desktop`, icons in `~/.local/share/icons/hicolor/256x256/apps/` |

## Tools that ship with Bazzite

| Tool | Use |
|---|---|
| MangoHud | FPS/frametime overlay: `mangohud %command%` (Steam) or `MANGOHUD=1` (Lutris env). Per-game config via `MANGOHUD_CONFIGFILE` |
| vkBasalt | post-processing (sharpening, SMAA) for Vulkan/DXVK games: `ENABLE_VKBASALT=1`, config via `VKBASALT_CONFIG_FILE`. `Home` toggles it in game |
| umu-run | runs Proton outside Steam, used by Lutris |

## Audio

Games default to the 7.1 *Sonar · Game (DTS)* sink. A game whose dialogue sounds thin there can be pinned to a stereo sink with `PULSE_SINK=<node>`. See [Audio](../docs/07-audio.md).

## Leftovers

`CompatToolMapping` still has entries for games that are no longer installed: Titanfall 2 (`1237970`, Proton Experimental, launch options `mangohud MANGOHUD_CONFIG= %command%`) and The Binding of Isaac: Rebirth (`250900`, Proton Hotfix). Steam reuses them on reinstall.
