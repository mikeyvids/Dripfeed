# Back the Files Up for MiSTer FPGA (v1.5.0)

**Back the Files Up** makes small, verified archives of the MiSTer data that is
hard to replace. It keeps local copies on the SD card and can also send them to
one shared Google Drive—or another remote supported by rclone.

The visible MiSTer menu script is exactly `backtheFup.sh`. The computer-side
helper is **Back the Files Up - Setup**.

## The five-year-old version

1. Open `Back-the-Files-Up-Setup.html` on a computer.
2. Press **Connect SD card** and choose the whole MiSTer card.
3. Pick **Local** or **Google Drive** and follow the cards on screen.
4. Put the card back in MiSTer.
5. Open Scripts → `backtheFup.sh` → **Back up everything now**.

To put data back, open the same script and choose **Restore from a local
backup**. Pick the backup, then choose everything, every player, one player, or
one part such as saves. The script checks the archive and makes a local safety
copy before it changes live data.

The script builds the backup locally first, checks that it opens correctly, and
only then gives it its final name. If Wi-Fi or the cloud fails, the verified
local archive stays safe in `/media/fat/_Backups/`.

## Exact backup boundary

This list is fixed in the engine. Setup cannot silently add more folders.

| Archive | Included |
|---|---|
| Live MiSTer | `saves/`, `savestates/`, `retroachievements.cfg`, small settings from `config/`, `MiSTer.ini`, and `Scripts/.dripfeed/` |
| Profiler | the complete `profiles/` tree plus the active player's live `saves/`, `savestates/`, `wallpapers/`, `retroachievements.cfg`, and `menu.png`/`menu.jpg` |

It deliberately does **not** back up ROMs, disc images, `_Arcade`, unrelated
media, screenshots, or rebuildable databases/caches/thumbnails/logs found under
`config/`. Before compression, the script prints the size of each protected
source so a surprise payload is visible before a long run. Dripfeed's settings,
occasion schedule, reveal ledger, and recovery journal are included. The queued
game files themselves are not backup payloads; after a lost card, restore games
from the library's original source.

The Profiler archive is intentionally complete and slightly redundant: it holds
every dormant/archived player and the active player's live-owned files. That
means restoring a player does not depend on remembering which separate archive
held their current saves, save states, achievements identity, wallpaper, or menu
image. The filename carries the active profile as a useful visual receipt, but
the archive still contains **all** profiles.

## Install or update

Copy these into `/media/fat/Scripts/`, preserving the hidden helper folder:

```text
Scripts/backtheFup.sh
Scripts/.backthefup/backtheFup-engine.sh
Scripts/.backthefup/backtheFup.conf
```

If only `backtheFup.sh` is present, first run creates the hidden folder and
downloads the current engine from this repository. If the console is offline,
copy the hidden folder as shown above.

If the old `Scripts/.backup/` exists, the new engine imports compatible
retention, destination, `rclone.conf`, and rclone-binary settings once. It never
imports the old editable include list, so an older custom include list cannot
cross the new boundary. After one successful backup and cloud check, the old
`Scripts/Backup.sh` and `Scripts/.backup/` can be removed to avoid two menu
entries.

Archives use names such as:

```text
MiSTer_Live_2026_07_28_153000.zip
2026_07_28_153000_Player_One_Profiler.zip
```

Each final archive has a `.sha256` checksum and `.manifest.txt` receipt. The
default keeps the newest eight live and eight Profiler archives locally. Remote
history is not automatically pruned.

## The setup wizard

Open [`Back-the-Files-Up-Setup.html`](Back-the-Files-Up-Setup.html) in current
Chrome, Edge, or Brave. Your configuration stays local. The page makes only one
kind of optional network request: it repairs a missing plain-text launcher or
engine from this repository. It never uploads card data.

The wizard can:

- show the fixed included/excluded boundary;
- repair a missing visible launcher or hidden engine directly into the correct
  card folders;
- run **Check my setup** and state the one next action in plain language;
- configure local-only backup;
- accept a pasted or selected `rclone.conf`;
- list the named remotes found in that file;
- validate that the chosen `rclone` file is a Linux ARMv7 program, then copy it
  directly into the correct hidden folder;
- choose a destination folder and local retention count;
- remove cloud authorization from the card without deleting cloud data.

This release uses one shared household destination for the whole MiSTer and all
Profiler profiles (`BACKUP_SCOPE=all-profiles`). A future version may ask whether
authorization is shared or per-player, but this release does not create separate
player cloud accounts.

## Does cloud backup work over Wi-Fi?

Yes. rclone uses whatever working internet connection MiSTer has—Wi-Fi or
Ethernet. Cloud use needs:

