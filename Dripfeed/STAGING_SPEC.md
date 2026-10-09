# Dripfeed staging format — the one spec

Both schedulers (`Dripfeed-Scheduler.html` and `Scripts/.dripfeed/dripfeed-schedule.sh`)
write the queue, and the engine reads it. This is the **single contract** they must all
agree on. `tests/run.sh` is the conformance test; CI runs it on every change.

## 1. Where a queued game lives

```
<STAGING_ROOT>/<SYSTEM>/<ENTRY>
```

- `STAGING_ROOT` — default `/media/fat/.dripfeed-library`; it sits outside
  `games/` so ordinary library scanners do not discover held-back titles.
- `<SYSTEM>` — the core's games-folder name exactly (`SNES`, `GENESIS`, `Saturn`, …).
- The old `<GAMES_DIR>/<SYSTEM>/.dripfeed/` layout remains readable during
  upgrades, but new scheduling writes only to `STAGING_ROOT`.
- `STAGING_ROOT` and `<GAMES_DIR>/<SYSTEM>` must be on the **same filesystem**
  (the SD card). Dripfeed manages games in the SD card's `games/` only; a move
  into or out of a system folder that is really USB, a network share, or another
  mount is refused, not copied (§3).

### Firmware and support folders are never queue entries

Some cores keep firmware beside games. MegaCD is the common example: `USA/`,
`Japan/`, and `Europe/` contain `cd_bios.rom`, not games. Jaguar `.mrq` files are
marquee/support assets. Both the web scheduler and the card-side CLI hide these
entries, and the reveal engine refuses to move them even if an old CSV or manual
run queued one. They remain in place for the core and frontend to use.

## 2. Entry name (the queue format)

```
YYYY-MM-DD_<FINAL_NAME>
```

- `YYYY-MM-DD` — the unlock date (ISO 8601). Must match `^\d{4}-\d{2}-\d{2}_`.
- `_` — a single underscore separator (the 11th character).
- `<FINAL_NAME>` — the **exact** name the game should have once revealed, including its
  extension (`Shiny Forts.md`) — or a **folder name** for a multi-disc set
  (`Shiny Forts III`, a directory containing the disc images + an `.m3u`).

Examples:
```
.dripfeed-library/GENESIS/2026-07-10_Shiny Forts.md
.dripfeed-library/MegaCD/2027-05-25_Shiny Forts Seedy.chd
.dripfeed-library/Saturn/2026-12-25_Shiny Forts III/     (folder: discs + Shiny Forts 3.m3u)
```

