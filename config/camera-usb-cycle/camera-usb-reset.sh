#!/usr/bin/env bash
#
# camera-usb-reset.sh — power-cycle the BRIO's USB socket.
#
# Three callers:
#   --boot      camera-usb-cycle-on.service   : cache location; recover if wedged
#   --shutdown  camera-usb-cycle-off.service  : always cycle, so Windows gets a
#                                               cold-started camera after F12
#   --now       you, from a terminal (`camera-reset`), when it dies mid-session
#
# Always exits 0 in --shutdown mode: nothing here may ever block a shutdown.
#
set -uo pipefail

# shellcheck source=/usr/local/lib/camera-usb-lib.sh
. /usr/local/lib/camera-usb-lib.sh

MODE="${1:---now}"
LOG_FILE="/var/log/camera-usb-cycle.log"

case "$MODE" in
    --shutdown)
        # The journal is torn down early in the shutdown transaction, so log to
        # a real file — same reasoning as the SteelSeries off unit.
        log() { echo "$(date '+%F %T' 2>/dev/null || echo '?') shutdown: $*" >>"$LOG_FILE" 2>/dev/null || true; }
        ;;
    *)
        log() { echo "camera-usb-reset: $*"; }
        ;;
esac

mapfile -t PORTS < <(resolve_ports)

if [ "${#PORTS[@]}" -eq 0 ]; then
    log "camera not on the bus and no cached socket location; nothing to do."
    [ "$MODE" = "--shutdown" ] && exit 0
    exit 1
fi

# --- Boot mode: cache, and only cycle if the camera failed to come up --------
if [ "$MODE" = "--boot" ]; then
    if dev="$(find_cam_dev)"; then
        speed="$(cat "/sys/bus/usb/devices/$dev/speed" 2>/dev/null)"
        log "$CAM_LABEL present at $dev (${speed}Mbps); caching socket."
        save_ports "${PORTS[@]}"
        forbid_lpm "${PORTS[@]}"
        if [ "$speed" = "480" ]; then
            log "NOTE: running at USB 2.0 speed — 4K/1080p60 unavailable."
            log "Cycling to give SuperSpeed another chance."
            cycle_ports "${PORTS[@]}"
        fi
        exit 0
    fi
    log "$CAM_LABEL did not enumerate; power-cycling cached socket to recover."
    cycle_ports "${PORTS[@]}"
    sleep 4
    if dev="$(find_cam_dev)"; then
        log "recovered at $dev ($(cat "/sys/bus/usb/devices/$dev/speed" 2>/dev/null)Mbps)."
    else
        log "still absent after cycle — camera may be unplugged."
    fi
    exit 0
fi

# --- Shutdown mode: unconditional cycle, never fail ---------------------------
if [ "$MODE" = "--shutdown" ]; then
    log "invoked; cycling ${#PORTS[@]} port(s) so the next OS sees a cold camera"
    cycle_ports "${PORTS[@]}"
    log "done"
    exit 0
fi

# --- Manual mode --------------------------------------------------------------
log "cycling ${#PORTS[@]} port(s): ${PORTS[*]}"
cycle_ports "${PORTS[@]}"
sleep 4
if dev="$(find_cam_dev)"; then
    speed="$(cat "/sys/bus/usb/devices/$dev/speed" 2>/dev/null)"
    log "$CAM_LABEL is back at $dev (${speed}Mbps)."
    [ "$speed" = "480" ] && log "WARNING: only USB 2.0 — rerun, or replug by hand."
    save_ports "${PORTS[@]}"
else
    log "camera did not come back; check the cable."
    exit 1
fi
