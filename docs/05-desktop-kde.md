# Desktop (KDE Plasma, Wayland)

Two panels: containment 3 on `DP-1` and containment 55 on `DP-2`, each with its own start menu (Kickoff) and system tray.

## Custom tray widgets

Both are hand-written Plasma 6 plasmoids in `~/.local/share/plasma/plasmoids/` (copies in [`config/.../plasmoids/`](../config/home/bazzite/.local/share/plasma/plasmoids/)):

| Widget | What it shows |
|---|---|
| `org.kde.plasma.peripheralbattery` | Mouse / keyboard / headset / spare-battery levels, low-battery warning. See [USB peripherals](06-usb-peripherals.md#battery-widget) |
| `org.kde.plasma.qbittorrentvpn` | qBittorrent + VPN state, speeds, *Show WebUI* / *Stop*. See [qBittorrent behind VPN](09-qbittorrent-vpn.md) |

Adding a widget to the tray of **both** panels means appending its id to `extraItems`, `knownItems` and `shownItems` of both systray applets (through `qdbus org.kde.plasmashell /PlasmaShell evaluateScript`), then restarting plasmashell. Being in the panel config is also what autostarts them; no autostart entry is needed.

Plasma **suppresses notification popups while a fullscreen window is active**, so on this gaming machine low-battery warnings often go straight to notification history.

## Autostart

`~/.config/autostart/`: KeePassXC, Easy Effects, OneDrive tray. Everything else that runs at login is a systemd user unit, see [`config/.../systemd/user/`](../config/home/bazzite/.config/systemd/user/).

## Start-menu favourites

Kickoff favourites are stored in KDE's activity database, not in a config file. Right-click → *Add to Favorites* is the easy way. From a script:

```bash
qdbus-qt6 org.kde.ActivityManager /ActivityManager/Resources/Linking \
  org.kde.ActivityManager.ResourcesLinking.LinkResourceToActivity \
  org.kde.plasma.favorites.applications applications:<desktop-file-name>.desktop :global
```

Favourites can be dragged to reorder, but Kickoff has no free-form placement. For that, use desktop icons (right-click the desktop → *Icons* → *Arrange*).

## Wrong icon in Alt+Tab or the task bar

The most common annoyance on KDE Wayland. Symptoms: a generic icon, the wrong icon, a task-bar entry labelled "python" or "electron", or for Brave `--app` windows an amber circle with a letter (that's Chromium's own fallback, meaning no match at all).

The cause is that different parts of the desktop look up a window's icon differently:

| Surface | Matches by |
|---|---|
| Task bar, start menu | `StartupWMClass` in the launcher first, then the desktop file name |
| Alt+Tab, window titlebar (KWin) | `~/.local/share/applications/<app_id>.desktop`, **exactly that name** |

So fixing everything takes **two files**:

1. The real launcher with `StartupWMClass=<app_id>` (task bar).
2. A stub `<app_id>.desktop` with `NoDisplay=true` and `Icon=<name>`, and **without** `StartupWMClass` (Alt+Tab). Two files claiming the same class break task-bar grouping.

**Never guess the `app_id`.** `--class` is ignored by Electron and by Chromium on Wayland. Dump it instead:

```bash
gdbus call --session --dest org.kde.KWin --object-path /KWin \
  --method org.kde.KWin.queryWindowInfo --timeout 240   # then click the window
# resourceClass = app_id
```

Rules of thumb: Electron apps use their lowercase internal name (`vesktop`), and a Brave `--app=http://127.0.0.1:8080` window is `brave-127.0.0.1__-Default` (the port is not part of it). XWayland windows (Proton games, Java apps such as PDFsam) carry their own icon and don't need the stub. Check with `xprop -root _NET_CLIENT_LIST`.

`Icon=` must be a **theme name**, not a path. Alt+Tab silently ignores paths. Put icons in `~/.local/share/icons/hicolor/scalable/apps/<name>.svg` plus 256/512 px PNGs, or they look **pixelated** in Alt+Tab, which draws large:

```bash
magick -background none -density 384 NAME.svg -resize 512x512 \
  ~/.local/share/icons/hicolor/512x512/apps/NAME.png
```

> **Never create `~/.local/share/icons/hicolor/index.theme`.** It *replaces* the system's hicolor definition instead of merging with it. Tried on 2026-08-29: every icon outside the declared folders fell back to generic, including the start button. The system index already declares every size.

After any change:

```bash
gtk-update-icon-cache -f --ignore-theme-index ~/.local/share/icons/hicolor
kbuildsycoca6 --noincremental
systemctl --user restart plasma-plasmashell.service
# then close and reopen the window: KWin picks the icon when the window is created
```

Applied to: Vesktop (`vesktop`), Proton VPN (`proton.vpn.app.gtk`), the qBittorrent WebUI window (`brave-127.0.0.1__-Default`). See [Apps](04-apps.md).
