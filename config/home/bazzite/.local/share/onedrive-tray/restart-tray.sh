#!/bin/bash
# Restart the tray cleanly. Lives in a file so that pkill's -f pattern cannot
# match this script's own (short) command line.
pkill -f onedrive-tray.py 2>/dev/null
sleep 1
nohup python3 "$HOME/.local/share/onedrive-tray/onedrive-tray.py" \
  >/tmp/onedrive-tray.log 2>&1 &
disown
sleep 4
echo "=== second launch must be refused by the single-instance guard ==="
python3 "$HOME/.local/share/onedrive-tray/onedrive-tray.py" 2>&1 | head -2
echo "=== running instances (expect exactly 1) ==="
pgrep -af onedrive-tray.py | grep -v restart-tray
echo "count: $(pgrep -f onedrive-tray.py | wc -l)"
echo "=== startup stderr (should be empty) ==="
cat /tmp/onedrive-tray.log
