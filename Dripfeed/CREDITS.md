# Credits & Acknowledgements

These tools stand on the shoulders of the MiSTer FPGA community. Thank you to
everyone whose work made them possible.

## Methods and code we adapted or built on

- **MiSTer-devel** — the MiSTer FPGA platform itself, the `.mgl` (MiSTer Game Link)
  file format, the `linux/user-startup.sh` boot-hook convention, and the
  underscore-prefixed top-level menu folder behavior we rely on.
  <https://github.com/MiSTer-devel>
- **wizzo (Callan Barrett)** — **MiSTer_Favorites / mrext**. Dripfeed's "What's New"
  shortcut folder adapts the per-core `.mgl` parameter table (`MGL_MAP`) and
  `SET_NAMES`, and follows the Favorites folder approach. (GPL-3.0)
  <https://github.com/wizzomafizzo/mrext>
- **theypsilon (José Manuel Barroso Galindo)** — Downloader_MiSTer / `update_all`,
  the update system everything here is designed to stay compatible with.
  <https://github.com/MiSTer-devel/Downloader_MiSTer>
- **odelot** and **manyhats-mike** — the MiSTer RetroAchievements fork and its
  deployment toolkit, whose `user-startup.sh` + parallel-folder pattern inspired our
  "survive `update_all`" approach. RetroAchievements: <https://retroachievements.org>

If your work belongs on this list and isn't here, please open an issue — credit is
important to us and the omission would be a mistake, not a slight.

## A note on how this was built

These tools were designed and written with the help of an AI coding assistant,
directed and tested by the author. Everything was reviewed and verified before
release. Flagged in the spirit of transparency.
