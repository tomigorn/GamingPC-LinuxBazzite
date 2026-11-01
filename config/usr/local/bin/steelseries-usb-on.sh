#!/usr/bin/env bash
#
# steelseries-usb-on.sh — runs at boot (steelseries-usb-on.service)
#
# This is where ALL the discovery/parsing happens, at boot, while /var is
# healthy. It resolves which hub/port the SteelSeries Arctis Nova Pro Wireless
# base station sits on, caches that location to /run (tmpfs) for the shutdown
# unit to consume, and asserts the port is powered so the headset charges.
#
# The shutdown unit intentionally does NOT run any script from /var — it only
# reads the /run cache written here. So it is important this resolves reliably.
#
set -euo pipefail

# --- Configuration -----------------------------------------------------------
USB_ID="1038:12e0"                                   # VID:PID (stable across replug)
DEVICE_LABEL="SteelSeries Arctis Nova Pro Wireless"
CACHE_DIR="/run/steelseries-usb"                     # tmpfs, cleared each boot
CACHE_FILE="${CACHE_DIR}/location"
UHUBCTL="$(command -v uhubctl || true)"; : "${UHUBCTL:=/usr/bin/uhubctl}"
MAX_TRIES=10                                         # ~5 s of retries for slow enumeration
TAG="steelseries-usb-on"

log() { echo "${TAG}: $*"; }

# --- Preconditions -----------------------------------------------------------
if [[ ! -x "$UHUBCTL" ]]; then
    log "uhubctl not found at '$UHUBCTL'; nothing to do."
    exit 0
fi

# --- Locate the device on a power-switchable hub -----------------------------
# uhubctl only lists hubs that support per-port power switching, so a match here
# also proves the port is controllable. USB enumeration is asynchronous, so we
# retry for a few seconds rather than assume the dock is ready at first probe.
#
# NOTE: today the dock is on a USB2-only hub, so a single hub/port pair is
# correct. If it is ever moved to a USB3 port, the hub presents both a USB2 and
# a USB3 instance and power must be toggled on BOTH — this "first match" logic
# would need to collect all matches. Not a concern on the current wiring.
hub="" port=""
for ((try = 1; try <= MAX_TRIES; try++)); do
    hub="" port=""
    while IFS= read -r line; do
        if [[ $line =~ ^Current\ status\ for\ hub\ ([^[:space:]]+) ]]; then
            hub="${BASH_REMATCH[1]}"
        elif [[ $line == *"$USB_ID"* && $line =~ Port\ ([0-9]+): ]]; then
            port="${BASH_REMATCH[1]}"
            break
        fi
    done < <("$UHUBCTL" 2>/dev/null || true)

    [[ -n "$hub" && -n "$port" ]] && break
    sleep 0.5
done

if [[ -z "$hub" || -z "$port" ]]; then
    log "Device $USB_ID not found on a power-switchable hub after ${MAX_TRIES} tries; leaving cache untouched."
    exit 0
fi

# --- Cache the resolved location for the shutdown unit -----------------------
mkdir -p "$CACHE_DIR"
printf '%s %s\n' "$hub" "$port" > "$CACHE_FILE"
log "Resolved $DEVICE_LABEL at hub $hub port $port (cached to $CACHE_FILE)."

# --- Belt-and-suspenders: assert the port is powered (charging) --------------
# The kernel already powers ports on at hub init, so this is redundant for
# charging; its real job above is writing the cache. Harmless if already on.
if "$UHUBCTL" -l "$hub" -p "$port" -a on >/dev/null 2>&1; then
    log "Port powered on."
else
    log "Note: could not assert power-on (port is most likely already on)."
fi
exit 0
