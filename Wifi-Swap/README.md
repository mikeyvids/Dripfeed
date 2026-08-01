# Wifi-Swap

Wifi-Swap gives a MiSTer several named Wi-Fi choices—such as **Home**, **Phone
Hotspot**, and **Travel**—without making you type credentials with a controller.
It is independent of Profiler: a Wi-Fi profile is a network, not a player.

Wifi-Swap is intentionally a small layer over MiSTer's current official
`wifi.sh`. Its helper remains responsible for adapter detection,
`wpa_supplicant`, DHCP, connection health, and restoring other saved networks.
Wifi-Swap adds only the friendly Registry and profile picker.

## What to copy

| File | Where it goes | Job |
|---|---|---|
| `Wifi-Swap-Registry.html` | Keep on a computer | Offline editor for network profiles on a mounted MiSTer SD card. |
| `Scripts/wifi-swap.sh` | `/media/fat/Scripts/wifi-swap.sh` | MiSTer Scripts-menu picker that safely installs/selects a Registry profile. |

Wifi-Swap uses a compatible installed official `wifi.sh` when available. If that
helper is absent or too old, the script can cache the current official helper in
its own hidden folder when MiSTer already has internet; it does not overwrite the
installed script. If the console is offline, update `wifi.sh` through MiSTer
Downloader first.

## Five-minute setup

1. Back up the SD card.
2. Copy `wifi-swap.sh` to the card's `Scripts/` folder.
3. On a computer, open `Wifi-Swap-Registry.html` in current Chrome, Edge, or
   Brave.
4. Click **Connect SD card** and choose the card's root—the folder containing
   both `Scripts` and `linux`.
5. If MiSTer already remembers a compatible connection, press **Import existing
   MiSTer Wi-Fi**. Otherwise add a friendly profile such as `Home` and enter the
   network name, password, and country where MiSTer is operating.
6. Safely eject the card. On MiSTer, open **Scripts → wifi-swap.sh** and choose
   the network.

The Registry never switches a running console. It prepares the card; the script
does the actual switch on MiSTer.

## Where the settings really live

MiSTer Wi-Fi credentials do **not** live in `MiSTer.ini`. The standard active
file is:

```text
/media/fat/linux/wpa_supplicant.conf
```

Wifi-Swap's friendly source profiles live separately under:

```text
/media/fat/Scripts/.wifi-swap/profiles/
```

When you choose a profile, the script validates the Registry, makes a same-card
temporary file and backup, replaces only blocks marked `WIFI-SWAP`, validates
the result with the official helper, gives the selected block a unique internal
ID and highest priority, and atomically installs it. Unmarked networks created
by official `wifi.sh` are preserved.

The Registry can read compatible WPA/WPA2 Personal and open connections already
present in `wpa_supplicant.conf` and copy them into friendly Wifi-Swap profiles.
It does not rename, tag, edit, or remove the originals, and it never renders a
saved key on screen. Connections using enterprise login, captive portals, WEP,
or unsupported WPA3-only settings are skipped instead of guessed.

The official scan may list the same network name more than once because one
router can advertise separate 2.4, 5, or 6 GHz radios. Those are access points,
not duplicate Wifi-Swap profiles. The Registry saves one friendly choice per
profile; Wifi-Swap selects its exact internal ID instead of guessing by name.

The Registry converts an 8–63-character WPA/WPA2 password to the standard
64-digit WPA key using PBKDF2-SHA1 (4096 rounds) in the browser. It writes no
plain-text password, uses no server, and makes no network request. The resulting
WPA key is still a usable credential; protect the SD card and backups like a
password.

## Safety and rollback

- The standard config is validated before and after every managed change.
- Replacement is a same-filesystem temporary-file rename, so the canonical file
  is never deliberately left half-written.
- A failed connection restores the previous standard config and regulatory
  country, then asks the official helper to reconnect the prior network.
- The **Last connected** profile changes only after a successful connection.
- A five-minute stale-lock timeout prevents two Wifi-Swap runs from writing at
  once without leaving the feature permanently locked after power loss.
- If power fails after the atomic file change, the installed file is still a
  complete validated WPA configuration. The official Wi-Fi service can use it
  again at boot; a uniquely named pre-change backup may remain beside it.

Always keep an off-card backup. Atomic replacement protects this particular
write; it cannot protect a failing card or unrelated filesystem corruption.

## Script commands

Normal controller use needs no command line. For terminal testing:

```sh
bash /media/fat/Scripts/wifi-swap.sh --list
bash /media/fat/Scripts/wifi-swap.sh --status
bash /media/fat/Scripts/wifi-swap.sh --diagnose
bash /media/fat/Scripts/wifi-swap.sh --connect PROFILE_ID
```

Profile IDs appear in square brackets in `--list`. Labels and SSIDs remain the
friendly text shown in the Registry.

## What it supports

- One compatible USB Wi-Fi adapter and one active Wi-Fi network at a time.
- Named home, hotspot, and travel profiles.
- WPA/WPA2 Personal passwords or precomputed 64-digit WPA keys.
- Open networks without a password.
- Hidden SSIDs.
- A per-profile two-letter regulatory country.
- Updating credentials later by editing the Registry profile.
- Preserving saved networks not owned by Wifi-Swap.
- One-click import of compatible networks remembered by MiSTer's normal Wi-Fi
  setup, without exposing or modifying its original connection blocks.

## What it does not do

- It does not enable Wi-Fi hardware through `MiSTer.ini`; the DE10-Nano has no
  built-in Wi-Fi radio. A supported USB adapter is required.
- It does not manage Profiler player profiles, saves, RetroAchievements, or
  wallpapers.
- It does not support WPA-Enterprise/802.1X, browser sign-in/captive portals,
  hotel-room terms pages, WEP, or SAE-only WPA3 networks.
- It cannot keep SSH, CIFS, network storage, or a browser session alive while
  moving away from the network carrying that connection.
- It cannot guarantee a hotspot is awake, in range, or willing to issue an IP.
- The browser Registry requires the File System Access API. Safari and Firefox
  cannot grant the needed card-folder write access.

If Wifi-Swap reports an invalid standard configuration, stop and use the
official `wifi.sh` **Repair WPA config** command. It deliberately refuses to
guess at or rewrite malformed network data.

## Test without a real card

From the repository root:

```sh
bash Wifi-Swap/tests/run.sh
```

The test creates a disposable fake card and official-helper test double. It
checks exact internal-ID selection, marked-block ownership, preservation of an
official network, country application, exact rollback, active-profile behavior,
remembered-network parsing, and the no-plaintext-password boundary. Real
adapter, controller, DHCP, and hotspot checks remain in the repository's
`GOLDEN_PATH.md`.

## License and upstream relationship

GPL-3.0-or-later. Wifi-Swap calls a compatible installed official `wifi.sh` or
caches an unmodified current copy through that script's library interface. See
the repository `CREDITS.md` for upstream authorship and links.
