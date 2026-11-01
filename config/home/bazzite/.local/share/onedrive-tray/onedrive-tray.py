#!/usr/bin/env python3
"""
onedrive-tray — a minimal KDE Plasma StatusNotifierItem for the abraunegg
OneDrive client (v2.5.11) running as the systemd user service
`homebrew.onedrive-cli`.

DESIGN: PASSIVE OBSERVER ONLY.
This program NEVER starts a sync of its own. The systemd service is the single
sync owner. All status comes from reading the log file the service already
writes (its unit does StandardOutput=append:<LOG_PATH>), plus querying systemd
for the unit's state. Nothing here opens the client's sqlite database, so there
is no possibility of a DB-lock conflict with the running monitor.

Dependencies: python3 + python3-gobject + libappindicator-gtk3 + libnotify,
all of which ship in the Bazzite base image. There are no pip dependencies and
no venv, which is why this is a single file with nothing alongside it.
"""

import os
import re
import subprocess
import time
from datetime import datetime

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")
gi.require_version("Notify", "0.7")
from gi.repository import AppIndicator3, GLib, Gtk, Notify  # noqa: E402

# --- Configuration ----------------------------------------------------------

LOG_PATH = "/home/linuxbrew/.linuxbrew/var/log/onedrive.log"
SYNC_DIR = os.path.expanduser("~/OneDrive")
UNIT = "homebrew.onedrive-cli.service"

LOG_POLL_MS = 1000       # how often to read new log bytes
UNIT_POLL_S = 5          # how often to ask systemd if the service is alive
PRIME_BYTES = 65536      # tail of the log read at startup to establish state
IDLE_AFTER_S = 90        # transfer considered stale if no line for this long
SETTLE_S = 20            # quiet period after which "syncing" becomes "up to date"
NOTIFY_MS = 10000        # notifications auto-dismiss after this many ms.
NOTIFY_MS_LONG = 20000   # errors linger a little longer, but still auto-expire.

# Breeze ships purpose-built tray status icons; all verified present on host.
ICONS = {
    "synced":  "state-ok",
    "syncing": "state-sync",
    "error":   "state-error",
    "paused":  "state-pause",
    "offline": "state-offline",
}

# --- Log line patterns ------------------------------------------------------
# Every pattern below was confirmed against actual v2.5.11 output on this
# machine, EXCEPT the "Downloading" variants: the client shares one progress
# routine for both directions, so the patterns accept either verb. Uploads were
# observed directly; downloads are matched by that shared shape.

# "Uploading: file.bin ... 42%  |  ETA    00:00:07"
# "Uploading: file.bin ... 100% | DONE in 00:00:11"
RE_PROGRESS = re.compile(
    r"^(Uploading|Downloading):\s+(.+?)\s+\.\.\.\s+(\d+)%\s*\|\s*"
    r"(?:ETA\s+(\S+)|DONE in\s+(\S+))"
)
# "Uploading new file: file.bin ... done"  /  "... modified file: ... done"
RE_DONE = re.compile(
    r"^(Uploading|Downloading)\s+(?:new\s+|modified\s+)?(?:file|item):\s+"
    r"(.+?)\s+\.\.\.\s+done"
)
# "New items to upload to Microsoft OneDrive: 3"
RE_PENDING = re.compile(r"^New items to upload to Microsoft OneDrive:\s+(\d+)")
# "Deleting item from Microsoft OneDrive: name"
RE_DELETING = re.compile(r"^Deleting item from Microsoft OneDrive:\s+(.+)")
# "  Error Message:     <text>"  (inside a multi-line ERROR: block)
RE_ERRMSG = re.compile(r"^\s+Error Message:\s+(.+)")

SYNC_START = ("Starting a sync with Microsoft OneDrive",
              "Syncing changes from Microsoft OneDrive")
SYNC_DONE = "Sync with Microsoft OneDrive is complete"

# The definitive "we are back online" signal. The client prints this on every
# successful contact, so it is the reliable way to clear a stale error state --
# waiting for the next "Sync ... is complete" can take a full monitor interval,
# or never arrive at all if nothing needed syncing.
RECOVERED = "Successfully reached the Microsoft OneDrive Service"

