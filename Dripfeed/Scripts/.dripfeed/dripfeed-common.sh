#!/bin/bash
# Dripfeed for MiSTer FPGA — GPL-3.0-or-later
# Copyright (C) 2026 MikeyVids
# See ../../LICENSE for the full license and CREDITS.md for upstream acknowledgements.
# dripfeed-common.sh — shared library for the Dripfeed toolkit (MiSTer FPGA).
#
# IMPORTANT (hardware lesson): on MiSTer, scripts are launched in ways where $0 is
# not always a usable path, so we DO NOT resolve our own location from $0. Every
# path is hardcoded under /media/fat (overridable by env vars for desktop testing),
# exactly like the stock MiSTer scripts do.
#
# PERFORMANCE NOTE: MiSTer runs this on a dual Cortex-A9 where every fork+exec
# costs milliseconds. Per-entry loops therefore use bash builtins only, and
# lookups across the whole queue are done in ONE awk pass, never per item.

# ---- Base locations (env overrides are for desktop testing only) ------------
DF_ROOT="${DRIPFEED_ROOT:-/media/fat}"
DF_SCRIPTS="$DF_ROOT/Scripts"
DF_HELP="$DF_SCRIPTS/.dripfeed"
DF_STATE="${DRIPFEED_STATE:-$DF_HELP}"   # state lives in hidden Scripts/.dripfeed (NOT a
                                         # visible _Dripfeed folder, which showed as an
                                         # empty category in the menu)
DF_CONFIG="$DF_STATE/config.ini"
DF_LOG="$DF_STATE/dripfeed.log"
DF_PENDING="$DF_STATE/pending_announce.log"
DF_LASTDAY="$DF_STATE/.last_run_day"
DF_LEDGER="$DF_STATE/revealed.tsv"    # durable history: date<TAB>system<TAB>name<TAB>timestamp
DF_TX_DIR="$DF_STATE/transactions"    # power-loss journal for the one in-flight reveal
DF_OCCASIONS="$DF_STATE/occasions.tsv"
DF_SCHEDULE_REQUESTS="$DF_STATE/schedule-requests.tsv"   # browser -> card-side atomic moves
DF_UNSCHEDULE_REQUESTS="$DF_STATE/unschedule-requests.tsv"
DF_SHOWNAME="$DF_STATE/showcase_name"    # the CURRENT showcase folder name (sticky:
                                         # only rewritten when a reveal unlocks games,
                                         # so ordinary boots never rename the folder)
DF_SHOWNAMES="$DF_STATE/showcase_names"  # record of EVERY showcase name ever stamped, so
                                         # old folders are consolidated and Undrip removes
                                         # exactly what Dripfeed created
DF_SYSDIRS="$DF_STATE/system_shortcut_dirs"   # record of per-system shortcut folder names
DF_GOTM_NAMES="$DF_STATE/gotm_names"     # record of Game of the Month folders built
DF_GOTM_MIRRORS="$DF_STATE/gotm_system_shortcuts"   # GOT'eM shortcuts put in system folders
                                         # ("<folder base><TAB><file>"); only these are removed
DF_WATCHPID="$DF_STATE/watch.pid"        # the boot watcher (pid, boot id)
DF_POSTLOG="$DF_STATE/post_reveal.log"   # output of the last POST_REVEAL_CMD run
DF_GOTM="$DF_STATE/gotm.tsv"             # Game of the Month schedule: YYYY-MM<TAB>path
                                         # (path relative to /media/fat, e.g.
                                         #  games/SNES/Chrono Trigger (USA).sfc or
                                         #  _Arcade/Robotron 2084.mra)
DF_GOTM_LAST="$DF_STATE/.gotm_built"     # what's currently built (month|path), so the
                                         # folder is only rebuilt when the pick changes
DF_USERSTARTUP="$DF_ROOT/linux/user-startup.sh"   # active boot hook (NOT _user-startup.sh)
DF_MEDIA="${DRIPFEED_MEDIA:-${DF_ROOT%/*}}"       # /media: where MiSTer mounts USB/network
DF_US=$'\037'                            # field separator for internal records (never in a
                                         # FAT file name, unlike tabs-as-whitespace for read)
DF_FAV_SUBDIR="_Dripfeed New"            # ONE stable Favorites mirror subfolder
DF_FRONTEND_HINT="Using a graphical frontend with its own game library? Refresh its library to see the new games."

# ---- Defaults (config.ini overrides these) ----------------------------------
GAMES_DIR="$DF_ROOT/games"
STAGE_DIRNAME=".dripfeed"
# New queues live outside games/. This prevents library scanners from seeing
# held-back titles and keeps a complete multi-disc folder together as one atomic
# rename. STAGE_DIRNAME remains supported as a read-only legacy location so an
# existing queue is never stranded after upgrading.
STAGING_ROOT="$DF_ROOT/.dripfeed-library"
REVEAL_AT_BOOT=1
DAILY=1
WATCH_INTERVAL=3600    # seconds between day-change checks (never below 60)
BOOT_DELAY=30          # seconds to wait at power-on before the first reveal, so we
                       # don't race the firmware/menu still coming up
SHOWCASE=1             # build the "What's New" menu folder of .mgl shortcuts
SHOWCASE_PREFIX="_Dripfeed - "   # folder-name prefix (leading _ shows it in the menu;
                       # "_@Dripfeed - " pins it to the very top). The date or your custom
                       # message follows. Old folders are replaced, not duplicated.
SHOWCASE_DATE=1        # 1 = folder name carries the date of the LATEST unlock (or that
                       # day's custom message). 0 = fixed folder name (just the prefix,
                       # trimmed) — custom messages still apply on their day either way.
                       # In BOTH modes the name only ever changes when a game actually
                       # unlocks: booting the console never renames the folder.
SHOWCASE_MAXLEN=30     # cap the folder name length (incl. prefix)
SHOWCASE_KEEP=12       # max shortcuts kept in the folder (oldest pruned)
GAMELIST=1             # also write gamelist.xml — the FULL custom message rides here for
                       # software that reads gamelist.xml metadata.
FAVORITES_MIRROR=0     # (opt-in) also copy shortcuts into the stock-menu Favorites folder,
                       # always into the ONE subfolder _@Favorites/_Dripfeed New.
FAVORITES_DIR="_@Favorites"
SYSTEM_SHORTCUTS=0     # (opt-in) also mirror each What's New shortcut into
                       # games/<SYSTEM>/<SYSTEM_SHORTCUTS_DIR>/, and a console GOT'eM pick
                       # into games/<SYSTEM>/<GOT'eM folder name>/ — standard .mgl files that
                       # graphical frontends which build their own library from system
                       # folders can list after their library is refreshed.
SYSTEM_SHORTCUTS_DIR="_Dripfeed New"
POST_REVEAL_CMD=""     # optional shell command run ONCE after a run that revealed, hid or returned games
                       # (with a 120 s timeout; never at shutdown). Use it to ask a
                       # frontend to refresh its library.
TOUCH_ON_REVEAL=1      # 1 = set a revealed game's file date to the reveal time
GOTM=1                 # build the Game of the Month menu folder (from gotm.tsv)
GOTM_DIRNAME="_Game of the Month"   # leading _ shows it in the menu ("_@..." pins to top)
GOTM_MONTH=0           # 1 = append the month to the folder name ("... - Aug")
# ---- Community Game of the Month (hook; not yet surfaced in the scheduler UI) ----
# GOTM_SOURCE lets a COMMUNITY-published pick fill months you haven't picked yourself:
#   - a filesystem path: e.g. a tsv that an update_all custom database drops on the
#     card each month (Scripts/.dripfeed/gotm-community.tsv is the suggested target —
#     a downloader.ini db entry can deliver it, so it rides the normal update flow)
#   - an http(s) URL: fetched at reveal time (clock is already network-synced then)
#     into $DF_STATE/gotm-community.tsv and read from there
# File format: same as gotm.tsv (YYYY-MM<TAB>path-relative-to-/media/fat).
# LOCAL picks in gotm.tsv always win over community picks for the same month.
# FUTURE (TODO): support "YYYY-MM<TAB>SYSTEM<TAB>Title" lines with fuzzy filename
# matching, so a Discord post like "2026-08  SNES  Plok" can resolve against
# whatever the user's rom is actually called; surface an opt-in + source picker
# in the web scheduler's Game of the Month tab.
GOTM_SOURCE=""         # empty = local picks only
GOTM_SRC_DIRNAME="_Discord GOTM"   # menu folder for the community pick (runs in
                                   # PARALLEL with the user's Game of the Month;
                                   # GOTM_MONTH month-tag applies to both folders)

# ---- Small builtin helpers -----------------------------------------------------
# bash >= 4.2 formats times without spawning date(1); MiSTer ships bash 5.
if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 2 ]; }; then
  df_strftime() { printf -v "$1" "%($2)T" -1; }
else
  df_strftime() { eval "$1=\$(date +\"\$2\")"; }
fi
df_trim() {   # $1 = variable name: strip leading/trailing whitespace in place
  local v; eval "v=\${$1}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  eval "$1=\$v"
}
# Integer config value: non-numeric -> default, below minimum -> minimum.
df_cfg_int() {
  local v; eval "v=\${$1}"
  case "$v" in ''|*[!0-9]*) v="$2" ;; esac
  v=$((10#$v))
  [ "$v" -ge "$3" ] || v="$3"
  eval "$1=\$v"
}
# 0/1 config switch (also accepts yes/no, true/false, on/off).
df_cfg_flag() {
  local v; eval "v=\${$1}"
  case "$v" in
    1|[Yy]|[Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]) v=1 ;;
    0|[Nn]|[Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]) v=0 ;;
    *) v="$2" ;;
  esac
  eval "$1=\$v"
}
# A single folder name (no slashes, no FAT-illegal characters, never hidden).
df_cfg_dirname() {
  local v; eval "v=\${$1}"
  v="${v//[<>:\"\/\\|?*]/}"
  df_trim v
  case "$v" in ''|.*) v="$2" ;; esac
  eval "$1=\$v"
}

