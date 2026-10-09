# Dripfeed + GOT'eM for MiSTer FPGA

**Community source project — GPLv3 or later.** Dripfeed is a readable, editable
MiSTer tool with two complementary lanes: Dripfeed schedules a file or multi-disc
folder, keeps it hidden, and reveals it atomically on the date you choose;
GOT'eM highlights an existing console, computer, handheld, or Arcade game as a
monthly spotlight without moving the original. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the small test-first workflow.

Reveal games to a player a few at a time, on a schedule you set — instead of
dumping a 600-game library on them at once. Queue a game for a future date; on
that day it quietly appears in the right system folder, and the next time the
**Dripfeed** script is opened it's announced on screen, one new game at a time,
"press a button to continue" style.

Built for a parent setting up a console for a kid, but it works for anyone who
wants to pace a backlog. POSIX-friendly `bash`, no dependencies, **survives
`update_all`**.

---

## What it does

- **Stage** any ROM (or a multi-disc folder) to unlock on a date you choose.
  Until then it lives in the hidden `/.dripfeed-library/<SYSTEM>/`, outside
  `games/`, so ordinary library scans do not discover it early.
- **Upgrade old queues automatically**: the first run moves older
  `games/SYSTEM/.dripfeed/` entries to that card-root library with same-card
  renames. A power interruption can pause the migration, but cannot create a
  half-copied game; the next run continues. Collisions and incomplete disc sets
  are held for review instead of overwritten or revealed.
- **Reveal** automatically at power-on and once per calendar day: due games are
  moved into their normal system folder with a clean filename (so saves and
  RetroAchievements hashes still match).
- **Announce** new games one at a time on the script console, advancing when the
  player presses a controller button.
- **Stay out of the way**: one visible entry in the Scripts menu; everything else
  is hidden, and nothing here is overwritten by `update_all`.
- **Incremental-safe updates**: successful reveals are recorded in
  `Scripts/.dripfeed/revealed.tsv`. The web scheduler labels those games as
  **unveiled** and will not re-hide/re-date them unless you deliberately enable the
  re-hide override.
- **GOT'eM monthly spotlights**: choose a personal Game of the Month and,
  optionally, a parallel community pick. GOT'eM can highlight Arcade entries and
  remains separate from the dated Dripfeed queue.
