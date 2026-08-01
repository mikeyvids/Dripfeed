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

## 3. Reveal rule

- Due when `int(YYYYMMDD) <= int(today)`.
- Reveal = **atomic rename** of the entry to `<GAMES_DIR>/<SYSTEM>/<FINAL_NAME>` (the
  date prefix stripped). Same filesystem ⇒ `mv` is `rename(2)`, atomic.
- The engine **never overwrites** an existing destination — it skips and logs, so a
  game/save already present is never clobbered.
- The browser never moves a multi-disc folder itself. With the whole card
  selected, it writes `Scripts/.dripfeed/schedule-requests.tsv`; the card-side
  engine consumes that request with one same-filesystem `mv`. Re-date and return
  requests use the same pattern. CUE and M3U references are checked again before
  reveal; missing referenced files place the folder on recovery hold.
- A single-runner lock (`<STATE>/.lock`) ensures the boot daemon and a manual launch
  never reveal the same queue simultaneously.

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
then uses same-filesystem `mv`. Scheduling an already queued name changes its
date; unscheduling returns it to `games/<SYSTEM>/`. A request remains in its
ledger when a source is missing or a destination collision needs attention, and
is removed only after the requested on-disk state is true.

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