# Tolerant config reader: handles "KEY = value", comments, surrounding quotes, and
# only assigns whitelisted keys (no arbitrary code execution, unlike sourcing).
# A quoted value may contain '#'; an unquoted value ends at the first '#'.
df_load_config() {
  if [ -f "$DF_CONFIG" ]; then
    local line key val q
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in *=*) ;; *) continue ;; esac
      key="${line%%=*}"; val="${line#*=}"
      key="${key//[[:space:]]/}"
      df_trim val
      case "$val" in
        \"*) q='"' ;;
        \'*) q="'" ;;
        *) q="" ;;
      esac
      if [ -n "$q" ]; then
        val="${val#?}"
        case "$val" in *"$q"*) val="${val%%"$q"*}" ;; esac
      else
        val="${val%%#*}"; df_trim val
      fi
      case "$key" in
        GAMES_DIR|STAGE_DIRNAME|STAGING_ROOT|REVEAL_AT_BOOT|DAILY|\
        WATCH_INTERVAL|BOOT_DELAY|SHOWCASE|SHOWCASE_PREFIX|SHOWCASE_MAXLEN|SHOWCASE_KEEP|\
        GAMELIST|FAVORITES_MIRROR|FAVORITES_DIR|GOTM|GOTM_DIRNAME|GOTM_MONTH|SHOWCASE_DATE|\
        GOTM_SOURCE|GOTM_SRC_DIRNAME|SYSTEM_SHORTCUTS|SYSTEM_SHORTCUTS_DIR|POST_REVEAL_CMD|TOUCH_ON_REVEAL)
          eval "$key=\$val" ;;
      esac
    done < "$DF_CONFIG"
  fi
  [ -n "${DRIPFEED_GAMES:-}" ] && GAMES_DIR="$DRIPFEED_GAMES"
  [ -n "${DRIPFEED_STAGING:-}" ] && STAGING_ROOT="$DRIPFEED_STAGING"
  # Validate everything numeric: a bad value must never busy-loop the daemon
  # (WATCH_INTERVAL=0 used to spin a CPU core) or break a test expression.
  df_cfg_int WATCH_INTERVAL 3600 60
  df_cfg_int BOOT_DELAY 30 0
  df_cfg_int SHOWCASE_KEEP 12 1
  df_cfg_int SHOWCASE_MAXLEN 30 8
  df_cfg_flag REVEAL_AT_BOOT 1; df_cfg_flag DAILY 1; df_cfg_flag SHOWCASE 1
  df_cfg_flag SHOWCASE_DATE 1; df_cfg_flag GAMELIST 1; df_cfg_flag FAVORITES_MIRROR 0
  df_cfg_flag GOTM 1; df_cfg_flag GOTM_MONTH 0; df_cfg_flag SYSTEM_SHORTCUTS 0
  df_cfg_flag TOUCH_ON_REVEAL 1
  df_cfg_dirname SYSTEM_SHORTCUTS_DIR "_Dripfeed New"
  DF_GOTM_DIRS=()   # GOT'eM folder names follow the config just read
  df_cfg_dirname FAVORITES_DIR "_@Favorites"
  case "$STAGE_DIRNAME" in ''|*/*|.|..) STAGE_DIRNAME=".dripfeed" ;; esac
}

df_stage_dir() { printf '%s/%s' "$STAGING_ROOT" "$1"; }
df_legacy_stage_dir() { printf '%s/%s/%s' "$GAMES_DIR" "$1" "$STAGE_DIRNAME"; }

# ---- Queue index (one builtin-only walk, then awk joins) ----------------------
# Write one line per queue entry: SYSTEM<TAB>CLEAN-NAME<TAB>PATH<TAB>new|legacy.
# $2 limits the walk to one system. Paths are spelled exactly as df_stage_dir and
# df_legacy_stage_dir spell them, so callers can compare them as strings.
df_index_write() {
  local out="$1" only="${2:-}" stage sys entry base sysdir
  {
    if [ -n "$only" ]; then set -- "$STAGING_ROOT/$only/"; else set -- "$STAGING_ROOT"/*/; fi
    for stage in "$@"; do
      [ -d "$stage" ] || continue
      sys="${stage%/}"; sys="${sys##*/}"
      for entry in "$stage"*; do
        base="${entry##*/}"
        df_is_valid_prefix "$base" || continue
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        printf '%s\t%s\t%s\tnew\n' "$sys" "${base:11}" "$entry"
      done
    done
    if [ -n "$only" ]; then set -- "$GAMES_DIR/$only/"; else set -- "$GAMES_DIR"/*/; fi
    for sysdir in "$@"; do
      stage="$sysdir$STAGE_DIRNAME/"
      [ -d "$stage" ] || continue
      sys="${sysdir%/}"; sys="${sys##*/}"
      for entry in "$stage"*; do
        base="${entry##*/}"
        df_is_valid_prefix "$base" || continue
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        printf '%s\t%s\t%s\tlegacy\n' "$sys" "${base:11}" "$entry"
      done
    done
  } > "$out"
}

# Print every queued entry for one clean game name. Both the current queue and
# the older per-system queue are searched because an interrupted browser copy
# can leave the same title in more than one dated folder. (Builtins only.)
df_staged_clean_paths() {
  local sys="$1" clean="$2" stage entry base
  for stage in "$(df_stage_dir "$sys")" "$(df_legacy_stage_dir "$sys")"; do
    [ -d "$stage" ] || continue
    for entry in "$stage"/*; do
      base="${entry##*/}"
      df_is_valid_prefix "$base" || continue
      [ "${base:11}" = "$clean" ] || continue
      [ -e "$entry" ] && printf '%s\n' "$entry"
    done
  done
}

df_staged_clean_count() {
  df_staged_clean_paths "$1" "$2" | awk 'END { print NR + 0 }'
}

# Return 0 and print the path only when exactly one queued copy exists. Return 1
# for none and 2 for an ambiguous duplicate. Callers must hold on status 2.
df_find_staged_clean() {
  local matches count
  matches=$(df_staged_clean_paths "$1" "$2")
  count=$(printf '%s\n' "$matches" | awk 'NF { n++ } END { print n + 0 }')
  [ "$count" -eq 1 ] && { printf '%s\n' "$matches"; return 0; }
  [ "$count" -eq 0 ] && return 1
  return 2
}

# A queue entry is revealable only when it is complete:
#  - an interrupted browser copy leaves a 0-byte placeholder under the final queue
#    name (a real game image is never empty), so an empty FILE is held;
#  - an old copy-based folder move could leave the .dripfeed-incomplete marker;
#  - every disc a folder's .m3u/.cue references must be present.
df_queue_entry_complete() {
  [ -e "$1" ] || return 1
  if [ -d "$1" ]; then
    [ ! -e "$1/.dripfeed-incomplete" ] && df_disc_manifests_complete "$1"
  else
    [ -s "$1" ]
  fi
}

# ---- Disc manifests (.m3u / .cue) -------------------------------------------------
# Playlists come from Windows Notepad, playlist generators and other emulators:
# tolerate a UTF-8 byte-order mark, CRLF, trailing whitespace, comment lines and
# absolute or foreign paths (matched by file name in the same folder).
DF_BOM="$(printf '\357\273\277')"
df_m3u_refs() {
  LC_ALL=C sed "1s/^$DF_BOM//; s/[[:space:]]*\$//; s/^[[:space:]]*//; /^#/d; /^\$/d" "$1" 2>/dev/null
}
df_cue_refs() {
  LC_ALL=C awk -v bom="$DF_BOM" '
    NR == 1 && substr($0, 1, 3) == bom { $0 = substr($0, 4) }
    { sub(/\r$/, "") }
    /^[ \t]*[Ff][Ii][Ll][Ee][ \t]+/ {
      line = $0; sub(/^[ \t]*[Ff][Ii][Ll][Ee][ \t]+/, "", line)
      if (substr(line, 1, 1) == "\"") { line = substr(line, 2); i = index(line, "\""); if (i) line = substr(line, 1, i - 1) }
      else sub(/[ \t].*$/, "", line)
      if (line != "") print line
    }' "$1" 2>/dev/null
}
# A referenced disc counts as present (and non-empty) beside its manifest, or by
# its bare file name when the manifest carries an absolute/foreign path.
df_ref_present() {
  local dir="$1" ref="$2" b
  [ -s "$dir/$ref" ] && return 0
  b="${ref##*/}"; b="${b##*\\}"
  [ -n "$b" ] && [ -s "$dir/$b" ]
}
# Print the path of a referenced file that exists beside the manifest.
df_ref_path() {
  local dir="$1" ref="$2" b
  [ -f "$dir/$ref" ] && { printf '%s\n' "$dir/$ref"; return 0; }
  b="${ref##*/}"; b="${b##*\\}"
  [ -n "$b" ] && [ -f "$dir/$b" ] && { printf '%s\n' "$dir/$b"; return 0; }
  return 1
}

