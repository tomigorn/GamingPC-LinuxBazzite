# qBittorrent behind ProtonVPN

qBittorrent runs in a container that **cannot reach the internet except through the VPN tunnel**. If the tunnel goes down, qBittorrent goes down with it.

Rootless **podman quadlets** (systemd units for containers) rather than compose, because the host is immutable:

| Path | What |
|---|---|
| `~/.config/containers/systemd/gluetun.container` | ProtonVPN WireGuard tunnel ([`qmcgaw/gluetun:v3`](https://github.com/qdm12/gluetun)) |
| `~/.config/containers/systemd/qbittorrent.container` | `linuxserver/qbittorrent` |
| `~/.config/qbit-vpn/proton.env` | the WireGuard key etc., `0600`, **not in this repo** |
| `~/.local/share/qbit-vpn/` | state + helper scripts |
| `/mnt/Secondary/qBittorrent` | downloads |

Copies: [`config/.../containers/systemd/`](../config/home/bazzite/.config/containers/systemd/), [`config/.../qbit-vpn/`](../config/home/bazzite/.local/share/qbit-vpn/).

## How "no VPN, no torrenting" is enforced

1. `Network=gluetun.container`: qBittorrent has **no network of its own**, only gluetun's. That's not a firewall rule that could be wrong. There's simply no other route.
2. `Notify=healthy` + gluetun's healthcheck (which tests *through* the tunnel): systemd doesn't consider gluetun started until the tunnel works, and qBittorrent is ordered `After=` it.
3. `BindsTo=` + `PartOf=` + `HealthOnFailure=kill`: a dying tunnel takes qBittorrent down.

Test it on purpose: `~/.local/share/qbit-vpn/verify.sh --killswitch`.

## Use

- Start-menu entry **qBittorrent** (`launch.sh`): starts the stack, waits for it, opens the WebUI as a Brave app window. Right-click actions: *Check VPN status*, *Stop qBittorrent and VPN*.
- Tray widget `org.kde.plasma.qbittorrentvpn` + `~/.local/bin/qbit-vpn-status`: state, exit IP, speeds, torrent counts. It says "behind ProtonVPN" only if gluetun is healthy **and** qBittorrent is up **and** a public IP was found through the tunnel.
- Starts **on demand only**, not at boot. Stop with `systemctl --user stop gluetun.service`.
- Change server country: edit `SERVER_COUNTRIES` in `proton.env`, then `systemctl --user restart gluetun.service`.

## Port forwarding

`PORT_FORWARD_ONLY=on` only picks servers that support it. gluetun runs [`set-qbit-port.sh`](../config/home/bazzite/.local/share/qbit-vpn/gluetun/set-qbit-port.sh) when it gets a port, and the script sets qBittorrent's listen port through the API.

## Traps

- **The port update fired before qBittorrent existed**, so it was lost silently. The script now waits for the WebUI and reads the value back.
- **`systemctl restart gluetun` left qBittorrent stopped** (`BindsTo` stops it, `PartOf` doesn't start it). Fixed with `Wants=qbittorrent.service` in gluetun.
- **`WebUI\LocalHostAuth=false` is required**, because the port script posts without logging in.
- **The WebUI API returns 403 from the host** (podman's port publishing changes the source address, so it isn't "localhost"). The status script queries from *inside* the container with `podman exec` instead of weakening auth.
- `Notify=healthy` keeps gluetun in `activating` for 20–60 s. Scripts must not treat that as failure.
- Inside the namespace, `ip route` shows the LAN default route. That's fine, because WireGuard uses policy routing. Prove the tunnel by the exit IP.
- BusyBox `ip` (in gluetun) has no `-br`.
- NAT-PMP occasionally refuses on a server that advertises forwarding. Restarting gluetun fixes it.
- Set a permanent WebUI login with `set-qbit-login.sh`. Otherwise the image makes a new temporary password on every start.
- The WebUI window's icon needed the Alt+Tab fix, see [Desktop](05-desktop-kde.md#wrong-icon-in-alttab-or-the-task-bar).
