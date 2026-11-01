# Updates

Everything is updated with one click in **Bazzite Updater**, from the start menu.

## What gets updated where

| Source | Updated by |
|---|---|
| Bazzite OS image (+ layered packages) | `uupd`, step *System*. Applied on next reboot |
| Flatpaks, system and user | `uupd`, steps *Flatpak* and *User Flatpak* |
| Homebrew (`onedrive-cli`, `bbrew`) | `uupd`, step *Brew* |
| Distrobox containers (`vscode`) | `uupd`, step *Distrobox* (`dnf upgrade` inside) |
| PDFsam Basic (tarball install) | `~/.local/bin/pdfsam-update`, step *Apps*, see below |
| Firmware | **not** updated, only reported. Run `fwupdmgr update` yourself |

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
3. Runs the extra updaters that uupd doesn't know about (`pdfsam-update`).
4. Diffs the snapshots and prints the summary: per category either *nothing needed updating* or `name old → new`, plus whether a reboot is needed and whether firmware updates are available.

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

Currently: **PDFsam Basic**, see [Apps](04-apps.md#pdfsam-basic).

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

(`bees-timeout.conf` in the same directory has identical content. One of the two can go.)