# Catch the most dangerous old-browser failure: a copied CUE/BIN or M3U folder
# whose playlist/control file arrived but one of its referenced discs did not.
# A playlist that lists no discs at all (comments only) makes no claim and is
# ignored; an EMPTY (0-byte) manifest is an interrupted copy and is held.
df_disc_manifests_complete() {
  local dir="$1" manifest refs ref seen bad
  for manifest in "$dir"/*; do
    [ -f "$manifest" ] || continue
    case "$manifest" in
      *.[Mm]3[Uu])
        [ -s "$manifest" ] || return 1
        refs=$(df_m3u_refs "$manifest") ;;
      *.[Cc][Uu][Ee])
        [ -s "$manifest" ] || return 1
        refs=$(df_cue_refs "$manifest")
        [ -n "$refs" ] || return 1 ;;          # a .cue without FILE lines cannot play
      *) continue ;;
    esac
    seen=0; bad=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      seen=1
      df_ref_present "$dir" "$ref" || bad=1
    done <<EOF_REFS
$refs
EOF_REFS
    [ "$bad" -eq 0 ] || return 1
    [ "$seen" -eq 1 ] || df_log "note: playlist lists no discs (not used for the completeness check): $manifest"
  done
  return 0
}

# ---- Rename-only moves -----------------------------------------------------------
# rename(2) is atomic only inside ONE filesystem. When games/ or the waiting
# library lives on USB, a network share, or behind a symlink, mv silently falls
# back to copy+delete: slow, not atomic, and it leaves a truncated "game" behind on
# ENOSPC or power loss. Every game move therefore goes through df_rename, which
# compares the device ids of the source and destination folders first and HOLDS
# (never copies) when they differ.
#
# The id is "<device>:<mount point>". The device is read THROUGH symlinks (a
# games/SNES that is a symlink to a USB drive reports the USB drive), and on Linux
# the mount point is compared as well, because rename(2) also fails (and mv then
# copies) across two mounts of the same filesystem, e.g. a bind mount.
# The cache is cleared whenever the lock is taken, so a drive mounted while the
# boot watcher sleeps is never judged by a stale answer.
DF_FSID_K=(); DF_FSID_V=(); DF_FSID=""; DF_MOUNTS=(); DF_MOUNTS_READ=0
df_fs_cache_reset() { DF_FSID_K=(); DF_FSID_V=(); DF_MOUNTS=(); DF_MOUNTS_READ=0; }
df_mounts_read() {   # mount points from /proc/self/mountinfo (Linux only; builtins)
  local a b c d mp rest
  DF_MOUNTS=(); DF_MOUNTS_READ=1
  [ -r /proc/self/mountinfo ] || return 0
  while read -r a b c d mp rest; do
    mp="${mp//\\040/ }"; mp="${mp//\\011/$'\t'}"; mp="${mp//\\012/$'\n'}"; mp="${mp//\\134/\\}"
    DF_MOUNTS[${#DF_MOUNTS[@]}]="$mp"
  done < /proc/self/mountinfo
}
df_mount_of() {   # $1 = canonical directory -> DF_MOUNT = its mount point (longest match)
  local p="$1" m
  DF_MOUNT=""
  for m in "${DF_MOUNTS[@]}"; do
    case "$m" in
      /) [ -n "$DF_MOUNT" ] || DF_MOUNT=/ ;;
      *) case "$p/" in "$m"/*) [ "${#m}" -ge "${#DF_MOUNT}" ] && DF_MOUNT="$m" ;; esac ;;
    esac
  done
}
df_fs_id() {   # sets DF_FSID for $1 (or its nearest existing parent)
  local p="${1:-.}" i=0 dev real mp=""
  while [ ! -e "$p" ]; do
    case "$p" in */*) p="${p%/*}"; [ -n "$p" ] || p=/ ;; *) p=. ;; esac
  done
  [ -d "$p" ] || { case "$p" in */*) p="${p%/*}"; [ -n "$p" ] || p=/ ;; *) p=. ;; esac; }
  while [ "$i" -lt "${#DF_FSID_K[@]}" ]; do
    [ "${DF_FSID_K[$i]}" = "$p" ] && { DF_FSID="${DF_FSID_V[$i]}"; return 0; }
    i=$((i+1))
  done
  # "$p/." makes stat follow a symlinked folder to the drive it really lives on.
  dev=$(stat -c %d "$p/." 2>/dev/null || stat -f %d "$p/." 2>/dev/null)
  DF_FSID=""
  [ -n "$dev" ] || return 0
  [ "$DF_MOUNTS_READ" = 1 ] || df_mounts_read
  if [ "${#DF_MOUNTS[@]}" -gt 0 ]; then
    real=$(cd -P -- "$p" 2>/dev/null && pwd -P)
    [ -n "$real" ] && { df_mount_of "$real"; mp="$DF_MOUNT"; }
  fi
  DF_FSID="$dev:$mp"
  DF_FSID_K[$i]="$p"; DF_FSID_V[$i]="$DF_FSID"
}
df_same_fs() {
  local a
  df_fs_id "$1"; a="$DF_FSID"
  df_fs_id "$2"
  [ -n "$a" ] && [ "$a" = "$DF_FSID" ]
}
DF_MV_MODE=""
df_mv_mode() {
  [ -n "$DF_MV_MODE" ] && return 0
  local h; h=$(mv --help 2>/dev/null)
  case "$h" in
    *--no-copy*) DF_MV_MODE=gnu-nocopy ;;       # coreutils >= 9.5: refuse to copy at all
    *--no-target-directory*) DF_MV_MODE=gnu ;;
    *) DF_MV_MODE=posix ;;                       # BSD/macOS/BusyBox
  esac
}
DF_XDEV_HOLDS=0
# 0 = renamed, 1 = failed or collision (nothing changed), 2 = cross-device hold
df_rename() {
  local src="$1" dest="$2" sp dp
  [ -e "$src" ] || [ -L "$src" ] || { df_log "MOVE skipped (source missing): $src"; return 1; }
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    df_log "MOVE held (destination exists, nothing changed): $dest"; return 1
  fi
  sp="${src%/*}"; [ "$sp" != "$src" ] || sp=.; [ -n "$sp" ] || sp=/
  dp="${dest%/*}"; [ "$dp" != "$dest" ] || dp=.; [ -n "$dp" ] || dp=/
  if ! df_same_fs "$sp" "$dp"; then
    DF_XDEV_HOLDS=$((DF_XDEV_HOLDS+1))
    df_log "CROSS-DEVICE HOLD (different drives; Dripfeed never copies games): $src -> $dest"
    return 2
  fi
  df_mv_mode
  case "$DF_MV_MODE" in
    gnu-nocopy) mv -n -T --no-copy -- "$src" "$dest" 2>/dev/null ;;
    gnu)        mv -n -T -- "$src" "$dest" 2>/dev/null ;;
    *)          mv -n -- "$src" "$dest" 2>/dev/null ;;
  esac
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && [ ! -e "$src" ] && [ ! -L "$src" ]; then return 0; fi
  df_log "MOVE failed (nothing changed): $src -> $dest"
  return 1
}

# ---- Single-runner lock ---------------------------------------------------------
# mkdir is atomic. The lock records its owner (pid, boot id, host). A holder that
# is still alive on this boot is NEVER preempted, however long a large move takes;
# a lock is reclaimed only when its holder is gone (dead pid, or an earlier boot).
# A lock without an owner record (older Dripfeed, or written from another machine
# whose processes we cannot see) falls back to the old 10-minute age rule.
# Only the process that took the lock ever removes it.
DF_LOCK="$DF_STATE/.lock"
DF_LOCK_HELD=0
DF_BOOT_ID=""
df_boot_id() {
  [ -n "$DF_BOOT_ID" ] && return 0
  [ -r /proc/sys/kernel/random/boot_id ] && read -r DF_BOOT_ID < /proc/sys/kernel/random/boot_id
  [ -n "$DF_BOOT_ID" ] || DF_BOOT_ID=$(sysctl -n kern.boottime 2>/dev/null)
  [ -n "$DF_BOOT_ID" ] || DF_BOOT_ID=none
}
df_pid_alive() { [ -n "$1" ] && { kill -0 "$1" 2>/dev/null || [ -d "/proc/$1" ]; }; }
df_lock_owner() {   # sets LOCK_PID LOCK_BOOT LOCK_HOST from the lock's owner record
  LOCK_PID=""; LOCK_BOOT=""; LOCK_HOST=""
  [ -f "$DF_LOCK/owner" ] && { read -r LOCK_PID; read -r LOCK_BOOT; read -r LOCK_HOST; } < "$DF_LOCK/owner"
  case "$LOCK_PID" in *[!0-9]*) LOCK_PID="" ;; esac
}
# 0 = the existing lock is stale and may be reclaimed, 1 = it is (or may be) live.
df_lock_stale() {
  local ts=0 now
  [ -d "$DF_LOCK" ] || return 0
  df_boot_id; df_lock_owner
  if [ -n "$LOCK_PID" ] && [ "$LOCK_HOST" = "${HOSTNAME:-}" ]; then
    [ "$LOCK_BOOT" = "$DF_BOOT_ID" ] || return 0          # left over from an earlier boot
    df_pid_alive "$LOCK_PID" && return 1                   # live holder: never stolen
    return 0                                               # holder died: stale
  fi
  [ -f "$DF_LOCK/ts" ] && read -r ts < "$DF_LOCK/ts"
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  if [ "$ts" -eq 0 ]; then
    # Not even a timestamp yet: someone may be creating it right now.
    [ -n "$(find "$DF_LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ]
    return
  fi
  df_strftime now '%s'
  [ $((now - ts)) -gt 600 ]
}
df_lock_take() {
  local now
  df_fs_cache_reset          # every locked operation judges drives afresh
  df_strftime now '%s'
  printf '%s\n%s\n%s\n' "$$" "$DF_BOOT_ID" "${HOSTNAME:-}" > "$DF_LOCK/owner" 2>/dev/null
  printf '%s\n' "$now" > "$DF_LOCK/ts" 2>/dev/null
  DF_LOCK_HELD=1
}
df_lock() {
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  df_boot_id
  if mkdir "$DF_LOCK" 2>/dev/null; then df_lock_take; return 0; fi
  df_lock_stale || return 1
  # Reclaim: rename the stale lock aside first (atomic, only one process wins),
  # then make sure what we moved is still the lock we judged stale.
  local snap junk="$DF_LOCK.stale.$$"
  snap=$(cat "$DF_LOCK/owner" "$DF_LOCK/ts" 2>/dev/null)
  rm -rf "$junk" 2>/dev/null          # never mv the lock INTO a leftover of a reused pid
  mv "$DF_LOCK" "$junk" 2>/dev/null || return 1
  if [ "$(cat "$junk/owner" "$junk/ts" 2>/dev/null)" != "$snap" ]; then
    [ -e "$DF_LOCK" ] || mv "$junk" "$DF_LOCK" 2>/dev/null
    return 1
  fi
  rm -rf "$junk" 2>/dev/null
  df_log "LOCK: reclaimed a stale lock (holder ${LOCK_PID:-unknown} is gone)"
  mkdir "$DF_LOCK" 2>/dev/null || return 1
  df_lock_take
}
# Wait up to $1 seconds (default DRIPFEED_LOCK_WAIT or 15) for the lock.
df_lock_wait() {
  local left="${1:-${DRIPFEED_LOCK_WAIT:-15}}"
  case "$left" in ''|*[!0-9]*) left=15 ;; esac
  while :; do
    df_lock && return 0
    [ "$left" -gt 0 ] || return 1
    sleep 1; left=$((left-1))
  done
}
df_unlock() {
  [ "$DF_LOCK_HELD" = 1 ] || return 0
  DF_LOCK_HELD=0
  df_lock_owner
  [ -z "$LOCK_PID" ] || [ "$LOCK_PID" = "$$" ] || return 0   # never release another's lock
  rm -rf "$DF_LOCK" 2>/dev/null
}
df_lock_describe() {
  if [ ! -d "$DF_LOCK" ]; then echo "free"; return; fi
  df_boot_id; df_lock_owner
  if [ -z "$LOCK_PID" ]; then echo "present (no owner record)"
  elif [ "$LOCK_HOST" != "${HOSTNAME:-}" ]; then echo "held by pid $LOCK_PID on another machine (${LOCK_HOST:-unknown})"
  elif [ "$LOCK_BOOT" != "$DF_BOOT_ID" ]; then echo "left over from an earlier boot (will be reclaimed)"
  elif df_pid_alive "$LOCK_PID"; then echo "held by running pid $LOCK_PID"
  else echo "held by pid $LOCK_PID, which is gone (will be reclaimed)"; fi
}
DF_BUSY_MSG="Dripfeed is busy (a reveal or another change is running). Nothing was changed; try again in a minute."

# ---- Logging (always on, so we can diagnose on real hardware) ---------------
df_log() {
  local ts
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  df_strftime ts '%Y-%m-%d %H:%M:%S'
  printf '%s  %s\n' "$ts" "$1" >> "$DF_LOG" 2>/dev/null
}
# Keep the log from growing forever (called once per boot by the watch daemon).
df_log_trim() {
  [ -f "$DF_LOG" ] || return 0
  [ "$(wc -l < "$DF_LOG" 2>/dev/null || echo 0)" -gt 2000 ] || return 0
  tail -n 500 "$DF_LOG" > "$DF_LOG.tmp" 2>/dev/null && mv "$DF_LOG.tmp" "$DF_LOG"
}

# ---- Date helpers -----------------------------------------------------------
df_today_int() { local t; df_strftime t '%Y%m%d'; printf '%s\n' "$t"; }
df_is_valid_prefix() {
  case "$1" in
    *.[Cc][Rr][Ss][Ww][Aa][Pp]) return 1 ;;   # Chromium write-in-progress swap file: never a game
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_*) return 0 ;;
    *) return 1 ;;
  esac
}
df_prefix_date_int() { printf '%s\n' "${1:0:4}${1:5:2}${1:8:2}"; }
df_strip_prefix()    { printf '%s\n' "${1:11}"; }

df_resolve_date() {
  case "$1" in
    today)    date +%Y-%m-%d ;;
    tomorrow) df_add_days 1 ;;
    +[0-9]*)  df_add_days "${1#+}" ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) df_valid_date "$1" || return 1; echo "$1" ;;
    *) return 1 ;;
  esac
}
df_valid_date() {
  local d="$1" y m day max
  case "$d" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 1 ;; esac
  y=${d%%-*}; m=${d#*-}; m=${m%%-*}; day=${d##*-}
  [ "$m" -ge 1 ] 2>/dev/null && [ "$m" -le 12 ] 2>/dev/null || return 1
  case "$m" in 01|03|05|07|08|10|12) max=31;; 04|06|09|11) max=30;; 02)
    max=28; [ $((y % 4)) -eq 0 ] && max=29; [ $((y % 100)) -eq 0 ] && [ $((y % 400)) -ne 0 ] && max=28;; esac
  [ "$day" -ge 1 ] 2>/dev/null && [ "$day" -le "$max" ] 2>/dev/null
}
df_add_days() {
  local n="$1" epoch
  epoch=$(( $(date +%s) + n * 86400 ))
  # Try GNU, BSD/macOS, then busybox forms of epoch->date so it works on-device too.
  date -d "@$epoch" +%Y-%m-%d 2>/dev/null && return 0          # GNU coreutils
  date -r "$epoch"  +%Y-%m-%d 2>/dev/null && return 0          # BSD / macOS
  date -d "$epoch" -D %s +%Y-%m-%d 2>/dev/null && return 0     # busybox
  return 1
}

# ---- Firmware/support guards ------------------------------------------------
# MiSTer system folders can contain firmware beside games. MegaCD commonly has
# USA/, Japan/, and Europe/ folders containing only cd_bios.rom. Jaguar .mrq files
# are marquee/support assets. Neither category is a game and neither may be moved
# into the queue. These checks are intentionally conservative: an unknown file is
# not classified as support, while a directory is support-only only when every
# visible file below it is known firmware/support. (Builtins only: no forks.)
df_support_file() {
  local n="${1##*/}" rc=1 nc=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$n" in
    gamelist.xml|n64-database.txt|sbi.zip|000-lo.lo|sfix.sfix|uni-bios.rom|cd_bios.rom|bsx_bios.rom|neo-epo.sp1|sp-s2.sp1|eeprom.jce|memorytrack.jmc|romsets.xml|gog-romsets.xml|gog-broken-romsets.xml) rc=0 ;;
    *.mrq|*.jce|*.jmc) rc=0 ;;
    boot*.rom|boot*.bin|firmware*.rom|mister-boot.*|mister-demo.*) rc=0 ;;
    *bios*.rom|*_bios.rom) rc=0 ;;
  esac
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  return "$rc"
}
df_support_dir_only() {
  local dir="$1" f base found=0
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    base="${f##*/}"
    case "$base" in .*) continue ;; esac
    found=1
    if [ -d "$f" ]; then
      df_support_dir_only "$f" || return 1
    else
      df_support_file "$base" || return 1
    fi
  done
  [ "$found" -eq 1 ]
}
df_support_entry() {
  local path="$1" base rc=1 nc=0
  base="${path##*/}"
  df_is_valid_prefix "$base" && base="${base:11}"
  if [ -f "$path" ]; then df_support_file "$base" && return 0; fi
  if [ -d "$path" ]; then
    shopt -q nocasematch && nc=1
    shopt -s nocasematch
    case "$base" in media|palettes|borders|cores) rc=0 ;; esac
    [ "$nc" -eq 1 ] || shopt -u nocasematch
    [ "$rc" -eq 0 ] && return 0
    df_support_dir_only "$path" && return 0
  fi
  return 1
}
# Dripfeed's own per-system shortcut folder is never a game to schedule.
df_is_shortcut_dir() {
  local n="${1##*/}" rc=1 nc=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  if [ -n "$n" ] && { [[ "$n" == "$SYSTEM_SHORTCUTS_DIR" ]] || [[ "$n" == "_Dripfeed New" ]]; }; then rc=0; fi
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  return "$rc"
}
# GOT'eM folders Dripfeed may write inside system folders (SYSTEM_SHORTCUTS=1): the
# configured and default folder names, with or without a " - Mon" suffix (or the
# bare " -" left when SHOWCASE_MAXLEN cuts the month off), this month's labels, and
# every folder that still holds a recorded shortcut (an old name stays guarded
# until its shortcuts are removed).
DF_GOTM_DIRS=()   # filled once per process (callers loop over every game; no fork per call)
df_is_gotm_dir() {
  local n="${1##*/}" b f rc=1 nc=0
  [ -n "$n" ] || return 1
  if [ "${#DF_GOTM_DIRS[@]}" -eq 0 ]; then
    DF_GOTM_DIRS=("$(df_showcase_sanitize "${GOTM_DIRNAME:-_Game of the Month}")" "$(df_showcase_sanitize "${GOTM_SRC_DIRNAME:-_Discord GOTM}")" "_Game of the Month" "_Discord GOTM")
    DF_GOTM_DIRS+=("$(df_gotm_label "${DF_GOTM_DIRS[0]}")" "$(df_gotm_label "${DF_GOTM_DIRS[1]}")")
    if [ -f "$DF_GOTM_MIRRORS" ]; then
      while IFS=$'\t' read -r b f || [ -n "$b" ]; do
        f="${f%/*}"; [ -n "$f" ] && DF_GOTM_DIRS+=("${f##*/}")
      done < "$DF_GOTM_MIRRORS"
    fi
  fi
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for b in "${DF_GOTM_DIRS[@]}"; do
    if [ -n "$b" ] && { [[ "$n" == "$b" ]] || [[ "$n" == "$b - "* ]] || [[ "$n" == "$b -" ]]; }; then rc=0; break; fi
  done
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  return "$rc"
}
# Generated folders inside a system folder are never games: never scheduled or listed.
df_is_generated_dir() { df_is_shortcut_dir "$1" || df_is_gotm_dir "$1"; }

