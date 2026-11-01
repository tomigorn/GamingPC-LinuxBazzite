# camera-usb-cycle — Logitech BRIO USB power-cycle for dual boot

Stops the BRIO from arriving dead in Windows after a Bazzite session.

## The bug

The BRIO wedges. It trains a USB link and reaches `enable connect`, then stops
answering `SET_ADDRESS`:

```
usb 2-3.4: Device not responding to setup address.
usb 2-3.4: device not accepting address 34, error -71
usb 2-3-port4: unable to enumerate USB device
```

`error -71` is `EPROTO`. The device is electrically present but its firmware is
hung, so **no OS can talk to it** — Linux fails identically to Windows. The port
was found parked in link state **U3** (suspended). Only removing VBUS resets it,
which is why physically unplugging and replugging is the only known cure.

Booting Windows with F12 after using Bazzite is a **warm reboot**: VBUS is never
interrupted, so Windows inherits the wedged camera. Result: Windows Hello can't
see you at the lock screen, and the Camera app shows no stream after PIN login.

## What was ruled out

- **Windows Fast Startup** — plausible at first, but wrong. The device is hung
  below the driver layer and Linux fails on a cold boot too. Disabling it is
  still sane dual-boot hygiene (dirty NTFS), but it does not fix this.
- **`uhubctl`** — works, but only on hubs advertising per-port power switching.
  The camera lives on a *root-hub* port, which `uhubctl` cannot see. The kernel's
  sysfs `disable` attribute covers root ports *and* hub ports, so it is used
  instead. One mechanism, works wherever the camera is plugged.

## The companion-port trap

A USB3 socket is two logical ports on two buses — a USB2 face and a SuperSpeed
face (`usb5-port2` and `usb6-port2` here). Cutting only one leaves the socket
partly powered. Measured: the camera survived and re-enumerated at **480 Mbps**,
silently losing 4K and 1080p60. Both faces must drop together. The kernel links
them with a `peer` symlink, which is how the pair is discovered rather than
hardcoded.

## What gets installed

| Path | Role |
|---|---|
| `/usr/local/bin/camera-usb-reset.sh` | the power-cycle, three modes |
| `/usr/local/bin/camera-reset` | symlink, for manual use |
| `/usr/local/lib/camera-usb-lib.sh` | shared helpers |
| `/etc/systemd/system/camera-usb-cycle-on.service` | boot: cache socket, recover if wedged |
| `/etc/systemd/system/camera-usb-cycle-off.service` | poweroff/halt/**reboot**: cycle |
| `/etc/udev/rules.d/99-logitech-brio.rules` | never autosuspend the camera |
| `/var/lib/camera-usb-cycle/ports` | cached socket location |
| `/var/log/camera-usb-cycle.log` | shutdown-path log |

The off unit **includes `reboot.target`** on purpose — the opposite of the
sibling `steelseries-usb-off` unit, which deliberately excludes it. The reboot
path is exactly the F12-into-Windows case this exists for.

A wedged camera never enumerates, so there is no device to resolve a port from.
That is why the boot unit caches the socket location while the camera is healthy.

## Install

```
distrobox-host-exec sudo bash ~/camera-usb-cycle/install.sh
```

The installer power-cycles the socket at the end and reports the resulting link
speed. Anything other than 5000/10000 Mbps means SuperSpeed did not train.

## Use

```
sudo camera-reset                          # wedged mid-session
systemctl status camera-usb-cycle-on       # what boot found
cat /var/log/camera-usb-cycle.log          # what shutdown did
```

## Also worth setting in BIOS

**ErP Ready = Enabled** (or *USB Power Delivery in Soft Off State (S5)* =
Disabled). That drops VBUS on full shutdown, cold-resetting the camera for free.
It does **not** cover the warm-reboot F12 path, so it complements these units
rather than replacing them. Costs: no wake-from-keyboard, no USB charging while
off.

## Uninstall

```
sudo systemctl disable --now camera-usb-cycle-on.service camera-usb-cycle-off.service
sudo rm -f /usr/local/bin/camera-usb-reset.sh /usr/local/bin/camera-reset \
           /usr/local/lib/camera-usb-lib.sh \
           /etc/systemd/system/camera-usb-cycle-{on,off}.service \
           /etc/udev/rules.d/99-logitech-brio.rules
sudo rm -rf /var/lib/camera-usb-cycle
sudo systemctl daemon-reload && sudo udevadm control --reload-rules
```
