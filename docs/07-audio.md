# Audio

The headset is the Arctis Nova Pro Wireless. Instead of SteelSeries Sonar (Windows only), PipeWire provides a similar set of virtual outputs, called **"Sonar"** sinks. All of them feed the headset.

## Sinks

Defined in `~/.config/pipewire/pipewire.conf.d/50-55*.conf` (copies in [`config/.../pipewire/`](../config/home/bazzite/.config/pipewire/)):

| Sink | Node | Type |
|---|---|---|
| Sonar · Chat | `chat_eq` | stereo + EQ |
| Sonar · Music | `music_eq` | stereo + EQ |
| Sonar · Movie | `movie_eq` | stereo + EQ |
| **Sonar · Game (DTS Headphone:X)** (default) | `effect_input.virtual-surround-7.1-hesuvi` | 7.1 → HRTF |
| Sonar · Game (Dolby Atmos) | `effect_input.game-atmos` | 7.1 → HRTF |
| Sonar · Game (Sennheiser GSX) | `effect_input.game-gsx` | 7.1 → HRTF |

The game sinks are 7.1 inputs that are rendered to binaural stereo with HeSuVi impulse responses (`~/.config/pipewire/hrir/{dtshx,atmos,gsx,hrir}.wav`, not in this repo, from the HeSuVi project).

`10-no-upmix.conf` (in `pipewire-pulse.conf.d` and `client.conf.d`) stops PipeWire from upmixing stereo to 7.1, so stereo content isn't smeared across virtual speakers.

Per-game sink: e.g. a Lutris game gets `PULSE_SINK: movie_eq` in its `system.env`. That's what *Harry Potter and the Deathly Hallows Part 1* uses, see [games](../games/harry-potter-6-7.md).

## Streaming 7.1 games in Discord (Vesktop) without losing voices

**Symptom:** streaming a game from Vesktop, viewers hear effects but **no dialogue**.

**Cause:** Vesktop's screen-share audio (venmic, node `vencord-screen-share`) only connects the shared app's front-left/right channels. Games on a 7.1 sink put dialogue on the **centre** channel, so it never reaches the stream.

**Fix (2026-10-11), two user services**, games can stay on surround sinks:

| Unit | Does |
|---|---|
| `discord-surround-downmix.service` | runs a standalone PipeWire filter ([`standalone/discord-surround-downmix.conf`](../config/home/bazzite/.config/pipewire/standalone/discord-surround-downmix.conf)): ITU downmix of FC/SL/SR/RL/RR at 0.707, LFE dropped |
| `discord-surround-linker.service` | runs [`discord-surround-linker`](../config/home/bazzite/.local/bin/discord-surround-linker), which watches `pw-dump` every second and connects captured apps' surround channels through the downmix into `vencord-screen-share` |

Both are started together with `pipewire.service` (`pipewire.service.wants/`). Moving a running stream to another sink drops venmic's connections. Restart the stream in Discord.

## System sounds volume

KDE system sounds (display detected, shutdown, …) play with role `Notification` straight to the Arctis sink, skipping the Sonar mix, so at 100% they are much louder than everything else. Set to 0.03 (about 30% on the slider) on 2026-11-08, stored in `~/.local/state/wireplumber/stream-properties`:

```sh
pw-metadata -n route-settings 0 'restore.stream.Output/Audio.media.role:Notification' '{ "mute": false, "volumes": [ 0.03, 0.03 ], "channels": [ "FL", "FR" ] }' 'Spa:String:JSON'
canberra-gtk-play -i device-added   # test
```

Same knob in the GUI: System Settings → Sound → Applications → *Notification Sounds*.