df_occasion() {
  [ -f "$DF_OCCASIONS" ] || return 0
  awk -F'\t' -v d="$1" '$1==d{ print substr($0, index($0,"\t")+1); exit }' "$DF_OCCASIONS"
}

# Record a successful reveal once. The scheduler uses this ledger to distinguish
# "available" from "already unveiled" when preparing an incremental update. Fields
# are deliberately simple TSV because MiSTer ships awk/sed but not SQLite.
df_ledger_record() {
  local d="$1" sys="$2" name="$3" ts
  [ -n "$d" ] && [ -n "$sys" ] && [ -n "$name" ] || return 1
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  if [ -f "$DF_LEDGER" ] && awk -F '\t' -v s="$sys" -v n="$name" '$2==s && $3==n {found=1} END{exit found?0:1}' "$DF_LEDGER"; then return 0; fi
  df_strftime ts '%Y-%m-%d %H:%M:%S'
  printf '%s\t%s\t%s\t%s\n' "$d" "$sys" "$name" "$ts" >> "$DF_LEDGER" 2>/dev/null
}

# A reveal is a same-filesystem rename, so the game itself cannot be copied only
# halfway. The small journal below closes the remaining gap: power can fail after
# the rename but before revealed.tsv and the What's New shortcut are updated.
df_tx_begin() {
  local d="$1" sys="$2" name="$3" src="$4" dest="$5" tmp
  [ -d "$DF_TX_DIR" ] || mkdir -p "$DF_TX_DIR" 2>/dev/null || return 1
  tmp="$DF_TX_DIR/current.tsv.new.$$"
  printf '%s\t%s\t%s\t%s\t%s\n' "$d" "$sys" "$name" "$src" "$dest" > "$tmp" || return 1
  mv "$tmp" "$DF_TX_DIR/current.tsv" || return 1
  sync 2>/dev/null || true
}

df_tx_clear() {
  rm -f "$DF_TX_DIR/current.tsv" 2>/dev/null
  sync 2>/dev/null || true
}

# Print a recovered reveal as system<TAB>name<TAB>date<TAB>destination. If the
# move never happened, discard the stale intent and let the normal queue retry.
# Ambiguous states are deliberately left in place for diagnosis—never delete or
# overwrite a user's game to guess what happened.
df_tx_recover() {
  local tx="$DF_TX_DIR/current.tsv" d sys name src dest
  [ -f "$tx" ] || return 0
  IFS=$'\t' read -r d sys name src dest < "$tx"
  case "$src:$dest" in
    "$STAGING_ROOT"/*:"$GAMES_DIR"/*|"$GAMES_DIR"/*/"$STAGE_DIRNAME"/*:"$GAMES_DIR"/*) ;;
    *) df_log "RECOVERY HOLD: invalid transaction paths"; return 1 ;;
  esac
  if [ -e "$dest" ] && [ ! -e "$src" ]; then
    df_ledger_record "$d" "$sys" "$name"
    printf '%s\t%s\t%s\t%s\n' "$sys" "$name" "$d" "$dest"
    df_log "RECOVERED reveal after interruption: $sys/$name"
    df_tx_clear
  elif [ -e "$src" ] && [ ! -e "$dest" ]; then
    df_log "RECOVERY retry: reveal move had not started: $sys/$name"
    df_tx_clear
  else
    df_log "RECOVERY HOLD: ambiguous reveal state for $sys/$name"
    return 1
  fi
}

# Set a revealed game's date to the reveal time (metadata only; the contents and
# the exact file name are untouched). For a folder: the folder and its top-level
# files. Runs after the reveal journal has cleared.
df_touch_revealed() {
  [ "${TOUCH_ON_REVEAL:-1}" -eq 1 ] || return 0
  local p="$1" f
  [ -e "$p" ] || return 0
  if [ -d "$p" ]; then
    set -- "$p"
    for f in "$p"/*; do [ -f "$f" ] && set -- "$@" "$f"; done
    touch -c "$@" 2>/dev/null
  else
    touch -c "$p" 2>/dev/null
  fi
  return 0
}

# ---- "What's New" showcase folder (.mgl shortcuts, Favorites-style) ----------
# Map a system folder + file extension to the MiSTer core .mgl parameters
# (rbf path, delay, type, index, setname, reset).
#
# CREDIT: the per-core values and set names below are adapted from wizzo's
# (Callan Barrett) MiSTer_Favorites / mrext MGL map — https://github.com/wizzomafizzo/mrext
# (GPL-3.0) — re-synced in 2026 with the shared MiSTer system catalog that mrext
# now uses. The .mgl file format and the "_"-prefixed-folder-shows-in-menu and
# Favorites convention are from MiSTer-devel. Thank you to both.
#
# The slot is chosen by EXTENSION, as the catalog does. Sets RBF/DELAY/MTYPE/
# MINDEX/SETNAME/RESET_DELAY/RESET_HOLD and returns 0; returns 1 (the caller skips
# the shortcut and logs it) for a system or extension that no slot accepts — for
# example .zip, an .m3u playlist, or an .iso for a CD core.
# Note: a .gg kept in the SMS folder (or .gbc in GAMEBOY, .fds in NES) launches
# WITHOUT a set name, so its saves stay where browsing that folder puts them.
df_mgl_lookup() {
  local sys="$1" ext="$2" id="" nc=0
  RBF=""; DELAY=1; MTYPE="f"; MINDEX=0; SETNAME=""; RESET_DELAY=0; RESET_HOLD=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$sys" in   # case-insensitive: install bases vary (GENESIS vs Genesis)
    nes|famicom) id=NES ;;
    fds) id=FDS ;;
    snes|sfc|supernes) id=SNES ;;
    megadrive|genesis|md) id=MegaDrive ;;
    gameboy|gb) id=GAMEBOY ;;
    gbc) id=GBC ;;
    megaduck) id=MegaDuck ;;
    gba) id=GBA ;;
    gamegear|gg) id=GameGear ;;
    sms|mastersystem) id=SMS ;;
    sg1000) id=SG1000 ;;
    s32x|32x|sega32x) id=S32X ;;
    n64|nintendo64) id=N64 ;;
    neogeo|neo) id=NEOGEO ;;
    neogeo-cd|neogeocd) id=NeoGeoCD ;;
    saturn|sat) id=Saturn ;;
    megacd|scd|segacd) id=MegaCD ;;
    psx|ps1|playstation) id=PSX ;;
    tgfx16|tg16|turbografx16|pce) id=TGFX16 ;;
    tgfx16-cd|tgcd|turbografx16-cd|pcecd) id=TGFX16CD ;;
    jaguar|jag) id=Jaguar ;;
    ngp|neogeopocket) id=NGP ;;
    ngpc|neogeopocketcolor) id=NGPC ;;
    amiga|minimig) id=Amiga ;;
    c64) id=C64 ;;
    ao486|pc) id=AO486 ;;
    spectrum|zxspectrum|zx-spectrum) id=Spectrum ;;
  esac
  case "$id:$ext" in
    NES:.nes|NES:.nsf|NES:.fds)                 RBF="_Console/NES"; DELAY=2; MINDEX=1 ;;
    FDS:.fds)                                   RBF="_Console/NES"; DELAY=2; MINDEX=1; SETNAME="FDS" ;;
    SNES:.sfc|SNES:.smc|SNES:.bin|SNES:.bs)     RBF="_Console/SNES"; DELAY=2; MINDEX=0 ;;
    SNES:.spc)                                  RBF="_Console/SNES"; DELAY=2; MINDEX=1 ;;
    MegaDrive:.bin|MegaDrive:.gen|MegaDrive:.md) RBF="_Console/MegaDrive"; MINDEX=1 ;;  # MegaDrive is the current default core
    GAMEBOY:.gb|GAMEBOY:.gbc|GAMEBOY:.bin)      RBF="_Console/Gameboy"; DELAY=2; MINDEX=1 ;;
    GBC:.gbc)                                   RBF="_Console/Gameboy"; DELAY=2; MINDEX=1; SETNAME="GBC" ;;
    MegaDuck:.bin)                              RBF="_Console/Gameboy"; DELAY=2; MINDEX=1 ;;
    GBA:.gba)                                   RBF="_Console/GBA"; DELAY=2; MINDEX=1 ;;
    GameGear:.gg)                               RBF="_Console/SMS"; MINDEX=2; SETNAME="GameGear" ;;
    SMS:.sms)                                   RBF="_Console/SMS"; MINDEX=1 ;;
    SMS:.gg)                                    RBF="_Console/SMS"; MINDEX=2 ;;
    SMS:.sg|SG1000:.sg)                         RBF="_Console/ColecoVision"; MINDEX=0; SETNAME="SG1000" ;;
    S32X:.32x)                                  RBF="_Console/S32X"; MINDEX=1 ;;
    N64:.n64|N64:.z64|N64:.v64)                 RBF="_Console/N64"; MINDEX=1 ;;
    NEOGEO:.neo)                                RBF="_Console/NeoGeo"; MINDEX=1 ;;
    NEOGEO:.cue|NEOGEO:.chd|NeoGeoCD:.cue|NeoGeoCD:.chd) RBF="_Console/NeoGeo"; MTYPE="s"; MINDEX=1 ;;
    Saturn:.cue|Saturn:.chd)                    RBF="_Console/Saturn"; MTYPE="s"; MINDEX=0; DELAY=2 ;;
    MegaCD:.cue|MegaCD:.chd)                    RBF="_Console/MegaCD"; MTYPE="s"; MINDEX=0 ;;
    PSX:.cue|PSX:.chd)                          RBF="_Console/PSX"; MTYPE="s"; MINDEX=1 ;;
    PSX:.exe)                                   RBF="_Console/PSX"; MINDEX=1 ;;
    TGFX16:.pce|TGFX16:.bin)                    RBF="_Console/TurboGrafx16"; MINDEX=0 ;;
    TGFX16:.sgx)                                RBF="_Console/TurboGrafx16"; MINDEX=1 ;;
    TGFX16CD:.cue|TGFX16CD:.chd)                RBF="_Console/TurboGrafx16"; MTYPE="s"; MINDEX=0 ;;
    Jaguar:.jag|Jaguar:.j64|Jaguar:.rom|Jaguar:.bin) RBF="_Console/Jaguar"; MINDEX=0; RESET_DELAY=1; RESET_HOLD=1 ;;
    Jaguar:.cdi)                                RBF="_Console/Jaguar"; MTYPE="s"; MINDEX=1; RESET_DELAY=1; RESET_HOLD=1 ;;
    NGP:.ngp)                                   RBF="_Arcade/JTNGP"; DELAY=2; MINDEX=1; SETNAME="NeoGeoPocket" ;;
    NGPC:.ngc)                                  RBF="_Arcade/JTNGPC"; DELAY=2; MINDEX=1; SETNAME="JTNGPC" ;;
    # ---- computers (used mainly by Game of the Month) ----
    Amiga:.adf)                                 RBF="_Computer/Minimig"; MINDEX=0 ;;          # df0
    C64:.d64|C64:.g64|C64:.t64|C64:.d81)        RBF="_Computer/C64"; MTYPE="s"; MINDEX=0 ;;   # drive #8
    C64:.prg|C64:.crt|C64:.reu|C64:.tap)        RBF="_Computer/C64"; MINDEX=1 ;;
    AO486:.img|AO486:.ima|AO486:.vfd)           RBF="_Computer/ao486"; MTYPE="s"; MINDEX=0 ;; # floppy A:
    AO486:.vhd)                                 RBF="_Computer/ao486"; MTYPE="s"; MINDEX=2 ;; # IDE 0-0
    Spectrum:.trd|Spectrum:.img|Spectrum:.dsk|Spectrum:.mgt) RBF="_Computer/ZX-Spectrum"; MTYPE="s"; MINDEX=0 ;;
    Spectrum:.tap|Spectrum:.csw|Spectrum:.tzx)  RBF="_Computer/ZX-Spectrum"; MINDEX=2 ;;
    Spectrum:.z80|Spectrum:.sna)                RBF="_Computer/ZX-Spectrum"; MINDEX=4 ;;
    Spectrum:.vhd)                              RBF="_Computer/ZX-Spectrum"; MTYPE="s"; MINDEX=1 ;;  # DivMMC
  esac
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  [ -n "$RBF" ] || return 1
  RBF="$(df_resolve_rbf "$RBF")"   # point at the core actually installed (handles renamed/deprecated cores)
  return 0
}

# Given a preferred "_Console/Name", return a core path that actually exists
# (MiSTer matches "<Name>.rbf" or "<Name>_<date>.rbf"). Falls back to known
# alternates for cores that were renamed, then to the preferred name.
df_resolve_rbf() {
  local pref="$1" dir base f alt
  dir="$DF_ROOT/${pref%/*}"; base="${pref##*/}"
  for f in "$dir/$base".rbf "$dir/$base"_*.rbf; do [ -e "$f" ] && { echo "$pref"; return; }; done
  case "$base" in
    MegaDrive) alt=Genesis ;;
    Genesis)   alt=MegaDrive ;;
    *) alt="" ;;
  esac
  if [ -n "$alt" ]; then
    for f in "$dir/$alt".rbf "$dir/$alt"_*.rbf; do [ -e "$f" ] && { echo "${pref%/*}/$alt"; return; }; done
  fi
  echo "$pref"
}