- a working route and DNS;
- a believable date/time so HTTPS certificates can be checked;
- the Linux ARMv7 rclone binary;
- a valid saved rclone authorization;
- enough connection time to finish the upload.

Network loss does not invalidate the local archive. Run `backtheFup.sh` →
**Check cloud connection** after changing Wi-Fi profiles or replacing OAuth.

## Do I authenticate every time?

Normally, no. In the **Terminal app on a computer**, run `rclone config` and
press Return. That command—not text pasted into a browser address bar—opens the
provider's real sign-in once. The resulting `rclone.conf` contains a refresh token, and rclone uses it to
renew short-lived access automatically. Re-authorize only if you revoke access,
the provider expires it, an administrator changes policy, or you replace the
remote.

For Google Drive, most users should leave Client ID and Client Secret blank. The
`drive.file` scope is a privacy-friendly choice because it limits rclone to files
and folders it creates. A custom Google Cloud OAuth app is optional; a custom app
left in Google's Testing state can have short-lived refresh tokens.

Official references:

- [rclone downloads](https://rclone.org/downloads/)
- [Google Drive setup](https://rclone.org/drive/)
- [headless/remote setup](https://rclone.org/remote_setup/)

## MiSTer controls and command line

Running Scripts → `backtheFup.sh` offers:

- **Back up everything now** — recommended; makes both archives;
- **Restore from a local backup** — guided, selective, and rollback-safe;
- **Check cloud connection** — tests authorization without making an archive;
- **Show exactly what is protected** — dry, read-only explanation;
- **Back up live MiSTer files only**;
- **Back up every complete player profile**.

SSH examples:

```sh
/media/fat/Scripts/backtheFup.sh all
/media/fat/Scripts/backtheFup.sh live
/media/fat/Scripts/backtheFup.sh profiler
/media/fat/Scripts/backtheFup.sh restore /media/fat/_Backups/ARCHIVE.zip profiles all
/media/fat/Scripts/backtheFup.sh restore /media/fat/_Backups/ARCHIVE.zip 'profile:Player One' saves
/media/fat/Scripts/backtheFup.sh restore /media/fat/_Backups/ARCHIVE.zip live savestates
/media/fat/Scripts/backtheFup.sh --dry-run live
/media/fat/Scripts/backtheFup.sh --status
/media/fat/Scripts/backtheFup.sh --check-cloud
```

## Optional boot schedule

This example runs on Sunday **only if MiSTer boots that Sunday**:

```sh
#=====BACKTHEFUP_WEEKLY=====
( D=$(date +%u); [ "$D" = "7" ] && /media/fat/Scripts/backtheFup.sh all >/media/fat/_Backups/last.log 2>&1 ) &
#=====BACKTHEFUP_WEEKLY_END=====
```

It is not a battery-backed scheduler. A manual run after an important session or
before `update_all` remains sensible.

## Restore

Exit any running game before restoring. Scripts → `backtheFup.sh` → **Restore
from a local backup** walks through:

1. the local ZIP or tar backup in `_Backups/`;
2. live MiSTer data, every profile, or one named profile;
3. everything in that scope or one aspect;
4. one final confirmation.

Live backups can restore all live data or only game saves, save states,
RetroAchievements settings, Dripfeed schedule/state, `config/`, or `MiSTer.ini`. Profiler backups can
restore every player or one player, with all data or only saves, save states,
RetroAchievements settings, wallpapers, or menu image.

Before changing live data, the engine:

- verifies that the archive opens;
- compares its SHA-256 sidecar when one is present;
- rejects unsafe paths, unexpected top-level files, and symbolic links;
- extracts into a same-card staging folder;
- makes a new local **Before Restore** safety archive;
- swaps only the selected data and automatically rolls it back if the operation
  stops before completion.

Restart MiSTer after a restore so cores and menu art reopen the restored files
cleanly. Version 1.5.0 chooses local archives only. To restore a cloud copy, first
download/copy its archive and matching `.sha256` into `_Backups/`.

## Limitations

- This is a data archive, not a bootable SD-card image or ROM backup.
- Test one disposable restore before depending on any backup system.
- Archives are not encrypted. `retroachievements.cfg` may contain a credential;
  protect local and cloud copies like a password.
- rclone authorization is stored on the SD card at
  `Scripts/.backthefup/rclone.conf` with restricted permissions where supported.
  It is not included in the backup archive.
- If both the SD card and its local `_Backups/` die before a cloud upload
  completes, that newest local-only copy is lost. Keep at least one off-card copy.

## License

GPL-3.0-or-later — see [`../LICENSE`](../LICENSE).
