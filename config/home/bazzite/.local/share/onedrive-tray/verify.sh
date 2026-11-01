#!/bin/bash
ITEM=$(gdbus call --session --dest org.kde.StatusNotifierWatcher \
  --object-path /StatusNotifierWatcher \
  --method org.freedesktop.DBus.Properties.Get \
  org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems \
  | tr ',' '\n' | grep -o ':[0-9.]*/org/ayatana/NotificationItem/onedrive_tray')
BUS=${ITEM%%/*}; OBJ=/${ITEM#*/}
prop() { gdbus call --session --dest "$BUS" --object-path "$OBJ" \
  --method org.freedesktop.DBus.Properties.Get \
  org.kde.StatusNotifierItem "$1" 2>/dev/null | sed "s/^(<'//;s/'>,)\$//"; }
echo "=== tray live state (read from Plasma's SNI) ==="
echo "  registered : ${BUS:-NOT REGISTERED}"
echo "  icon       : $(prop IconName)"
echo "  status     : $(prop Title)"
echo
echo "=== deliverables ==="
ls -la ~/.local/share/onedrive-tray/
ls -la ~/.config/autostart/onedrive-tray.desktop
echo "total size: $(du -sh ~/.local/share/onedrive-tray/ | cut -f1)"
echo
echo "=== sync service untouched ==="
systemctl --user is-active homebrew.onedrive-cli.service
systemctl --user is-enabled homebrew.onedrive-cli.service
pgrep -af "onedrive --monitor" | wc -l
echo
echo "=== no stray files left in ~/OneDrive ==="
ls ~/OneDrive/tray-* 2>/dev/null || echo "  none"
