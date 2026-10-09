# Hardware Golden Path

Desktop tests cannot emulate MiSTer's menu, controller devices, network clock,
graphical menu indexing, or a real rclone remote. Before calling a release hardware-
verified, complete these checks on a backed-up or disposable card.

## Dripfeed

- Install `Dripfeed/Scripts/Dripfeed.sh`; reboot once and confirm the boot hook.
- On an upgraded card, run the migration-only engine once and confirm every old
  `games/<system>/.dripfeed/` entry moved to `/.dripfeed-library/<system>/`
  without revealing a due game. Confirm incomplete disc sets remain held.
- After upgrading, confirm `linux/user-startup.sh` holds the new start-only hook
  block (one copy). Reboot and power off from the menu, then confirm `boot.log`
  was written by the boot only and no watcher started during shutdown.
- Refresh the graphical frontend/library database and confirm no unreleased
  entry from `/.dripfeed-library/` appears in its system browser. A previously
  cached title may remain until that frontend completes its own rescan.
- Schedule one cartridge ROM, one CHD, and one multi-disc folder for today.
- Confirm firmware folders and Jaguar `.mrq` files never appear as games.
- Confirm clean reveal names, What's New launch, and GOT'eM console + Arcade
  launch in the stock MiSTer menu.
- Launch a multi-disc What's New shortcut (PSX or Saturn, `.m3u` + `.cue/.chd`)
  and confirm the core boots disc 1; confirm the `.mgl` path does not end in
  `.m3u`.
- Launch What's New shortcuts for one Jaguar and one Neo Geo Pocket game, and one
  Game Gear file kept in the Master System folder, on the current core builds.
- Reveal one title containing `&` and one containing `'`; reboot twice and confirm
  both What's New shortcuts survive and `gamelist.xml` still opens as valid XML.
- Pick a GOT'eM Arcade game whose core name is a prefix of another core (for
  example `jtcps1` beside `jtcps15`) and confirm the copied core is the right,
  newest one and the spotlight launches.
- In the stock core list, read the What's New folder row unselected and selected:
  about 21 characters show before `<DIR>`, and the selected row scrolls the rest.
- On a disposable card, bind-mount a USB drive folder over one scheduled system's
  `games/<system>`, then repeat with a symlink to the USB drive instead. In both
  cases confirm its reveal and browser requests are refused with a log line,
  nothing is copied, and `--diag` warns. Separately, with a USB drive
  holding `games/<system>` beside the SD card's, confirm `--diag` warns that
  MiSTer browses the USB folder first.
- Start a long manual pass over SSH, then open Undrip and the CLI scheduler from
  a second session; confirm both report busy and move nothing until it finishes.
- Leave `TOUCH_ON_REVEAL=1` and confirm a revealed file's date shows the reveal
  time while the stock menu lists and launches it normally.
- In a graphical frontend that builds its own library from system folders,
  refresh its library after a reveal day and confirm the new games appear and
  nothing from `/.dripfeed-library/` is listed. Set a test `POST_REVEAL_CMD` (for
  example a script that appends a line to a file), reveal one game, and confirm
  it ran once, its exit status is in `dripfeed.log`, and it never ran at shutdown.
- Turn on `SYSTEM_SHORTCUTS=1`, reveal games in two systems, refresh the
  frontend's library, and confirm each system shows a `_Dripfeed New` folder whose
  shortcuts launch. Confirm the stock core file browser shows that folder without
  breaking normal browsing. Set it back to `0` and confirm the next run removes
  every `_Dripfeed New` folder; run Undrip once with it on and confirm the same.
- Interrupt power once only on a disposable card, then confirm the next boot logs
  `RECOVERED reveal after interruption` and creates no duplicate.

### Dripfeed Scheduler (browser)

- On a disposable card, connect the whole card and schedule a few thousand games
  across systems in one batch; confirm it completes in seconds and each request
  file is written once.
- Review a CSV with hundreds of unknown paths; confirm the tab stays responsive
  and each NOT FOUND row offers a type-to-pick list.
- Connect only the `games/` folder (limited mode) on Windows and macOS. Schedule
  one large CHD with a preview or antivirus scan holding the file open, and
  confirm the real error is shown, no `.crswap` file appears, and the game is not
  moved or copied.
