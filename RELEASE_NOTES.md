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
