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
| `discord-surround-linker.service` | runs [`discord-surround-linker`](../config/home/bazzite/.local/bin/discord-surround-linker), which follows the graph through one long-lived `pw-dump --monitor` (~0 % CPU, reacts instantly) and connects captured apps' surround channels through the downmix into `vencord-screen-share` |

Both are started together with `pipewire.service` (`pipewire.service.wants/`). Moving a running stream to another sink drops venmic's connections. Restart the stream in Discord.

## Mic: Easy Effects

Easy Effects (Flatpak, autostarts) processes **only the mic**; outputs go through the Sonar sinks instead. Input preset *SteelSeries Arctis Nova Pro Wireless* ([copy](../config/home/bazzite/.var/app/com.github.wwmm.easyeffects/data/easyeffects/input/)):

DeepFilterNet → gate → EQ → de-esser → compressor → exciter

DeepFilterNet (neural noise removal) is the heaviest plugin, ~3 % CPU on average while the mic is used. Kept on purpose (2026-11-09) for its noise removal; the lighter RNNoise model is installed if that ever changes.

## Headset settings (base station)

| Setting | Value | Note |
|---|---|---|
| Sidetone | **Low** (2026-11-08) | Medium passed too much keyboard typing; Off → tendency to shout |

Echo of typing/speakers while wearing the headset with speakers on: not sidetone, not the PC (no mic loopback). Likely Transparency mode (headset button: ANC → Transparency → Off).

## Speakers: keep-alive tone

The Logitech Z337 speakers are on the base station's line-out, which only plays while the headset is off. Their auto-standby (about 2 h, not documented by Logitech) also kicks in during quiet playback. Windows used SoundKeeper; here it's `speaker-keepalive.service`, which runs [`speaker-keepalive`](../config/home/bazzite/.local/bin/speaker-keepalive) (started with `pipewire.service`):

| Headset (base station status byte 15) | Tone |
|---|---|
| offline (`0x01`) | on: 20 Hz sine, amplitude 0.02, straight into the Arctis sink (not through the Sonar EQs) |
| online, charging, unknown, unreadable | off |

- Reacts within about a second: the base station sends a HID report when the headset switches, plus a fallback check every 10 s. ~0 % CPU (one second of tone is precomputed and looped, so whole-number Hz only). Needs hidraw access, see [USB peripherals](06-usb-peripherals.md#battery-widget).
- Shows up as stream "Speaker keep-alive" in the volume mixer.
- Tray icon (widget `org.kde.plasma.speakerkeepalive`): speaker = tone on, headset = tone off, warning = service stopped or base station unreadable. The state is the file name `/run/user/1000/speaker-keepalive.<state>`; the widget watches the folder (inotify), so no polling and no spawned processes.
- Tune with `SPEAKER_KEEPALIVE_FREQ` / `SPEAKER_KEEPALIVE_AMPLITUDE` in the unit, then `systemctl --user restart speaker-keepalive`.
- Log: `journalctl --user -u speaker-keepalive`. Tests: `python3 -m unittest tests/test_speaker_keepalive.py`.

## System sounds volume

KDE system sounds (display detected, shutdown, …) play with role `Notification` straight to the Arctis sink, skipping the Sonar mix, so at 100% they are much louder than everything else. Set to 0.03 (about 30% on the slider) on 2026-11-08, stored in `~/.local/state/wireplumber/stream-properties`:

```sh
pw-metadata -n route-settings 0 'restore.stream.Output/Audio.media.role:Notification' '{ "mute": false, "volumes": [ 0.03, 0.03 ], "channels": [ "FL", "FR" ] }' 'Spa:String:JSON'
canberra-gtk-play -i device-added   # test
```

Same knob in the GUI: System Settings → Sound → Applications → *Notification Sounds*.
