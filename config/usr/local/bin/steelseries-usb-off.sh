#!/usr/bin/env bash
#
# steelseries-usb-off.sh — runs at poweroff/halt (steelseries-usb-off.service)
#
# Cuts USB VBUS to the SteelSeries base station's port so its OLED goes dark
# while the PC is off. Reads the location cached at boot; falls back to a live
# probe. Logs to a PERSISTENT file (/var/log) because the journal is torn down
# too early in shutdown to trust. Always exits 0 so it can never block shutdown.
#
# This is a real script (not an inlined ExecStart) on purpose: systemd performs
# its own $VAR expansion on ExecStart lines, which silently ate "$h"/"$p" in the
# previous inlined version and made uhubctl run with empty arguments.
#
set -uo pipefail   # NOT -e: we must always reach the log line and exit 0

USB_ID="1038:12e0"
CACHE_FILE="/run/steelseries-usb/location"
UHUBCTL="/usr/bin/uhubctl"
LOG="/var/log/steelseries-usb-off.log"

ts()  { date '+%F %T' 2>/dev/null || echo '?'; }
log() { echo "$(ts) off: $*" >>"$LOG" 2>/dev/null || true; }

log "invoked (shutdown/halt)"

if [[ ! -x "$UHUBCTL" ]]; then
    log "uhubctl missing at $UHUBCTL; nothing to do"
    exit 0
fi

hub="" port=""
if [[ -r "$CACHE_FILE" ]]; then
    read -r hub port < "$CACHE_FILE" || true
    log "cache says hub='$hub' port='$port'"
else
    log "no cache at $CACHE_FILE"
fi

# Live-probe fallback if the cache was empty/missing.
if [[ -z "$hub" || -z "$port" ]]; then
    log "live-probing for $USB_ID"
    while IFS= read -r line; do
        if [[ $line =~ ^Current\ status\ for\ hub\ ([^[:space:]]+) ]]; then
            hub="${BASH_REMATCH[1]}"
        elif [[ $line == *"$USB_ID"* && $line =~ Port\ ([0-9]+): ]]; then
            port="${BASH_REMATCH[1]}"
            break
        fi
    done < <("$UHUBCTL" 2>/dev/null || true)
fi

if [[ -z "$hub" || -z "$port" ]]; then
    log "device $USB_ID not found; nothing to do"
    exit 0
fi

log "cutting hub $hub port $port"
out="$("$UHUBCTL" -l "$hub" -p "$port" -a off 2>&1)" ; rc=$?
log "uhubctl rc=$rc output=[${out//$'\n'/ | }]"
exit 0
