#!/usr/bin/env python3
"""Drive the tray's state machine with the exact log lines captured from the
01:12 boot, without touching the real service or the real log."""
import importlib.util
import os
import sys
import tempfile

APP = os.path.expanduser("~/.local/share/onedrive-tray/onedrive-tray.py")
tmp = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
tmp.write("Sync with Microsoft OneDrive is complete\n")
tmp.flush()

spec = importlib.util.spec_from_file_location("odt", APP)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.LOG_PATH = tmp.name          # redirect to the fixture
m.SETTLE_S = 1                 # keep the test quick

tray = m.OneDriveTray()
fails = 0

# Capture every notification (title, body, urgent) from the start.
notes = []
tray._notify = lambda title, body, urgent=False: notes.append((title, body, urgent))


def step(lines, expect_state, label):
    global fails
    with open(tmp.name, "a") as fh:
        fh.write("".join(l + "\n" for l in lines))
    tray._poll_log()
    head, detail = tray._summary()
    ok = tray.state == expect_state
    print(f"  [{'ok ' if ok else 'FAIL'}] {label}\n"
          f"         state={tray.state!r} (want {expect_state!r})  icon={m.ICONS[tray.state]}\n"
          f"         shows: {head} — {detail}")
    if not ok:
        fails += 1


print("=== replaying the real 01:12 boot sequence ===")
step(["Attempting to contact the Microsoft OneDrive Service",
      "Cannot connect to the Microsoft OneDrive Service - Network Connection "
      "Issue: Could not resolve hostname on handle 565154BE80C0"],
     "offline", "first DNS failure -> offline, NOT error")

step(["ERROR: Microsoft OneDrive API returned an error with the following message:",
      "  Error Message:       Could not resolve hostname on handle 565154BE98A0"],
     "offline", "ERROR: block for the same network issue stays offline")

step(["Attempting to contact the Microsoft OneDrive Service",
      "Successfully reached the Microsoft OneDrive Service"],
     "syncing", "recovery clears the stale error (the bug you hit)")

import time
time.sleep(1.5)
tray._poll_log()
print(f"  [{'ok ' if tray.state == 'synced' else 'FAIL'}] settles to idle after recovery\n"
      f"         state={tray.state!r}  shows: {' — '.join(tray._summary())}")
if tray.state != "synced":
    fails += 1

print("\n=== a genuine (non-network) error must still show as an error ===")
notes.clear()
step(["ERROR: The local file system returned an error with the following details:",
      "  Calling Function:  syncEngine.scanPathForNewData()",
      "  Path:              ./x.txt",
      "  Error Message:     ./x.txt: Permission denied"],
     "error", "real fault -> error state")
# The whole point of this round: the notification body must carry the DETAIL
# from the "Error Message:" line, not just the preamble the popup used to show.
body_ok = len(notes) == 1 and "Permission denied" in notes[0][1]
print(f"  [{'ok ' if body_ok else 'FAIL'}] notification body includes the detail\n"
      f"         body: {notes[0][1] if notes else '(none)'}")
if not body_ok:
    fails += 1
step(["Attempting to contact the Microsoft OneDrive Service",
      "Successfully reached the Microsoft OneDrive Service"],
     "syncing", "contact also clears a real error once things proceed")

print("\n=== an ERROR block with no 'Error Message:' line still notifies ===")
notes.clear()
step(["Sync with Microsoft OneDrive is complete"], "synced", "reset to idle")
notes.clear()
step(["ERROR: Something went wrong with no detail block",
      "NOTE: This error requires attention; the client may continue running."],
     "error", "preamble-only error")
fallback_ok = len(notes) == 1 and "Something went wrong" in notes[0][1]
print(f"  [{'ok ' if fallback_ok else 'FAIL'}] fell back to preamble "
      f"(got {len(notes)}): {notes[0][1] if notes else '(none)'}")
if not fallback_ok:
    fails += 1
step(["Attempting to contact the Microsoft OneDrive Service",
      "Successfully reached the Microsoft OneDrive Service",
      "Sync with Microsoft OneDrive is complete"],
     "synced", "clear back to idle")

print("\n=== the recurring 'recommended limit' warning must stay calm ===")
notes.clear()

WARN = ("WARNING: The number of objects stored online in 'd15b866b937b384c' "
        "exceeds Microsoft OneDrive's recommended limit. This may cause "
        "unreliable application behaviour due to inconsistent or incomplete "
        "API responses. Immediate action is strongly advised to avoid data "
        "integrity issues.")
step([WARN], "synced", "object-count warning does NOT turn the icon red")

