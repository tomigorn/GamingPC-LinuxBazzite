#!/usr/bin/env bash
# One-time HOST changes needed before the qBittorrent/gluetun containers can run.
# Run on the host with: sudo bash ~/.local/share/qbit-vpn/host-selinux-setup.sh
#
# Two SELinux problems, both verified by testing rather than assumed:
#   1. /dev/net/tun is tun_tap_device_t; container_t may not open it unless the
#      container_use_devices boolean is on. gluetun cannot build a tunnel without it.
#   2. /mnt/Secondary is ntfs3, which cannot store SELinux xattrs, so every file
#      there is unlabelled and container_t is denied. The fix is a mount-time
#      context= option, which labels the whole filesystem uniformly.
set -euo pipefail

FSTAB=/etc/fstab
UUID=EE74AD5974AD24F5
CONTEXT='context=system_u:object_r:container_file_t:s0'

if [[ $EUID -ne 0 ]]; then
  echo "Run me as root: sudo bash $0" >&2
  exit 1
fi

echo "==> 1/2  Allowing containers to use device nodes (/dev/net/tun)"
if [[ "$(getsebool container_use_devices | awk '{print $3}')" == "on" ]]; then
  echo "    already on, nothing to do"
else
  setsebool -P container_use_devices 1
  echo "    container_use_devices -> on"
fi

echo "==> 2/2  Labelling the /mnt/Secondary mount for container access"
if grep -q "$UUID.*$CONTEXT" "$FSTAB"; then
  echo "    fstab already carries the context option, nothing to do"
else
  backup="${FSTAB}.bak.qbit-vpn"
  cp -a "$FSTAB" "$backup"
  echo "    backed up $FSTAB -> $backup"

  # Append the context option to that one line's option field (field 4).
  awk -v uuid="$UUID" -v ctx="$CONTEXT" '
    $1 == "UUID=" uuid && $0 !~ ctx { $4 = $4 "," ctx }
    { print }
  ' OFS='\t' "$backup" > "$FSTAB"

  echo "    new fstab line:"
  grep "$UUID" "$FSTAB" | sed 's/^/      /'
fi

echo "==> Remounting /mnt/Secondary so the new label takes effect"
systemctl daemon-reload
if umount /mnt/Secondary 2>/dev/null; then
  echo "    unmounted"
else
  echo "    could not unmount (files in use?) - it will pick up the label at next boot"
fi
systemctl restart mnt-Secondary.automount 2>/dev/null || true
ls /mnt/Secondary >/dev/null 2>&1 || true

echo
echo "Result:"
findmnt -T /mnt/Secondary -o TARGET,FSTYPE,OPTIONS | sed 's/^/  /'
echo
ls -Zd /mnt/Secondary/qBittorrent | sed 's/^/  /'
echo
echo "Done. If the context above still shows '?', reboot and it will apply."
