# Changelog — Dripfeed

## 1.4.0 — 2026-10-09

Large libraries, large games, and graphical frontends. Open `Dripfeed.sh` once
on MiSTer after copying it to the card so the helpers and boot hook update.

### On the card (engine, CLI, Undrip)

- **Same-card moves only.** Every game move (reveal, browser schedule/re-date/
  return requests, legacy migration, CLI add/remove, Undrip) is now a rename that
  first checks both places are on the same filesystem. Dripfeed manages games in
  the SD card's `games/` only. A move that would cross to a USB drive, network
  share, or other mount is refused and logged, with nothing copied; previously
  `mv` could silently turn it into a slow copy+delete and leave a truncated,
  launchable "game" after a full card or power cut. `--diag` warns about games or
  system folders on another drive, and about USB system folders that MiSTer
  would browse instead of the SD card.
- **Leftover browser files are never revealed.** Queue entries ending in
  `.crswap` (a browser's temporary swap file) and empty 0-byte queue entries are
  held instead of revealed as games.
- **The lock can't be taken from a live pass.** The single-runner lock records
  the process that holds it. A running pass is never preempted, however long a
  large move takes; a lock left by a crashed or powered-off run is reclaimed at
  once; and a process can release only its own lock. Undrip and the command-line
  scheduler now take the same lock and report "busy" instead of moving games
  under a running pass.
- **Boot hook runs at start only.** MiSTer calls `user-startup.sh` at shutdown
  and reboot as well as at boot; the hook now starts the watcher only at boot, so
  nothing moves games while filesystems unmount. An existing hook block is
  replaced with the new one when Dripfeed updates.
- **Faster large queues.** Queue scans and duplicate checks no longer start
  helper processes for every entry, so the browser-request lane and `--diag`
  scale roughly linearly: a 400-game queue went from minutes to seconds on a test
  machine.
- **Multi-disc shortcuts launch.** What's New and GOT'eM shortcuts for a disc
  folder point at the first disc named in its `.m3u` (or the first `.cue`, then
  `.chd`), never at the `.m3u` itself, which MiSTer cores cannot mount.
- **Shortcuts with `&` or `'` survive.** The What's New pruner decodes the
  shortcut's escaped path before checking it, so games such as
  `ToeJam & Earl` or `Kirby's Dream Course` no longer lose their shortcut on the
  next pass.
- **Tolerant disc-set checks.** `.m3u` and `.cue` files saved with a byte-order
  mark, Windows line endings, trailing spaces, or full paths from a PC no longer
  hold a complete set forever (and Undrip no longer quarantines them). A playlist
  with only comments makes no claim. A set that is really missing a disc, or whose
  playlist is an empty (0-byte) file, is still held. Discs are ordered naturally,
  so "Disc 2" comes before "Disc 10".
- **MGL map re-synced** with the current upstream MiSTer system catalog (adapted
  from mrext, GPL-3.0), including the Jaguar, Neo Geo Pocket, and Saturn launch
  settings and Game Gear files kept in the Master System folder. The core slot is
  chosen by file extension, as the catalog does; a file no slot accepts (such as a
  `.zip`, an `.m3u`, or an `.iso` for a CD core) gets no shortcut and a log line
  instead of a shortcut that boots to an empty core.
- **Exact GOT'eM arcade core matching.** The core for an `.mra` is chosen the way
  the firmware chooses it: the exact name or `Arcade-` name followed by `_` or
  `.`, newest version first. `jtcps1` no longer copies `jtcps15`.
- **No more stale menu folders.** What's New folders from a custom
  `SHOWCASE_PREFIX` are consolidated like the default ones, and
  `FAVORITES_MIRROR` now uses one stable subfolder (`_@Favorites/_Dripfeed New`)
  instead of one per date. New records in the state folder (`showcase_names`,
  `system_shortcut_dirs`, `gotm_names`) list every folder Dripfeed created, so
  clean-up and Undrip remove exactly those. A folder is removed only when it holds
  nothing but Dripfeed's shortcut files; anything a user put there is kept.
  Folder names drop emoji and other characters the menu cannot show.
- **Valid `gamelist.xml` with real dates.** Paths are XML-escaped (a name with
  `&` used to make the file invalid), and each entry's release date is the game's
  actual reveal date from `revealed.tsv` instead of the date the file was
  rewritten.
- **Undrip** takes the lock, stops a running boot watcher first, removes every
  menu folder Dripfeed recorded (What's New, Game of the Month, the Favorites
  mirror, per-system shortcut folders), and leaves a game that sits on another
  drive where it is instead of copying it.
- **Browser requests**: when one game is requested more than once, the last row
  wins and the earlier rows are merged; a request that names Dripfeed's own
  shortcut folder is skipped. The CLI refuses that folder too.
- **Clearer `--diag`**: shows whether games and the waiting library share a
  drive, whether the boot hook is the new start-only version, who holds the lock,
  the new options, leftover browser swap files, system folders on USB, network,
  or the card root that MiSTer opens before `games/`, and any cross-drive holds.
  Request counts no longer print a stray `0` line.
- **Settings are validated.** A non-numeric or too-small `WATCH_INTERVAL` (`0`
  used to spin a CPU core forever), `BOOT_DELAY`, `SHOWCASE_KEEP`, or
  `SHOWCASE_MAXLEN` falls back to a safe value; on/off settings also accept
  yes/no, true/false, and on/off; a quoted value may contain `#`. The unused
  `WAIT_BUTTON` and `WAIT_TIMEOUT` settings were removed (they never had an
  effect; old lines are ignored).
- `dripfeed-schedule.sh list` sorts every row by date, including the new
  library's rows.
- Updating or repairing keeps announcements that have not been shown yet.
- The launcher and Undrip restart only on a real MiSTer; when Undrip finds
  Dripfeed busy it says nothing was reset and does not restart.
- **New options** (existing `config.ini` files keep working; missing keys use
  these defaults):
  - `SYSTEM_SHORTCUTS=0` — opt-in: mirror each What's New shortcut into
    `games/<SYSTEM>/<SYSTEM_SHORTCUTS_DIR>/` for graphical frontends that build
    their own library from system folders. Names carry no system prefix, each
    system keeps `SHOWCASE_KEEP` shortcuts, Undrip removes the folders, and
    turning the option off removes them on the next run.
  - `SYSTEM_SHORTCUTS_DIR="_Dripfeed New"` — that folder's name.
  - `POST_REVEAL_CMD=""` — optional command run once at the end of a pass that
    revealed at least one game (120-second limit, exit status logged, never from
    the shutdown path); for example a library refresh you set up for your
    frontend.
  - `TOUCH_ON_REVEAL=1` — after the reveal journal clears, set the revealed
    file's date (or a disc folder's and its top-level files') to the reveal time.
- After a pass that revealed games, the console summary adds: "Using a graphical
  frontend with its own game library? Refresh its library to see the new games."

### In the browser (Dripfeed-Scheduler.html)

- **CSV review no longer hangs.** Each NOT FOUND row used to build its own
  drop-down of every file in the system and rebuild it on every click; 1,000 bad
  rows grew the tab to 11 GB and it stopped responding after 28 minutes. Rows now
  share one type-to-pick list per system, renders are built off-screen and never
  interleave, and review shows progress (300 bad rows: 129 s down to about 1 s).
  Re-dating already scheduled rows uses a per-review index of waiting games (500
  rows: 86 s down to about 0.5 s).
- **Batched request-ledger writes.** Scheduling, re-dating, returning, and CSV
  apply read and write each request file once per batch instead of twice per
  game. 8,500 games: 128 s and 17,004 file writes down to about 1.3 s and 1 write.
  Banner messages are written once per import.
- **The browser never copies game data.** The stream-copy fallback is gone. In
  whole-card mode every change is a request the MiSTer engine applies; in
  games-folder-only ("limited") mode a single file is renamed or left untouched,
  and the real error is shown (for example, another program has the file open)
  instead of silently copying a multi-GB file through a `.crswap` swap file.
  Leftover `.crswap` files are ignored everywhere.
- **No lost clicks.** Writes to the request ledgers, banners, Game of the Month
  picks, and `config.ini` are serialized, and bulk buttons are disabled while
  they run: six quick **Unschedule** clicks now record six returns, not one.
- **No mixed-system selections.** A slow system load can no longer mix another
  system's games into the list, and **Select all systems** records every game
  under its own system.
- The schedule tab no longer doubles its rows when opened twice quickly.
- **Faster search and browsing.** The game list shows the first 500 matches with
  a **Show more** button and waits for typing to pause (about 4–5 ms per keystroke
  on a 5,000-game system, down from 50–67 ms). Folder inspection stops as soon as
  it finds a playable file, so connecting and switching systems are faster.
- **Fixed `.ics` export.** Each game keeps one stable event ID for life and every
  export carries a higher `SEQUENCE`, so re-importing after a re-date moves the
  event instead of duplicating it. Text is escaped and long lines folded as the
  calendar format requires, and an optional **Add a 9 AM alert on the day**
  reminder is available. Events exported by older versions used different IDs,
  so the first import after upgrading adds new events beside the old ones:
  delete the old Dripfeed events once, and later imports update in place.
  (Google Calendar's file import may ignore `SEQUENCE` updates; Apple Calendar
  and Outlook honour them.)
- Folder settings include the new per-system shortcut switch.

### Docs and tests

- README and INTEGRATION explain, in frontend-neutral terms, how graphical
  frontends that build their own library from system folders see Dripfeed's
  files, and correct the What's New name-length rationale: the stock menu shows
  about 21 characters of a top-level folder name on a row that isn't selected.
- New browser-logic tests run the scheduler's own code against in-memory folders.
- The suite-level check that banned a third-party product name was removed; the
  credential, vault, and host-path leak check remains.

## 1.1.0 – 1.3.2

- **1.3.2 automatic legacy-queue migration**: the first card-side pass moves
  every older `games/SYSTEM/.dripfeed/` queue entry into the hidden card-root
  `.dripfeed-library/SYSTEM/`. Each entry is a same-card rename, so interrupted
  upgrades simply continue next run. Name collisions are held without overwrite,
  incomplete disc sets stay hidden, and ordinary game-library scanners no longer
  traverse the held queue through a system folder.

- **1.3.1 duplicate-queue recovery guard**: the CLI and browser-request lanes
  refuse to act when an older queue contains two copies of the same clean game
  name. Diagnostics label duplicate entries, incomplete sets, and visible/queued
  collisions. Undrip quarantines incomplete legacy CUE/M3U sets instead of
  restoring them as runnable games.

- **1.3.0 queue and disc-safety repair**: new schedules use a hidden card-root
  waiting library outside `games/`; legacy per-system queues remain readable.
  Browser scheduling no longer recursively copies multi-disc folders—it writes a
  tiny request that the card-side engine fulfills with one same-card move. CUE/M3U
  references and interrupted-copy markers are checked before reveal. Undrip now
  quarantines a staged/visible collision instead of deleting either copy.
  Regression coverage includes Mega CD firmware folders, incomplete disc sets,
  and an exact `ToeJam & Earl, Panic on Funkotron` punctuation path.

- **1.2.1 public-boundary cleanup**: presents Dripfeed and GOT'eM as the two
  primary curation lanes, keeps output frontend-neutral, and removes an
  unapproved optional integration hook and its public documentation.

- **1.2.0 interrupted-reveal recovery**: a durable intent journal is flushed
  before each same-filesystem reveal. If power fails after the move but before
  ledger/shortcut creation, the next pass repairs both without duplicating or
  overwriting the game. The launcher can now be regenerated from its readable
  helper sources with `tools/sync-launcher.sh`.

- **1.1.1 firmware guard**: MegaCD region folders (`USA`, `Japan`, `Europe`) are
  inspected as firmware folders when they contain BIOS-only content. Jaguar `.mrq`
  marquee assets and other known support files are protected in the web scheduler,
  CLI, and card-side reveal engine. Legacy bad queue entries are skipped and logged;
  `remove` can explicitly restore one to its original system folder, and no firmware
  or support files are deleted automatically.

- **1.1.0 safety iteration**: durable reveal ledger, incremental CSV protection,
  explicit re-hide override, real calendar-date validation, destination collision
  guards, bulk select/invert controls, and XML-safe `.mgl` attributes.

- Fixed CSV Game-of-the-Month path normalization: non-arcade rows remain
  `System/File` in CSV but become `games/System/File` in `gotm.tsv`; arcade
  `_Arcade/File.mra` paths remain unchanged. CSV export now returns the same
  canonical form, and legacy `games/System/File` imports are accepted.
- Made the regression harness portable across BSD/macOS and GNU command-line
  tools, and added a persistent CSV/GOTM contract test.

## 1.0.0 — 2026-07-02

First public release.

**Dripfeed** reveals a game library a few titles at a time, on a schedule you
set — built for pacing a big install for a family (or yourself) on MiSTer FPGA.

- **Single-file install**: drop `Dripfeed.sh` into `Scripts/`, open it once.
  It extracts its own helpers (syntax-verified before they replace anything),
  writes its config, and installs a boot hook. Survives `update_all`.
- **Scheduling**: hide any ROM or multi-disc folder until a date you choose.
  Reveal is an atomic rename back to the exact original filename, so saves,
  artwork, and RetroAchievements hashes are never disturbed. Never overwrites.
- **Boot updates**: waits (indefinitely) for a valid clock after power-on, then
  reveals anything due; re-checks once per calendar day while powered on.
- **"What's New" menu folder** of `.mgl` shortcuts, named for the latest unlock
  (`_Dripfeed - New Fri Jul 3, 26`) or your custom banner for that day. The name
  is sticky — it only changes when a game actually unlocks — and can be fully
  customized (fixed name, custom prefix, "date of latest Dripfeed" toggle) with
  automatic cleanup of characters the MiSTer menu can't display and length
  limits that adapt to what the toggles add.
- **Game of the Month**: a `_Game of the Month` folder driven by the scheduler —
  consoles, handhelds, computers, and arcade (`.mra` + core copied in). Picks
  are never renamed or moved; hidden picks appear the day they unlock. Optional
  month tag in the folder name (`… - Aug`).
- **Visual scheduler** (`Dripfeed-Scheduler.html`, Chromium browsers): calendar
  scheduling across systems, custom banners, CSV import/export with re-dating
  and in-review date fixing (per row or all at once), bulk schedule tools
  (filter/unschedule/re-date), Game of the Month picker, folder-name settings,
  calendar (.ics) export, and step-by-step reconnect if the card goes away.
  Game lists hide BIOS/boot/support files behind a "show system files" link.
- **Launcher menu**: UP = Undrip (full clean reset — restores every game,
  removes all traces, keeps only Dripfeed.sh), DOWN = repair reinstall that
  keeps your schedule. Any run shows what's new.
- **Frontend-neutral output**: writes standard `gamelist.xml` + `.mgl`
  breadcrumbs without modifying a frontend or its private database.
- Conformance/regression test suite (`tests/run.sh`).
