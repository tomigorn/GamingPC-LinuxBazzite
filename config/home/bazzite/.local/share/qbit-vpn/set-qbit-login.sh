#!/usr/bin/env bash
# Set a permanent qBittorrent WebUI username/password.
#
# Without one, the linuxserver image generates a NEW temporary password on every
# start and prints it to the container log - which is why the WebUI kept asking
# for credentials nobody had. Setting one stops that.
#
# The request is made from INSIDE the container: qBittorrent waives auth for
# genuine loopback peers, and there the source really is 127.0.0.1. From the host
# podman's port publish rewrites the source address and the same call gets 403,
# so this needs no existing password.
set -euo pipefail

# Podman and the units live on the HOST. Test whether WE are inside a container -
# NOT whether distrobox-host-exec exists, because it is present on the host too,
# where invoking it just fails. /run/.containerenv is written by podman inside
# the container and is absent on the host.
if [ -f /run/.containerenv ] || [ -n "${container:-}" ]; then
  HOST="distrobox-host-exec"
else
  HOST=""
fi

if ! $HOST podman inspect -f '{{.State.Running}}' qbittorrent 2>/dev/null | grep -q true; then
  echo "qBittorrent is not running. Start it first:" >&2
  echo "  systemctl --user start qbittorrent.service" >&2
  exit 1
fi

read -rp "WebUI username [admin]: " USER
USER="${USER:-admin}"

read -rsp "New password (min 6 chars): " P1; echo
read -rsp "Repeat password: " P2; echo
if [ "$P1" != "$P2" ]; then echo "Passwords do not match." >&2; exit 1; fi
if [ "${#P1}" -lt 6 ]; then echo "Too short - qBittorrent requires at least 6 characters." >&2; exit 1; fi

# Passed via env, not on the command line, so it never lands in the container's
# process list. python3 does the JSON escaping so quotes/backslashes survive.
json=$(QB_U="$USER" QB_P="$P1" python3 -c '
import json, os
print(json.dumps({"web_ui_username": os.environ["QB_U"],
                  "web_ui_password": os.environ["QB_P"]}))')

$HOST podman exec -e QBJSON="$json" qbittorrent sh -c '
  curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    --data-urlencode "json=$QBJSON" \
    http://127.0.0.1:8080/api/v2/app/setPreferences' > /tmp/.qbcode 2>/dev/null

code=$(cat /tmp/.qbcode); rm -f /tmp/.qbcode
if [ "$code" != "200" ]; then
  echo "setPreferences returned HTTP $code - password not changed." >&2
  exit 1
fi

# Prove it: log in from the host, which is the path that was prompting you.
sleep 1
login=$($HOST curl -s -o /dev/null -w "%{http_code}" --max-time 8 \
        --data-urlencode "username=$USER" --data-urlencode "password=$P1" \
        http://127.0.0.1:8080/api/v2/auth/login)
case "$login" in
  200|204) echo "Done. Log in at http://127.0.0.1:8080 as '$USER'." ;;
  *) echo "Password was set but the login test returned HTTP $login." >&2; exit 1 ;;
esac
