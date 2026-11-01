#!/bin/sh
# Run by qBittorrent inside the container when a torrent finishes.
# It cannot reach the desktop to raise a notification, so it just appends the
# name to a log on the shared /config volume; the tray widget watches that file
# from the host and notifies. Keeps the always-on poll a cheap file read rather
# than an API call.
printf '%s\n' "$1" >> /config/completed.log