# Read names on stdin and print the first in natural order, so "Disc 2" comes
# before "Disc 10" and "(Disc 1)" is always first (case-insensitive).
df_natural_first() {
  LC_ALL=C awk '
    { s = tolower($0); k = ""
      while (match(s, /[0-9]+/)) {
        d = substr(s, RSTART, RLENGTH); while (length(d) < 12) d = "0" d
        k = k substr(s, 1, RSTART - 1) d; s = substr(s, RSTART + RLENGTH)
      }
      k = k s
      if (NR == 1 || k < best) { best = k; name = $0 } }
    END { if (NR) print name }'
}

# The launchable disc of a multi-disc folder. MiSTer cores mount a .cue or .chd,
# never an .m3u playlist (and CD cores take no .iso): use the playlist's FIRST
# entry when it names a .cue/.chd present here, else the first .cue, then the first
# .chd, in natural Disc-1 order. Returns 1 when nothing launchable exists.
df_disc_target() {
  local dir="$1" m first f ext list
  for m in "$dir"/*; do
    [ -f "$m" ] || continue
    case "$m" in *.[Mm]3[Uu]) ;; *) continue ;; esac
    first=$(df_m3u_refs "$m" | head -n 1)
    case "$first" in *.[Cc][Uu][Ee]|*.[Cc][Hh][Dd]) df_ref_path "$dir" "$first" && return 0 ;; esac
  done
  for ext in cue chd; do
    list=""
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      case "$ext:${f##*.}" in cue:[Cc][Uu][Ee]|chd:[Cc][Hh][Dd]) list="$list${f##*/}"$'\n' ;; esac
    done
    if [ -n "$list" ]; then
      first=$(printf '%s' "$list" | df_natural_first)
      [ -n "$first" ] && { printf '%s/%s\n' "$dir" "$first"; return 0; }
    fi
  done
  return 1
}

# The unescaped path="..." of an .mgl file.
df_mgl_path() {
  sed -n 's/.*path="\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -n 1 | df_xml_unescape
}

# Write one .mgl shortcut for a revealed game into $1 (the showcase dir).
#   $1 = showcase dir   $2 = system folder name   $3 = absolute path of revealed item
#   $4 = optional custom label (e.g. "User GOTM May - Plok" for Game of the Month)
# Returns 1 (and logs) when the item has nothing MiSTer can launch.
df_make_mgl() {
  local outdir="$1" sys="$2" item="$3" target base ext label mgl first
  if [ -d "$item" ]; then
    # multi-disc folder: point at the first launchable disc inside, never the .m3u
    target="$(df_disc_target "$item")" || {
      df_log "no launchable disc (.cue/.chd) in $sys/${item##*/} - shortcut skipped"; return 1; }
    base="${item##*/}"
  else
    target="$item"; base="${item##*/}"; base="${base%.*}"
    case "$item" in
      *.[Mm]3[Uu])   # a playlist picked directly: launch its first disc instead
        first=$(df_m3u_refs "$item" | head -n 1)
        case "$first" in *.[Cc][Uu][Ee]|*.[Cc][Hh][Dd]) target="$(df_ref_path "${item%/*}" "$first")" || target="" ;; *) target="" ;; esac
        [ -n "$target" ] || { df_log "playlist names no launchable disc: $sys/${item##*/} - shortcut skipped"; return 1; } ;;
    esac
  fi
  ext="${target##*/}"; ext=".${ext##*.}"
  df_mgl_lookup "$sys" "$ext" || { df_log "no MGL slot for $sys ($ext) - shortcut skipped"; return 1; }
  # Label shows the system so the player knows the platform ($4 = custom label override).
  label="$sys - $base"
  [ -n "${4:-}" ] && label="$4"
  label="${label//[<>:\"\/\\|?*]/}"
  [ -n "$label" ] || return 1
  [ -d "$outdir" ] || mkdir -p "$outdir"
  local xml_target xml_rbf xml_set
  xml_target="$(df_xml_attr "$target")"; xml_rbf="$(df_xml_attr "$RBF")"; xml_set="$(df_xml_attr "$SETNAME")"
  mgl="<mistergamedescription>
	<rbf>$xml_rbf</rbf>"
  [ -n "$SETNAME" ] && mgl="$mgl
	<setname>$xml_set</setname>"
  mgl="$mgl
	<file delay=\"$DELAY\" type=\"$MTYPE\" index=\"$MINDEX\" path=\"$xml_target\"/>"
  [ "${RESET_DELAY:-0}" -gt 0 ] && mgl="$mgl
	<reset delay=\"$RESET_DELAY\" hold=\"$RESET_HOLD\"/>"
  mgl="$mgl
</mistergamedescription>"
  printf '%s\n' "$mgl" > "$outdir/$label.mgl"
  df_log "showcase mgl: $label.mgl -> $target"
}

# ---- Frontend breadcrumbs (optional; we never modify the frontend itself) -----
# Write a gamelist.xml (a common frontend metadata format) describing the shortcuts in the
# showcase folder (names, the reveal date from revealed.tsv, and the "what's new"
# message). Every field is XML-escaped. Harmless to any software that ignores it.
df_write_gamelist() {
  local dir="$1" today msg gl entry path rel rest sys name stamp list ledger
  [ "${GAMELIST:-1}" -eq 1 ] || return 0
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  df_strftime today '%Y-%m-%d'; msg=$(df_occasion "$today")
  gl="$dir/gamelist.xml"; list="$DF_STATE/.gamelist.$$"
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  : > "$list"
  for entry in "$dir"/*.mgl; do
    [ -e "$entry" ] || continue
    path=$(df_mgl_path "$entry"); sys=""; name=""
    rel="${path#"$GAMES_DIR"/}"
    if [ -n "$path" ] && [ "$rel" != "$path" ]; then sys="${rel%%/*}"; rest="${rel#*/}"; name="${rest%%/*}"; fi
    stamp=$(date -r "$entry" +%Y%m%dT%H%M%S 2>/dev/null)
    printf '%s\t%s\t%s\t%s\n' "${entry##*/}" "$sys" "$name" "$stamp" >> "$list"
  done
  ledger="$DF_LEDGER"; [ -f "$ledger" ] || ledger=/dev/null
  DF_GL_DESC="New on Dripfeed${msg:+ — $msg}" awk -F'\t' -v q="'" '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s)
                      gsub(/"/, "\\&quot;", s); gsub(q, "\\&apos;", s); return s }
    function stampof(t) { gsub(/[^0-9]/, "", t); return (length(t) >= 14) ? substr(t, 1, 8) "T" substr(t, 9, 6) : "" }
    BEGIN { desc = ENVIRON["DF_GL_DESC"]; print "<?xml version=\"1.0\"?>"; print "<gameList>" }
    FILENAME == ARGV[1] { if ($2 != "" && $3 != "") when[$2 FS $3] = $4; next }
    { file = $1; nm = file; sub(/\.mgl$/, "", nm)
      d = ""; if ($2 != "" && ($2 FS $3) in when) d = stampof(when[$2 FS $3])
      if (d == "") d = $4
      print "  <game>"
      print "    <path>./" esc(file) "</path>"
      print "    <name>" esc(nm) "</name>"
      print "    <desc>" esc(desc) "</desc>"
      if (d != "") print "    <releasedate>" esc(d) "</releasedate>"
      print "  </game>" }
    END { print "</gameList>" }' "$ledger" "$list" > "$gl.tmp" && mv "$gl.tmp" "$gl"   # write-then-rename: readers never see a partial file
  rm -f "$list" 2>/dev/null
  df_log "wrote gamelist.xml ($dir)"
}
df_xml() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
df_xml_attr() { df_xml "$1" | sed 's/"/\&quot;/g; s/'"'"'/\&apos;/g'; }
# Reverse df_xml_attr (stdin -> stdout). &amp; is decoded LAST so "&amp;lt;"
# stays "&lt;" instead of turning into "<".
df_xml_unescape() { sed "s/&quot;/\"/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\\&/g"; }

