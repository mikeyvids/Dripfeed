# Frontend-neutral output notes

Dripfeed + GOT'eM use standard MiSTer files and menu conventions. They do not
modify a frontend, its private database, its settings, or its binaries.

## What is written

- Revealed games return to their normal `games/<SYSTEM>/` location under their
  exact original name, so saves, artwork, and any per-game data a frontend keeps
  by path still match.
- What's New and GOT'eM use ordinary top-level menu folders.
- Console, computer, and handheld shortcuts are standard `.mgl` files. A
  multi-disc shortcut points at the first disc image (`.cue` or `.chd`), never at
  an `.m3u` playlist, because MiSTer cores mount disc images.
- Arcade GOT'eM picks copy the existing `.mra` and its matching core into the
  generated spotlight folder; the originals remain untouched. The core is matched
  the way the MiSTer firmware matches it (exact name or `Arcade-` name, newest
  version), so a similarly named core is never copied by mistake.
- `gamelist.xml` carries friendly names, each game's real reveal date, and the
  full occasion message for software that understands EmulationStation-style
  metadata. Names with `&`, `'`, or `<` are escaped so the file stays valid XML.
- With `TOUCH_ON_REVEAL=1` (the default), a revealed file's date is set to the
  moment of its reveal. Contents are never changed.
- Optional, off by default: `.mgl` shortcuts inside each system folder
  (`SYSTEM_SHORTCUTS=1`, see below).

## Menu placement

The default What's New folder begins with `_Dripfeed - `. To pin it nearer the
top of the stock MiSTer menu, use:

```ini
SHOWCASE_PREFIX="_@Dripfeed - "
```

The stock menu shows about 21 characters of a top-level folder name (after the
leading `_`) on a row that isn't selected; the selected row scrolls to show the
rest. Keep the part you need to read, such as the date, near the front.

The optional `FAVORITES_MIRROR=1` setting copies `.mgl` shortcuts into the
stock-menu/mrext `_@Favorites` layout, always into one stable subfolder
(`_@Favorites/_Dripfeed New`) so old dated copies do not pile up. It does not
write to any application's private favorites database, and it never removes
favorites you made yourself.

## Graphical frontends that build their own library from system folders

Some setups replace the stock menu with a graphical frontend that scans the system
folders (`games/SNES`, `games/PSX`, …) into a library of its own and browses that
library instead of the card. Dripfeed treats these frontends like any other
reader of standard files. What to expect:

- **A system shows every game in its folder.** These frontends present a system as
  the whole contents of its folder, usually sorted by name, with no "new" view.
  Dripfeed keeps waiting games outside `games/` (in the hidden
  `/.dripfeed-library/`), so a fresh library lists only games that have been
  released.
- **Top-level menu folders never appear.** What's New and `_Game of the Month`
  live at the top of the card, where the stock menu lists them next to the cores.
  A frontend that only looks inside system folders never sees them, whatever their
  prefix. Open them from the stock menu, or use `SYSTEM_SHORTCUTS` below.
- **The library is a snapshot.** Such frontends usually update their library only
  when you ask (a refresh, rescan, or library update):
  - *After upgrading Dripfeed*, refresh once. Older versions kept the waiting queue
    inside `games/<SYSTEM>/.dripfeed/`, where some library and search tools listed
    held games early with date-prefixed names. The upgrade moves that queue outside
    `games/`; a refresh then removes the stale entries.
  - *After a reveal*, refresh again; new games appear only after the frontend
    rescans. After a pass that revealed games, Dripfeed's console summary says so:
    "Using a graphical frontend with its own game library? Refresh its library to
    see the new games."
- **`POST_REVEAL_CMD` can run the refresh for you.** If your frontend offers a
  command or script that refreshes its library on the MiSTer, set it here.
  Dripfeed runs it once (through `sh -c`) at the end of any run that changed the
  system folders: games revealed, games hidden by scheduling, games put back, or
  Dripfeed's own system-folder shortcuts (What's New, GOT'eM) added or removed.
  It has a 120-second time limit. Its output goes to
  `Scripts/.dripfeed/post_reveal.log` and its exit status to `dripfeed.log`; it
  can read `DRIPFEED_REVEALED_COUNT`, `DRIPFEED_HIDDEN_COUNT`,
  `DRIPFEED_RETURNED_COUNT`, `DRIPFEED_REVEALED_SYSTEMS` and
  `DRIPFEED_CHANGED_SYSTEMS` to refresh only the systems that changed. It never
  runs from the shutdown path, on a run that changed nothing, or on a computer
  with the card mounted, and it is empty by default. Dripfeed does not ship or guess a command for any particular
  frontend.

  ```ini
  POST_REVEAL_CMD="/media/fat/Scripts/my-library-refresh.sh"
  ```

- **`SYSTEM_SHORTCUTS=1` puts What's New inside each system folder.** Every
  What's New shortcut is mirrored into `games/<SYSTEM>/_Dripfeed New/` (the name
  comes from `SYSTEM_SHORTCUTS_DIR`). Inside a system folder the shortcut is named
  after the game alone, without the `SYSTEM - ` prefix. Each system keeps its
  newest `SHOWCASE_KEEP` shortcuts. Undrip removes these folders, and setting
  `SYSTEM_SHORTCUTS=0` removes them on the next run. Trade-offs to accept before
  turning it on:
  - it is per system; there is no single list across systems;
  - the shortcuts are `.mgl` files in system folders, so tools that index `.mgl`
    files there (search, random-game, attract-mode) list each new game twice: the
    game itself and its shortcut;
  - in the stock menu's file browser for that core, `_Dripfeed New` appears as a
    folder that looks empty, because cores do not list `.mgl` files;
  - the frontend still needs a library refresh before the folder appears.

  The games never move into this folder; it holds only small shortcuts that point
  at the real files.
- **The same option covers GOT'eM.** A console or computer Game of the Month pick
  also gets a shortcut in `games/<SYSTEM>/_Game of the Month/` (the community pick
  in `_Discord GOTM`; both follow your GOT'eM folder names). It changes with the
  month, and is removed when the option is switched off and by Undrip. Arcade
  picks stay in the top-level GOT'eM folder only, because arcade games have no
  system folder under `games/`. Only shortcuts Dripfeed wrote are ever removed.

## Where games must live

Dripfeed manages games in the SD card's `games/` folder only. The waiting library
sits on the same card, so every schedule, reveal, and return is an instant rename.
When the card's `games/` or one of its system folders is really a USB drive, a
network share, or another mount (a symlink, or a share mounted over it), Dripfeed
refuses the move rather than copying a large game across drives, logs why, and
`--diag` warns about it. Games kept only on USB or network storage are outside
Dripfeed. MiSTer looks for a system's games on USB and network storage before the
SD card, so a USB folder with the same system name can also hide games Dripfeed
revealed on the card.

## GOT'eM is independent of the drip

GOT'eM highlights games that already exist on the card. It does not hide,
rename, or relocate the original game. Personal and optional community picks can
appear in parallel folders, and a hidden Dripfeed game waits until its reveal
date before GOT'eM builds a launchable spotlight for it.

## Compatibility boundary

Different menu programs decide for themselves which folders they show and when
they refresh their libraries. This project guarantees standard on-card files and
stock-menu behavior only. Test one `.mgl`, one Arcade `.mra`, and one multi-disc
item on the exact software build you use before scheduling a large library.
