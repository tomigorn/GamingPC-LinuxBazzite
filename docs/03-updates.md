# Updates

Everything is updated with one click in **Bazzite Updater**, from the start menu.

## What gets updated where

| Source | Updated by |
|---|---|
| Bazzite OS image (+ layered packages) | `uupd`, step *System*. Applied on next reboot |
| Flatpaks, system and user | `uupd`, steps *Flatpak* and *User Flatpak* |
| Homebrew (`onedrive-cli`, `bbrew`) | `uupd`, step *Brew* |
| Distrobox containers (`vscode`) | `uupd`, step *Distrobox* (`dnf upgrade` inside) |
| PDFsam Basic, HeadsetControl (tarball/source installs) | `pdfsam-update`, `headsetcontrol-update` via [`update-extras`](../config/home/bazzite/.local/bin/update-extras), see below |
| Podman images of the quadlets (qBittorrent, gluetun) | `update-extras`: `podman pull` + prune dangling. `podman auto-update` would only touch *running* containers, and this stack runs on demand |
| Firmware | **not** updated, only reported. Run `fwupdmgr update` yourself |

Two paths run all of it:

| Path | When | Runs |
|---|---|---|
| Automatic | `uupd.timer` daily 04:00 (catches up after boot), then `update-extras.timer` 04:30 (same) | uupd, then [`update-extras.service`](../config/home/bazzite/.config/systemd/user/update-extras.service): `update-extras` + `security-scan`, at idle CPU/IO priority |
| Manual | Bazzite Updater button | `update-summary`: uupd, `update-extras`, `security-scan`, one summary |

## The update summary

Out of the box the updater's console prints uupd's raw JSON log. It now runs a wrapper instead, which prints what actually changed:

`/etc/bazzite-updater/config.ini`:

```ini
[Commands]
systemUpdateCommand=/home/bazzite/.local/bin/update-summary
systemRollbackCommand=bazzite-rollback-helper rollback -y
```

[`update-summary`](../config/home/bazzite/.local/bin/update-summary) does this:

1. Snapshots versions before the update (brew, flatpak, image, every distrobox, and the tarball apps).
2. Starts `uupd-manual.service` and follows its journal. With no terminal attached (that is, inside the GUI), it passes uupd's JSON through unchanged, so the updater's progress bars still work.
3. Runs `update-extras` (tarball apps, container images).
4. Diffs the snapshots and prints the summary: per category (incl. *Containers*) either *nothing needed updating* or `name old → new`, plus whether a reboot is needed, firmware updates, and the security scan result.

It also runs in a normal terminal (`update-summary`), where it shows a live progress view instead.

A drop-in keeps uupd's own output parseable and skips the hardware check:

```ini
# /etc/systemd/system/uupd-manual.service.d/quiet.conf
[Service]
ExecStart=
ExecStart=/usr/bin/uupd --hw-check=false --json --log-level=info
```

## Apps outside every package manager

Some software has no Flatpak, no Fedora RPM and no Linux Homebrew cask. Those go into `~/.local/opt/<name>-<version>`, with a symlink `~/.local/opt/<name>` pointing at the current version, and get a `~/.local/bin/<name>-update` script that `update-summary` calls. The summary lists them under **Apps**.

Rules for such an updater (see [`pdfsam-update`](../config/home/bazzite/.local/bin/pdfsam-update)):

- Ask the project's GitHub `releases/latest`, and never downgrade.
- **Verify the release signature against a pinned key**, kept in `~/.local/share/<name>/signing-key.gpg`, with `gpgv --keyring`. Anything else is refused.
- Unpack next to the live install and only then swap the symlink, so an update that fails halfway leaves the old version working.
- Keep the previous version for rollback and delete older ones.
- Print nothing when up to date, `name old → new` on update, and to stderr plus a non-zero exit on failure (the summary then shows it under the failure list).

Currently: **PDFsam Basic**, see [Apps](04-apps.md#pdfsam-basic), and **HeadsetControl** ([`headsetcontrol-update`](../config/home/bazzite/.local/bin/headsetcontrol-update)): verifies the release tarball's `.asc` against the pinned key in `~/.local/share/headsetcontrol/signing-key.gpg` (Denis Arnst, primary `77BE B7E2 32CF 1E51 5477 7D4D D586 6C58 9401 97BF`, release subkey `893E 9C96 …C92C F077`, expires 2028-07-22: re-pin by hand then), builds inside the `vscode` box (needs `cmake gcc gcc-c++ hidapi-devel` there), checks the new binary runs on the host, then swaps `~/.local/opt/headsetcontrol`. The first run migrates the old hand-built binary into `~/.local/opt/headsetcontrol-0.0.0-e529bc1` as rollback.

## Security scans

[`security-scan`](../config/home/bazzite/.local/bin/security-scan), run by both update paths (~1 min, idle priority). Tools from Homebrew: `clamav` (no `clamd` daemon, ~1 GB RAM saved; `freshclam.conf` in the brew prefix), `trivy`, `lynis`.

| Scanner | What | Notifies |
|---|---|---|
| ClamAV | files new/changed since the last scan in Downloads, Desktop, Documents, OneDrive (first run: all of Downloads) | any find |
| Trivy | the quadlet images, HIGH + CRITICAL CVEs | CRITICAL |
| Lynis | system audit as user, weekly | never (report only) |

Report: `~/.local/state/security-scan/latest.txt`. Run by hand: `security-scan`. Tests: `tests/test_security_scan.py`.

## btrfs deduplication (bees)

Bazzite runs `beesd` to deduplicate the btrfs filesystem. Unbounded, it can keep the disk and CPU busy for hours after a big install. A drop-in caps every run at 30 minutes at idle I/O priority, and makes it the first thing the OOM killer picks:

```ini
# /etc/systemd/system/beesd@.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/timeout 30m /usr/bin/beesd --no-timestamps %i
Restart=no
SuccessExitStatus=124
OOMScoreAdjust=1000
OOMPolicy=stop
IOSchedulingClass=idle
```
