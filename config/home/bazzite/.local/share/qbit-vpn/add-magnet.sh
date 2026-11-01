#!/usr/bin/env bash
# Add whatever magnet link is on the clipboard to qBittorrent.
#
# Klipper is the only clipboard reader that works here: wl-paste needs a Wayland
# connection this may not have, and xclip is X11. The add itself goes through the
# container for the same reason as everything else - qBittorrent waives auth only
# for genuine loopback peers, and podman's port publish rewrites the source.
set -uo pipefail

notify() { notify-send -a "qBittorrent" -i qbittorrent "$@" 2>/dev/null || true; }

clip=$(qdbus-qt6 org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents 2>/dev/null)
clip="${clip%%$'\n'*}"          # a multi-line clipboard: take the first line only

case "$clip" in
  magnet:\?*) ;;
  *)
    notify -u critical "No magnet link on the clipboard" \
           "Copy a magnet: link first, then try again."
    exit 1 ;;
esac

if ! podman inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true; then
  notify -u critical "qBittorrent is not running" "Start it from the tray first."
  exit 1
fi

code=$(podman exec -e M="$clip" qbittorrent sh -c '
  curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
    --data-urlencode "urls=$M" \
    http://127.0.0.1:8080/api/v2/torrents/add' 2>/dev/null)

if [ "$code" = "200" ]; then
  # The magnet's display name if it has one, else just the hash-ish head.
  name=$(printf '%s' "$clip" | sed -n 's/.*[?&]dn=\([^&]*\).*/\1/p' | sed 's/+/ /g')
  [ -n "$name" ] && name=$(printf '%b' "${name//%/\\x}")
  notify "Torrent added" "${name:-Magnet link added to qBittorrent.}"
else
  notify -u critical "Could not add the torrent" "qBittorrent returned HTTP ${code:-no response}."
  exit 1
fi