- **Play well with graphical frontends**: frontends that build their own library
  from system folders can see new reveals after a library refresh, and an
  opt-in setting puts a small "_Dripfeed New" shortcut folder inside each
  system folder for them. See
  [Graphical frontends with their own library](#graphical-frontends-with-their-own-library).

---

## Why it survives `update_all`

`update_all` / `Downloader_MiSTer` only replaces the things it manages (the
`MiSTer` binary, `menu.rbf`, and cores under `_Console`/`_Computer`/`_Arcade`/
`_Other`/`_Utility`). Dripfeed deliberately lives everywhere it *doesn't* look:

| Piece | Location | Why it's safe |
|-------|----------|---------------|
| State, config, logs | `Scripts/.dripfeed/` | hidden dot-folder; the updater never touches it |
| Queued games | `.dripfeed-library/<SYSTEM>/` | hidden and outside `games/`; the updater never touches it |
| Helper scripts | `Scripts/.dripfeed/` | hidden; custom scripts are left alone |
| Boot hook | one block in `linux/user-startup.sh` | the updater preserves this file |

This is the same pattern the MiSTer RetroAchievements deployment uses, so it
plays nicely alongside it.

---

## Install (one file)

1. Copy **just `Scripts/Dripfeed.sh`** onto the SD card at `/media/fat/Scripts/`.
   (You do NOT need to copy the `.dripfeed` folder — the launcher writes it itself.)
2. On the MiSTer, open **Scripts → Dripfeed** once. It shows "Installing… please
   wait", extracts its helper scripts into `Scripts/.dripfeed/`, writes
   `config.ini`, adds the boot hook, then "Done — press any button". Open it again
   any time to see what's new; if there's nothing new it tells you so (never a
   blank screen).
3. **Updating:** replace `Dripfeed.sh` with a newer version and open it once — it
   compares an embedded version string and re-extracts the helpers automatically.

The `Scripts/.dripfeed/` source files are kept in this repo for editing/building;
the single `Dripfeed.sh` is the only file end users need.

> After a *major* MiSTer update that rewrites `user-startup.sh`, just open the
> Dripfeed script once — it self-heals, silently re-adding the boot hook. Your
> queue is never affected.

---

## How to use it

### Easiest way: the visual scheduler (no terminal)

Open **`Dripfeed-Scheduler.html`** in Chrome, Edge, or Brave (any OS). It's a single
self-contained file — no install, no server.

1. Plug the SD card into your computer.
2. Click **Connect SD card** and pick the **whole card**—the folder that contains
   both `games/` and `Scripts/`. This lets new queues live outside `games/`.
3. Tick games from **any number of systems** — switch cores freely, your picks
   stay in one selection — then click a day on the **calendar**.
4. Optionally type a **custom banner** ("Happy Birthday Player One").
5. Click **Schedule selected games**. Your whole selection gets that one date. Eject,
   back in the console.

Available games remain in their normal system folder while scheduled games wait
under the hidden card-root library. Scheduling only hides the ones you pick, and
revealing never overwrites a game (or save) that's already there.

When you update a schedule later, the scheduler protects anything already recorded
as unveiled. This lets you revise the remaining queue without disturbing games that
have already appeared on the console.

The **Dripfeed schedule** tab shows everything waiting, with an **Unschedule** button to
pull anything back, and **Export CSV / .ics** buttons. (Safari/Firefox can't write to
local folders from a web page — use a Chromium browser.)

**The browser never copies game data.** With the whole card connected, every
schedule, re-date, and return is written as a one-line request; MiSTer moves the
game itself the next time Dripfeed runs. If you connect only the `games/` folder
("limited mode"), the scheduler can still schedule single files by renaming them
on the card, but it never falls back to copying: if the browser refuses the
rename, you see the real reason (for example, another program has the file open)
and the game stays exactly where it was. Multi-disc folders always need the whole
card.

Large libraries are fine: scheduling thousands of games at once writes each request
file once, the game list shows the first 500 matches (type to search, or click
**Show more**), and quick repeated clicks are queued rather than lost.

**Bulk import (CSV).** The **Import CSV** tab takes `path, date, message` rows (a
header row is auto-detected) — e.g. `MegaDrive/Shiny Forts.md, 2026-07-10,` or
`Saturn/Shiny Forts III, 5/25/2027, Happy Towel Day!`. Paste or choose a file,
click **Review**, and you get a per-row check: dates are normalized (ISO,
`M/D/YYYY`, etc.), missing files are flagged with a **type-to-pick box listing that
system's files**, and anything you don't want can be **skipped** — then schedule the
OK rows in one click. Review shows its progress on long sheets. There's a **blank
template** download and a **schedule → CSV** export for round-tripping with a
spreadsheet.

A month-only date such as `2026-08` is a **Game of the Month** row. CSV paths
remain relative to `games/` (`SNES/Game.sfc`); the scheduler adds `games/` when
it writes the `/media/fat`-relative `gotm.tsv` entry. Arcade picks use
`_Arcade/Game.mra` unchanged. `_Arcade` is GOTM-only and cannot be scheduled as
a normal dated drip.

### GOT'eM: the monthly spotlight

GOT'eM is not a small add-on to Dripfeed; it is the suite's second curation
lane. Use its dedicated scheduler tab to select a month and an existing game.
The engine builds a `_Game of the Month` folder without hiding, renaming, or
moving the original. A local pick and optional community pick can run in
parallel. If a chosen game is still waiting in Dripfeed, GOT'eM waits and builds
the spotlight after that game's reveal.

### Power-user way: the command-line scheduler (SSH / desktop)

Prefer a terminal? The same actions are available as a script. Run it where a
keyboard is easy: on your computer with the SD card mounted, or over SSH. Off the
device, tell it where `games/` is with `DRIPFEED_GAMES`.

```sh
# On the MiSTer (over SSH):
Scripts/.dripfeed/dripfeed-schedule.sh add MegaDrive 2026-07-10 "games/MegaDrive/Shiny Forts.md"

# On a Mac/PC with the card mounted:
DRIPFEED_GAMES="/Volumes/MiSTer/games" \
  Scripts/.dripfeed/dripfeed-schedule.sh add MegaCD +14 "/Volumes/MiSTer/games/MegaCD/Shiny Forts Seedy.chd"

# Batch several at once (same date):
... dripfeed-schedule.sh add NES tomorrow game1.nes game2.nes game3.nes

# See the queue, or just what's ready now:
... dripfeed-schedule.sh list
... dripfeed-schedule.sh due

# Set a custom banner for a date (Happy Birthday, Happy Towel Day, Back to School):
... dripfeed-schedule.sh message 2027-01-23 "Happy Birthday Player One"
... dripfeed-schedule.sh message 2027-01-23            # (no text = clear it)

# Change your mind — pull one back to visible immediately:
... dripfeed-schedule.sh remove GENESIS "2026-07-10_Shiny Forts.md"

# No arguments → a guided numbered menu (pick system, pick files, type a date):
... dripfeed-schedule.sh
```

**Dates accept:** `YYYY-MM-DD`, `today`, `tomorrow`, or `+N` (N days from now).

A nice workflow: copy a big batch of new games in normally (visible), then use
`add` to hide-and-date the ones you want to hold back. Anything you don't stage
stays available right away.

### Reveal & announce (the player side)

Nothing to do — games appear on their date. To *see* the announcements, open
**Scripts → Dripfeed**. It shows any games added since last time (one at a time,
press a button to advance), reveals anything due right now, then offers the small
menu. Kids can just watch the announcements and pick **Exit**.

After a pass that revealed games, the summary adds one line: *"Using a graphical
frontend with its own game library? Refresh its library to see the new games."*
The stock MiSTer menu needs nothing; it reads folders fresh each time you open them.

---

## Graphical frontends with their own library

Some MiSTer setups replace the stock menu with a graphical frontend that builds its
own library from system folders (`games/SNES`, `games/PSX`, …). Dripfeed writes only
standard on-card files and never touches such a frontend's database, binaries, or
settings, so it helps to know how these frontends see the card:

- **They list a system as everything in its folder.** Choosing a system shows every
  game in that folder, usually sorted by name. There is no "new" view. That is
  expected: Dripfeed keeps unreleased games out of `games/` entirely (in the hidden
  `/.dripfeed-library/`), so after a refresh only released games are listed.
- **They do not show top-level menu folders.** What's New (`_Dripfeed - …`) and
  `_Game of the Month` are top-level folders in the stock menu's core list. A
  frontend that only looks inside system folders never sees them. Use the stock menu
  for those folders, or turn on `SYSTEM_SHORTCUTS` (below).
- **Their library is a saved snapshot.** They usually update it only when you ask
  (a "refresh", "rescan", or "update library" action). So:
  - **After upgrading Dripfeed**, refresh the library once. Older Dripfeed versions
    kept waiting games inside `games/<SYSTEM>/.dripfeed/`, where some library tools
    listed them early with date-prefixed names. The upgrade moves them outside
    `games/`, and a refresh drops those stale entries.
  - **After each reveal day**, refresh again to see the new games, and after you
    schedule games so they drop out of the list. If your frontend offers a refresh
    command you can run on the MiSTer, put it in `POST_REVEAL_CMD` and Dripfeed
    runs it for you after any run that revealed, hid or put back games.
- **`SYSTEM_SHORTCUTS=1` adds a What's New folder inside each system folder.** Each
  reveal also gets an `.mgl` shortcut in `games/<SYSTEM>/_Dripfeed New/` (name set
  by `SYSTEM_SHORTCUTS_DIR`), named after the game without a system prefix and
  trimmed to the newest `SHOWCASE_KEEP` per system. A console or computer GOT'eM
  pick also gets a shortcut in `games/<SYSTEM>/_Game of the Month/` (arcade picks
  have no system folder there and stay in the top-level GOT'eM folder). The games
  themselves never move there. Caveats:
  - it is per system, not one list across systems;
  - tools that index `.mgl` files in system folders (search, random-game, and
    attract-mode tools) will list each new game twice: the game and its shortcut;
  - the stock menu's file browser for that core shows `_Dripfeed New` as a folder
    (it looks empty there, because cores do not list `.mgl` files);
  - your frontend still needs a library refresh before the folder appears.

  Undrip removes these folders, and turning the setting off removes them on the next
  run.
- **`TOUCH_ON_REVEAL=1`** (the default) sets a revealed game's file date to the
  moment it was revealed, so date-sorted file browsers and tools show it as new. The
  stock menu ignores file dates. Backup or sync tools will see the new date as a
  change; set `TOUCH_ON_REVEAL=0` to keep the original dates.

---

## Features

- Power-on **and** daily reveals (no `cron` needed — a tiny boot watcher handles both).
- One-at-a-time on-screen announcements with **controller button-to-continue**
  (reads `/dev/input/js0`; falls back to ENTER on a keyboard).
- **"What's New" menu folder** (`.mgl` shortcuts, Favorites-style): every unlock also
  drops a shortcut into a top-level menu folder named **`_Dripfeed - New Fri Jul 3, 26`**
  — or your custom message for that day (`_Dripfeed - Happy Birthday Deme` — capped
  by `SHOWCASE_MAXLEN`). Each shortcut's
  name shows the system (`GENESIS - Shiny Forts`). It holds the newest `SHOWCASE_KEEP`
  unlocks (default 12). The name is **sticky**: it changes only when games actually
  unlock, and the custom message stays until the next unlock — simply powering the
  console on never renames the folder. This is the
  on-screen "announcement" that needs no changes to the MiSTer main — it just appears
  in the menu like recently-played. Uses absolute-path `.mgl` files with a core
  mapping adapted from mrext and re-synced with the current upstream MiSTer system
  catalog. Names with `&`, `'`, or other punctuation keep their shortcuts. If you
  change `SHOWCASE_PREFIX`, older folders with the previous prefix are tidied up
  instead of piling up. Set `SHOWCASE=0` to disable. (Jaguar and Neo Geo Pocket
  mappings follow the catalog but are the least tested — verify them on your build.)
- **Custom occasion banners**: tie a message to a date ("Happy Birthday Player One");
  it shows as a big banner above the games that unlock that day. Set it in the
  visual tool's message box or with `dripfeed-schedule.sh message`.
- **Calendar export**: the visual tool's **Export to Calendar (.ics)** button turns
  your whole queue into all-day events (one per game, on its reveal date) with the
  custom banner text in each event's notes — import it into Apple/Google/Outlook
  Calendar to see the drip schedule at a glance. Each game keeps the same calendar
  event across exports, so after re-dating, a fresh import moves the event instead
  of adding a second one. Tick **Add a 9 AM alert on the day** for a reminder.
- Multi-disc support: stage a **folder** (discs + `.m3u`) and it's revealed intact.
  Its What's New and GOT'eM shortcuts point at the first disc (`.cue` or `.chd`),
  never at the `.m3u`, because MiSTer cores mount disc images, not playlists.
- Multi-disc safety: the browser writes a tiny move request; the MiSTer-side
  engine performs the whole-folder same-card move. The browser never copies game
  data. Disc-set checks accept playlists saved by common PC tools (a byte-order
  mark, Windows line endings, trailing spaces, or full paths) while still holding a
  set that is really missing a disc.
- **Same card only**: Dripfeed manages games in the SD card's `games/` folder.
  Every move is a rename on that one card. If the card's `games/` or one of its
  system folders is really a USB drive, network share, or other mount (for example
  a symlink or a share mounted over it), or a game you add from the command line
  sits on another drive, Dripfeed refuses the move (nothing is copied or
  half-written), logs why, and `--diag` warns about it.
- Punctuation-safe names: commas, ampersands, apostrophes, and spaces remain exact.
- Clean reveals: the date prefix is stripped, so the final filename is exactly
  what the core/saves/RetroAchievements expect.
- Safe by default: never overwrites an existing game; logs every reveal to
  `Scripts/.dripfeed/dripfeed.log`. Empty (0-byte) queue entries and leftover
  browser `.crswap` files are held, never revealed as games.
- **One runner at a time**: the boot watcher, a manual launch, Undrip, and the
  command-line scheduler share one lock. A long pass is never interrupted by another
  one, and a lock left by a crashed or powered-off run is reclaimed automatically.
- The boot hook runs only when MiSTer starts, never during shutdown or reboot.
- Fast on large queues: hundreds of waiting games are processed in seconds, not
  minutes.
- Re-datable: scheduling an already-staged item just updates its date.
- Cross-platform scheduler (Linux/MiSTer + macOS/BSD date handling).

---

## Configuration (`/media/fat/Scripts/.dripfeed/config.ini`)

```ini
GAMES_DIR=/media/fat/games
STAGE_DIRNAME=.dripfeed
STAGING_ROOT=/media/fat/.dripfeed-library
REVEAL_AT_BOOT=1     # reveal due games at power-on
DAILY=1              # also reveal once per calendar day while powered on
WATCH_INTERVAL=3600  # seconds between day-change checks
SYSTEM_SHORTCUTS=0   # 1 = also put What's New and GOT'eM shortcuts inside each system folder
SYSTEM_SHORTCUTS_DIR="_Dripfeed New"   # that per-system folder's name
POST_REVEAL_CMD=""   # optional command to run once after a run that revealed, hid or put back games
TOUCH_ON_REVEAL=1    # 1 = a revealed game's file date shows when it was revealed
```

The installer writes the full list, including the What's New (`SHOWCASE_*`),
Favorites mirror, and Game of the Month settings, with a comment on each line.
Settings added in a newer version use their defaults until you add them. Values
are checked when read: a missing, non-numeric, or too-small number (for example
`WATCH_INTERVAL=0`) falls back to a safe value, and on/off settings accept `1/0`,
`yes/no`, `true/false`, or `on/off`.

- **`SYSTEM_SHORTCUTS`** (default `0`): mirrors each What's New shortcut into
  `games/<SYSTEM>/<SYSTEM_SHORTCUTS_DIR>/` for graphical frontends that build their
  own library from system folders, and a console or computer GOT'eM pick into
  `games/<SYSTEM>/_Game of the Month/` (arcade picks stay top-level). Kept to
  `SHOWCASE_KEEP` per system, removed by Undrip, and removed on the next run after
  you set it back to `0`. The web
  scheduler's folder settings include the same switch. Read the caveats in
  [Graphical frontends with their own library](#graphical-frontends-with-their-own-library)
  before turning it on.
- **`POST_REVEAL_CMD`** (default empty): a command Dripfeed runs once at the end of
  any run that changed what is in the system folders, for example a library-refresh
  script you wrote for your frontend
  (`POST_REVEAL_CMD="/media/fat/Scripts/my-refresh.sh"`). That means games revealed
  (on schedule, or early with `remove`), games hidden (scheduled from the browser or
  with `add`), games put back (unscheduled, or by Undrip), and Dripfeed's own
  shortcuts inside system folders added or removed (`SYSTEM_SHORTCUTS`, including
  GOT'eM). A run that changed nothing does not call it, and it only runs on the
  MiSTer itself (never when you use the command-line scheduler on a computer with
  the card mounted). At boot, games hidden
  before the first reveal share one call with that reveal. It runs through `sh -c`
  with a 120-second time limit, never from the shutdown path. Its output goes to
  `Scripts/.dripfeed/post_reveal.log` and its exit status to `dripfeed.log`. The
  command can read `DRIPFEED_REVEALED_COUNT`, `DRIPFEED_HIDDEN_COUNT`,
  `DRIPFEED_RETURNED_COUNT`, `DRIPFEED_REVEALED_SYSTEMS` and
  `DRIPFEED_CHANGED_SYSTEMS` (space-separated system folder names) to refresh only
  what changed. Dripfeed ships no frontend-specific command.
- **`TOUCH_ON_REVEAL`** (default `1`): after a reveal is safely recorded, updates the
  date of the revealed file (or of a disc folder and the files directly inside it).
  Contents are untouched. Set `0` to keep original dates.

---

## Dos and don'ts

**Do**
- Run the **scheduler from a computer or SSH**, where typing names and dates is easy.
- Use ISO dates (`YYYY-MM-DD`) — they sort chronologically and never get ambiguous.
- Stage **multi-disc games as a folder** containing the discs and the `.m3u` (e.g. a
  `Saturn/Shiny Forts III` folder holding the disc images + `Shiny Forts 3.m3u`).
- Just open the Dripfeed script after a big update if power-on reveals ever stop —
  it self-heals and re-adds the boot hook automatically.
- Make sure the console's **clock is set** (RTC / network time). Reveals are
  date-based, so a wrong clock means wrong-day reveals.
- Keep a backup of your SD card before first use, as with any MiSTer tinkering.
- If you use a graphical frontend with its own library, refresh that library once
  after upgrading Dripfeed and again after reveal days.

**Don't**
- Don't rename a game *after* staging it expecting saves to carry over — the
  reveal name is whatever follows the `YYYY-MM-DD_` prefix.
- Don't expect Dripfeed to manage games on a USB drive or network share, and don't
  put `.dripfeed-library` on a *different* drive than `games/`. Dripfeed only
  manages the SD card's `games/` folder, where every move is an instant rename. A
  move that would cross drives is refused and logged (nothing is copied), and
  `--diag` warns about it. MiSTer also looks for a system's games on USB before the
  SD card, so a game revealed on the SD card can be hidden behind a USB folder of
  the same system name.
- Don't hand the scheduler to the kid on the TV — the **announcement** is the
  kid-facing part; scheduling is the parent's.
- Don't expect a game whose name already exists in the system folder to reveal —
  it's skipped and logged, so you don't clobber an existing save.
- Don't manually edit files inside `.dripfeed` unless you keep the
  `YYYY-MM-DD_` prefix intact (malformed entries are ignored).

---

## How it works (one paragraph)

`dripfeed-schedule.sh` moves a file into `.dripfeed-library/<SYS>/` and prefixes it
with `YYYY-MM-DD_`. `dripfeed-engine.sh --watch` is started at boot (and only at
boot, never at shutdown) by a hook in `user-startup.sh`; it reveals due items
immediately, then wakes hourly to catch the date rolling over. Revealing converts
the ISO prefix to an integer, compares it to today, and if due, renames the item up
to `games/<SYS>/` with the prefix stripped — after checking that both places are on
the same card, so the move is a rename and never a copy — logging it and queuing an
announcement. One lock keeps the engine, Undrip, and the command-line scheduler from
moving games at the same time. Opening `Dripfeed.sh` from the
Scripts menu flushes those queued announcements to the screen one at a time,
waiting on a controller button between each.

---

## Files

```
Dripfeed-Scheduler.html              visual scheduler — open in Chrome/Edge (no install)
Scripts/Dripfeed.sh                  visible Scripts-menu entry (controller-only announcer; self-heals boot hook)
Scripts/.dripfeed/dripfeed-common.sh shared functions (dates, button-wait, occasions, config)
Scripts/.dripfeed/dripfeed-engine.sh reveal engine + boot/daily watcher
Scripts/.dripfeed/dripfeed-schedule.sh date/staging tool (CLI + guided menu)
Scripts/.dripfeed/dripfeed-install.sh installer / uninstaller (boot hook)
Scripts/.dripfeed/config.ini         settings, created on first use
Scripts/.dripfeed/occasions.tsv      custom banners (date -> message), created on first use
Scripts/.dripfeed/revealed.tsv       durable history used by incremental scheduling
Scripts/.dripfeed/schedule-requests.tsv   browser requests awaiting an atomic card-side move
Scripts/.dripfeed/unschedule-requests.tsv browser return requests awaiting the card-side engine
Scripts/.dripfeed/transactions/      in-flight reveal journal (normally empty)
Scripts/.dripfeed/.lock/             single-runner lock; its owner file names the running pass
Scripts/.dripfeed/watch.pid          the boot watcher's process ID
Scripts/.dripfeed/showcase_names     every What's New folder name Dripfeed has stamped
Scripts/.dripfeed/system_shortcut_dirs  per-system shortcut folder names Dripfeed has used
Scripts/.dripfeed/gotm_names         Game of the Month folders Dripfeed has built
Scripts/.dripfeed/post_reveal.log    output of the last POST_REVEAL_CMD run
games/<SYS>/_Dripfeed New/           optional per-system shortcuts (SYSTEM_SHORTCUTS=1 only)
games/<SYS>/_Game of the Month/      optional GOT'eM pick shortcut (SYSTEM_SHORTCUTS=1 only)
Scripts/.dripfeed/gotm_system_shortcuts  the GOT'eM shortcuts Dripfeed put in system folders
```

The three name records let a later run tidy up old folders and let Undrip remove
exactly the folders Dripfeed created, even after you change a prefix or folder
name.

## Troubleshooting (real-hardware notes)

- **A revealed game doesn't show right away.** The MiSTer menu caches a folder's
  listing while it's open. Reveals happen at boot *before* you browse, so normally
  it's already there. If you reveal mid-session (via the Dripfeed script), **back out
  of the system folder and re-open it** (or switch INI / reload the core) to refresh
  the list.
- **A graphical frontend shows every game in a system, or none of the new ones.**
  Frontends that build their own library from system folders list a system as its
  whole folder and only notice changes when you refresh their library. Waiting games
  live outside `games/`, so a refresh after upgrading removes stale entries, and a
  refresh after a reveal day adds the new games. They never show the top-level
  What's New folder; see
  [Graphical frontends with their own library](#graphical-frontends-with-their-own-library).
- **A previously scanned library still lists held-back games.** New schedules wait
  outside `games/`, so a fresh file scan cannot see them. A tool that cached the
  old locations (including search, random-game, and attract-mode indexes) may retain
  stale entries until its own library is refreshed.
- **The log says a move was refused because it would cross drives.** The game, the
  card's `games/`, or that system folder is really on a USB drive, a network share,
  or another mount. Dripfeed left everything where it was. Keep scheduled games on
  the SD card's `games/`; `--diag` shows which folders are affected.
- **"Dripfeed is busy".** Another pass (usually the boot watcher) holds the lock.
  Wait for it to finish and try again; a lock left by a crash or power cut is
  cleared automatically.
- **An older build left both a visible and waiting copy of a disc folder.** Do not
  run Undrip as a cleanup shortcut. Copy both folders off-card first, then follow
  [`RECOVERY.md`](RECOVERY.md). The current reset keeps collisions in a recovery
  folder instead of deleting either side.

## Safe incremental behavior (v1.1–v1.4)

- A card-side `Scripts/.dripfeed/revealed.tsv` ledger records each successful
  reveal. The scheduler marks those entries **unveiled** and will not re-hide them
  during a later CSV update unless the explicit re-hide override is enabled.
- Whole-card browser changes first appear as **MOVE PENDING**. Put the card back
  in MiSTer and open Dripfeed once (or boot with its hook enabled); the engine
  applies the requested schedule/re-date/return atomically, then clears the
  request receipt.
- The scheduler supports selecting all systems and inverting the visible selection,
  making “hide everything except these few” a deliberate, fast workflow. Collision
  checks protect existing ROMs, while the card-side engine—not the browser—moves
  whole multi-disc folders.
- Firmware/support content is protected end-to-end. MegaCD region folders such as
  `USA`, `Japan`, and `Europe` are inspected and hidden when they contain BIOS
  firmware; Jaguar `.mrq` marquee files are also hidden. The CLI and reveal engine
  refuse to stage or reveal these entries, so they stay beside the games where the
  core expects them.
- Dates are checked as real calendar dates, not only by shape. Legacy cards still
  work; the new launcher/helpers add the ledger as reveals happen.
- **Nothing happens at power-on.** Dripfeed waits `BOOT_DELAY` seconds (default 30)
  so it doesn't race the firmware coming up. Check
  `/media/fat/Scripts/.dripfeed/boot.log` and `dripfeed.log`. Increase
  `BOOT_DELAY` in `config.ini` if your card is slow.
- **The boot hook lives in `linux/user-startup.sh`** (the *active* file). MiSTer's
  `_user-startup.sh` with the underscore is only a dormant template and is never run
  — the installer creates the real `user-startup.sh` for you.
- **Diagnose anything:** run `Scripts/.dripfeed/dripfeed-engine.sh --diag` over SSH.
  It prints paths, whether games and the waiting library share a drive, whether
  the boot hook is installed (and whether it is the current start-only version),
  who holds the lock, today's date, the full queue with which items are due, and
  warnings for system folders on USB, network storage, or the card root that MiSTer
  opens before `games/`. If it says the boot hook is outdated, open Dripfeed once.
  Every run also appends to `Scripts/.dripfeed/dripfeed.log`.
- **Scripts use hardcoded `/media/fat` paths**, not `$0`, so they run no matter how
  the menu launches them. (Set `DRIPFEED_ROOT` only when testing on a desktop.)
- **State lives in the hidden `Scripts/.dripfeed/`** (config, logs, occasions), NOT a
  visible `_Dripfeed` folder — so it never shows as an empty menu category. If you
  have a leftover empty `_Dripfeed` folder from an older version, delete it.
- **"Press any button" reads a single keypress**, so any controller button advances
  (older builds waited for ENTER, which made other buttons type characters).
- **The "What's New" folder name is length-capped** (`SHOWCASE_MAXLEN`, default 30,
  including the prefix) and stripped of characters the menu can't display. The
  default is `New <weekday> <Mon DD, YY>` — e.g. **"New Fri Jan 20, 26"** — which
  with the prefix is exactly 30 chars. The stock menu shows only about 21 characters
  of a top-level folder name (after the leading `_`) on a row that isn't selected,
  followed by `<DIR>`; the selected row scrolls to show the whole name. So the
  default name reads `Dripfeed - New Fri Ja` until you highlight it. To see the date
  at a glance, use a shorter prefix: `SHOWCASE_PREFIX="_DF "` shows the whole
  `DF New Fri Jan 20, 26`. Custom messages longer than the cap are trimmed for the
  folder name only (the full text still shows on the banner and in gamelist.xml);
  keep them ≈18 chars. Renaming the folder on each unlock also means a stock
  **Recent cores** entry for a shortcut inside it stops working; `SHOWCASE_DATE=0`
  keeps one fixed name (except on a day with a custom message).

## Development

- **[STAGING_SPEC.md](STAGING_SPEC.md)** is the single source of truth for the queue
  format both schedulers (web + CLI) and the engine must agree on.
- **`tests/run.sh`** seeds a fake card under a temporary `DRIPFEED_ROOT` and runs
  the regression suite: install, schedule, reveal, hold-back, firmware guards,
  multi-disc, showcase/`.mgl`/gamelist, interruption recovery, no-overwrite, config
  tolerance, GOT'eM, reset, and idempotent install. Run `bash tests/run.sh`.
- `tests/csv-contract.test.js` checks the CSV and Game of the Month path contract,
  and `tests/scheduler-logic.test.js` runs the scheduler's own browser code
  (calendar export, request ledgers, rename-only moves, folder inspection) against
  in-memory folders. Both run with Node.js.
- The repository-level `.github/workflows/test.yml` runs the full suite on every
  push and pull request.
- Editing helpers: change `Scripts/.dripfeed/*.sh`, then regenerate the single-file
  `Scripts/Dripfeed.sh` with `tools/sync-launcher.sh`, which embeds them. Bump
  `DRIPFEED_VERSION` in the launcher so installed cards re-extract the helpers.
- See **[CHANGELOG.md](CHANGELOG.md)**.

## Credits

The "What's New" shortcut folder adapts the per-core `.mgl` mapping and Favorites
approach from **wizzo's MiSTer_Favorites / mrext** (GPL-3.0), and uses the `.mgl`
format and menu conventions from **MiSTer-devel**. The visual scheduler's calendar
export and the save-safe design follow standard MiSTer practice. Full list in the
repo-level [CREDITS.md](../CREDITS.md). Thank you to the MiSTer community.

## License

**GPL-3.0** — see `LICENSE`. (Chosen to match the MiSTer community norm and because
the `.mgl` core map is adapted from the GPL-3.0 `mrext` project — see CREDITS.md.)
Contributions and forks welcome.
