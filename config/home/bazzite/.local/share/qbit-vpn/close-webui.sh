#!/usr/bin/env bash
# Close the WebUI window(s). Stopping the containers leaves the browser window
# behind showing a dead page, which reads as "still running".
#
# There is no way to close a native Wayland window from the shell: wmctrl/xdotool
# are X11-only. KWin scripting is the supported route. Note Scripting.start does
# NOT re-run an already-started script - run() on the script object does.
set -uo pipefail
JS="$HOME/.local/share/qbit-vpn/close-webui.js"
[ -f "$JS" ] || exit 0
command -v qdbus-qt6 >/dev/null 2>&1 || exit 0

n="qbitclose$$"
id=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$JS" "$n" 2>/dev/null) || exit 0
[ -n "${id:-}" ] || exit 0
qdbus-qt6 org.kde.KWin "/Scripting/Script${id}" org.kde.kwin.Script.run >/dev/null 2>&1
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$n" >/dev/null 2>&1
exit 0
