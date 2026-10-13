# Unreleased

- Renames the visible backup entry to **backtheFup.sh** and adds the offline
  **Back the Files Up - Setup** wizard.
- Hard-locks live backup to saves, save states, RetroAchievements configuration,
  Dripfeed schedule/state, `config/`, and `MiSTer.ini`; Profiler backup contains the full `profiles/`
  tree plus the active player's live saves, save states, achievements settings,
  wallpapers, and menu image. ROMs and unrelated media are excluded.
- Adds one shared household rclone destination for the whole MiSTer and all
  profiles, Wi-Fi/Ethernet cloud checks, reusable OAuth guidance, authorization
  removal, safe legacy-setting import, and exact-boundary regression tests.
- Adds a guided **Restore from a local backup** workflow for all live data, all
  profiles, one profile, or one selected aspect. Restores verify archive/checksum,
  reject unsafe contents, create a Before Restore safety archive, stage on-card,
  and roll back an incomplete replacement.
- Adds **Wifi-Swap 0.1.0**, an offline Home/Hotspot/Travel network Registry and
  MiSTer profile picker layered on the current official `wifi.sh` library API.
- Preserves unowned official networks, marks only Wifi-Swap-owned WPA blocks,
  derives WPA keys locally without retaining a plain-text password, and restores
  the previous configuration/country after a failed switch.
- Adds disposable-card coverage plus real-adapter, controller, DHCP, hotspot,
  hidden-network, and power-interruption steps to the Golden Path.

# Dripfeed + GOT'eM 1.4.2

Safety fixes from an outside review of 1.4.1. No new options; existing
schedules, folders and settings are kept. Open `Dripfeed.sh` once on MiSTer
after copying it so the helpers update. Full details are in
[`Dripfeed/CHANGELOG.md`](Dripfeed/CHANGELOG.md).

## Highlights

- **CSV import you can trust.** A blank or day-first date is a repair row, not a
  blank page; a failed import keeps your rows and pasted text for a retry and
  says, per row, what went wrong; a review that cannot finish says why.
- **Writes land on the right card.** A browser write that was still waiting when
  you reconnected another card is refused instead of overwriting that card's
  ledger, GOT'eM pick or settings. Keep one browser tab per card.
- **Nothing is lost on a full card.** A reveal whose ledger row cannot be written
  keeps its journal, is retried on the next hourly tick, and is recorded as soon
  as the card can be written; a journal Dripfeed cannot resolve is kept aside and
  shown by `--diag`.
- **One pass at a time, always.** Reclaiming a crashed run's lock can no longer
  preempt a starter that got there first; a lock set aside by a run that died is
  swept with the other scratch files.
- **Hold, don't guess.** A browser request for a game with both a queued and a
  visible copy stays pending and is flagged by `--diag`.
- **Undrip asks twice,** says plainly what the second press does, and asks the
  second question only once the button has been released, so a held button never
  answers both.
- **The waiting library is marked** with an empty `.zaparooignore` file that some
  library indexers honour; it is the only frontend-specific file Dripfeed writes.

## Verification

- Card simulation 223 checks, scheduler browser logic 31, suite-level 36, all
  passing. New checks cover the lock race, the collision hold, the unwritable
  ledger and its hourly retry, the held and incomplete journals, the scratch-file
  sweep, the two presses and the held button, the marker placement, and three
  release guards: the version matches the CHANGELOG, a card on an older version
  is updated, and the launcher's embedded helpers are byte-identical to
  `Scripts/`.
- Hardware steps for `GOLDEN_PATH.md`: update an existing card and use Undrip
  from the launcher; Undrip with one press, with two, and with a held key and a
  held controller button (must not reset); a frontend that scans the card root
  must not list waiting games.

# Dripfeed + GOT'eM 1.4.1

Large libraries, large games, and graphical frontends, including GOT'eM picks in
system folders. Full details are in
[`Dripfeed/CHANGELOG.md`](Dripfeed/CHANGELOG.md).

## Highlights

- **No game data is ever copied.** On the card, every move is checked to be a
  same-card rename; a move that would cross to a USB drive, network share, or
  other mount is refused and logged instead of turning into a copy+delete. In
  the browser, the copy fallback is gone: whole-card mode writes requests for
  MiSTer, and games-folder-only mode renames a single file or shows the real
  error.
- **Safer runs.** The lock is never taken from a pass that is still running,
  Undrip and the command-line scheduler share it, and the boot hook no longer
  starts at shutdown. Leftover browser swap files and empty entries are held,
  not revealed.
- **Fixes for large libraries.** CSV review of sheets with many unknown paths no
  longer exhausts browser memory; scheduling 8,500 games takes about a second
  with one write per request file; card-side queue processing scales linearly.
- **Better shortcuts.** Multi-disc shortcuts open the first disc instead of the
  `.m3u`; shortcuts for names with `&` or `'` are no longer pruned; the `.mgl`
  core map follows the current upstream catalog; GOT'eM copies the exact Arcade
  core; `gamelist.xml` is valid and carries real reveal dates.
- **Graphical frontends.** Plain-language guidance for frontends that build their
  own library from system folders, plus three standard-file options:
  `SYSTEM_SHORTCUTS` (opt-in per-system `_Dripfeed New` shortcut folders, plus
  the GOT'eM pick in `games/<SYSTEM>/_Game of the Month/`),
  `POST_REVEAL_CMD` (run a refresh command you supply after games are revealed,
  hidden or put back), and
  `TOUCH_ON_REVEAL` (a revealed file's date shows its reveal time). Dripfeed
  still never writes to a frontend's database, settings, or binaries.
- **Calendar export fixed.** Stable event IDs, `SEQUENCE`, correct escaping and
  line folding, and an optional 9 AM alert.

## Verification

- The Dripfeed disposable-card regression suite, the CSV/GOT'eM contract, the
  new scheduler browser-logic tests, and the suite-level checks pass.
- The suite no longer bans a third-party product name; it still scans for
  leaked credentials, vault paths, and host paths.
- New hardware steps for these changes are in `GOLDEN_PATH.md`.

# Dripfeed 1.2.0 — MiSTer QoL Suite

The first public Dripfeed repository release packages three independently
installable tools under one GPLv3-or-later project. Dripfeed + GOT'eM are the main experience;
Profiler and Backup are optional companions in the same suite.

## Included

- **Dripfeed + GOT'eM 1.2.0** — incremental scheduling, console and Arcade
  showcases, firmware/support guards, multi-disc folder support, offline web
  scheduler, and journal-based recovery after an interrupted reveal.
- **Profiler 0.4.0** — non-destructive player profile creation, switching,
  archiving, optional per-profile RetroAchievements credentials, wallpapers,
  responsive web management, and immediate menu refresh.
- **Backup 1.2.0** — independently verified live and Profiler archives, ZIP and
  tar fallback, ZIP/tar-aware rolling retention, manifests, SHA-256 sidecars,
  and optional rclone upload of all three artifacts.

## Verification

- 64 Dripfeed disposable-card and regression checks.
- 18 cross-component checks covering Profiler, Backup, web interfaces, shell
  syntax, CSV/GOT'eM behavior, and the public/private boundary.
- Responsive visual inspection at desktop and 390-pixel mobile widths.

The native browser directory picker, real MiSTer hardware, network-clock boot,
controller navigation, graphical menu indexing, and real rclone authorization
remain hardware/account checks documented in `GOLDEN_PATH.md`.
