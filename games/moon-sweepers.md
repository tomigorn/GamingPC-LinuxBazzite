# Moon Sweepers (Steam)

Unity game, appid `5335510`. ProtonDB: Platinum. Crashed twice on 2026-11-04, stable since.

## Settings

| Setting | Value |
|---|---|
| Proton | Steam default (Proton Experimental), not forced |
| Graphics API (launcher choice) | **DX11** (developer default on AMD; DX12 crashed too) |
| Launch options | none |
| Steam overlay | on |
| GE-Proton 11-11 | installed for this game, **not selected**; fallback if crashes return |

## Crash history

| When | Situation | API | Result |
|---|---|---|---|
| 2026-11-04 21:23 | hosting, crew of 4 | DX11 | crash after 4.8 min |
| 2026-11-04 21:29 | crewmate, crew of 5 | DX12 | crash after 4.3 min |
| 2026-11-07 | solo, ~50 min | DX11 | no crash |
| 2026-11-08 | joined a friend, ~65 min | DX11 | no crash |

- Both crashes: same null-pointer read at `UnityPlayer.dll+0x10a652f`, same stack. Not the graphics API.
- Still open: **hosting** for friends. Next host session: watch for a crash. If it returns, try overlay off, then GE-Proton 11-11 (one change at a time). If hosting is stable, send the two crash reports to the developer.

## Where things are

| What | Where (in `steamapps/compatdata/5335510/pfx/drive_c/users/steamuser/`) |
|---|---|
| Saves, `Player.log` | `AppData/LocalLow/DragDropGames/MoonSweepers/` |
| Crash reports | `AppData/LocalLow/DragDropGames/MoonSweepers/Crash reports/` |
| Crash dumps | `AppData/Local/Temp/DragDropGames/MoonSweepers/Crashes/` |
| Test save from the crash hunt | slot 5 (Invite only), delete in the slot menu |