# True if the console clock looks set (year >= 2020). Reveals must never run on an
# unsynced clock (RTC/network time not up yet) — that caused 1970-dated folders.
df_clock_ok() { local y; df_strftime y '%Y'; [ "$y" -ge 2020 ] 2>/dev/null; }

# ---- Interactive console session --------------------------------------------
# HARD-LEARNED (fixes the "black screen" + "stray text on the prompt line" bugs):
#   1. All interactive UI (prompts, countdowns) is drawn on STDERR. Menu functions
#      return their answer on stdout, so callers use c="$(...)" — if the prompt also
#      went to stdout it would be CAPTURED by the $() and never reach the screen,
#      which made the launcher look dead/black while it silently counted down.
#   2. Terminal echo is switched off for the whole session (df_ui_begin/df_ui_end),
#      and every escape-sequence tail is drained, so controller/keyboard presses can
#      never type stray characters onto the prompt line.
DF_STTY_SAVED=""
df_ui_begin() {
  [ -t 0 ] || return 0
  DF_STTY_SAVED="$(stty -g 2>/dev/null)"
  stty -echo 2>/dev/null
}
df_ui_end() {
  [ -t 0 ] || return 0
  if [ -n "$DF_STTY_SAVED" ]; then stty "$DF_STTY_SAVED" 2>/dev/null; else stty echo 2>/dev/null; fi
}
df_drain_input() { while IFS= read -rsn1 -t 0.05 _ 2>/dev/null; do :; done; }

# On-screen countdown that doubles as the menu. Counts $1 seconds; if the d-pad UP or
# DOWN is pressed it returns immediately ("up"/"down" on stdout); ALL other keys are
# consumed and ignored; returns "" on timeout. UI goes to stderr (see note above).
df_menu_countdown() {
  local s="${1:-5}" label="${2:-Continuing}" k r
  while [ "$s" -gt 0 ]; do
    printf '\r  %s in %2ds ...    ' "$label" "$s" >&2
    if IFS= read -rsn1 -t 1 k 2>/dev/null; then
      if [ "$k" = "$(printf '\033')" ]; then           # ESC -> arrow-key sequence
        IFS= read -rsn2 -t 0.3 r 2>/dev/null
        case "$r" in "[A"|"OA") printf '\n' >&2; echo up;   return ;;
                     "[B"|"OB") printf '\n' >&2; echo down; return ;; esac
      fi
      df_drain_input                                   # swallow the rest, no stray text
    fi
    s=$((s-1))
  done
  printf '\n' >&2; echo ""
}

# Wait up to $1 seconds for ANY button/key (controllers reach the script console as
# keystrokes on MiSTer). Returns 0 if pressed, 1 on timeout. UI is the caller's.
df_confirm_any() {
  local t="${1:-10}" waited=0
  while [ "$waited" -lt "$t" ]; do
    if IFS= read -rsn1 -t 1 _ 2>/dev/null; then df_drain_input; return 0; fi
    waited=$((waited+1))
  done
  return 1
}

# ---- Showcase folder name (STICKY) -------------------------------------------
# The folder is renamed ONLY when a reveal actually unlocks a game (df_showcase_stamp_name
# is called by the engine right before revealing). Every other launch/boot reuses the
# saved name, so starting the console never looks like "an update" and never renames
# the folder out from under a frontend.

# Sanitize + cap a label into a legal folder name. Strips FAT-illegal characters
# AND anything non-printable-ASCII (emojis, smart quotes, …) that would confuse the
# MiSTer browser, guarantees the leading "_" a menu folder needs, and never returns
# an empty name.
df_showcase_sanitize() {
  local name="$1"
  name="$(printf '%s' "$name" | tr -d '<>:"/\\|?*' | tr -cd '\11\40-\176' | sed 's/  */ /g; s/^ *//; s/ *$//')"
  case "$name" in _*) ;; *) name="_$name" ;; esac
  [ "${#name}" -gt "${SHOWCASE_MAXLEN:-30}" ] && name="$(printf '%s' "$name" | cut -c1-"${SHOWCASE_MAXLEN:-30}" | sed 's/ *$//')"
  [ "$name" = "_" ] && name="_Dripfeed"
  printf '%s' "$name"
}

# The fixed name used when SHOWCASE_DATE=0 and no custom message applies:
# the prefix with any trailing separator trimmed ("_Dripfeed - " -> "_Dripfeed").
df_showcase_static_name() {
  df_showcase_sanitize "$(printf '%s' "${SHOWCASE_PREFIX:-_Dripfeed - }" | sed 's/[ -]*$//')"
}

# Default label: "New Fri Jul 3, 26" — day-of-month with NO leading zero.
df_showcase_default_label() {
  local dom; dom="$(date +%d)"; dom="${dom#0}"
  printf 'New %s %s %s, %s' "$(date +%a)" "$(date +%b)" "$dom" "$(date +%y)"
}

# Append NAME to a record file once (one name per line).
df_record_add() {
  local file="$1" name="$2" line
  [ -n "$name" ] || return 0
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do [ "$line" = "$name" ] && return 0; done < "$file"
  fi
  [ -d "${file%/*}" ] || mkdir -p "${file%/*}" 2>/dev/null
  printf '%s\n' "$name" >> "$file" 2>/dev/null
}

# Compute today's name (custom message for today if set, else the dated default)
# and SAVE it as the current sticky name. Engine calls this only on a real reveal.
df_showcase_stamp_name() {
  local label name
  label=$(df_occasion "$(date +%Y-%m-%d)")
  if [ -n "$label" ]; then
    name="$(df_showcase_sanitize "${SHOWCASE_PREFIX}${label}")"
  elif [ "${SHOWCASE_DATE:-1}" -eq 1 ]; then
    name="$(df_showcase_sanitize "${SHOWCASE_PREFIX}$(df_showcase_default_label)")"
  else
    name="$(df_showcase_static_name)"          # fixed name mode: no date suffix
  fi
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  printf '%s' "$name" > "$DF_SHOWNAME" 2>/dev/null
  df_record_add "$DF_SHOWNAMES" "$name"
  df_log "showcase name stamped: $name"
  printf '%s' "$name"
}

# The current sticky name. First ever call (no saved name yet) stamps today's default
# once so later boots keep reusing it rather than re-deriving a new date each day.
df_showcase_current_name() {
  local name=""
  [ -f "$DF_SHOWNAME" ] && name="$(cat "$DF_SHOWNAME" 2>/dev/null)"
  # Accept the saved name if it still matches the configured prefix OR the fixed
  # name; otherwise the user changed config, so restamp once.
  case "$name" in
    "${SHOWCASE_PREFIX}"*) ;;
    *) [ "$name" = "$(df_showcase_static_name)" ] || name="" ;;
  esac
  [ -n "$name" ] || name="$(df_showcase_stamp_name)"
  printf '%s' "$name"
}

# ---- Dripfeed-made folders: recognise and remove ONLY what Dripfeed created -------
# True when an .mgl launches a game Dripfeed revealed (its target is listed in
# revealed.tsv). User-made shortcuts never match.
df_is_dripfeed_mgl() {
  local path rel rest sys name
  [ -f "$DF_LEDGER" ] || return 1
  path=$(df_mgl_path "$1")
  rel="${path#"$GAMES_DIR"/}"
  [ -n "$path" ] && [ "$rel" != "$path" ] || return 1
  sys="${rel%%/*}"; rest="${rel#*/}"; name="${rest%%/*}"
  [ -n "$sys" ] && [ -n "$name" ] || return 1
  awk -F'\t' -v s="$sys" -v n="$name" '$2 == s && $3 == n { f = 1; exit } END { exit f ? 0 : 1 }' "$DF_LEDGER"
}
# 0 when DIR holds nothing but shortcut files (*.mgl, gamelist.xml) — and, with
# $2=strict, only shortcuts to games Dripfeed revealed.
df_dir_only_shortcuts() {
  local dir="$1" strict="${2:-}" f
  [ -d "$dir" ] || return 1
  for f in "$dir"/* "$dir"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    [ -f "$f" ] || return 1
    case "${f##*/}" in
      gamelist.xml) ;;
      *.mgl) [ -z "$strict" ] || df_is_dripfeed_mgl "$f" || return 1 ;;
      .DS_Store|._*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}
