# USB peripherals

| Device | USB id | Notes |
|---|---|---|
| SteelSeries Arctis Nova Pro Wireless (base station) | `1038:12e0` | power-off at shutdown, battery incl. spare cell |
| Logitech BRIO | `046d:085e` | USB wedge fix |
| Razer Viper V3 Pro | `1532:00c1` | battery over hidraw |
| Cidoo ABM 084 keyboard | `05ac:024f` | Apple-cloned id, `fnmode`, no battery telemetry |

## SteelSeries base station: turn off with the PC

On Windows, SteelSeries GG switches the base station off at shutdown. Linux has no GG, so the OLED stays lit and the dock stays awake. Instead, the USB port's power is cut with `uhubctl` (layered package, see [System](01-system.md)).

```bash
$ sudo uhubctl            # find the hub/port the 1038:12e0 is on
$ sudo uhubctl -l 1-3 -p 3 -a off
```

This replaced the first version (`steelseries-poweroff.service`, which looked the port up *during* shutdown, now in [`archive/`](../archive/)). The current version is two units plus two scripts:

| File | Job |
|---|---|
| [`steelseries-usb-on.service`](../config/etc/systemd/system/steelseries-usb-on.service) + [`steelseries-usb-on.sh`](../config/usr/local/bin/steelseries-usb-on.sh) | at boot: find the base station by **VID:PID** (not by name), cache `hub port` in `/run/steelseries-usb/location`, make sure the port is powered |
| [`steelseries-usb-off.service`](../config/etc/systemd/system/steelseries-usb-off.service) + [`steelseries-usb-off.sh`](../config/usr/local/bin/steelseries-usb-off.sh) | at poweroff/halt: cut that port. Uses the cache, and live-probes only if the cache is missing. Logs to `/var/log/steelseries-usb-off.log`. Always exits 0 so it can never block shutdown |

Why it's split: during shutdown `uhubctl`'s scan can be slow or fail, so the lookup happens at boot. `off` only runs on **poweroff/halt**, not reboot, so the headset keeps charging through a reboot.

```bash
sudo cp config/usr/local/bin/steelseries-usb-*.sh /usr/local/bin/
sudo cp config/etc/systemd/system/steelseries-usb-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now steelseries-usb-on.service
sudo systemctl enable steelseries-usb-off.service
```

## Logitech BRIO: camera dead after booting into Windows

**Symptom:** after using Bazzite and F12-booting Windows, Windows Hello can't see you and the Camera app shows no image. Unplugging the camera fixes it.

**Cause:** the camera's firmware hangs at the USB level (`device not accepting address, error -71`). Nothing in software can reach it, so Linux and Windows fail the same way. A warm reboot never cuts USB power, so Windows inherits the hung camera. Windows Fast Startup was investigated and is **not** the cause.

**Fix:** [`config/camera-usb-cycle/`](../config/camera-usb-cycle/) (full analysis in its README):

- a udev rule stops the BRIO from autosuspending,
- systemd units power-cycle its socket at boot (only if it's hung) and at poweroff/halt/**reboot**,
- `sudo camera-reset` does it by hand mid-session.

```bash
distrobox-host-exec sudo bash ~/camera-usb-cycle/install.sh
```

Two traps:

1. **`uhubctl` can't do this.** The BRIO is on a *root-hub* port, which doesn't advertise per-port power switching. The kernel's `/sys/bus/usb/devices/<port>/disable` works on any port.
2. **A USB 3 socket is two ports** on two buses (e.g. `usb5-port2` and `usb6-port2`, linked by a `peer` symlink). Cut only one and the camera comes back at 480 Mbps, without 4K or 1080p60. Check with `cat /sys/bus/usb/devices/*/speed`.

## Battery widget

A custom tray widget (`org.kde.plasma.peripheralbattery`) shows battery levels for the mouse, keyboard, headset and the spare battery in the base station, because none of these reach UPower, so KDE's own battery widget can't show them.

- Collector: [`~/.local/bin/peripheral-battery`](../config/home/bazzite/.local/bin/peripheral-battery) (Python, prints JSON). The widget polls it every 2 minutes, and every 15 s right after login until the devices have appeared.
- At or below 20 % it sends one notification per low episode and shows a red badge. Charging devices never count.
- Sleeping devices show the last known value, marked stale, for up to 12 h. Devices that can never be read show "—".
- Tests: `<plasmoid>/tests/test_*.py`.

**hidraw access** comes from our own rule, [`/etc/udev/rules.d/70-hidraw-uaccess.rules`](../config/etc/udev/rules.d/70-hidraw-uaccess.rules): it gives the logged-in user access to every `/dev/hidraw*`. The image used to do this with `92-viia.rules` (`0666`) until a 2026-11 image dropped it, and the widget lost the headset. Symptom: `ls -l /dev/hidraw*` shows `0600 root` and `getfacl` shows no `user:bazzite`. The file must sort before `73-seat-late.rules`, or `uaccess` has no effect.

```sh
echo 'KERNEL=="hidraw*", SUBSYSTEM=="hidraw", TAG+="uaccess"' | sudo tee /etc/udev/rules.d/70-hidraw-uaccess.rules
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=hidraw
```

### Per device

- **Razer Viper V3 Pro.** Bazzite dropped the OpenRazer kernel module in image `44.20260820`. The battery is now read **in userspace over hidraw**: the OpenRazer 90-byte feature report on the control interface (`:1.0`), class `0x07`, id `0x80` = level (0–255), id `0x84` = charging. **A level of 0 means "asleep, no answer"**, not empty. The old sysfs path (`charge_level`, needed the `plugdev` group) is still tried first in case the module returns.
- **Arctis Nova Pro.** `headsetcontrol` (built from source in the distrobox so the host can run it, kept current by `headsetcontrol-update`, see [Updates](03-updates.md)) reads the headset. The **spare battery in the base station** is read directly: interface 4, report `06 b0`, **byte 7** (0–8 scale, 0 = slot empty). This is undocumented and was found by pulling the battery out and watching which byte changed. `~/.local/bin/arctis-battery-probe` watches the report for further fields.
- **Cidoo ABM 084.** Cannot be read in wired or 2.4 GHz mode: its HID descriptors have no battery usage at all. Over Bluetooth it would report through BlueZ natively. Epomaker's WebHID protocol was decoded and does **not** apply to this dongle. Don't probe it blind: factory reset (`0x0F`) is right next to device info (`0x10`).
