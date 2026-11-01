#!/usr/bin/env bash
# Re-apply Proton's currently-forwarded port to qBittorrent.
#
# gluetun only runs its UP_COMMAND when Proton hands out or renews a lease. If
# qBittorrent restarts on its own (crash, manual restart, a preferences change
# that needs a bounce) it comes back on Session\Port from its config - 6881 -
# and stays there until the next lease renewal, up to an hour later. Wired as
# ExecStartPost so every qBittorrent start re-applies the live port.
set -uo pipefail
PORT=$(cat "$HOME/.local/share/qbit-vpn/gluetun/forwarded_port" 2>/dev/null | tr -dc '0-9')
[ -n "$PORT" ] || exit 0
# Reuse the one script that knows how to wait for the WebUI and verify the value.
exec podman exec gluetun /bin/sh /gluetun/set-qbit-port.sh "$PORT"
