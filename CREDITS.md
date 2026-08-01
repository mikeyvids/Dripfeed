# Credits and acknowledgements

Dripfeed and its companion MiSTer QoL suite are vibed by **MikeyVids** and built
on community-documented formats and conventions.

- **MiSTer-devel** — MiSTer FPGA, `.mgl` files, the
  `linux/user-startup.sh` convention, menu-folder behavior, current Wi-Fi
  documentation, and the maintained official `wifi.sh` library interface used
  by Wifi-Swap. Wifi-Swap does not bundle or fork that helper.
  <https://github.com/MiSTer-devel>
- **Porkchop Express / MiSTerAddons and the RetroPie contributors** — the
  original MiSTer port and upstream foundation of the official Wi-Fi helper.
  Wifi-Swap delegates its adapter, WPA, DHCP, and health operations to that
  installed GPLv3-or-later helper. <https://github.com/RetroPie/RetroPie-Setup>
- **wizzo (Callan Barrett)** — MiSTer_Favorites / `mrext`. Dripfeed adapts the
  GPLv3 `MGL_MAP`, `SET_NAMES`, and Favorites-style shortcut approach.
  <https://github.com/wizzomafizzo/mrext>
- **theypsilon (José Manuel Barroso Galindo)** — Downloader_MiSTer / `update_all`,
  whose preserved-card behavior informs the install layout.
  <https://github.com/MiSTer-devel/Downloader_MiSTer>
- **The rclone contributors** — the optional cloud transport, provider
  configuration, and reusable OAuth-token handling used by Back the Files Up.
  This repository does not bundle rclone; users obtain the official Linux ARMv7
  build separately. <https://rclone.org>
- **odelot**, **manyhats-mike**, and the RetroAchievements/MiSTer community —
  the parallel-folder and startup-hook deployment patterns that informed the
  non-destructive design. <https://retroachievements.org>

Development used AI coding assistance under the author's direction. Source,
tests, and release artifacts are reviewed before publication. If an upstream
credit is incomplete, please open an issue so it can be corrected.