# Delete the shortcut files Dripfeed writes, then the folder if that left it empty.
# Never rm -rf: anything else a user put there survives.
df_remove_shortcut_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  rm -f "$dir"/*.mgl "$dir/gamelist.xml" "$dir/gamelist.xml.tmp" "$dir/.DS_Store" "$dir"/._* 2>/dev/null
  rmdir "$dir" 2>/dev/null || df_log "kept $dir (it holds files Dripfeed did not create)"
  return 0
}
# MiSTer's own top-level folders (and the Favorites root): never a Dripfeed folder,
# whatever a configured name says. Case-insensitive, like the FAT card.
df_mister_folder() {
  local n="$1" rc=1 nc=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  case "$n" in
    _Arcade|_Console|_Computer|_Other|_Utility|_Unstable|_LLAPI|_Jotego|_CoinOp|_Homebrew|_Alternatives|_Unofficial|_Favorites|_@Favorites) rc=0 ;;
  esac
  [[ "$n" == "${FAVORITES_DIR:-_@Favorites}" ]] && rc=0
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  return "$rc"
}
# Every folder name that is (or was) a What's New folder: the record of stamped
# names, the legacy default prefixes, and the configured prefix.
DF_SHOWCASE_KIND=""
DF_SHOWCASE_PRE=""; DF_SHOWCASE_STATIC=""; DF_GOTM_BASE1=""; DF_GOTM_BASE2=""
df_showcase_kind() {   # sets DF_SHOWCASE_KIND for a folder NAME: record|legacy|prefix|""
  local n="$1" line body g
  DF_SHOWCASE_KIND=""
  # Never a MiSTer folder, the Favorites root or a Game of the Month folder,
  # whatever the prefix.
  df_mister_folder "$n" && return 1
  [ -n "$DF_GOTM_BASE1" ] || DF_GOTM_BASE1="$(df_showcase_sanitize "${GOTM_DIRNAME:-_Game of the Month}")"
  [ -n "$DF_GOTM_BASE2" ] || DF_GOTM_BASE2="$(df_showcase_sanitize "${GOTM_SRC_DIRNAME:-_Discord GOTM}")"
  for g in "$DF_GOTM_BASE1" "$DF_GOTM_BASE2" "_Game of the Month" "_Discord GOTM"; do
    case "$n" in "$g"|"$g - "*|"$g -") return 1 ;; esac
  done
  if [ -f "$DF_SHOWNAMES" ]; then
    while IFS= read -r line || [ -n "$line" ]; do [ "$line" = "$n" ] && { DF_SHOWCASE_KIND=record; return 0; }; done < "$DF_SHOWNAMES"
  fi
  case "$n" in "_Dripfeed - "*|"_@Dripfeed - "*|_Dripfeed|_@Dripfeed) DF_SHOWCASE_KIND=legacy; return 0 ;; esac
  # The configured prefix as folder names spell it ("_New Games - " -> "_New Games -").
  [ -n "$DF_SHOWCASE_PRE" ] || DF_SHOWCASE_PRE="$(df_showcase_sanitize "${SHOWCASE_PREFIX:-_Dripfeed - }")"
  [ -n "$DF_SHOWCASE_STATIC" ] || DF_SHOWCASE_STATIC="$(df_showcase_static_name)"
  [ "$n" = "$DF_SHOWCASE_STATIC" ] && { DF_SHOWCASE_KIND=record; return 0; }
  # Only a distinctive configured prefix is trusted (never a bare "_" or "_@").
  body="${DF_SHOWCASE_PRE#_}"; body="${body#@}"
  [ "${#body}" -ge 3 ] || return 1
  case "$n" in "$DF_SHOWCASE_PRE"*) DF_SHOWCASE_KIND=prefix; return 0 ;; esac
  return 1
}

# (opt-in) Mirror the showcase shortcuts into ONE stable subfolder of the stock-menu
# Favorites folder: _@Favorites/_Dripfeed New. Older dated mirror folders that hold
# nothing but Dripfeed shortcuts are removed; user-made favorites are never touched.
# A graphical frontend's own in-app favorites are separate and not written.
df_mirror_favorites() {
  local dir="$1" favroot="$DF_ROOT/${FAVORITES_DIR:-_@Favorites}" fav d n
  fav="$favroot/$DF_FAV_SUBDIR"
  if [ -d "$favroot" ]; then
    for d in "$favroot"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"; n="${d##*/}"
      [ "$n" = "$DF_FAV_SUBDIR" ] && continue
      df_showcase_kind "$n" || continue
      if df_dir_only_shortcuts "$d" strict; then
        df_remove_shortcut_dir "$d"; df_log "removed old Favorites mirror: $n"
      fi
    done
  fi
  if [ "${FAVORITES_MIRROR:-0}" -ne 1 ] || [ -z "$dir" ] || [ ! -d "$dir" ]; then
    # Mirror switched off (or no showcase): remove our own stable folder.
    [ "${FAVORITES_MIRROR:-0}" -eq 1 ] || { [ -d "$fav" ] && df_remove_shortcut_dir "$fav"; }
    return 0
  fi
  [ -d "$fav" ] || mkdir -p "$fav"
  rm -f "$fav"/*.mgl "$fav/gamelist.xml" 2>/dev/null
  cp -p "$dir"/*.mgl "$fav"/ 2>/dev/null
  [ -f "$dir/gamelist.xml" ] && cp -p "$dir/gamelist.xml" "$fav"/ 2>/dev/null
  df_log "mirrored shortcuts to Favorites: $fav"
}

# ---- (opt-in) per-system shortcut folders ------------------------------------------
# SYSTEM_SHORTCUTS=1 mirrors each What's New shortcut into games/<SYSTEM>/<dir>/ as a
# standard .mgl named without the system prefix. Graphical frontends that build
# their own library from system folders can list it there after a library refresh.
# No gamelist.xml is written there. Each folder keeps the newest SHOWCASE_KEEP.
df_system_shortcut_add() {   # $1 = system folder  $2 = revealed path
  [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] || return 0
  local sys="$1" item="$2" title
  [ -d "$GAMES_DIR/$sys" ] || return 0
  title="${item##*/}"; [ -d "$item" ] || title="${title%.*}"
  df_record_add "$DF_SYSDIRS" "$SYSTEM_SHORTCUTS_DIR"
  df_make_mgl "$GAMES_DIR/$sys/$SYSTEM_SHORTCUTS_DIR" "$sys" "$item" "$title" && df_pass_changed "$sys"
}
# For each .mgl given, print "D|U<TAB>target path<TAB>file" in ONE awk pass (the
# MiSTer's slow CPU pays per process): D = it launches a game Dripfeed revealed
# (listed in revealed.tsv), U = anything else (a user's own shortcut).
df_mgl_scan() {
  local ledger="$DF_LEDGER"
  [ "$#" -gt 0 ] || return 0
  [ -f "$ledger" ] || ledger=/dev/null
  LC_ALL=C awk -v games="$GAMES_DIR/" '
    FILENAME == ARGV[1] { n = split($0, f, "\t"); if (n >= 3) seen[f[2] "\t" f[3]] = 1; next }
    !(FILENAME in got) && match($0, /path="[^"]*"/) {
      p = substr($0, RSTART + 6, RLENGTH - 7)
      gsub(/&quot;/, "\"", p); gsub(/&apos;/, "\047", p); gsub(/&lt;/, "<", p); gsub(/&gt;/, ">", p)
      gsub(/&amp;/, "\\&", p)
      got[FILENAME] = p }
    END { for (i = 2; i < ARGC; i++) {
            fn = ARGV[i]; p = (fn in got) ? got[fn] : ""; k = "U"
            if (p != "" && index(p, games) == 1) {
              rel = substr(p, length(games) + 1); sy = rel; sub(/\/.*/, "", sy)
              nm = substr(rel, length(sy) + 2); sub(/\/.*/, "", nm)
              if (sy != "" && nm != "" && ((sy "\t" nm) in seen)) k = "D" }
            print k "\t" p "\t" fn } }' "$ledger" "$@" 2>/dev/null
}
# Remove only the .mgl files in DIR that launch a game Dripfeed revealed, then DIR
# itself if that left it empty. A system folder may share its name with something
# the user made: user files are never deleted.
df_remove_system_shortcuts() {
  local dir="$1" m kind path rel files=()
  [ -d "$dir" ] || return 0
  rel="${dir#"$GAMES_DIR"/}"
  for m in "$dir"/*.mgl; do [ -f "$m" ] && files[${#files[@]}]="$m"; done
  if [ "${#files[@]}" -gt 0 ]; then
    while IFS=$'\t' read -r kind path m; do
      [ "$kind" = D ] && [ -n "$m" ] && rm -f "$m" && df_pass_changed "${rel%%/*}"
    done <<EOF_SCAN
$(df_mgl_scan "${files[@]}")
EOF_SCAN
  fi
  rm -f "$dir/.DS_Store" "$dir"/._* 2>/dev/null
  rmdir "$dir" 2>/dev/null || df_log "kept ${dir#"$GAMES_DIR"/} (it holds files Dripfeed did not create)"
  return 0
}
df_system_shortcuts_finalize() {
  local d name m label sys path rel title kind keep="${SHOWCASE_KEEP:-12}" files mine
  [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] || df_gotm_mirror_clear ""   # switched off or Undrip: GOT'eM ones too
  # Folder names Dripfeed has used: the current one, the default, the record.
  set -- "$SYSTEM_SHORTCUTS_DIR" "_Dripfeed New"
  if [ -f "$DF_SYSDIRS" ]; then
    while IFS= read -r name || [ -n "$name" ]; do [ -n "$name" ] && set -- "$@" "$name"; done < "$DF_SYSDIRS"
  fi
  # Remove Dripfeed's shortcuts from every folder that is switched off or no
  # longer current (only Dripfeed's own .mgl files; the folder only if emptied).
  for name in "$@"; do
    case "$name" in ''|*/*|.*) continue ;; esac
    [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] && [ "$name" = "$SYSTEM_SHORTCUTS_DIR" ] && continue
    for d in "$GAMES_DIR"/*/"$name"; do
      [ -d "$d" ] || continue
      df_remove_system_shortcuts "$d"
      [ -d "$d" ] || df_log "removed system shortcut folder: ${d#"$GAMES_DIR"/}"
    done
  done
  [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] || return 0
  # Backfill from What's New (e.g. right after the option is switched on). Only
  # shortcuts to games Dripfeed revealed are mirrored, so every file Dripfeed puts
  # in a system folder can later be recognised and removed again.
  if [ -n "${SHOWCASE_DIR:-}" ] && [ -d "$SHOWCASE_DIR" ]; then
    files=()
    for m in "$SHOWCASE_DIR"/*.mgl; do [ -f "$m" ] && files[${#files[@]}]="$m"; done
    if [ "${#files[@]}" -gt 0 ]; then
      while IFS=$'\t' read -r kind path m; do
        [ "$kind" = D ] && [ -e "$path" ] || continue
        rel="${path#"$GAMES_DIR"/}"; sys="${rel%%/*}"
        label="${m##*/}"; label="${label%.mgl}"; title="${label#"$sys - "}"
        [ -n "$title" ] && [ -d "$GAMES_DIR/$sys" ] || continue
        d="$GAMES_DIR/$sys/$SYSTEM_SHORTCUTS_DIR"
        [ -e "$d/$title.mgl" ] && continue
        [ -d "$d" ] || mkdir -p "$d"
        cp -p "$m" "$d/$title.mgl" 2>/dev/null && { df_record_add "$DF_SYSDIRS" "$SYSTEM_SHORTCUTS_DIR"; df_pass_changed "$sys"; }
      done <<EOF_SCAN
$(df_mgl_scan "${files[@]}")
EOF_SCAN
    fi
  fi
  # Prune Dripfeed's own shortcuts only: those whose game is gone, then all but
  # the newest SHOWCASE_KEEP. Anything else in the folder is left alone.
  for d in "$GAMES_DIR"/*/"$SYSTEM_SHORTCUTS_DIR"; do
    [ -d "$d" ] || continue
    sys="${d#"$GAMES_DIR"/}"; sys="${sys%%/*}"
    files=(); mine=()
    for m in "$d"/*.mgl; do [ -f "$m" ] && files[${#files[@]}]="$m"; done
    if [ "${#files[@]}" -gt 0 ]; then
      while IFS=$'\t' read -r kind path m; do
        [ "$kind" = D ] && [ -n "$m" ] || continue
        if [ ! -e "$path" ]; then rm -f "$m"; df_pass_changed "$sys"; df_log "pruned orphan: ${m#"$GAMES_DIR"/}"; continue; fi
        mine[${#mine[@]}]="$m"
      done <<EOF_SCAN
$(df_mgl_scan "${files[@]}")
EOF_SCAN
    fi
    if [ "${#mine[@]}" -gt "$keep" ]; then
      df_pass_changed "$sys"
      ls -1t -- "${mine[@]}" 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r m; do rm -f "$m"; done
    fi
    rmdir "$d" 2>/dev/null || true      # an empty shortcut folder is not left behind
  done
  return 0
}


# ---- (opt-in) GOT'eM picks inside system folders ------------------------------------
# With SYSTEM_SHORTCUTS=1, a console/computer GOT'eM pick also gets a shortcut in
# games/<SYSTEM>/<GOT'eM folder name>/, so frontends that only read system folders can
# show it. GOT'eM picks are often games Dripfeed never revealed, so ownership cannot
# come from the reveal ledger: every file written here is listed in $DF_GOTM_MIRRORS
# and only listed files are ever removed. A file of the same name that Dripfeed did
# not write is never replaced. Arcade picks (.mra) have no system folder under games/
# and are not mirrored.
df_gotm_label() {   # $1 = sanitized folder base -> the folder name GOT'eM uses this month
  if [ "${GOTM_MONTH:-0}" -eq 1 ]; then df_showcase_sanitize "$1 - $(date +%b)"; else printf '%s\n' "$1"; fi
}
df_gotm_mirror_clear() {   # $1 = GOT'eM folder base to clear; empty = every one
  [ -f "$DF_GOTM_MIRRORS" ] || return 0
  local want="$1" base f dir keep=""
  while IFS=$'\t' read -r base f || [ -n "$base" ]; do
    [ -n "$f" ] || continue
    if [ -n "$want" ] && [ "$base" != "$want" ]; then keep="$keep$base"$'\t'"$f"$'\n'; continue; fi
    case "$f" in "$GAMES_DIR"/*/*/*.mgl) ;; *) continue ;; esac
    if [ -f "$f" ]; then dir="${f#"$GAMES_DIR"/}"; rm -f "$f" && { [ "${DF_GOTM_QUIET:-0}" = 1 ] || df_pass_changed "${dir%%/*}"; }; fi
    dir="${f%/*}"; rm -f "$dir/.DS_Store" "$dir"/._* 2>/dev/null
    rmdir "$dir" 2>/dev/null && df_log "removed GOT'eM system shortcut folder: ${dir#"$GAMES_DIR"/}"
  done < "$DF_GOTM_MIRRORS"
  if [ -n "$keep" ]; then printf '%s' "$keep" > "$DF_GOTM_MIRRORS"; else rm -f "$DF_GOTM_MIRRORS"; fi
  return 0
}
df_gotm_mirror_prune() {   # keep the shortcuts of the folder bases given; clear the rest (none given = all)
  [ -f "$DF_GOTM_MIRRORS" ] || return 0
  local base f k stale=""
  while IFS=$'\t' read -r base f || [ -n "$base" ]; do
    [ -n "$base" ] || continue
    for k in "$@"; do [ "$base" = "$k" ] && continue 2; done
    case $'\n'"$stale" in *$'\n'"$base"$'\n'*) ;; *) stale="$stale$base"$'\n' ;; esac
  done < "$DF_GOTM_MIRRORS"
  while IFS= read -r base; do
    [ -n "$base" ] && df_gotm_mirror_clear "$base"
  done <<EOF_GOTM_STALE
$stale
EOF_GOTM_STALE
  return 0
}
# "path<TAB>checksum" for each system-folder shortcut recorded for one GOT'eM base, so a
# rebuild that writes back the same files is not counted as a change for POST_REVEAL_CMD.
df_gotm_mirror_snapshot() {
  [ -f "$DF_GOTM_MIRRORS" ] || return 0
  local base f
  while IFS=$'\t' read -r base f || [ -n "$base" ]; do
    [ "$base" = "$1" ] && [ -f "$f" ] || continue
    printf '%s\t%s\n' "$f" "$(cksum < "$f" 2>/dev/null)"
  done < "$DF_GOTM_MIRRORS"
}
df_gotm_mirror_add() {     # $1 = folder base  $2 = folder label  $3 = pick (relative to /media/fat)  $4 = custom label
  [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] || return 0
  local base="$1" label="$2" want="$3" custom="${4:-}" item rel sys dir title out made=0
  case "$want" in ''|*.[Mm][Rr][Aa]) return 0 ;; esac
  item="$DF_ROOT/$want"
  case "$item" in "$GAMES_DIR"/*/*) ;; *) return 0 ;; esac
  [ -e "$item" ] || return 0
  rel="${item#"$GAMES_DIR"/}"; sys="${rel%%/*}"
  [ -d "$GAMES_DIR/$sys" ] || return 0
  if df_is_shortcut_dir "$label"; then
    df_log "GOTM ($base): '$label' is also the What's New system folder - GOT'eM not mirrored into system folders"; return 0
  fi
  title="${item##*/}"; [ -d "$item" ] || title="${title%.*}"
  [ -n "$custom" ] && title="$custom"
  title="${title//[<>:\"\/\\|?*]/}"
  [ -n "$title" ] || return 0
  dir="$GAMES_DIR/$sys/$label"; out="$dir/$title.mgl"
  if [ -e "$out" ] && ! grep -qxF -- "$base"$'\t'"$out" "$DF_GOTM_MIRRORS" 2>/dev/null; then
    df_log "GOTM ($base): kept ${out#"$GAMES_DIR"/} (Dripfeed did not create it) - no system shortcut"; return 0
  fi
  [ -d "$dir" ] || made=1
  if df_make_mgl "$dir" "$sys" "$item" "$title"; then
    grep -qxF -- "$base"$'\t'"$out" "$DF_GOTM_MIRRORS" 2>/dev/null || printf '%s\t%s\n' "$base" "$out" >> "$DF_GOTM_MIRRORS"
    [ "${DF_GOTM_QUIET:-0}" = 1 ] || df_pass_changed "$sys"
    df_log "GOTM ($base): system shortcut ${out#"$GAMES_DIR"/}"
  elif [ "$made" -eq 1 ]; then
    rmdir "$dir" 2>/dev/null
  fi
  return 0
}
df_gotm_mirror_ensure() {  # same arguments; adds the shortcut only if this folder has none yet
  [ "${SYSTEM_SHORTCUTS:-0}" -eq 1 ] && [ -n "${3:-}" ] || return 0
  local b f d
  if [ -f "$DF_GOTM_MIRRORS" ]; then
    while IFS=$'\t' read -r b f || [ -n "$b" ]; do
      [ "$b" = "$1" ] && [ -f "$f" ] || continue
      d="${f%/*}"; [ "${d##*/}" = "$2" ] && return 0
      df_gotm_mirror_clear "$1"; break      # folder label changed (GOTM_MONTH): move it
    done < "$DF_GOTM_MIRRORS"
  fi
  df_gotm_mirror_add "$@"
}

