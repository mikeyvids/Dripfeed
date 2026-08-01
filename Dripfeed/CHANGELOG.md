# Changelog — Dripfeed

## Unreleased

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
