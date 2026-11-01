#!/usr/bin/env bash
# Desktop launcher for the VPN-locked qBittorrent.
#
# Brings up gluetun + qBittorrent (systemd pulls gluetun in as a dependency),
# waits for the WebUI to actually answer, then opens it as a chrome-less app
# window. If the VPN never comes up the WebUI never answers, and you get a
# notification saying so rather than a browser error page - which is the
# behaviour we want: no tunnel, no qBittorrent.
set -uo pipefail

URL="http://127.0.0.1:8080"
WMCLASS="qbittorrent"
ICON="qbittorrent"
# gluetun now reports "started" only once its healthcheck passes (Notify=healthy),
# so a cold start is tunnel negotiation + the 60s health start period.
TIMEOUT=150

notify() { notify-send -a "qBittorrent" -i "$ICON" "$@" 2>/dev/null || true; }

case "${1:-}" in
  --stop)
    # Close the WebUI window too - a leftover browser window showing a dead page
    # looks like the stack is still running.
    bash "$HOME/.local/share/qbit-vpn/close-webui.sh" 2>/dev/null || true
    systemctl --user stop qbittorrent.service gluetun.service
    notify "qBittorrent stopped" "The VPN tunnel has been shut down too."
    exit 0
    ;;
  --status)
    exec konsole -e bash -c "bash $HOME/.local/share/qbit-vpn/verify.sh; echo; read -rp 'Press Enter to close…'"
    ;;
esac

# Already answering? Just open the window, skip the startup dance.
if ! curl -sf --max-time 2 -o /dev/null "$URL"; then
  notify "Starting qBittorrent" "Connecting to ProtonVPN first…"
  # --no-block: with Notify=healthy a blocking start would sit silent for up to
  # TimeoutStartSec(180s) before returning. Letting the loop below do the waiting
  # keeps the user informed and reports failure sooner.
  systemctl --user start --no-block qbittorrent.service 2>/dev/null

  waited=0
  until curl -sf --max-time 2 -o /dev/null "$URL"; do
    # "activating" is the normal state while the tunnel comes up and the
    # healthcheck has not passed yet, so only a terminal state is a failure.
    # is-active --quiet would treat that healthy waiting period as a failure.
    case "$(systemctl --user is-active gluetun.service)" in
      activating|active|reloading) ;;
      *)
        notify -u critical "VPN failed to start" \
          "qBittorrent was not started. Check: journalctl --user -u gluetun -e"
        exit 1
        ;;
    esac
    if (( waited >= TIMEOUT )); then
      notify -u critical "Timed out waiting for the VPN" \
        "qBittorrent is not reachable after ${TIMEOUT}s. Check: journalctl --user -u gluetun -e"
      exit 1
    fi
    sleep 2
    (( waited += 2 ))
  done
fi

# --class has NO effect on Wayland: Chromium derives the app_id from the --app
# URL and profile instead, giving "brave-127.0.0.1__-Default". The icon comes
# from two files keyed to that app_id, not from these flags:
#   ~/.local/share/applications/brave-127.0.0.1__-Default.desktop  (KWin/Alt+Tab)
#   StartupWMClass in qbittorrent.desktop                          (task bar)
# They are kept only so the window still matches if this ever runs on X11.
# NOTE: the app_id is built from the URL's HOST and PATH only - the port is not
# in it, so changing 8080 does NOT rename it. Changing the host or path does.
# Re-check with the dump recipe in the kwin-alttab-icon-appid note if it moves.
exec flatpak run com.brave.Browser \
  --app="$URL" \
  --class="$WMCLASS" \
  --name="$WMCLASS" \
  >/dev/null 2>&1