# Transient connectivity problems, which are NOT faults needing attention.
# These are routine at boot, when the service starts before DNS is up:
#   "Cannot connect to the Microsoft OneDrive Service - Network Connection
#    Issue: Could not resolve hostname on handle 565154BE98A0"
# They are shown as "offline" (and never notified) rather than as errors,
# because the client retries and recovers on its own.
NET_HINTS = ("Could not resolve hostname", "Network Connection Issue",
             "Cannot connect to the Microsoft OneDrive Service",
             "Unable to reach", "Failed to reach", "no network connection",
             "Timeout was reached", "Connection refused")


class OneDriveTray:
    def __init__(self):
        # --- observed state ---
        self.state = "synced"        # synced|syncing|error|paused|offline
        self.activity = "Starting up"
        self.xfer = None             # dict(dir, name, pct, eta) or None
        self.xfer_seen = 0.0         # monotonic time of last progress line
        self.pending = 0
        self.last_sync = None        # datetime of last "sync complete"
        self.last_sync_approx = False
        self.last_error = None
        self.did_work = False        # were there transfers this sync cycle?
        self.priming = True          # suppress notifications while catching up
        self.last_line_ts = 0.0      # monotonic time of last meaningful log line
        self.warning = None          # standing non-fatal warning, if any
        self.notified = set()        # warning texts already notified this run
        self.err_notified = set()    # error texts notified in the current episode
        self.err_await = None        # preamble of an ERROR block awaiting detail

        # --- log file position tracking ---
        self.fh = None
        self.inode = None
        self.buf = ""

        Notify.init("OneDrive")
        self.ind = AppIndicator3.Indicator.new(
            "onedrive-tray", ICONS["synced"],
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS)
        self.ind.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        self._build_menu()

        self._open_log(prime=True)
        self._poll_unit()
        self._refresh_ui()
        self.priming = False

        GLib.timeout_add(LOG_POLL_MS, self._poll_log)
        GLib.timeout_add_seconds(UNIT_POLL_S, self._poll_unit)

    # --- menu ---------------------------------------------------------------

    def _build_menu(self):
        self.menu = Gtk.Menu()

        # Header lines double as the status readout, since Plasma does not show
        # a hover tooltip for every SNI implementation. set_title() is also set
        # below so the tooltip works where it is supported.
        self.hdr_state = Gtk.MenuItem(label="…")
        self.hdr_state.set_sensitive(False)
        self.hdr_detail = Gtk.MenuItem(label="…")
        self.hdr_detail.set_sensitive(False)
        for w in (self.hdr_state, self.hdr_detail):
            self.menu.append(w)
        self.menu.append(Gtk.SeparatorMenuItem())

        def add(label, cb):
            mi = Gtk.MenuItem(label=label)
            mi.connect("activate", cb)
            self.menu.append(mi)
            return mi

        add("Open ~/OneDrive", lambda _w: self._spawn(["xdg-open", SYNC_DIR]))
        self.mi_toggle = add("Pause sync", self._on_toggle)
        add("Restart sync", self._on_restart)
        add("Show log", lambda _w: self._spawn(["xdg-open", LOG_PATH]))
        self.menu.append(Gtk.SeparatorMenuItem())
        add("Quit", lambda _w: Gtk.main_quit())

        self.menu.show_all()
        self.ind.set_menu(self.menu)

    def _spawn(self, argv):
        try:
            subprocess.Popen(argv, start_new_session=True,
                             stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        except OSError as e:
            self._notify("OneDrive tray", f"Could not run {argv[0]}: {e}")

    # --- service control ----------------------------------------------------
    # NOTE: pause/resume deliberately uses systemctl rather than
    # `brew services stop`. `brew services stop` runs `systemctl --user disable`,
    # which deletes the default.target.wants symlink and would silently turn OFF
    # auto-start at login. systemctl start/stop leaves enablement untouched.

    def _systemctl(self, *args):
        try:
            return subprocess.run(["systemctl", "--user", *args],
                                  capture_output=True, text=True,
                                  timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""

    def _on_toggle(self, _w):
        if self.state == "paused":
            self._systemctl("start", UNIT)
            self._notify("OneDrive", "Sync resumed")
        else:
            self._systemctl("stop", UNIT)
            self._notify("OneDrive", "Sync paused")
        GLib.timeout_add_seconds(1, self._poll_unit)

    def _on_restart(self, _w):
        self._systemctl("restart", UNIT)
        self._notify("OneDrive", "Sync service restarted")
        GLib.timeout_add_seconds(2, self._poll_unit)

    def _poll_unit(self):
        active = self._systemctl("is-active", UNIT) == "active"
        if not active:
            # Service down: that is a paused/stopped condition, not an error.
            # Clear any in-flight transfer so the UI cannot show a stale file.
            self.state = "paused"
            self.xfer = None
            self.activity = "Sync service is stopped"
            self._refresh_ui()
        elif self.state == "paused":
            # Came back up; log tailing will refine this shortly.
            self.state = "syncing"
            self.activity = "Service started"
            self._refresh_ui()
        return True

    # --- log tailing --------------------------------------------------------

    def _open_log(self, prime=False):
        """Open the log, seeking to the end (or to a small tail when priming)."""
        try:
            fh = open(LOG_PATH, "r", errors="replace")
        except OSError:
            self.fh = None
            return
        st = os.fstat(fh.fileno())
        self.inode = st.st_ino
        if prime:
            fh.seek(max(0, st.st_size - PRIME_BYTES))
            fh.readline()  # discard the partial first line
            for line in fh:
                self._consume(line.rstrip("\n"))
            # The log has no per-line timestamps, so if the priming tail ended
            # in a completed sync, approximate its time from the file mtime.
            if self.state == "synced" and self.last_sync is None:
                self.last_sync = datetime.fromtimestamp(st.st_mtime)
                self.last_sync_approx = True
        else:
            fh.seek(st.st_size)
        self.fh = fh

    def _poll_log(self):
        try:
            if self.fh is None:
                self._open_log()
                return True
            st_disk = os.stat(LOG_PATH)
            pos = self.fh.tell()
            # Rotated (new inode) or truncated (shrunk): reopen from the start.
            if st_disk.st_ino != self.inode or st_disk.st_size < pos:
                self.fh.close()
                self.fh = open(LOG_PATH, "r", errors="replace")
                self.inode = os.fstat(self.fh.fileno()).st_ino
            chunk = self.fh.read()
        except OSError:
            self.fh = None
            return True

        if chunk:
            self.buf += chunk
            *lines, self.buf = self.buf.split("\n")
            for line in lines:
                self._consume(line)
            self._refresh_ui()
            return True

        quiet = time.monotonic() - self.last_line_ts
        if self.xfer and time.monotonic() - self.xfer_seen > IDLE_AFTER_S:
            # Guard against a transfer line that never got a completion line.
            self.xfer = None
            self._refresh_ui()
        elif self.state == "syncing" and not self.xfer and quiet > SETTLE_S:
            # The client only prints "Sync ... is complete" at the end of a
            # scheduled monitor cycle. A transfer triggered by inotify between
            # cycles gets no such line, so without this the icon would stay
            # "syncing" for up to monitor_interval (300s) after the work is
            # actually done. Treat a quiet period as settled instead.
            # Deliberately ignores self.pending: the client announces items to
            # upload but prints no counter-line if one is then removed or
            # skipped, so a stale count must never wedge the icon on "syncing".
            self.state = "synced"
            self.pending = 0
            self.last_sync = datetime.now()
            self.last_sync_approx = True
            self.activity = "Idle"
            self.err_notified.clear()   # a clean settle ends the error episode
            if self.did_work:
                self._notify("OneDrive", "Sync complete")
                self.did_work = False
            self._refresh_ui()
        return True

    def _consume(self, line):
        """Fold one log line into the observed state."""
        if not line.strip():
            return
        self.last_line_ts = time.monotonic()

        # An ERROR: block spans several lines; the useful text is on an indented
        # "Error Message:" line further down. We defer the notification until we
        # see it. A non-indented line means the block ended — if no detail ever
        # arrived, notify with the preamble alone so the error is never silent.
        if self.err_await is not None and not line.startswith((" ", "\t")):
            self._flush_error()

        if m := RE_PROGRESS.match(line):
            direction, name, pct, eta, done_in = m.groups()
            self.xfer = {"dir": direction, "name": name, "pct": int(pct),
                         "eta": eta or done_in or ""}
            self.xfer_seen = time.monotonic()
            self.state = "syncing"
            self.did_work = True
            self.activity = f"{direction} {name}"
            return

        if m := RE_DONE.match(line):
            direction, name = m.group(1), m.group(2)
            self.xfer = None
            self.did_work = True
            self.state = "syncing"
            # This item has left the queue. Without decrementing, the queued
            # count would outlive the transfer and mask later activity.
            self.pending = max(0, self.pending - 1)
            verb = "Uploaded" if direction == "Uploading" else "Downloaded"
            self.activity = f"{verb} {name}"
            return

        if m := RE_PENDING.match(line):
            self.pending = int(m.group(1))
            self.state = "syncing"
            return

        if m := RE_DELETING.match(line):
            self.did_work = True
            self.state = "syncing"
            self.pending = 0          # a delete supersedes any stale queue count
            self.activity = f"Deleting {m.group(1)}"
            return

        if line.startswith(RECOVERED):
            # Contact restored: drop any offline/error state immediately.
            if self.state in ("offline", "error"):
                self.state = "syncing"
                self.last_error = None
                self.activity = "Reconnected"
            return

        # Checked before the generic ERROR: handler, because network failures
        # are reported BOTH as a plain "Cannot connect ..." line and as an
        # "ERROR: ... API returned an error" block. Without this ordering a
        # transient boot-time DNS blip would show as a hard error.
        #
        # This ALSO catches the indented "  Error Message:  Could not resolve
        # hostname ..." line (it contains a NET hint), which is why err_await
        # must be cleared here too: otherwise the pending ERROR: preamble would
        # survive and get flushed as a bogus detail-less error popup when the
        # next non-indented line ends the block. That was the boot-time bug.
        if any(h in line for h in NET_HINTS):
            self.state = "offline"
            self.last_error = None
            self.activity = "Waiting for network"
            self.err_await = None
            return

        if line.startswith("WARNING:"):
            # Warnings are non-fatal: the client keeps syncing. So do NOT turn
            # the icon red, and do NOT renotify. The "recommended limit" (online
            # object-count) warning in particular reprints on every sync cycle
            # for large drives, and treating each occurrence as a fresh critical
            # error was pure noise. Notify at most once per unique text per run.
            msg = line.split(":", 1)[1].strip()
            self.warning = msg
            if not self.priming and msg not in self.notified:
                self.notified.add(msg)
                self._notify("OneDrive notice", msg[:160], urgent=False)
            return

        if line.startswith("ERROR:"):
            self.state = "error"
            preamble = line.split(":", 1)[1].strip()
            self.last_error = preamble[:120]
            self.activity = "Error — see log"
            # Defer notifying: the specific cause is on a later "Error Message:"
            # line. _flush_error emits it once we have that detail (or when the
            # block ends without one).
            self.err_await = preamble
            return

        if m := RE_ERRMSG.match(line):
            # The specific cause of the pending ERROR block. If it is a network
            # problem, downgrade to offline and drop the pending notification
            # (network blips are transient and self-heal). Otherwise emit the
            # deferred error notification, now with the real detail included.
            detail = m.group(1).strip()
            if any(h in detail for h in NET_HINTS):
                self.state = "offline"
                self.last_error = None
                self.activity = "Waiting for network"
                self.err_await = None
                return
            self.last_error = detail[:120]
            if self.err_await is not None:
                preamble = self.err_await
                self.err_await = None
                body = f"{preamble} {detail}" if preamble else detail
                if not self.priming and detail not in self.err_notified:
                    self.err_notified.add(detail)
                    self._notify("OneDrive error", body[:220], urgent=True)
            return

        if line.startswith(SYNC_START):
            if self.state not in ("error", "offline"):
                self.state = "syncing"
                self.activity = "Checking for changes"
            return

        if line.startswith(SYNC_DONE):
            self.state = "synced"
            self.xfer = None
            self.pending = 0
            self.last_sync = datetime.now()
            self.last_sync_approx = False
            self.last_error = None
            self.err_notified.clear()   # a completed sync ends the error episode
            self.activity = "Up to date"
            # Only notify when the cycle actually moved data, otherwise this
            # would fire every monitor interval (300s) forever.
            if self.did_work and not self.priming:
                self._notify("OneDrive", "Sync complete")
            self.did_work = False
            return

        if "termination signal" in line:
            self.state = "paused"
            self.activity = "Shutting down"

    # --- presentation -------------------------------------------------------

    def _summary(self):
        """Two lines: headline state, and the detail/current transfer."""
        if self.state == "paused":
            return "OneDrive: paused", "Service stopped — Resume to sync"
        if self.state == "offline":
            return "OneDrive: offline", self.activity
        if self.state == "error":
            return "OneDrive: error", self.last_error or self.activity
        if self.state == "syncing":
            if self.xfer:
                x = self.xfer
                detail = f"{x['dir']} {x['name']} — {x['pct']}%"
                if x["eta"] and not x["eta"].startswith("--"):
                    detail += f" (ETA {x['eta']})"
                return "OneDrive: syncing", detail
            if self.pending:
                return "OneDrive: syncing", f"{self.pending} item(s) queued"
            return "OneDrive: syncing", self.activity
        # synced. A standing warning is surfaced here (not as an error) so it
        # stays discoverable on hover without an alarming icon.
        head = "OneDrive: up to date"
        if self.warning:
            head = "OneDrive: up to date ⚠"
        if self.last_sync:
            stamp = self.last_sync.strftime("%H:%M:%S")
            prefix = "Last sync ≈" if self.last_sync_approx else "Last sync"
            detail = f"{prefix} {stamp}"
            if self.warning:
                detail += f" — note: {self.warning[:80]}"
            return head, detail
        return head, (self.warning[:100] if self.warning else "No sync observed yet")

    def _refresh_ui(self):
        head, detail = self._summary()
        self.ind.set_icon_full(ICONS.get(self.state, "state-sync"), head)
        # Tooltip where the host supports it; harmless where it does not.
        self.ind.set_title(f"{head} — {detail}")
        self.hdr_state.set_label(head)
        self.hdr_detail.set_label(detail)
        # Show a compact percentage beside the tray icon only while moving data.
        self.ind.set_label(f"{self.xfer['pct']}%" if self.xfer else "", "100%")
        self.mi_toggle.set_label(
            "Resume sync" if self.state == "paused" else "Pause sync")

    def _flush_error(self):
        """Emit a pending ERROR notification whose block ended without an
        "Error Message:" detail line, using the preamble alone."""
        preamble = self.err_await
        self.err_await = None
        if preamble and not self.priming and preamble not in self.err_notified:
            self.err_notified.add(preamble)
            self._notify("OneDrive error", preamble[:220], urgent=True)

    def _notify(self, title, body, urgent=False):
        try:
            n = Notify.Notification.new(title, body, ICONS.get(self.state))
            # Never use Urgency.CRITICAL: KDE Plasma treats critical
            # notifications as *resident* — they stay on screen until the user
            # clicks them away and never time out. That is what caused popups to
            # pile up. NORMAL urgency plus an explicit timeout auto-dismisses.
            n.set_urgency(Notify.Urgency.NORMAL)
            n.set_timeout(NOTIFY_MS_LONG if urgent else NOTIFY_MS)
            n.show()
        except Exception:
            pass  # a broken notification daemon must never take down the tray


def _single_instance():
    """Hold an exclusive lock so autostart + a manual launch cannot both run.

    The lock is released automatically when the process dies, so a crash or a
    reboot never leaves a stale lock behind.
    """
    import fcntl
    runtime = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    fh = open(os.path.join(runtime, "onedrive-tray.lock"), "w")
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        raise SystemExit("onedrive-tray is already running")
    return fh  # keep referenced for the process lifetime


if __name__ == "__main__":
    _lock = _single_instance()
    OneDriveTray()
    Gtk.main()
