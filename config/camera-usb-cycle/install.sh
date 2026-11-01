#!/usr/bin/env bash
#
# Installer for the Logitech BRIO USB power-cycle units.
# Target: Bazzite / atomic Fedora (rpm-ostree, /usr/local -> /var/usrlocal).
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN=/usr/local/bin
LIB=/usr/local/lib
UNITDIR=/etc/systemd/system
RULEDIR=/etc/udev/rules.d

# Must run on the host: the units, udev and the USB stack are the host's.
if [[ -f /run/.containerenv || -n "${container:-}" ]]; then
    echo "!! Running INSIDE the distrobox container. Re-run on the host:"
    echo "       distrobox-host-exec sudo bash ~/camera-usb-cycle/$(basename "$0")"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo…"
    exec sudo -- "$0" "$@"
fi

# 1. Install script, library, units and udev rule.
install -D -m 0755 "$SRC/camera-usb-reset.sh"          "$BIN/camera-usb-reset.sh"
install -D -m 0644 "$SRC/camera-usb-lib.sh"            "$LIB/camera-usb-lib.sh"
install -D -m 0644 "$SRC/camera-usb-cycle-on.service"  "$UNITDIR/camera-usb-cycle-on.service"
install -D -m 0644 "$SRC/camera-usb-cycle-off.service" "$UNITDIR/camera-usb-cycle-off.service"
install -D -m 0644 "$SRC/99-logitech-brio.rules"       "$RULEDIR/99-logitech-brio.rules"

# Convenience: `sudo camera-reset` when it wedges mid-session.
ln -sf "$BIN/camera-usb-reset.sh" "$BIN/camera-reset"

# 2. Apply the udev rule to the already-connected camera.
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --attr-match=idVendor=046d --attr-match=idProduct=085e || true

# 3. Enable both units.
systemctl daemon-reload
systemctl enable camera-usb-cycle-on.service camera-usb-cycle-off.service

echo
echo "=== installed. current camera state ==="
. "$LIB/camera-usb-lib.sh"
if dev="$(find_cam_dev)"; then
    speed="$(cat "/sys/bus/usb/devices/$dev/speed" 2>/dev/null)"
    echo "  found at $dev, ${speed} Mbps, power/control=$(cat "/sys/bus/usb/devices/$dev/power/control" 2>/dev/null)"
else
    echo "  camera NOT on the bus (wedged or unplugged)"
fi

echo
echo "=== power-cycling now (both faces of the socket) ==="
"$BIN/camera-usb-reset.sh" --now || true

echo
echo "=== result ==="
if dev="$(find_cam_dev)"; then
    speed="$(cat "/sys/bus/usb/devices/$dev/speed" 2>/dev/null)"
    echo "  $dev @ ${speed} Mbps  power/control=$(cat "/sys/bus/usb/devices/$dev/power/control" 2>/dev/null)"
    if [[ $speed == 5000 || $speed == 10000 ]]; then
        echo "  OK: SuperSpeed restored."
    else
        echo "  WARNING: still USB 2.0 (480 Mbps) — 4K/1080p60 unavailable."
    fi
else
    echo "  camera did not come back — replug it by hand."
fi
echo
echo "Verify later with:"
echo "    systemctl status camera-usb-cycle-on.service"
echo "    cat /var/log/camera-usb-cycle.log      # written on shutdown/reboot"
