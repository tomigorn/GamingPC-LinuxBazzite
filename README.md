# GamingPC-LinuxBazzite

How my gaming PC (`bazzite-prime`) is set up: Bazzite with KDE Plasma on Wayland, AMD GPU, dual boot with Windows. Written so I can rebuild it, and so I remember *why* things are the way they are.

| | |
|---|---|
| [System basics](docs/01-system.md) | hostname, GRUB/Windows first, what survives updates, layered packages, keyboard Fn keys |
| [Dev environment](docs/02-dev-environment.md) | VS Code in the `vscode` distrobox, git + GitHub SSH key + commit signing, Claude Code |
| [Updates](docs/03-updates.md) | Bazzite Updater with update summary, apps outside package managers, bees limits |
| [Apps](docs/04-apps.md) | full inventory, PDFsam, Brave Teams PWA, Brave↔KeePassXC, Vesktop/Proton VPN fixes, Fusion 360, games |
| [Desktop (KDE)](docs/05-desktop-kde.md) | tray widgets, favourites, fixing wrong/pixelated icons in Alt+Tab |
| [USB peripherals](docs/06-usb-peripherals.md) | SteelSeries base station off at shutdown, BRIO camera fix, battery widget |
| [Audio](docs/07-audio.md) | "Sonar" sinks with 7.1 HRTF, Discord streaming without losing dialogue |
| [Storage and sync](docs/08-storage-sync.md) | NTFS data partition, SMB share from fastpi, OneDrive |
| [qBittorrent behind VPN](docs/09-qbittorrent-vpn.md) | podman quadlets, how "no VPN, no torrenting" is enforced |

## Repo layout

- `docs/`: the write-ups above.
- `config/`: copies of the actual files, at their paths on the machine (`config/etc/...` = `/etc/...`, `config/usr/local/...` = `/usr/local/...`, `config/home/bazzite/...` = `~/...`). `config/camera-usb-cycle/` is a self-contained installer.
- `archive/`: superseded files (old `fnkeys.service` and the first SteelSeries shutdown service), kept for reference.

**No secrets in here.** The VPN key (`~/.config/qbit-vpn/proton.env`), SMB credentials (`/etc/smb-mouse.cred`), OneDrive tokens and SSH private keys stay on the machine. The docs say where they go and what they contain.

## Core ideas

- **The host stays clean.** GUI apps are Flatpaks, CLI tools come from Homebrew, dev tools live in the `vscode` distrobox. Only 2 layered packages.
- **`/etc` and `/var` persist** on Bazzite, so plain config files there are the right tool. No re-apply-at-boot hacks.
- **One click updates everything**, including the things no package manager knows about.
