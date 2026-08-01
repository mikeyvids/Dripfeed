# Hardware Golden Path

Desktop tests cannot emulate MiSTer's menu, controller devices, network clock,
graphical menu indexing, or a real rclone remote. Before calling a release hardware-
verified, complete these checks on a backed-up or disposable card.

## Dripfeed

- Install `Dripfeed/Scripts/Dripfeed.sh`; reboot once and confirm the boot hook.
- On an upgraded card, run the migration-only engine once and confirm every old
  `games/<system>/.dripfeed/` entry moved to `/.dripfeed-library/<system>/`
  without revealing a due game. Confirm incomplete disc sets remain held.
- Refresh the graphical frontend/library database and confirm no unreleased
  entry from `/.dripfeed-library/` appears in its system browser. A previously
  cached title may remain until that frontend completes its own rescan.
- Schedule one cartridge ROM, one CHD, and one multi-disc folder for today.
- Confirm firmware folders and Jaguar `.mrq` files never appear as games.
- Confirm clean reveal names, What's New launch, and GOT'eM console + Arcade
  launch in the stock MiSTer menu.
- Interrupt power once only on a disposable card, then confirm the next boot logs
  `RECOVERED reveal after interruption` and creates no duplicate.

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
