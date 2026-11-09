# Storage and sync

## Filesystems

| Mount | What |
|---|---|
| `/`, `/home`, `/var` | btrfs subvolumes on LUKS (`nvme1n1`), `compress=zstd:1`, unlocked by TPM2 |
| `/mnt/Secondary` | ~1.4 TB NTFS data partition (`nvme1n1p4`): movies, downloads |
| `/mnt/mouse` | Samba share from `fastpi` (Raspberry Pi in the homelab) |
| `~/OneDrive` | OneDrive sync (~78 GB) |

Both extra mounts are single lines in `/etc/fstab` (which persists, see [System](01-system.md)). Excerpt: [`config/etc/fstab.excerpt`](../config/etc/fstab.excerpt).

### `/mnt/Secondary` (NTFS)

```
UUID=EE74AD5974AD24F5  /mnt/Secondary  ntfs3  defaults,nofail,uid=1000,gid=1000,umask=022,windows_names,x-systemd.automount,x-gvfs-show,context=system_u:object_r:container_file_t:s0  0 0
```

- Kernel `ntfs3` driver. `windows_names` refuses filenames Windows can't open.
- `nofail` + `x-systemd.automount`: boot never waits for it.
- **`context=...container_file_t`**: NTFS can't store SELinux labels, and without this the distroboxes and podman containers (e.g. qBittorrent) are denied access.
- From inside the `vscode` distrobox, it's at `/run/host/mnt/Secondary`.
- Windows is on the *other* disk, so there's no hibernation/Fast Startup risk to this partition.

### `/mnt/mouse` (SMB from fastpi)

```
//192.168.1.2/mouse  /var/mnt/mouse  cifs  credentials=/etc/smb-mouse.cred,seal,vers=3.1.1,uid=1000,gid=1000,file_mode=0664,dir_mode=0775,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=15,context=system_u:object_r:container_file_t:s0,x-gvfs-show  0 0
```

`/etc/smb-mouse.cred` (`0600 root:root`, **not** in this repo):

```
username=...
password=...
```

- **`seal` is required**: the server enforces SMB encryption. Check that it was actually negotiated: `findmnt -no OPTIONS /mnt/mouse | tr , '\n' | grep seal`.
- **Use the IP**, not `fastpi`: the name resolves to a link-local IPv6 address that cifs can't use.
- `context=` for the same reason as `Secondary`. It is scoped to this mount, which is better than turning on the `virt_use_samba` boolean.
- `cifs-utils` is already in the Bazzite image, so no layering or reboot.
- Boot safety: `_netdev` + automount means a powered-off Pi never delays boot, and the kernel's default `soft` mount returns errors instead of hanging.

## OneDrive

The abraunegg `onedrive` client (v2.5.x) from **Homebrew**, running as the user service `homebrew.onedrive-cli`. It syncs to `~/OneDrive`.

```bash
brew install onedrive-cli
onedrive                       # first run: log in, paste the redirect URL
brew services start onedrive-cli
```

> Only ever **one** `onedrive --monitor`. The service is the sync owner, and a second monitor on the same account corrupts the sync state.

Manage it from inside the distrobox with `distrobox-host-exec brew services list|start|stop|restart onedrive-cli`. Log: `/home/linuxbrew/.linuxbrew/var/log/onedrive.log`.

Customisations:

- **Wait for DNS before starting**, [`override.conf`](../config/home/bazzite/.config/systemd/user/homebrew.onedrive-cli.service.d/override.conf): polls `getent hosts graph.microsoft.com` for up to 120 s, and always continues. It lives in a drop-in because `brew services` regenerates the main unit on upgrade.
- **WebSocket push disabled**: `~/.config/onedrive/config` contains `disable_websocket_support = "true"`. Microsoft's change-notification subscription kept failing with `400 Bad Request / notSupported` (popups, roughly daily). File sync was never affected. Now it polls every 300 s plus inotify for local changes. If Microsoft fixes it, flip it back for instant sync.
- **Full re-scan once a day**, not hourly: `monitor_fullscan_frequency = "288"` (288 × 300 s). The default (every 12th loop) re-fetched all ~358k online items every hour, ~9 % of a core on average. Remote changes still arrive with the 5-min delta poll; the full scan is only the consistency safety net. Config copy: [`config/.../onedrive/config`](../config/home/bazzite/.config/onedrive/config).
- **Tray icon**: a small self-written indicator, [`onedrive-tray`](../config/home/bazzite/.local/share/onedrive-tray/) (README inside). It only reads the service's log and never touches the sync itself. Autostarts via `~/.config/autostart/onedrive-tray.desktop`.

**Known warning:** *"number of objects stored online exceeds Microsoft OneDrive's recommended limit"*. The account has ~358k files and folders online (limit ~300k). It's about the **count**, not space. Sync keeps working. The real fix is archiving trees with many small files (old study/code folders). `sync_list` doesn't help, since it only changes what is downloaded.