# ---- Optional command after games change in the system folders ---------------------
# A frontend with its own game library lists a snapshot of the system folders, so it
# needs a refresh whenever a Dripfeed run changes them: games revealed (or revealed
# early from the command line), games hidden (scheduled from the browser or the
# command line, or moved from an old in-games queue), games put back (unscheduled,
# Undrip), or Dripfeed's own shortcuts inside system folders added or removed
# (What's New, GOT'eM). Each run counts what it changed and then calls df_pass_flush
# ONCE, after releasing the lock, so POST_REVEAL_CMD runs at most once per run and
# never when nothing changed, and only on the MiSTer itself. It never runs from the
# shutdown hook (the engine does not run at shutdown at all), always with a timeout; its output goes to
# post_reveal.log and the exit status is logged. The command sees:
#   DRIPFEED_REVEALED_COUNT   games revealed          DRIPFEED_REVEALED_SYSTEMS  their systems
#   DRIPFEED_HIDDEN_COUNT     games hidden            DRIPFEED_RETURNED_COUNT    games put back
#   DRIPFEED_CHANGED_SYSTEMS  every system folder whose contents changed (space-separated)
DF_PASS_REVEALED=0; DF_PASS_HIDDEN=0; DF_PASS_RETURNED=0; DF_PASS_SYSTEMS=""; DF_PASS_CHANGED=""
# The MiSTer itself, never a computer with the card mounted at /media/fat (exFAT shows
# every file as executable there): the same three tests as the launchers' on_mister().
df_on_mister() {
  [ "$DF_ROOT" = /media/fat ] && [ -x /media/fat/MiSTer ] &&
    case "$(uname -m 2>/dev/null)" in arm*) true ;; *) false ;; esac
}
df_pass_changed() {   # $1 = system folder whose contents changed
  [ -n "$1" ] || return 0
  case " $DF_PASS_CHANGED " in *" $1 "*) ;; *) DF_PASS_CHANGED="${DF_PASS_CHANGED:+$DF_PASS_CHANGED }$1" ;; esac
}
df_pass_reveal_sys() { # $1 = system folder that had games revealed
  [ -n "$1" ] || return 0
  case " $DF_PASS_SYSTEMS " in *" $1 "*) ;; *) DF_PASS_SYSTEMS="${DF_PASS_SYSTEMS:+$DF_PASS_SYSTEMS }$1" ;; esac
  df_pass_changed "$1"
}
df_pass_revealed() { DF_PASS_REVEALED=$((DF_PASS_REVEALED+1)); df_pass_reveal_sys "$1"; }
df_pass_hidden()   { DF_PASS_HIDDEN=$((DF_PASS_HIDDEN+1)); df_pass_changed "$1"; }
df_pass_returned() { DF_PASS_RETURNED=$((DF_PASS_RETURNED+1)); df_pass_changed "$1"; }
df_pass_flush() {     # run POST_REVEAL_CMD for everything counted so far, then count afresh
  local r="$DF_PASS_REVEALED" h="$DF_PASS_HIDDEN" b="$DF_PASS_RETURNED" s="$DF_PASS_SYSTEMS" c="$DF_PASS_CHANGED"
  DF_PASS_REVEALED=0; DF_PASS_HIDDEN=0; DF_PASS_RETURNED=0; DF_PASS_SYSTEMS=""; DF_PASS_CHANGED=""
  [ "$r" -gt 0 ] || [ "$h" -gt 0 ] || [ "$b" -gt 0 ] || [ -n "$c" ] || return 0
  df_post_reveal "$r" "$s" "$h" "$b" "$c"
}
df_post_reveal() {    # $1 revealed  $2 their systems  $3 hidden  $4 returned  $5 changed systems
  local count="${1:-0}" systems="${2:-}" hidden="${3:-0}" returned="${4:-0}" changed="${5:-$2}"
  local t="${DRIPFEED_POST_REVEAL_TIMEOUT:-120}" rc pid w
  [ -n "${POST_REVEAL_CMD:-}" ] || return 0
  # The command is meant for the MiSTer (a frontend running there). The command-line
  # scheduler and --migrate also run on a computer with the card mounted: never
  # run it there (DRIPFEED_POST_REVEAL_ANYWHERE=1 allows it, e.g. for tests).
  if [ "${DRIPFEED_POST_REVEAL_ANYWHERE:-0}" != 1 ] && ! df_on_mister; then
    df_log "POST_REVEAL_CMD not run: this is not the MiSTer itself ($count revealed, $hidden hidden, $returned returned)"
    return 0
  fi
  case "$t" in ''|*[!0-9]*|0) t=120 ;; esac
  df_log "POST_REVEAL_CMD start ($count revealed, $hidden hidden, $returned returned: ${changed:-shortcuts only})"
  export DRIPFEED_REVEALED_COUNT="$count" DRIPFEED_REVEALED_SYSTEMS="$systems" \
         DRIPFEED_HIDDEN_COUNT="$hidden" DRIPFEED_RETURNED_COUNT="$returned" DRIPFEED_CHANGED_SYSTEMS="$changed"
  if timeout -k 5 1 true >/dev/null 2>&1; then
    # GNU coreutils (MiSTer): TERM to the whole process group, KILL 5 s later if
    # the command ignores TERM, so a stuck command can never hang the pass.
    { timeout -k 5 "$t" sh -c "$POST_REVEAL_CMD" </dev/null >"$DF_POSTLOG" 2>&1; rc=$?; } 2>/dev/null
    [ "$rc" -eq 137 ] && rc=124
  else
    # No usable timeout(1) (macOS, older BusyBox): our own watchdog, TERM then KILL.
    sh -c "$POST_REVEAL_CMD" </dev/null >"$DF_POSTLOG" 2>&1 & pid=$!
    ( sleep "$t"; kill "$pid" 2>/dev/null; sleep 5; kill -9 "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 & w=$!
    { wait "$pid"; rc=$?; } 2>/dev/null
    { kill "$w"; wait "$w"; } 2>/dev/null
    { [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; } && rc=124
  fi
  unset DRIPFEED_REVEALED_COUNT DRIPFEED_REVEALED_SYSTEMS DRIPFEED_HIDDEN_COUNT DRIPFEED_RETURNED_COUNT DRIPFEED_CHANGED_SYSTEMS
  if [ "$rc" -eq 124 ]; then df_log "POST_REVEAL_CMD timed out after ${t}s (exit status 124)"
  else df_log "POST_REVEAL_CMD exit status $rc"; fi
  return 0
}

# ---- On-screen output -------------------------------------------------------
df_announce() {
  echo
  echo "  ================================================================"
  echo "    $1"
  echo "  ================================================================"
  echo
}
df_have_tty() { [ -t 0 ] && [ -t 1 ]; }