# Fire it four more times, as real sync cycles do.
for _ in range(4):
    with open(tmp.name, "a") as fh:
        fh.write(WARN + "\n")
    tray._poll_log()

crit = [n for n in notes if n[2]]                     # any urgent/critical?
print(f"  [{'ok ' if len(notes) == 1 else 'FAIL'}] notified exactly once over "
      f"5 occurrences (got {len(notes)})")
if len(notes) != 1:
    fails += 1
print(f"  [{'ok ' if not crit else 'FAIL'}] the notice was NOT critical/urgent")
if crit:
    fails += 1

head, detail = tray._summary()
shows_note = "⚠" in head and "note:" in detail and "number of objects" in detail
print(f"  [{'ok ' if shows_note else 'FAIL'}] standing warning shown on hover, "
      f"icon still {m.ICONS[tray.state]}\n         shows: {head} — {detail[:70]}...")
if not shows_note:
    fails += 1

print("\n=== a repeating error must not restack popups ===")
with open(tmp.name, "a") as fh:
    fh.write("Sync with Microsoft OneDrive is complete\n")
tray._poll_log()
notes.clear()

ERR = ["ERROR: The local file system returned an error with the following details:",
       "  Error Message:     ./x.txt: Permission denied"]
# Same error reprinted across five sync cycles.
for _ in range(5):
    with open(tmp.name, "a") as fh:
        fh.write("".join(l + "\n" for l in ERR))
    tray._poll_log()
print(f"  [{'ok ' if len(notes) == 1 else 'FAIL'}] identical error over 5 cycles "
      f"notified once (got {len(notes)}), icon={m.ICONS[tray.state]}")
if len(notes) != 1 or tray.state != "error":
    fails += 1

# A clean sync ends the episode; the SAME error afterwards must alert again.
with open(tmp.name, "a") as fh:
    fh.write("Attempting to contact the Microsoft OneDrive Service\n"
             "Successfully reached the Microsoft OneDrive Service\n"
             "Sync with Microsoft OneDrive is complete\n")
tray._poll_log()
notes.clear()
with open(tmp.name, "a") as fh:
    fh.write("".join(l + "\n" for l in ERR))
tray._poll_log()
print(f"  [{'ok ' if len(notes) == 1 else 'FAIL'}] same error after a clean sync "
      f"re-alerts (got {len(notes)})")
if len(notes) != 1:
    fails += 1

print("\n=== real boot DNS storm must produce ZERO popups (the 22:46 bug) ===")
with open(tmp.name, "a") as fh:
    fh.write("Sync with Microsoft OneDrive is complete\n")
tray._poll_log()
notes.clear()

# Verbatim from the live log, lines 1985-1992: an ERROR block whose detail is a
# DNS failure, followed by the non-indented "Cannot connect"/next-ERROR lines
# that used to flush a bogus preamble-only popup.
BOOT = [
    "ERROR: Microsoft OneDrive API returned an error with the following message:",
    "  Error Message:       Could not resolve hostname on handle 7F5C400126B0",
    "",
    "Cannot connect to the Microsoft OneDrive Service - Network Connection Issue: "
    "Could not resolve hostname on handle 7F5C400126B0",
    "",
    "ERROR: Microsoft OneDrive API returned an error with the following message:",
    "  Error Message:       Could not resolve hostname on handle 7F5C400126B0",
    "",
    "Unable to reach the Microsoft OneDrive API service at this point in time, "
    "re-trying network tests based on applicable intervals",
    "",
    "Attempting to contact the Microsoft OneDrive Service",
]
# Feed one line per poll — the worst case that triggered the original bug, since
# err_await then had to survive across poll boundaries.
for ln in BOOT:
    with open(tmp.name, "a") as fh:
        fh.write(ln + "\n")
    tray._poll_log()

ok = len(notes) == 0 and tray.state == "offline"
print(f"  [{'ok ' if ok else 'FAIL'}] {len(notes)} popup(s) (want 0), "
      f"state={tray.state!r} (want 'offline')")
if notes:
    for n in notes:
        print(f"         LEAKED: {n[0]} — {n[1]}")
if not ok:
    fails += 1

# And it must recover cleanly afterwards.
step(["Successfully reached the Microsoft OneDrive Service",
      "Sync with Microsoft OneDrive is complete"],
     "synced", "recovers to idle after the storm")

os.unlink(tmp.name)
print(f"\n{'ALL PASS' if fails == 0 else str(fails) + ' FAILURES'}")
sys.exit(1 if fails else 0)
