#!/usr/bin/env bash
#
# camera-usb-lib.sh — shared helpers for the Logitech BRIO port power-cycle.
#
# Installed to /usr/local/lib (i.e. /var/usrlocal/lib on atomic Fedora); both
# units are ordered so /var is still mounted when they run.
#
# WHY THIS EXISTS
# ---------------
# The BRIO periodically wedges: it trains a USB link, gets "enable connect",
# then stops answering SET_ADDRESS ("device not accepting address, error -71").
# Nothing software-side can talk to it in that state — only removing VBUS
# resets it, which is why a physical unplug/replug is the only known cure.
# When it wedges under Linux and you warm-reboot into Windows, VBUS never
# drops, so Windows inherits a dead camera: no Windows Hello, no video stream.
#
# We use the kernel's per-port "disable" attribute rather than uhubctl.
# Writing 1 clears PORT_POWER on the port; unlike uhubctl it also works on
# root-hub ports, which is where this camera actually lives.
#
# THE COMPANION-PORT TRAP
# -----------------------
# A USB3 socket is TWO logical ports: a USB2 face and a SuperSpeed face, on
# different buses (here usb5-port2 and usb6-port2). Cutting only one leaves the
# socket partly powered — measured behaviour: the BRIO stayed alive and
# re-enumerated at 480 Mbps (USB 2.0), which silently costs you 4K and 1080p60.
# Both faces must go down together. The kernel links them via a "peer" symlink,
# so we resolve the pair instead of hardcoding it.

CAM_VID="046d"
CAM_PID="085e"
CAM_LABEL="Logitech BRIO"
STATE_DIR="/var/lib/camera-usb-cycle"
CACHE_FILE="${STATE_DIR}/ports"
OFF_SECONDS="${OFF_SECONDS:-5}"

# find_cam_dev — print the camera's sysfs bus id (e.g. "5-2" or "1-3.4"),
# non-zero if it is not on the bus (unplugged, or wedged before enumeration).
find_cam_dev() {
    local d
    for d in /sys/bus/usb/devices/*-*; do
        case "$d" in *:*) continue ;; esac          # skip interface dirs
        [ -e "$d/idVendor" ] || continue
        [ "$(cat "$d/idVendor")" = "$CAM_VID" ] || continue
        [ "$(cat "$d/idProduct")" = "$CAM_PID" ] || continue
        basename "$d"
        return 0
    done
    return 1
}

# port_dir_of <bus-id> — print the sysfs port directory that owns that device.
#   "5-2"   -> /sys/bus/usb/devices/5-0:1.0/usb5-port2     (root-hub port)
#   "1-3.4" -> /sys/bus/usb/devices/1-3:1.0/1-3-port4      (external hub port)
# The port dir hangs off the parent hub's *interface*, not the hub device.
port_dir_of() {
    local dev="$1" hub port bus
    if [ "${dev#*.}" != "$dev" ]; then
        hub="${dev%.*}"; port="${dev##*.}"
        printf '/sys/bus/usb/devices/%s:1.0/%s-port%s\n' "$hub" "$hub" "$port"
    else
        bus="${dev%%-*}"; port="${dev#*-}"
        printf '/sys/bus/usb/devices/%s-0:1.0/usb%s-port%s\n' "$bus" "$bus" "$port"
    fi
}

# peer_of <port-dir> — print the companion port dir, or nothing if unpaired.
peer_of() {
    local p; p="$(readlink -f "$1/peer" 2>/dev/null)" || return 1
    [ -n "$p" ] && [ -d "$p" ] && printf '%s\n' "$p"
}

# cycle_ports <port-dir>... — drop VBUS on every given port, hold, restore.
# Ends with the ports powered ON so the machine is never left with a dark
# socket; a warm reboot into Windows then sees a freshly cold-started device,
# which is exactly what a manual replug achieves.
cycle_ports() {
    local p rc=0
    for p in "$@"; do
        if printf '1' > "$p/disable" 2>/dev/null; then
            log "  power OFF $(basename "$p")"
        else
            log "  WARN: could not disable $(basename "$p")"; rc=1
        fi
    done

    log "  holding ${OFF_SECONDS}s with VBUS removed"
    sleep "$OFF_SECONDS"

    for p in "$@"; do
        if printf '0' > "$p/disable" 2>/dev/null; then
            log "  power ON  $(basename "$p")"
        else
            log "  WARN: could not re-enable $(basename "$p")"; rc=1
        fi
    done
    return $rc
}

# resolve_ports — print the socket's port dirs (one per line), preferring a
# live probe and falling back to the cache. The cache matters because a wedged
# camera never enumerates, so there is no device to resolve a port from.
resolve_ports() {
    local dev pd peer
    if dev="$(find_cam_dev)"; then
        pd="$(port_dir_of "$dev")"
        if [ -d "$pd" ]; then
            printf '%s\n' "$pd"
            peer="$(peer_of "$pd")" && [ -n "$peer" ] && printf '%s\n' "$peer"
            return 0
        fi
    fi
    if [ -r "$CACHE_FILE" ]; then
        grep -v '^[[:space:]]*$' "$CACHE_FILE"
        return 0
    fi
    return 1
}

# save_ports <port-dir>... — persist the socket location for the wedged case.
save_ports() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    printf '%s\n' "$@" > "$CACHE_FILE"
}

# forbid_lpm <port-dir>... — turn off USB3 link power management (U1/U2) on any
# SuperSpeed port in the set. U1/U2 are the shallow link-power states that lead
# into U3, and U3 is where this camera was found dead.
#
# Only SuperSpeed port dirs have this attribute, so a missing file is normal and
# not an error. On this machine the kernel already reports "We don't know the
# algorithms for LPM for this host, disabling LPM" for the controller the camera
# sits on, making this a no-op there — it earns its keep if the camera is ever
# moved to the Realtek hub, whose port WAS observed sitting in U3.
forbid_lpm() {
    local p
    for p in "$@"; do
        [ -w "$p/usb3_lpm_permit" ] || continue
        if printf 'none' > "$p/usb3_lpm_permit" 2>/dev/null; then
            log "  U1/U2 link power management disabled on $(basename "$p")"
        fi
    done
}
