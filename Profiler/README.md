# Profiler — player profiles for MiSTer FPGA (v0.5.0, reliable menu switching)

One MiSTer, several players. Each profile owns its own **game saves, save
states, RetroAchievements login, and wallpapers**. Switching uses same-filesystem
renames with preflight checks and rollback on a failed step — no symlinks
(FAT/exFAT can't do them), no copying of big files, and nothing is ever deleted
(removed profiles are archived).

## Install
Copy `Profiler.sh` to `/media/fat/Scripts/`. Done.

## Use (on the MiSTer)
Two ways to switch:

1. **Fastest:** Scripts → `Profiler - <Active Name>` → **Switch to <Other>**.
   These are real executable MiSTer scripts, so the selection performs the swap.
2. **Manager:** Scripts → `Profiler.sh` opens the picker with create/archive
   controls as well.

The top-level `_Profiler - <Name>` folder is now only a visual indicator of
who is active. Older `.mgl` switch entries relied on behavior MiSTer does not
guarantee; this release removes those entries and its background watcher.

## Manage (on your computer)
Open **Profiler-Manager.html** in Chrome/Edge/Brave, connect the SD card:
create/edit profiles, set RA username+password, add a wallpaper. Archive is
non-destructive → `profiles/.archive/`.

After connecting, the manager links to the dedicated **Back the Files Up - Setup**
wizard. That offline page configures local/cloud backup in one place, so Profiler
does not maintain a second partial copy of rclone settings.

The matching Back the Files Up v1.5 tool stores the complete `profiles/` tree
and the active player's live saves, save states, achievements settings,
wallpapers, and menu image in one complete Profiler archive (for example
`2026_07_28_Player_1_Profiler.zip`). The active player's name is a receipt in the
filename; the archive still contains every profile and each profile's owned
files. Its MiSTer menu can restore every player, one player, or one selected
aspect after verifying the archive and making a Before Restore safety copy. Do
not mix this engine with the older `_Profiles` package without its migration
notes.

## Design notes
- Active profile's files live in their normal stock locations, so every core,
  tool, and update behaves exactly as usual. Only inactive profiles are parked
  under `/media/fat/profiles/<Name>/`.
- Swapped items: `saves/`, `savestates/`, `wallpapers/`,
  `retroachievements.cfg`, `menu.png/jpg` (list is one variable in the script).
- Wizzo's `setname` suggestion (per-core alt identity) is great for a *single
  shared core* needing split saves, but for whole-library profiles it would
  need wrapper .mgl files for every game+profile combo — the rename-swap keeps
  the stock layout untouched, which is the same philosophy as Dripfeed.
- Wallpapers/background: on 15 kHz CRT output the menu shows the noise pattern
  because the framebuffer (which draws wallpapers) needs the scaler; wallpapers
  show on HDMI. That's a MiSTer video-path fact, not a Profiler limitation.

## Boundaries and limitations

- One profile is active at a time; Profiler does not merge saves or sync them to
  another MiSTer.
- Return to the menu before switching. The generated Scripts-menu command is the safest
  route because no game core is writing a save. Do not force a switch over SSH
  while a game is running.
- The web manager needs Chrome, Edge, or Brave's local File System Access API. It
  creates/edits/archives card data but does not switch the running console.
- RetroAchievements credentials use MiSTer's standard plain-text
  `retroachievements.cfg`. The web page keeps them local, but the SD card does not
  encrypt them.
- This is a whole-library player profile, not a per-game or per-core profile.
- Archive is deliberately non-destructive, but restoring an archived profile is
  currently a manual folder move from `profiles/.archive/`.
