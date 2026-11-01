# onedrive-tray

A minimal KDE Plasma tray indicator (StatusNotifierItem) for the abraunegg
OneDrive client running as the systemd user service `homebrew.onedrive-cli`.

## Single sync owner

This tray is a **passive observer**. It never starts a sync, never runs
`onedrive` at all, and never opens the client's sqlite database. All state comes
from reading the log file the service already writes, plus `systemctl --user
is-active`. There is no way for it to conflict with the running monitor.

## Files

| Path | Purpose |
|---|---|
| `~/.local/share/onedrive-tray/onedrive-tray.py` | the whole application |
| `~/.config/autostart/onedrive-tray.desktop` | starts it at login |

## Dependencies

None to install. It uses `python3` + `python3-gobject` + `libappindicator-gtk3`
+ `libnotify`, all already present in the Bazzite base image. There is no venv
and no `requirements.txt` because there are no pip packages — a venv was
evaluated (PySide6) and rejected at 246 MB versus 0 MB for this route.

## Run / stop manually

```bash
python3 ~/.local/share/onedrive-tray/onedrive-tray.py &   # start
pkill -f onedrive-tray.py                                 # stop
```

## Data source

`/home/linuxbrew/.linuxbrew/var/log/onedrive.log` — the service unit sets
`StandardOutput=append:` to it, so it already contains everything the client
prints, including per-file transfer percentages. No client config change was
needed. Note that `journalctl --user -u homebrew.onedrive-cli` shows only
systemd lifecycle lines, *not* sync detail, because of that redirect.

## Pause/Resume uses systemctl, not `brew services`

`brew services stop` runs `systemctl --user disable`, which deletes the
`default.target.wants` symlink and would silently turn OFF auto-start at login.
The tray uses `systemctl --user stop/start`, which leaves enablement untouched.
Verified: enablement survives a pause/resume cycle.

## Boot-time network race

The service starts at login before DNS is necessarily up, so the client logs
`Could not resolve hostname` a couple of times and then reconnects by itself
(observed: recovered ~35s after boot, unaided). This is expected and needs no
service change.

The tray therefore treats connectivity failures as **offline** (a quiet,
transient state, never notified) rather than **error**, and clears them on
`Successfully reached the Microsoft OneDrive Service` — the client prints that
on every successful contact. Earlier versions cleared errors only on
`Sync ... is complete`, which could leave a stale red icon long after the
problem resolved. `parsertest.py` replays the real captured boot sequence to
guard against a regression.

## Notifications auto-dismiss

Notifications use NORMAL urgency with an explicit timeout (`NOTIFY_MS`), so KDE
auto-hides them. They must **never** use `Urgency.CRITICAL`: Plasma treats
critical notifications as resident — they stay on screen until clicked and never
time out, which caused popups to pile up. Errors also dedupe within an episode
(`err_notified`, cleared on return to synced) and warnings dedupe for the whole
run (`notified`), so a message that reprints every sync cycle notifies only
once. `parsertest.py` covers both.

## Known behaviour

The client prints `Sync ... is complete` only at the end of a scheduled monitor
cycle (`monitor_interval`, currently 300s). Transfers triggered by inotify
between cycles get no completion line, so the tray treats 20s of log silence as
"settled" and returns the icon to *up to date*. Such timestamps are shown with a
`≈` prefix to mark them as inferred rather than read from a completion line.
