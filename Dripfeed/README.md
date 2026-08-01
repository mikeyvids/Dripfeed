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

**Bulk import (CSV).** The **Import CSV** tab takes `path, date, message` rows (a
header row is auto-detected) — e.g. `MegaDrive/Shiny Forts.md, 2026-07-10,` or
`Saturn/Shiny Forts III, 5/25/2027, Happy Towel Day!`. Paste or choose a file,
click **Review**, and you get a per-row check: dates are normalized (ISO,
`M/D/YYYY`, etc.), missing files are flagged with a **drop-down to pick the right
file**, and anything you don't want can be **skipped** — then schedule the OK rows in
one click. There's a **blank template** download and a **schedule → CSV** export for
round-tripping with a spreadsheet.

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

---

## Features

- Power-on **and** daily reveals (no `cron` needed — a tiny boot watcher handles both).
- One-at-a-time on-screen announcements with **controller button-to-continue**
  (reads `/dev/input/js0`; falls back to ENTER on a keyboard).
- **"What's New" menu folder** (`.mgl` shortcuts, Favorites-style): every unlock also
  drops a shortcut into a top-level menu folder named **`_Dripfeed - New Fri Jul 3, 26`**
  — or your custom message for that day (`_Dripfeed - Happy Birthday Deme` — trimmed to the OSD width). Each shortcut's
  name shows the system (`GENESIS - Shiny Forts`). It holds the newest `SHOWCASE_KEEP`
  unlocks (default 12). The name is **sticky**: it changes only when games actually
  unlock, and the custom message stays until the next unlock — simply powering the
  console on never renames the folder. This is the
  on-screen "announcement" that needs no changes to the MiSTer main — it just appears
  in the menu like recently-played. Uses absolute-path `.mgl` files with the core
  mapping taken from this firmware's own `favorites.sh`. Set `SHOWCASE=0` to disable.
  (Jaguar's core mapping is a best-guess — verify it on your build.)
- **Custom occasion banners**: tie a message to a date ("Happy Birthday Player One");
  it shows as a big banner above the games that unlock that day. Set it in the
  visual tool's message box or with `dripfeed-schedule.sh message`.
- **Calendar export**: the visual tool's **Export to Calendar (.ics)** button turns
  your whole queue into all-day events (one per game, on its reveal date) with the
  custom banner text in each event's notes — import it into Apple/Google/Outlook
  Calendar to see the drip schedule at a glance.
- Multi-disc support: stage a **folder** (discs + `.m3u`) and it's revealed intact.
- Multi-disc safety: the browser writes a tiny move request; the MiSTer-side
  engine performs the whole-folder same-card move. The browser never recursively
  copy/deletes a disc set.
- Punctuation-safe names: commas, ampersands, apostrophes, and spaces remain exact.
- Clean reveals: the date prefix is stripped, so the final filename is exactly
  what the core/saves/RetroAchievements expect.
- Safe by default: never overwrites an existing game; logs every reveal to
  `Scripts/.dripfeed/dripfeed.log`.
- Re-datable: scheduling an already-staged item just updates its date.
- Cross-platform scheduler (Linux/MiSTer + macOS/BSD date handling).

---

## Configuration (`/media/fat/Scripts/.dripfeed/config.ini`)

```ini
GAMES_DIR=/media/fat/games
STAGE_DIRNAME=.dripfeed
STAGING_ROOT=/media/fat/.dripfeed-library
WAIT_BUTTON=1        # 1 = wait for a controller button between each new game
WAIT_TIMEOUT=0       # keyboard-only fallback timeout, seconds (0 = wait forever)
REVEAL_AT_BOOT=1     # reveal due games at power-on
DAILY=1              # also reveal once per calendar day while powered on
WATCH_INTERVAL=3600  # seconds between day-change checks
```

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

**Don't**
- Don't rename a game *after* staging it expecting saves to carry over — the
  reveal name is whatever follows the `YYYY-MM-DD_` prefix.
- Don't put `.dripfeed-library` on a *different* drive than `games/`; reveals use
  a fast same-filesystem move.
- Don't hand the scheduler to the kid on the TV — the **announcement** is the
  kid-facing part; scheduling is the parent's.
- Don't expect a game whose name already exists in the system folder to reveal —
  it's skipped and logged, so you don't clobber an existing save.
- Don't manually edit files inside `.dripfeed` unless you keep the
  `YYYY-MM-DD_` prefix intact (malformed entries are ignored).

---

## How it works (one paragraph)

`dripfeed-schedule.sh` moves a file into `.dripfeed-library/<SYS>/` and prefixes it
with `YYYY-MM-DD_`. `dripfeed-engine.sh --watch` is started at boot by a hook in
`user-startup.sh`; it reveals due items immediately, then wakes hourly to catch
the date rolling over. Revealing converts the ISO prefix to an integer, compares
it to today, and if due, `mv`s the item up to `games/<SYS>/` with the prefix
stripped — logging it and queuing an announcement. Opening `Dripfeed.sh` from the
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
```

## Troubleshooting (real-hardware notes)

- **A revealed game doesn't show right away.** The MiSTer menu caches a folder's
  listing while it's open. Reveals happen at boot *before* you browse, so normally
  it's already there. If you reveal mid-session (via the Dripfeed script), **back out
  of the system folder and re-open it** (or switch INI / reload the core) to refresh
  the list.
- **A previously scanned library still lists held-back games.** New schedules wait
  outside `games/`, so a fresh file scan cannot see them. A tool that cached the
  old locations may retain stale entries until its own library is refreshed.
- **An older build left both a visible and waiting copy of a disc folder.** Do not
  run Undrip as a cleanup shortcut. Copy both folders off-card first, then follow
  [`RECOVERY.md`](RECOVERY.md). The current reset keeps collisions in a recovery
  folder instead of deleting either side.

## Safe incremental behavior (v1.1–v1.3)

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
  It prints paths, whether the boot hook is installed, today's date, and the full
  queue with which items are due. Every run also appends to
  `Scripts/.dripfeed/dripfeed.log`.
- **Scripts use hardcoded `/media/fat` paths**, not `$0`, so they run no matter how
  the menu launches them. (Set `DRIPFEED_ROOT` only when testing on a desktop.)
- **State lives in the hidden `Scripts/.dripfeed/`** (config, logs, occasions), NOT a
  visible `_Dripfeed` folder — so it never shows as an empty menu category. If you
  have a leftover empty `_Dripfeed` folder from an older version, delete it.
- **"Press any button" reads a single keypress**, so any controller button advances
  (older builds waited for ENTER, which made other buttons type characters).
- **The "What's New" folder name is length-capped** (`SHOWCASE_MAXLEN`, default 30) to
  the OSD's visible width and stripped of illegal characters, so the date/message
  isn't cut off mid-word. The default is `New <weekday> <Mon DD, YY>` — e.g.
  **"New Fri Jan 20, 26"** — which with the prefix is exactly 30 chars. Custom messages
  longer than the cap are trimmed for the folder name only (the full text still shows on
  the banner and in gamelist.xml); keep them ≈18 chars.

## Development

- **[STAGING_SPEC.md](STAGING_SPEC.md)** is the single source of truth for the queue
  format both schedulers (web + CLI) and the engine must agree on.
- **`tests/run.sh`** seeds a fake card under a temporary `DRIPFEED_ROOT` and runs
  69 checks: install, schedule, reveal, hold-back, firmware guards, multi-disc,
  showcase/`.mgl`/gamelist, interruption recovery, no-overwrite, config tolerance,
  GOT'eM, reset, and idempotent install. Run `bash tests/run.sh`.
- The repository-level `.github/workflows/test.yml` runs the full suite on every
  push and pull request.
- Editing helpers: change `Scripts/.dripfeed/*.sh`, then the single-file `Scripts/Dripfeed.sh`
  is regenerated from them (it embeds them with a version bump).
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
