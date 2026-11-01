# Apps

## Where software comes from

In order of preference:

1. **Flatpak** (Flathub). GUI apps. Updated automatically.
2. **Homebrew**. CLI tools and services on the host. Updated automatically.
3. **`vscode` distrobox** (`dnf`). Dev tools, see [Dev environment](02-dev-environment.md).
4. **Tarball in `~/.local/opt`** with its own updater, when nothing above has it. See [Updates](03-updates.md#apps-outside-every-package-manager).
5. **`rpm-ostree install`** (layering). Only for things that must be in the base OS, because it costs a reboot.

## Inventory (2026-11-01)

### Flatpak, system

| App | ID | Notes |
|---|---|---|
| Brave | `com.brave.Browser` | main browser, KeePassXC bridge below |
| Firefox | `org.mozilla.firefox` | |
| KeePassXC | `org.keepassxc.KeePassXC` | autostarts |
| Proton VPN | `com.protonvpn.www` | icon fix below |
| Vesktop | `dev.vencord.Vesktop` | Discord client, rebranded below |
| Signal | `org.signal.Signal` | |
| Telegram | `org.telegram.desktop` | |
| Spotify | `com.spotify.Client` | |
| VLC | `org.videolan.VLC` | |
| Haruna | `org.kde.haruna` | video player |
| Gwenview | `org.kde.gwenview` | images |
| Okular | `org.kde.okular` | PDF viewer |
| KCalc | `org.kde.kcalc` | |
| Easy Effects | `com.github.wwmm.easyeffects` | autostarts, see [Audio](07-audio.md) |
| Volume Control | `org.pulseaudio.pavucontrol` | |
| Prism Launcher | `org.prismlauncher.PrismLauncher` | Minecraft |
| ProtonPlus | `com.vysp3r.ProtonPlus` | Proton/GE-Proton versions |
| Protontricks | `com.github.Matoking.protontricks` | |
| SABnzbd | `org.sabnzbd.sabnzbd` | Usenet |
| Kontainer | `io.github.DenysMb.Kontainer` | distrobox GUI |
| Warehouse | `io.github.flattool.Warehouse` | Flatpak manager |
| Flatseal | `com.github.tchx84.Flatseal` | Flatpak permissions |
| Firmware | `org.gnome.Firmware` | fwupd GUI |
| Disk Usage Analyzer | `org.gnome.baobab` | |

### Flatpak, user

| App | ID | Notes |
|---|---|---|
| Bambu Studio | `com.bambulab.BambuStudio` | 3D printer slicer |
| FreeCAD | `org.freecad.FreeCAD` | parametric 3D CAD, replaces Fusion, see below |
| PDF Arranger | `com.github.jeromerobert.pdfarranger` | merge/reorder PDFs, imports JPG/PNG directly |
| QDirStat | `io.github.shundhammer.qdirstat` | disk usage. *View → Mounted Filesystems* shows free space |

Install user Flatpaks with `flatpak install --user flathub <id>`.

### Shipped with Bazzite

Steam, Lutris, the Bazzite Portal, Bazzite Updater, Konsole, Dolphin and the rest of KDE. Steam and Lutris games get their own `.desktop` entries in `~/.local/share/applications`.

### Layered (rpm-ostree)

`uhubctl`, `ghostty`. See [System](01-system.md#layered-packages).

### Homebrew

| Formula | Why |
|---|---|
| `onedrive-cli` | OneDrive sync, runs as a service, see [Storage](08-storage-sync.md) |
| `bbrew` | TUI for Homebrew |

Everything else in `brew list` is a dependency of these.

### Manual installs

| App | Where |
|---|---|
| PDFsam Basic | `~/.local/opt/pdfsam`, see below |
| headsetcontrol | `~/.local/bin/headsetcontrol`, see [USB peripherals](06-usb-peripherals.md) |

---

## PDFsam Basic

Not on Flathub, and the Homebrew cask is macOS only. Installed from the signed GitHub release, which bundles its own Java runtime:

```bash
# verify: signed by Sober Lemur S.r.l. (the company behind PDFsam)
# key 640D1DF51837142D026B0A191C144474400E1619 (on keyserver.ubuntu.com,
# not keys.openpgp.org)
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 640D1DF51837142D026B0A191C144474400E1619
gpg --verify pdfsam-basic-6.0.9-linux-x64.tar.gz.asc pdfsam-basic-6.0.9-linux-x64.tar.gz

mkdir -p ~/.local/opt
tar xzf pdfsam-basic-6.0.9-linux-x64.tar.gz -C ~/.local/opt
ln -sfn pdfsam-basic-6.0.9-linux-x64 ~/.local/opt/pdfsam

# pin the key for the auto-updater
mkdir -p ~/.local/share/pdfsam
gpg --export 640D1DF51837142D026B0A191C144474400E1619 > ~/.local/share/pdfsam/signing-key.gpg
```

- **Icons**: the tarball has no loose icons. They sit inside `lib/pdfsam-basic-<ver>.jar` under `images/basic/` (16 to 512 px) and are extracted to `~/.local/share/icons/hicolor/<size>/apps/pdfsam-basic.png`.
- **Launcher**: [`pdfsam-basic.desktop`](../config/home/bazzite/.local/share/applications/pdfsam-basic.desktop). The window runs under XWayland with WM_CLASS `org.pdfsam.gui.PdfsamApp`, which is set as `StartupWMClass`.
- **Updates**: `~/.local/bin/pdfsam-update`, run by the Bazzite Updater, see [Updates](03-updates.md).

PDFsam can't make a PDF from images. For photos → PDF use PDF Arranger, or `magick a.jpg b.jpg out.pdf`.

## Brave: Teams as an app

Teams has no Linux app any more, not even on Flathub. Install it as a PWA from Brave (install button at the right of the address bar), then open `brave://apps/`, right-click Teams → *Create shortcuts* → *Applications menu*.

## Brave ↔ KeePassXC browser integration

Both are Flatpaks, which KeePassXC officially doesn't support. It works through a hand-made bridge:

1. Let Brave see KeePassXC's socket. **The `:create` suffix is required**:
   ```bash
   flatpak override --user --filesystem=xdg-run/app/org.keepassxc.KeePassXC:create com.brave.Browser
   ```
   Without it, starting Brave *before* KeePassXC gives Brave no mount at all for that whole session. Flatpak silently skips binding a directory that doesn't exist yet.
2. `keepassxc-proxy` can't run inside Brave's sandbox (it needs KDE's Qt5 runtime), so a small Python stdio↔socket relay replaces it: `~/.var/app/com.brave.Browser/data/keepassxc-relay.py`. It keeps retrying the connection for 10 minutes, so KeePassXC may start after Brave.
3. The native-messaging manifest goes into **Brave's sandboxed config**, not `~/.config`: `~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json`, with `path` pointing to the relay under `~/.var/app/...`.

**Don't** press *Reset* or re-run KeePassXC's browser-integration setup. It rewrites the manifest to the wrong place and breaks this. After changing an override, quit Brave completely.

Debug: if the socket exists on the host but not in `/proc/$(pgrep -f com.brave.Browser | head -1)/root/run/user/1000/app/org.keepassxc.KeePassXC/`, it's the mount, not the extension.

## Vesktop as "Discord"

The Vesktop Flatpak is renamed so searching "Discord" finds it, and it gets the Discord logo:

- `~/.local/share/applications/dev.vencord.Vesktop.desktop`: override of the Flatpak's launcher with `Name=Discord / Vesktop`, `StartupWMClass=vesktop`.
- `~/.local/share/applications/vesktop.desktop`: a `NoDisplay` stub so Alt+Tab finds the icon, see [Desktop](05-desktop-kde.md#wrong-icon-in-alttab-or-the-task-bar).
- `~/.local/share/icons/hicolor/scalable/apps/dev.vencord.Vesktop.svg`: the Discord mark, squared up. It takes priority over the Flatpak's icon.

Flatpak updates don't touch any of this.

## Proton VPN: "python" in the task bar

The Flatpak's launcher declares `StartupWMClass=protonvpn-app`, but the window's real app id is `proton.vpn.app.gtk`, so the task bar labelled it "python" with a generic icon. Fixed with an overriding `com.protonvpn.www.desktop` (`StartupWMClass=proton.vpn.app.gtk`) and a `proton.vpn.app.gtk.desktop` stub. Both are in [`config/.../applications/`](../config/home/bazzite/.local/share/applications/).

## CAD: FreeCAD

FOSS (LGPL) parametric CAD, native on Linux, from Flathub. Since 1.0 it fixes the old topological-naming breakage and has a built-in Assembly workbench.

```bash
flatpak install --user flathub org.freecad.FreeCAD
```

- Workflow like Fusion: **Part Design** workbench (sketch → pad/pocket/fillet).
- Prints: export STL/3MF, slice in Bambu Studio.
- Old Fusion designs (`.f3d`) can't be opened. Export them as STEP from the Fusion web app (fusion.online.autodesk.com) and import that. One cached design is saved in `~/Documents/Fusion360-export/`.

## Removed: Autodesk Fusion (via Proton)

Removed on 2026-11-01: too buggy to use under Proton. Kept here in case it's ever retried.

Free personal licence, installed with the cryinkfly community installer, which moved from GitHub to **Codeberg** in Feb 2026. It ran on **GE-Proton11-5**, not Wine, and used ~11 GB in `~/.autodesk_fusion`.

```bash
./autodesk_fusion_installer_x86-64.sh --proton=GE-Proton11-5-x86_64 --default
```

Three Bazzite-specific fixes, **all needed again on a reinstall**:

1. **Installer quits on unknown distro.** Remove `"wbinfo"` from `REQUIRED_COMMANDS` in the script (Wine auth, irrelevant under Proton). Don't fake Fedora instead, or it runs `sudo dnf` against the host.
2. **Launcher fails with `AUTODESK_ROOT_DIRECTORY does not match`.** `/home` is a symlink to `/var/home`. Rewrite line 2 of `~/.autodesk_fusion/logs/wineprefixes.log` to the `/var/home/...` form, and leave line 3 alone. Re-running the installer undoes this.
3. **Missing start-menu icon.** The generated entry references an icon that was never created. The real one is `resources/Fusion.ico` in `webdeploy/production/<hash>/` (entry 0 of six 256 px PNGs), installed as `~/.local/share/icons/hicolor/256x256/apps/autodesk-fusion.png`.

It runs on XWayland, so Alt+Tab picks up the icon from the window by itself.

## Games

See [games/](../games/README.md): every installed game, which Proton it runs on, and per-game tweaks.