Never valid queue entries, even with a correct prefix: names ending in `.crswap`
(a browser's temporary swap file) and empty (0-byte) files. The engine holds and
logs them instead of revealing them, and the web scheduler skips `.crswap` names.

## 3. Reveal rule

- Due when `int(YYYYMMDD) <= int(today)`.
- Reveal = **atomic rename** of the entry to `<GAMES_DIR>/<SYSTEM>/<FINAL_NAME>` (the
  date prefix stripped). Before every game move (reveal, request, migration, CLI,
  Undrip) the engine checks that source and destination are on the same
  filesystem, so the move is `rename(2)`. If they are not, it refuses and logs the
  hold with nothing copied; `mv` must never fall back to copy+delete.
- The engine **never overwrites** an existing destination — it skips and logs, so a
  game/save already present is never clobbered.
- The browser never moves a multi-disc folder itself. With the whole card
  selected, it writes `Scripts/.dripfeed/schedule-requests.tsv`; the card-side
  engine consumes that request with one same-filesystem rename. Re-date and return
  requests use the same pattern. CUE and M3U references are checked again before
  reveal; missing referenced files place the folder on recovery hold.
- A single-runner lock (`<STATE>/.lock/`, created with an atomic `mkdir`) ensures
  the boot daemon, a manual launch, Undrip, and the CLI scheduler never move games
  at the same time. Inside it:

  ```
  .lock/owner   →   three lines: PID, boot ID, host name of the holder
  .lock/ts      →   one line: when the lock was taken (Unix seconds)
  ```

  A holder that is still running on the current boot is never preempted, however
  long it takes. A lock whose holder has exited, or that was left by an earlier
  boot, is reclaimed. A lock with no `owner` file (an older Dripfeed, or one taken
  from another machine) falls back to the old 10-minute age rule. A process removes
  only a lock it owns. Undrip and the CLI wait briefly, then report "busy" and
  change nothing.
- After a successful reveal, with `TOUCH_ON_REVEAL=1`, the engine updates the
  modification time of the revealed file (or of a folder and its top-level files)
  once the reveal journal has cleared. Contents and names are unchanged.

## 4. Custom messages (occasions)

```
<STATE>/occasions.tsv   →   lines of:   YYYY-MM-DD<TAB>message
```

- `STATE` — `/media/fat/Scripts/.dripfeed` (hidden; the engine + both schedulers use it).
- One message per date. If a date has more than one line, the **first** wins.
- The message is shown in full on the on-screen banner and in the showcase
  `gamelist.xml <desc>`; the first ~18 chars (cap minus prefix) also name the menu folder.

## 4b. Showcase folder name (sticky)

```
<STATE>/showcase_name   →   the CURRENT "What's New" folder name (one line)
```

- The engine renames/stamps the folder **only when a reveal actually unlocks ≥ 1
  game**: it becomes `<PREFIX><message-for-that-day>` if an occasion exists, else
  `<PREFIX>New Www Mmm D, YY` (day-of-month **not** zero-padded, e.g. `New Wed Jul 1, 26`).
- Every other launch/boot **reuses the saved name verbatim** — powering the console
  on must never rename the folder (frontends key on the path).
- If the saved name no longer starts with the configured `SHOWCASE_PREFIX` (prefix
  changed in `config.ini`), the engine re-stamps once with today's default.
- Every folder name the engine creates is also recorded, one name per line:

  ```
  <STATE>/showcase_names         →  every What's New folder name ever stamped
  <STATE>/system_shortcut_dirs   →  per-system shortcut folder names used (§4c)
  <STATE>/gotm_names             →  Game of the Month folders built
  ```

  Consolidation (merging an older What's New folder into the current one) and
  Undrip use these records together with the default prefixes and a distinctive
  configured prefix (at least three characters after `_` / `_@`), so a custom
  prefix never leaves stale folders behind and Undrip removes only folders
  Dripfeed created.
- The optional Favorites mirror (`FAVORITES_MIRROR=1`) always writes into one
  stable subfolder, `<FAVORITES_DIR>/_Dripfeed New/`. Older dated mirror folders
  that hold only Dripfeed shortcuts are removed; other favorites are never touched.

## 4c. Per-system shortcut folders (optional)

```
<GAMES_DIR>/<SYSTEM>/<SYSTEM_SHORTCUTS_DIR>/<TITLE>.mgl
```

`<TITLE>` is `<FINAL_NAME>` without its extension (a multi-disc folder keeps its
folder name).

- Written only when `SYSTEM_SHORTCUTS=1` (default `0`); `SYSTEM_SHORTCUTS_DIR`
  defaults to `_Dripfeed New`.
- Holds only `.mgl` shortcuts that mirror the What's New folder: no system prefix
  in the name, newest `SHOWCASE_KEEP` per system, the same absolute target path.
- It is generated output, not a game: neither scheduler may queue it, and the
  engine never reveals or moves it. Undrip removes it, and the next run removes it
  when `SYSTEM_SHORTCUTS=0`.

## 5. Invariants both schedulers must uphold

1. Never write a queue entry without a valid `YYYY-MM-DD_` prefix.
2. `<FINAL_NAME>` carries the real extension (so saves / RetroAchievements hashes match
   after reveal).
3. Re-dating a game replaces its prefix; it does not create a second copy.
4. Occasions go to `<STATE>/occasions.tsv` in `date<TAB>message` form, sorted by date.

The whole-card web scheduler does not move game data. It writes one unique row
per game to one of these ledgers:

```
schedule-requests.tsv   → YYYY-MM-DD<TAB>SYSTEM<TAB>FINAL_NAME
unschedule-requests.tsv → SYSTEM<TAB>FINAL_NAME
```

On the next Dripfeed run, the engine validates the request and firmware guard,
then uses a same-filesystem rename (§3). Scheduling an already queued name changes its
date; unscheduling returns it to `games/<SYSTEM>/`. A request remains in its
ledger when a source is missing, a destination collision needs attention, or the
move would cross filesystems, and is removed only after the requested on-disk
state is true.

The browser never copies game data. In games-folder-only mode it may rename a
single file with the File System Access `move()`; if that is refused, it reports
the error and changes nothing.

If you change any of the above, update this file, the engine, **both** schedulers, and
`tests/run.sh` together.

## 6. Reveal ledger (incremental updates)

The engine appends one row to `<STATE>/revealed.tsv` after each successful reveal:

```
YYYY-MM-DD<TAB>SYSTEM<TAB>FINAL_NAME<TAB>YYYY-MM-DD HH:MM:SS
```

The scheduler reads this ledger before export. Rows already recorded are shown as
**unveiled** and are protected from re-hiding or re-dating unless the operator turns
on the explicit **Allow re-hide of already unveiled games** override. This makes a
later CSV import incremental by default: only queued/unreleased games are changed.
The ledger is local state, not a replacement for the queue; keep it in the same
`Scripts/.dripfeed` folder when migrating a card.
