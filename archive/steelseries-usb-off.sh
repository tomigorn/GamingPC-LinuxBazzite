#!/bin/bash

DEVICE_NAME="SteelSeries"

# Read uhubctl output line by line
HUB=""
PORT=""

while IFS= read -r line; do
    # If the line defines a hub, store it
    if [[ $line =~ ^Current\ status\ for\ hub\ ([^[:space:]]+) ]]; then
        HUB="${BASH_REMATCH[1]}"
    fi

    # If the line contains the device name, get the port
    if echo "$line" | grep -iq "$DEVICE_NAME"; then
        # Extract "Port N"
        if [[ $line =~ Port\ ([0-9]+) ]]; then
            PORT="${BASH_REMATCH[1]}"
            break  # stop after finding the first match
        fi
    fi
done < <(uhubctl)

# Print for verification
echo "Hub: $HUB"
echo "Port: $PORT"

# Power off the device
sudo uhubctl -l "$HUB" -p "$PORT" -a off