- Export `.ics`, re-date one game, export again, and import both into one
  calendar app; confirm the event moves rather than duplicating, and the optional
  9 AM alert fires on the day.

## Profiler

- Create three disposable profiles, add credentials later to one, and switch in
  both Scripts and the generated menu folder.
- Confirm saves, save states, RA identity, and HDMI wallpaper follow the profile.
- Archive a dormant profile and confirm it remains under `profiles/.archive/`.

## Back the Files Up

- Open `Backup/Back-the-Files-Up-Setup.html` in Chrome/Edge/Brave, connect a
  disposable card, and confirm the fixed include/exclude cards match the script.
- Run **Check my setup** with no helper, a wrong-architecture helper, an
  unfinished cloud authorization, and a finished authorization. Confirm it
  identifies exactly one safe next action in each state and installs repaired
  launcher/engine files only after confirmation.
- Run `backtheFup.sh --dry-run live` and `backtheFup.sh --dry-run profiler`.
- Create both archives and verify their checksum and manifest off-card.
- On a disposable card, use **Restore from a local backup** to restore: all live
  data; one live aspect; every profile; one profile; and one aspect of one
  profile. Confirm unselected data remains unchanged.
- Confirm each restore first creates a new local `Before_Restore` archive.
- Tamper with a disposable copy of an archive and confirm checksum verification
  stops before any live data changes.
- Interrupt a disposable restore after its first replacement and confirm the
  original data is rolled back on exit. Never power-cut a card holding the only
  copy of real saves for this test.
- Confirm Dripfeed engine state is present in the live archive and can be
  selectively restored; confirm waiting game payloads, ROMs, and unrelated media
  are absent.
- Configure an ARMv7 rclone build and one shared test remote. Check over Wi-Fi,
  then over Ethernet if used; confirm archive, checksum, and manifest arrive in
  `live` and `profiler` remote folders without a second browser sign-in.
- Revoke the disposable OAuth grant, confirm cloud check fails while local backup
  still completes, then replace authorization through the wizard.
- Confirm the active profile remains visible in `_Profiler - <Active>` and the
  Profiler archive filename while the archive itself contains every profile.
- Confirm the Profiler archive also contains the active profile's top-level
  saves, save states, achievements settings, wallpapers, and menu image.
- Copy one cloud archive and its `.sha256` sidecar back to `_Backups/` and confirm
  the local restore picker can use it; direct cloud browsing is not in v1.5.

## Wifi-Swap

- With a current official MiSTer `wifi.sh` installed, confirm its normal
  status/diagnostics screen still works before adding Wifi-Swap. Separately test
  the cache-helper fallback on a disposable card with the installed helper absent.
- On a disposable or backed-up card, use Wifi-Swap Registry in Chrome/Edge/Brave
  to create **Home** and **Phone Hotspot**. Confirm no web request is made and no
  plain-text password appears under `Scripts/.wifi-swap/`.
- Import compatible networks remembered by the normal MiSTer Wi-Fi setup.
  Confirm each appears once, its original unmarked configuration block remains
  unchanged, and unsupported or duplicate networks are explained and skipped.
- With a compatible USB Wi-Fi adapter, connect to Home from
  `Scripts/wifi-swap.sh`; verify the SSID, IPv4 lease, internet/DNS health, and
  correct network-clock synchronization.
- Run `wifi-swap.sh --diagnose` and confirm the credential-free report identifies
  the helper, adapter/interface, profile count, configuration health, SSID, and IP.
- Switch to Phone Hotspot with the controller. Expect SSH/CIFS/browser sessions
  carried by Home to end; verify the hotspot receives a fresh IPv4 lease.
- Edit the hotspot to a deliberately incorrect password and try it once. Confirm
  Wifi-Swap reports failure, restores Home's configuration/country, and leaves
  **Last connected** on Home.
- Remove the failed test profile in the Registry, run one successful switch, and
  confirm its marked block is gone while an unmarked network saved through the
  official `wifi.sh` remains unchanged.
- Test one hidden SSID if the household uses one. Test travel-country switching
  only in the country represented by that two-letter regulatory code.
- Interrupt one Registry write only on a disposable card, then confirm an
  incomplete profile is ignored. Interrupt one MiSTer switch after the config
  transaction and confirm the next boot has a complete, parseable
  `linux/wpa_supplicant.conf`.
