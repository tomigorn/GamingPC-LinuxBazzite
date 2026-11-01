#!/bin/sh
# Called by gluetun whenever Proton hands out a new forwarded port.
# gluetun and qBittorrent share a network namespace, so 127.0.0.1 here IS
# qBittorrent's WebUI. Needs "bypass authentication for localhost" enabled
# (WebUI\LocalHostAuth=false in qBittorrent.conf).
set -eu

PORT="${1:-}"
[ -n "$PORT" ] || exit 0

API="http://127.0.0.1:8080/api/v2"

# qBittorrent is ordered to start only once gluetun reports healthy, and Proton
# hands out the port within seconds of that - so on a cold start this command
# fires BEFORE qBittorrent is listening and the POST is lost. Wait for the WebUI
# instead of firing blind; without this the listen port silently stays at its
# old value and the forwarded port does nothing.
i=0
while [ "$i" -lt 60 ]; do
  wget -q -O /dev/null "${API}/app/version" 2>/dev/null && break
  i=$((i + 1))
  sleep 2
done
if [ "$i" -ge 60 ]; then
  echo "qbit WebUI did not answer within 120s; listen port not set to ${PORT}" >&2
  exit 1
fi

wget -qO- \
  --post-data="json={\"listen_port\":${PORT},\"random_port\":false,\"upnp\":false}" \
  "${API}/app/setPreferences" >/dev/null 2>&1 || {
    echo "failed to set qbit listen port to ${PORT}" >&2; exit 1; }

# Read it back: a 200 from setPreferences does not prove the value took.
actual=$(wget -qO- "${API}/app/preferences" 2>/dev/null \
  | tr ',' '\n' | grep '"listen_port"' | tr -dc '0-9')
if [ "$actual" = "$PORT" ]; then
  echo "qbit listen port set to ${PORT}"
else
  echo "qbit listen port is ${actual:-unknown}, expected ${PORT}" >&2
  exit 1
fi
