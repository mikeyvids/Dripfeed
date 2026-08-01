# Frontend-neutral output notes

Dripfeed + GOT'eM use standard MiSTer files and menu conventions. They do not
modify a frontend, its private database, or its binaries.

## What is written

- Revealed games return to their normal `games/<SYSTEM>/` location.
- What's New and GOT'eM use ordinary top-level menu folders.
- Console, computer, and handheld shortcuts are standard `.mgl` files.
- Arcade GOT'eM picks copy the existing `.mra` and matching core into the
  generated spotlight folder; the originals remain untouched.
- `gamelist.xml` carries friendly names, dates, and the full occasion message for
  software that understands EmulationStation-style metadata.

## Menu placement

The default What's New folder begins with `_Dripfeed - `. To pin it nearer the
top of the stock MiSTer menu, use:

```ini
SHOWCASE_PREFIX="_@Dripfeed - "
```

The optional `FAVORITES_MIRROR=1` setting copies `.mgl` shortcuts into the
stock-menu/mrext `_@Favorites` layout. It does not write to any application's
private favorites database.

## GOT'eM is independent of the drip

GOT'eM highlights games that already exist on the card. It does not hide,
rename, or relocate the original game. Personal and optional community picks can
appear in parallel folders, and a hidden Dripfeed game waits until its reveal
date before GOT'eM builds a launchable spotlight for it.

## Compatibility boundary

Different menu programs decide for themselves which top-level folders they show
and when they refresh their indexes. This project guarantees standard on-card
files and stock-menu behavior only. Test one `.mgl`, one Arcade `.mra`, and one
multi-disc item on the exact software build you use before scheduling a large
library.
