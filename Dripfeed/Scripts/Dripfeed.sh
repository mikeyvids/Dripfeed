#!/bin/bash
# Dripfeed for MiSTer FPGA — GPL-3.0-or-later
# Copyright (C) 2026 MikeyVids
# See LICENSE for the full license and CREDITS.md for upstream acknowledgements.
# Dripfeed.sh — single-file, self-installing launcher for MiSTer FPGA.
# Drop ONLY this file into /media/fat/Scripts. Menu: UP = Undrip (press any button to
# confirm), DOWN = Reinstall/repair (keeps your schedule); otherwise it shows what's
# new and returns to the menu (no reboot). Undrip/Reinstall reboot when done. Writes
# its helpers + boot hook, maintains ONE dated "What's New" menu folder whose name only
# changes when games actually unlock. See CHANGELOG.md.

DRIPFEED_VERSION="1.4.0"
DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
HELP="$DRIPFEED_ROOT/Scripts/.dripfeed"
export DRIPFEED_INTERACTIVE=1
# Never create /media/fat (or anything else) on a machine that is not a MiSTer card.
if [ ! -d "$DRIPFEED_ROOT/Scripts" ]; then
  echo "  Dripfeed: $DRIPFEED_ROOT/Scripts was not found, so this is not a MiSTer SD card."
  echo "  Nothing was changed."
  exit 1
fi
scr_clear(){ clear 2>/dev/null || printf '\033[2J\033[H'; }
# Restart only on a real MiSTer: never reboot (or otherwise touch system state on)
# a desktop where this file is being tested, even when it runs as root.
on_mister(){
  [ "${DRIPFEED_NO_REBOOT:-0}" != 1 ] && [ "$DRIPFEED_ROOT" = /media/fat ] && [ -x /media/fat/MiSTer ] &&
    case "$(uname -m 2>/dev/null)" in arm*) true ;; *) false ;; esac
}
restart(){
  sync
  if on_mister; then reboot 2>/dev/null || true
  else echo; echo "  (not running on a MiSTer: restart skipped)"; fi
}
banner(){ echo; echo "  ================================================================"; echo "     D R I P F E E D"; echo "  ================================================================"; echo; }
extract_helpers(){
  # FAILSAFE: everything is written to a staging dir first and syntax-checked;
  # only a fully valid set replaces the live helpers (see end of function). A
  # truncated / corrupted Dripfeed.sh (bad download or copy) can therefore never
  # brick a working install.
  EXNEW="$HELP/.new"
  rm -rf "$EXNEW"; mkdir -p "$EXNEW"
  cat > "$EXNEW/dripfeed-common.sh" <<'__DF_COMMON__'
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
                       # games/<SYSTEM>/<SYSTEM_SHORTCUTS_DIR>/ — standard .mgl files that
                       # graphical frontends which build their own library from system
                       # folders can list after their library is refreshed.
SYSTEM_SHORTCUTS_DIR="_Dripfeed New"
POST_REVEAL_CMD=""     # optional shell command run ONCE after a pass that revealed games
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
    case "$n" in "$g"|"$g - "*) return 1 ;; esac
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
  df_make_mgl "$GAMES_DIR/$sys/$SYSTEM_SHORTCUTS_DIR" "$sys" "$item" "$title"
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
  local dir="$1" m kind path files=()
  [ -d "$dir" ] || return 0
  for m in "$dir"/*.mgl; do [ -f "$m" ] && files[${#files[@]}]="$m"; done
  if [ "${#files[@]}" -gt 0 ]; then
    while IFS=$'\t' read -r kind path m; do
      [ "$kind" = D ] && [ -n "$m" ] && rm -f "$m"
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
        cp -p "$m" "$d/$title.mgl" 2>/dev/null && df_record_add "$DF_SYSDIRS" "$SYSTEM_SHORTCUTS_DIR"
      done <<EOF_SCAN
$(df_mgl_scan "${files[@]}")
EOF_SCAN
    fi
  fi
  # Prune Dripfeed's own shortcuts only: those whose game is gone, then all but
  # the newest SHOWCASE_KEEP. Anything else in the folder is left alone.
  for d in "$GAMES_DIR"/*/"$SYSTEM_SHORTCUTS_DIR"; do
    [ -d "$d" ] || continue
    files=(); mine=()
    for m in "$d"/*.mgl; do [ -f "$m" ] && files[${#files[@]}]="$m"; done
    if [ "${#files[@]}" -gt 0 ]; then
      while IFS=$'\t' read -r kind path m; do
        [ "$kind" = D ] && [ -n "$m" ] || continue
        if [ ! -e "$path" ]; then rm -f "$m"; df_log "pruned orphan: ${m#"$GAMES_DIR"/}"; continue; fi
        mine[${#mine[@]}]="$m"
      done <<EOF_SCAN
$(df_mgl_scan "${files[@]}")
EOF_SCAN
    fi
    if [ "${#mine[@]}" -gt "$keep" ]; then
      ls -1t -- "${mine[@]}" 2>/dev/null | tail -n +$((keep + 1)) | while IFS= read -r m; do rm -f "$m"; done
    fi
    rmdir "$d" 2>/dev/null || true      # an empty shortcut folder is not left behind
  done
  return 0
}

# ---- Optional command after a pass that revealed games ------------------------------
# POST_REVEAL_CMD runs ONCE, at the end of a reveal pass that revealed at least one
# game, with a timeout. It never runs from the shutdown hook (the engine does not run
# at shutdown at all). Its output goes to post_reveal.log; the exit status is logged.
# The command sees DRIPFEED_REVEALED_COUNT and DRIPFEED_REVEALED_SYSTEMS.
df_post_reveal() {
  local count="$1" systems="$2" t="${DRIPFEED_POST_REVEAL_TIMEOUT:-120}" rc pid w
  [ -n "${POST_REVEAL_CMD:-}" ] || return 0
  [ "$count" -gt 0 ] 2>/dev/null || return 0
  case "$t" in ''|*[!0-9]*|0) t=120 ;; esac
  df_log "POST_REVEAL_CMD start ($count revealed: $systems)"
  export DRIPFEED_REVEALED_COUNT="$count" DRIPFEED_REVEALED_SYSTEMS="$systems"
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
  unset DRIPFEED_REVEALED_COUNT DRIPFEED_REVEALED_SYSTEMS
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
__DF_COMMON__
  cat > "$EXNEW/dripfeed-engine.sh" <<'__DF_ENGINE__'
#!/bin/bash
# Dripfeed for MiSTer FPGA — GPL-3.0-or-later
# Copyright (C) 2026 MikeyVids
# See ../../LICENSE for the full license and CREDITS.md for upstream acknowledgements.
# dripfeed-engine.sh — reveals scheduled games whose date has arrived.
# Paths are hardcoded under /media/fat (see dripfeed-common.sh) — never $0-based.
#
# Modes:
#   --watch     boot daemon (from user-startup.sh at "start" only): wait BOOT_DELAY,
#               reveal, then re-check once per calendar day. Silent. Logs to dripfeed.log.
#   --auto      one silent reveal pass (queues announcements). For cron-style use.
#   --reveal    one interactive pass (announce each, wait for a button). DEFAULT.
#   --pending   announce games revealed silently since last look.
#   --migrate   move old in-games queues to the hidden card-root library only.
#   --diag      print/log environment + the current queue (for troubleshooting).

DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh" 2>/dev/null || {
  echo "Dripfeed ERROR: cannot load $DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh"; exit 1; }
df_load_config

# Chromium cannot atomically move a user-chosen directory on a mounted SD card.
# The web scheduler therefore writes tiny request ledgers; this card-side engine
# performs every file/folder move with a same-filesystem rename (df_rename, which
# holds instead of copying across drives). A request is removed only after its
# requested state is true on disk.
df_migrate_legacy_queues() {
  local sysdir legacy stage entry base moved=0 held=0 sys rc
  # Every move must be a rename on ONE drive: if the games folder and the waiting
  # library are on different drives, migration would become a copy, so hold.
  if [ -d "$GAMES_DIR" ] && ! df_same_fs "$GAMES_DIR" "$STAGING_ROOT"; then
    for sysdir in "$GAMES_DIR"/*/"$STAGE_DIRNAME"; do
      [ -d "$sysdir" ] || continue
      df_log "LEGACY MIGRATION held: the games folder and the waiting library are on different drives"
      return 1
    done
    return 0
  fi
  for sysdir in "$GAMES_DIR"/*/; do
    legacy="$sysdir$STAGE_DIRNAME"; [ -d "$legacy" ] || continue
    sys="${sysdir%/}"; sys="${sys##*/}"; stage="$(df_stage_dir "$sys")"
    [ -d "$stage" ] || mkdir -p "$stage" 2>/dev/null || { df_log "LEGACY MIGRATION held: cannot create $stage"; continue; }
    for entry in "$legacy"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      base="${entry##*/}"
      if [ -e "$stage/$base" ]; then
        held=$((held+1)); df_log "LEGACY MIGRATION held (destination exists): $sys/$base"; continue
      fi
      df_rename "$entry" "$stage/$base"; rc=$?
      if [ "$rc" -eq 0 ]; then
        moved=$((moved+1)); df_log "LEGACY MIGRATION moved outside games/: $sys/$base"
      else
        held=$((held+1)); df_log "LEGACY MIGRATION held: $sys/$base"
      fi
    done
    # Finder metadata is never a game. Removing it lets an otherwise empty old
    # queue disappear; real queue entries are never deleted here.
    rm -f "$legacy"/.DS_Store "$legacy"/._* 2>/dev/null || true
    rmdir "$legacy" 2>/dev/null || true
  done
  [ "$moved" -eq 0 ] || { sync 2>/dev/null || true; df_log "LEGACY MIGRATION complete: $moved moved, $held held"; }
  return 0
}

# Upgrade the queue layout without processing schedule requests or revealing
# anything. This is useful while an SD card is mounted on a computer: every
# entry is a same-filesystem rename, so an interruption merely leaves the rest
# for the next pass.
df_migrate_only() {
  if ! df_lock_wait; then
    echo "Dripfeed is busy; no queue entries were moved."
    return 1
  fi
  df_migrate_legacy_queues; local rc=$?
  df_unlock
  return "$rc"
}

df_request_fields_ok() {
  [ -n "$1" ] && [ -n "$2" ] &&
    case "$1$2" in *$'\t'*|*$'\r'*|*$'\n'*|*/*|*\\*|*"$DF_US"*) false;; *) true;; esac &&
    case "$1" in .|..) false;; *) true;; esac &&
    case "$2" in .|..|"$STAGE_DIRNAME") false;; *) true;; esac   # never a parent or a queue folder
}

# Annotate a request ledger with what the queue already holds for each row, in ONE
# awk pass over a prebuilt index (the old per-row rescans spawned processes
# quadratically: minutes of CPU at boot for a few hundred games). Rows are split
# exactly as bash `IFS=$'\t' read` splits them; when one game is requested more
# than once, its LAST row wins. Output fields, separated by DF_US:
#   extra-fields-flag  superseded-flag  date  system  name  queued-count  queued-path
df_annotate_requests() {   # $1 ledger  $2 index  $3 = 3 (schedule) or 2 (unschedule)
  LC_ALL=C awk -F'\t' -v nf="$3" -v US="$DF_US" '
    FILENAME == ARGV[1] { k = $1 FS $2; c[k]++; if (!(k in p)) p[k] = $3; next }
    { line = $0; sub(/^\t+/, "", line); sub(/\t+$/, "", line)
      m = split(line, f, /\t+/); n++
      X[n] = (m > nf) ? "x" : ""
      if (nf == 3) { D[n] = f[1]; S[n] = f[2]; N[n] = f[3] } else { D[n] = ""; S[n] = f[1]; N[n] = f[2] }
      if (S[n] != "" && N[n] != "") last[S[n] FS N[n]] = n }
    END { for (i = 1; i <= n; i++) {
            k = S[i] FS N[i]; sup = ((k in last) && last[k] != i) ? "dup" : ""
            cnt = (k in c) ? c[k] : 0
            printf "%s%s%s%s%s%s%s%s%s%s%d%s%s\n", X[i], US, sup, US, D[i], US, S[i], US, N[i], US, cnt, US, (cnt == 1 ? p[k] : "") } }
  ' "$2" "$1"
}

df_process_unschedule_requests() {
  [ -s "$DF_UNSCHEDULE_REQUESTS" ] || return 0
  local tmp="$DF_UNSCHEDULE_REQUESTS.tmp.$$" idx="$DF_STATE/.index.$$" ann="$DF_STATE/.requests.$$"
  local extra sup d sys name count staged dest rc
  df_index_write "$idx"
  df_annotate_requests "$DF_UNSCHEDULE_REQUESTS" "$idx" 2 > "$ann"
  : > "$tmp"
  while IFS="$DF_US" read -r extra sup d sys name count staged; do
    if [ -n "$extra" ] || ! df_request_fields_ok "$sys" "$name"; then
      df_log "BAD browser unschedule request ignored: $sys/$name"; continue
    fi
    [ -z "$sup" ] || { df_log "BROWSER UNSCHEDULE repeated row merged: $sys/$name"; continue; }
    dest="$GAMES_DIR/$sys/$name"
    if [ "$count" -gt 1 ]; then
      printf '%s\t%s\n' "$sys" "$name" >> "$tmp"
      df_log "BROWSER UNSCHEDULE held (duplicate queue entries): $sys/$name"
      continue
    fi
    if [ -e "$dest" ] && [ -z "$staged" ]; then
      df_log "BROWSER UNSCHEDULE already visible: $sys/$name"; continue
    fi
    if [ -e "$dest" ] || [ -z "$staged" ]; then
      printf '%s\t%s\n' "$sys" "$name" >> "$tmp"
      df_log "BROWSER UNSCHEDULE held (missing/collision): $sys/$name"; continue
    fi
    [ -d "$GAMES_DIR/$sys" ] || mkdir -p "$GAMES_DIR/$sys" 2>/dev/null || { printf '%s\t%s\n' "$sys" "$name" >> "$tmp"; continue; }
    df_rename "$staged" "$dest"; rc=$?
    if [ "$rc" -eq 0 ]; then df_log "BROWSER UNSCHEDULE applied: $sys/$name"
    else
      printf '%s\t%s\n' "$sys" "$name" >> "$tmp"
      [ "$rc" -eq 2 ] && df_log "BROWSER UNSCHEDULE held (different drives): $sys/$name"
    fi
  done < "$ann"
  mv "$tmp" "$DF_UNSCHEDULE_REQUESTS"; sync
  rm -f "$idx" "$ann" 2>/dev/null
}

df_process_schedule_requests() {
  [ -s "$DF_SCHEDULE_REQUESTS" ] || return 0
  local tmp="$DF_SCHEDULE_REQUESTS.tmp.$$" idx="$DF_STATE/.index.$$" ann="$DF_STATE/.requests.$$"
  local extra sup d sys name count staged source stage dest rc
  df_index_write "$idx"
  df_annotate_requests "$DF_SCHEDULE_REQUESTS" "$idx" 3 > "$ann"
  : > "$tmp"
  while IFS="$DF_US" read -r extra sup d sys name count staged; do
    if [ -n "$extra" ] || ! df_valid_date "$d" || ! df_request_fields_ok "$sys" "$name"; then
      df_log "BAD browser schedule request ignored: $d $sys/$name"; continue
    fi
    [ -z "$sup" ] || { df_log "BROWSER SCHEDULE earlier row superseded: $d $sys/$name"; continue; }
    source="$GAMES_DIR/$sys/$name"; stage="$STAGING_ROOT/$sys"; dest="$stage/${d}_$name"
    if df_is_shortcut_dir "$name"; then
      df_log "SKIP browser request for Dripfeed's own shortcut folder: $sys/$name"; continue
    fi
    if [ -e "$source" ] && df_support_entry "$source"; then
      df_log "SKIP browser firmware/support request: $sys/$name"; continue
    fi
    if [ -f "$source" ] && [ ! -s "$source" ]; then
      df_log "SKIP browser request for an empty (0-byte) file: $sys/$name"; continue
    fi
    if [ "$count" -gt 1 ]; then
      printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"
      df_log "BROWSER SCHEDULE held (duplicate queue entries): $d $sys/$name"
      continue
    fi
    if [ "$staged" = "$dest" ] && [ -e "$dest" ]; then
      df_log "BROWSER SCHEDULE already applied: $d $sys/$name"; continue
    fi
    if [ -e "$dest" ]; then
      printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"
      df_log "BROWSER SCHEDULE held (destination exists): $d $sys/$name"; continue
    fi
    [ -d "$stage" ] || mkdir -p "$stage" 2>/dev/null || { printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"; continue; }
    if [ -n "$staged" ]; then
      df_rename "$staged" "$dest"; rc=$?
      [ "$rc" -eq 0 ] && df_log "BROWSER REDATE applied: $d $sys/$name"
    elif [ -e "$source" ]; then
      df_rename "$source" "$dest"; rc=$?
      [ "$rc" -eq 0 ] && df_log "BROWSER SCHEDULE applied: $d $sys/$name"
    else
      rc=1; df_log "BROWSER SCHEDULE held (source missing): $d $sys/$name"
    fi
    if [ "$rc" -ne 0 ]; then
      printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"
      [ "$rc" -eq 2 ] && df_log "BROWSER SCHEDULE held (different drives): $d $sys/$name"
    fi
  done < "$ann"
  mv "$tmp" "$DF_SCHEDULE_REQUESTS"; sync
  rm -f "$idx" "$ann" 2>/dev/null
}

# Print due entries as date<TAB>system<TAB>path. Builtins only per entry; the
# (slower) completeness and firmware checks run only for entries that are due.
df_find_due() {
  local today stage entry base sysname sysdir
  df_strftime today '%Y%m%d'
  # Current queue: one hidden library outside games/. A staged folder can be
  # renamed into its final system folder atomically, so every disc arrives or
  # none of them does.
  for stage in "$STAGING_ROOT"/*/; do
    [ -d "$stage" ] || continue
    sysname="${stage%/}"; sysname="${sysname##*/}"
    [ -d "$GAMES_DIR/$sysname" ] || { df_log "SKIP queue for missing system: $sysname"; continue; }
    for entry in "$stage"*; do
      base="${entry##*/}"
      df_is_valid_prefix "$base" || continue
      [ "${base:0:4}${base:5:2}${base:8:2}" -le "$today" ] 2>/dev/null || continue
      [ -e "$entry" ] || continue
      if ! df_queue_entry_complete "$entry"; then
        df_log "RECOVERY HOLD: incomplete or empty staged entry: $entry"
        continue
      fi
      if df_support_entry "$entry"; then
        df_log "SKIP firmware/support queue entry: $entry"
        continue
      fi
      printf '%s\t%s\t%s\n' "${base:0:10}" "$sysname" "$entry"
    done
  done
  # Legacy queue: kept readable so upgrades never strand already scheduled
  # games. New scheduling never writes here.
  for sysdir in "$GAMES_DIR"/*/; do
    stage="$sysdir$STAGE_DIRNAME/"
    [ -d "$stage" ] || continue
    sysname="${sysdir%/}"; sysname="${sysname##*/}"
    for entry in "$stage"*; do
      base="${entry##*/}"
      df_is_valid_prefix "$base" || continue
      [ "${base:0:4}${base:5:2}${base:8:2}" -le "$today" ] 2>/dev/null || continue
      [ -e "$entry" ] || continue
      if ! df_queue_entry_complete "$entry"; then
        df_log "RECOVERY HOLD: incomplete or empty legacy staged entry: $entry"
        continue
      fi
      if df_support_entry "$entry"; then
        # A legacy CSV/manual run may have queued firmware (for example
        # MegaCD/USA/cd_bios.rom). Leave it untouched and never reveal it.
        df_log "SKIP firmware/support queue entry: $entry"
        continue
      fi
      printf '%s\t%s\t%s\n' "${base:0:10}" "$sysname" "$entry"
    done
  done
}

# 0 revealed, 1 failed (nothing changed), 2 destination exists, 3 incomplete,
# 4 held because the queue and the system folder are on different drives.
df_reveal_entry() {
  local d="$1" sysname="$2" entry="$3" base clean dest rc
  base="${entry##*/}"
  [ -d "$GAMES_DIR/$sysname" ] || { df_log "FAIL missing system folder: $sysname"; return 1; }
  df_queue_entry_complete "$entry" || { df_log "RECOVERY HOLD: incomplete queue entry: $entry"; return 3; }
  clean="${base:11}"; dest="$GAMES_DIR/$sysname/$clean"
  REVEAL_SYS="$sysname"; REVEAL_NAME="$clean"; REVEAL_DEST="$dest"
  if [ -e "$dest" ]; then df_log "SKIP exists: $sysname/$clean"; return 2; fi
  if ! df_same_fs "${entry%/*}" "$GAMES_DIR/$sysname"; then
    DF_XDEV_HOLDS=$((DF_XDEV_HOLDS+1))
    df_log "CROSS-DEVICE HOLD (different drives; Dripfeed never copies games): $entry -> $dest"
    return 4
  fi
  df_tx_begin "$d" "$sysname" "$clean" "$entry" "$dest" || { df_log "FAIL journal: $entry -> $dest"; return 1; }
  df_rename "$entry" "$dest"; rc=$?
  if [ "$rc" -ne 0 ]; then
    df_tx_clear; df_log "FAIL rename (nothing changed): $entry -> $dest"
    [ "$rc" -eq 2 ] && return 4
    return 1
  fi
  # Test hook: simulate power loss in the only vulnerable window. Production
  # never sets this variable; the next run repairs the ledger and shortcut.
  [ "${DRIPFEED_TEST_INTERRUPT_AFTER_MOVE:-0}" = "1" ] && return 75
  df_log "REVEAL: $sysname/$clean"; return 0
}

# Point at the ONE showcase folder (the saved STICKY name — renamed only when
# df_showcase_stamp_name was called for a real reveal), and foolproof-consolidate any
# strays into it: folders with a recorded Dripfeed name or a legacy default name,
# and folders with the configured prefix that hold only Dripfeed shortcuts. A stray
# is merged and removed only when it holds nothing but shortcut files; anything a
# user put there is left alone. Ordinary boots keep the exact same folder name.
df_showcase_prepare() {
  SHOWCASE_DIR=""
  [ "${SHOWCASE:-1}" -eq 1 ] || return 0
  [ -n "$DF_ROOT" ] || return 0
  local name canon d n m target
  name="$(df_showcase_current_name)"; canon="$DF_ROOT/$name"
  [ -d "$canon" ] || mkdir -p "$canon"
  df_record_add "$DF_SHOWNAMES" "$name"
  for d in "$DF_ROOT"/_*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; n="${d##*/}"
    [ "$d" = "$canon" ] && continue
    [ "$d" -ef "$canon" ] && continue
    df_showcase_kind "$n" || continue
    if [ "$DF_SHOWCASE_KIND" = prefix ]; then df_dir_only_shortcuts "$d" strict || continue
    else df_dir_only_shortcuts "$d" || { df_log "kept $n (it holds files Dripfeed did not create)"; continue; }; fi
    for m in "$d"/*.mgl; do
      [ -f "$m" ] || continue
      cp -pf "$m" "$canon"/ 2>/dev/null && rm -f "$m"
    done
    df_remove_shortcut_dir "$d"
    [ -d "$d" ] || df_log "consolidated old What's New folder: $n"
  done
  # Prune shortcuts whose target game is gone (rescheduled/moved) so nothing
  # flip-flops. The path is XML-unescaped first: "Kirby&apos;s" is "Kirby's".
  for m in "$canon"/*.mgl; do
    [ -e "$m" ] || continue
    target="$(df_mgl_path "$m")"
    [ -n "$target" ] && [ ! -e "$target" ] && { rm -f "$m"; df_log "pruned orphan: ${m##*/}"; }
  done
  SHOWCASE_DIR="$canon"; export SHOWCASE_DIR
}

# ---- Game of the Month ---------------------------------------------------------
# gotm.tsv (written by the web scheduler) holds one pick per month:
#     YYYY-MM<TAB>path-relative-to-/media/fat
# Console/handheld/computer picks get an .mgl shortcut; arcade picks (.mra) are
# copied in along with their core so they launch from the folder. The folder is
# only (re)built when the month or the pick changes — never renamed on plain boots.
# A pick that is still hidden (scheduled but not yet revealed) is retried on every
# pass and appears the moment Dripfeed reveals it. Visible games are NEVER renamed.
# USER pick for a month, from gotm.tsv. Optional 3rd field = custom shortcut label.
df_gotm_user_pick() {
  [ -f "$DF_GOTM" ] || return 0
  awk -F'\t' -v m="$1" '$1==m{ print $2 "\t" $3; exit }' "$DF_GOTM"
}

# COMMUNITY pick for a month, from GOTM_SOURCE (file path, or URL fetched to state).
# Runs IN PARALLEL with the user pick — each gets its own menu folder.
df_gotm_src_pick() {
  local month="$1" src="${GOTM_SOURCE:-}" cache="$DF_STATE/gotm-community.tsv"
  [ -n "$src" ] || return 0
  case "$src" in
    http://*|https://*) curl -sfL -m 15 "$src" -o "$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache" ;;
    *) [ -f "$src" ] && cache="$src" ;;
  esac
  [ -f "$cache" ] || return 0
  # Only rows whose 2nd field is a real path (contains "/") are used today.
  # Reserved for the future: "YYYY-MM<TAB>SYSTEM<TAB>Title" rows (no slash) will get
  # fuzzy title matching against the user's own rom names.
  awk -F'\t' -v m="$month" '$1==m && index($2,"/")>0 { print $2 "\t" $3; exit }' "$cache"
}

# The arcade core an .mra names, picked the way the MiSTer firmware picks it: a
# file named exactly "<rbf>" or "Arcade-<rbf>" followed by "_" or "." (compared
# case-insensitively), the newest by C-locale name order. Prints the path.
df_arcade_core() {
  local rbf="$1" dir="$DF_ROOT/_Arcade/cores" f n nc=0 list=""
  [ -n "$rbf" ] && [ -d "$dir" ] || return 1
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    n="${f##*/}"
    [[ "$n" == *.rbf ]] || continue
    if [[ "$n" == "$rbf"[._]* ]] || [[ "$n" == "Arcade-$rbf"[._]* ]]; then list="$list$n"$'\n'; fi
  done
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  [ -n "$list" ] || return 1
  n=$(printf '%s' "$list" | LC_ALL=C sort | tail -n 1)
  [ -n "$n" ] && printf '%s/%s\n' "$dir" "$n"
}

# A Game of the Month folder is removed only when it holds nothing but what
# df_gotm_build writes (.mgl/.mra shortcuts, gamelist.xml, a cores/ folder of .rbf
# files) and is not one of MiSTer's own folders — so a GOTM_DIRNAME such as
# "_Arcade" can never wipe a real core or game folder.
df_gotm_dir_like() {
  local d="$1" f g n nc=0 rc=0
  [ -d "$d" ] || return 0
  n="${d##*/}"
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  df_mister_folder "$n" && rc=1
  [ -f "$DF_SHOWNAME" ] && [[ "$n" == "$(cat "$DF_SHOWNAME" 2>/dev/null)" ]] && rc=1
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  [ "$rc" -eq 0 ] || return 1
  for f in "$d"/* "$d"/.[!.]*; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    case "${f##*/}" in
      *.mgl|*.mra|*.MRA|gamelist.xml|.DS_Store|._*) [ -f "$f" ] || return 1 ;;
      cores)
        [ -d "$f" ] || return 1
        for g in "$f"/* "$f"/.[!.]*; do
          [ -e "$g" ] || [ -L "$g" ] || continue
          case "${g##*/}" in *.rbf|*.RBF|.DS_Store|._*) [ -f "$g" ] || return 1 ;; *) return 1 ;; esac
        done ;;
      *) return 1 ;;
    esac
  done
  return 0
}
df_gotm_clear() {   # remove Dripfeed's GOT'eM folders; leave anything else alone
  local d rc=0
  for d in "$@"; do
    [ -e "$d" ] || continue
    if df_gotm_dir_like "$d"; then rm -rf "$d" 2>/dev/null
    else df_log "GOTM: left ${d##*/} alone (it is a MiSTer folder or holds files Dripfeed did not create)"; rc=1; fi
  done
  return "$rc"
}

# Build ONE Game of the Month folder.  $1=folder base  $2=pick path  $3=custom label
# Returns 1 if the pick exists but its file isn't on disk yet (caller retries later).
df_gotm_build() {
  local base label dir want="$2" custom="$3" target
  base="$(df_showcase_sanitize "$1")"
  label="$base"
  [ "${GOTM_MONTH:-0}" -eq 1 ] && label="$(df_showcase_sanitize "$base - $(date +%b)")"
  dir="$DF_ROOT/$label"
  if [ -z "$want" ]; then                       # no pick: clear this folder family
    df_gotm_clear "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "*
    return 0
  fi
  target="$DF_ROOT/$want"
  if [ ! -e "$target" ]; then
    df_log "GOTM ($base): '$want' not found yet (still scheduled?) - will retry"
    return 1
  fi
  # replace, never duplicate: clear this month's name AND any older-month leftovers
  df_gotm_clear "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "*
  if [ -e "$dir" ]; then
    df_log "GOTM ($base): cannot use '$label' as the Game of the Month folder - choose another name"
    return 0
  fi
  mkdir -p "$dir"
  df_record_add "$DF_GOTM_NAMES" "$label"
  case "$want" in
    *.[Mm][Rr][Aa])
      if [ -n "$custom" ]; then cp -f "$target" "$dir/$(df_showcase_sanitize "_$custom" | cut -c2-).mra" 2>/dev/null
      else cp -f "$target" "$dir/" 2>/dev/null; fi
      local rbf corefile
      rbf=$(sed -n 's/.*<rbf>\(.*\)<\/rbf>.*/\1/p' "$target" | head -n 1)
      df_trim rbf
      if [ -n "$rbf" ]; then
        if corefile=$(df_arcade_core "$rbf"); then
          mkdir -p "$dir/cores"; cp -f "$corefile" "$dir/cores/" 2>/dev/null
          df_log "GOTM ($base): core ${corefile##*/}"
        else
          df_log "GOTM ($base): no core named '$rbf' or 'Arcade-$rbf' in _Arcade/cores"
        fi
      fi ;;
    *)
      local rel sys
      rel="${want#*/}"; sys="${rel%%/*}"
      if ! df_make_mgl "$dir" "$sys" "$target" "$custom"; then
        df_log "GOTM ($base): nothing MiSTer can launch for '$want' - no shortcut"
        rmdir "$dir" 2>/dev/null
        return 0
      fi ;;
  esac
  df_log "GOTM built ($base): $want"
  return 0
}

df_gotm_update() {
  [ "${GOTM:-1}" -eq 1 ] || return 0
  { [ -f "$DF_GOTM" ] || [ -n "${GOTM_SOURCE:-}" ]; } || return 0
  df_clock_ok || return 0                       # never act on an unsynced clock
  local month cur u s upick ulabel spick slabel TAB ok=0
  TAB="$(printf '\t')"
  month=$(date +%Y-%m)
  u="$(df_gotm_user_pick "$month")"; upick="${u%%$TAB*}"; ulabel="${u#*$TAB}"; [ "$ulabel" = "$u" ] && ulabel=""
  s="$(df_gotm_src_pick "$month")";  spick="${s%%$TAB*}"; slabel="${s#*$TAB}"; [ "$slabel" = "$s" ] && slabel=""
  cur=$(cat "$DF_GOTM_LAST" 2>/dev/null)
  [ "$cur" = "$month|$upick|$spick" ] && return 0
  df_gotm_build "${GOTM_DIRNAME:-_Game of the Month}" "$upick" "$ulabel" || ok=1
  if [ -n "${GOTM_SOURCE:-}" ]; then
    df_gotm_build "${GOTM_SRC_DIRNAME:-_Discord GOTM}" "$spick" "$slabel" || ok=1
  fi
  [ "$ok" -eq 0 ] && printf '%s' "$month|$upick|$spick" > "$DF_GOTM_LAST"   # else retry next pass
}

# Keep only the newest SHOWCASE_KEEP shortcuts, refresh gamelist.xml, then the
# optional Favorites mirror and per-system shortcut folders (both also clean up
# after themselves when switched off).
df_showcase_finalize() {
  if [ -n "${SHOWCASE_DIR:-}" ] && [ -d "$SHOWCASE_DIR" ]; then
    ls -1t "$SHOWCASE_DIR"/*.mgl 2>/dev/null | tail -n +$(( ${SHOWCASE_KEEP:-12} + 1 )) | while IFS= read -r old; do rm -f "$old"; done
    df_write_gamelist "$SHOWCASE_DIR"
  fi
  df_mirror_favorites "${SHOWCASE_DIR:-}"
  df_system_shortcuts_finalize
}

# One reveal pass under the lock. Returns 2 (and changes nothing) when another
# Dripfeed process holds the lock.
df_run_reveal() {
  local interactive=0 rc
  if [ "${1:-}" != "--silent" ]; then
    { [ "${DRIPFEED_INTERACTIVE:-0}" = "1" ] || df_have_tty; } && interactive=1
  fi
  # Only one pass at a time (boot daemon vs. a manual launch vs. the CLI/Undrip).
  if ! df_lock; then
    df_log "reveal skipped (another pass holds the lock)"
    [ "$interactive" -eq 1 ] && df_announce "Dripfeed is busy finishing up — try again in a moment."
    return 2
  fi
  DF_PASS_REVEALED=0; DF_PASS_SYSTEMS=""
  df_reveal_pass "$interactive"; rc=$?
  df_unlock
  # Optional user command (e.g. ask a frontend to refresh its library): once per
  # pass that revealed something, always with a timeout, and after the lock is
  # released so a slow command never blocks Dripfeed itself.
  [ "$DF_PASS_REVEALED" -gt 0 ] && df_post_reveal "$DF_PASS_REVEALED" "$DF_PASS_SYSTEMS"
  return "$rc"
}

df_reveal_pass() {
  local interactive="$1"
  df_migrate_legacy_queues
  df_process_unschedule_requests
  df_process_schedule_requests
  # Never reveal / name a folder on an unsynced clock (would create a 1970-dated folder
  # and reveal games with the wrong date).
  if ! df_clock_ok; then
    df_log "reveal skipped: clock not set (year $(date +%Y 2>/dev/null))"
    [ "$interactive" -eq 1 ] && df_announce "Console clock isn't set yet. Set the time (Scripts > timezone / WiFi), then try again."
    return 0
  fi
  local recovered="$DF_STATE/.recovered.$$"
  : > "$recovered"
  df_tx_recover > "$recovered" 2>/dev/null || true
  local recovered_count; recovered_count=$(wc -l < "$recovered" 2>/dev/null | tr -d '[:space:]')
  [ -n "$recovered_count" ] || recovered_count=0
  local due; due=$(df_find_due | sort)
  local count=0 line
  while IFS= read -r line; do [ -n "$line" ] && count=$((count+1)); done <<EOF_COUNT
$due
EOF_COUNT
  df_log "reveal pass (interactive=$interactive): $count due"
  if [ -z "$due" ] && [ "$recovered_count" -eq 0 ]; then
    rm -f "$recovered" 2>/dev/null
    # Nothing due: tidy the CURRENT (sticky-named) folder only — consolidate strays,
    # prune orphans, refresh gamelist. NEVER rename it (that made every boot look
    # like an update and renamed the folder out from under frontends).
    df_showcase_prepare
    df_showcase_finalize
    df_gotm_update
    [ "$interactive" -eq 1 ] && df_announce "No new games scheduled for today."
    return 0
  fi
  # Pass 1: reveal the due games (no subshell — counters survive the loop).
  local revealed="$recovered_count" d sys entry rc last_date="" msg held_xdev=0 systems=""
  local revlist="$DF_STATE/.revealed.$$" rsys rname rdate rdest
  mv "$recovered" "$revlist" 2>/dev/null || : > "$revlist"
  if [ "$recovered_count" -gt 0 ]; then
    while IFS=$'\t' read -r rsys rname rdate rdest; do
      [ -n "$rname" ] || continue
      df_touch_revealed "$rdest"
      if [ "$interactive" -eq 1 ]; then
        df_announce "RECOVERED AFTER POWER LOSS:  $rname    [$rsys]"
      else
        printf '%s\t%s\t%s\n' "$rsys" "$rname" "$rdate" >> "$DF_PENDING"
      fi
    done < "$revlist"
  fi
  while IFS=$'\t' read -r d sys entry; do
    [ -n "$entry" ] && [ -e "$entry" ] || continue
    df_reveal_entry "$d" "$sys" "$entry"; rc=$?
    [ "$rc" -eq 4 ] && { held_xdev=$((held_xdev+1)); continue; }
    [ "$rc" -eq 1 ] && continue
    if [ "$rc" -eq 0 ]; then
      revealed=$((revealed+1))
      df_ledger_record "$d" "$REVEAL_SYS" "$REVEAL_NAME"
      df_tx_clear
      df_touch_revealed "$REVEAL_DEST"
      printf '%s\t%s\t%s\t%s\n' "$REVEAL_SYS" "$REVEAL_NAME" "$d" "$REVEAL_DEST" >> "$revlist"
    fi
    if [ "$interactive" -eq 1 ]; then
      if [ "$d" != "$last_date" ]; then
        msg=$(df_occasion "$d"); [ -n "$msg" ] && df_announce "$msg"
        last_date="$d"
      fi
      [ "$rc" -eq 0 ] && df_announce "NEW GAME UNLOCKED:  $REVEAL_NAME    [$REVEAL_SYS]"
    elif [ "$rc" -eq 0 ]; then
      printf '%s\t%s\t%s\n' "$REVEAL_SYS" "$REVEAL_NAME" "$d" >> "$DF_PENDING"
    fi
  done <<EOF_DUE
$due
EOF_DUE
  # Pass 2: only a REAL unlock re-stamps the folder name (today's date, or today's
  # custom message which then sticks until the next unlock), then builds shortcuts.
  if [ "$revealed" -gt 0 ]; then
    df_showcase_stamp_name >/dev/null
    df_showcase_prepare
    while IFS=$'\t' read -r rsys rname rdate rdest; do
      [ -n "$rdest" ] || continue
      [ -n "$SHOWCASE_DIR" ] && df_make_mgl "$SHOWCASE_DIR" "$rsys" "$rdest"
      df_system_shortcut_add "$rsys" "$rdest"
      case " $systems " in *" $rsys "*) ;; *) systems="${systems:+$systems }$rsys" ;; esac
    done < "$revlist"
  else
    df_showcase_prepare
  fi
  rm -f "$revlist" 2>/dev/null
  df_showcase_finalize
  df_gotm_update
  DF_PASS_REVEALED="$revealed"; DF_PASS_SYSTEMS="$systems"
  if [ "$interactive" -eq 1 ]; then
    [ "$held_xdev" -gt 0 ] && df_announce "HELD: $held_xdev game(s) are on a different drive than the waiting library. See --diag."
    df_announce "All caught up. Enjoy!"
    [ -n "$SHOWCASE_DIR" ] && echo "  New games are also collected in the menu folder: ${SHOWCASE_DIR##*/}"
    echo "  If a game isn't showing yet, back out of the folder and re-open it."
    [ "$revealed" -gt 0 ] && echo "  $DF_FRONTEND_HINT"
    echo
  fi
  return 0
}

df_announce_pending() {
  [ "${DRIPFEED_INTERACTIVE:-0}" = "1" ] || df_have_tty || return 0
  [ -s "$DF_PENDING" ] || return 0
  df_announce "WHILE YOU WERE AWAY - NEW GAMES ADDED"
  local sys name d last_date="" msg
  sort -t"$(printf '\t')" -k3 "$DF_PENDING" | while IFS=$'\t' read -r sys name d; do
    [ -n "$name" ] || continue
    if [ -n "$d" ] && [ "$d" != "$last_date" ]; then
      msg=$(df_occasion "$d"); [ -n "$msg" ] && { echo; echo "    >>> $msg <<<"; echo; }
      last_date="$d"
    fi
    echo "    * $name    [$sys]"
  done
  echo
  echo "  $DF_FRONTEND_HINT"
  echo
  : > "$DF_PENDING"
}

df_watch() {
  df_log_trim
  df_boot_id
  printf '%s\n%s\n' "$$" "$DF_BOOT_ID" > "$DF_WATCHPID" 2>/dev/null
  df_log "watch start (BOOT_DELAY=${BOOT_DELAY:-30})"
  # Hiding requested games does not depend on the clock. Do it immediately so
  # the ordinary game tree is clean as early in boot as this user hook allows.
  if df_lock; then
    df_migrate_legacy_queues
    df_process_unschedule_requests
    df_process_schedule_requests
    df_unlock
  fi
  sleep "${BOOT_DELAY:-30}"
  # Wait until games/ is mounted AND the clock is synced (RTC/network time) before the
  # boot update runs — revealing on a 1970 clock is what created a wrong-dated folder.
  # We wait INDEFINITELY (no try-cap): the moment a current network clock appears, the
  # update runs. On a console with no network/RTC it simply never fires (by design),
  # and that is logged so it's diagnosable.
  local waited=0
  while [ ! -d "$GAMES_DIR" ] || ! df_clock_ok; do
    sleep 5; waited=$((waited+5))
    [ $(( waited % 300 )) -eq 0 ] && df_log "watch: still waiting (games dir: $([ -d "$GAMES_DIR" ] && echo ok || echo no), clock: $(df_clock_ok && echo ok || echo unset)) ${waited}s"
  done
  [ "$waited" -gt 0 ] && df_log "watch: ready after ${waited}s — running boot update"
  local day rc=0
  if [ "${REVEAL_AT_BOOT:-1}" -eq 1 ]; then df_run_reveal --silent; rc=$?; fi
  # A pass skipped because another process held the lock is retried later.
  [ "$rc" -eq 2 ] || df_today_int > "$DF_LASTDAY"
  [ "${DAILY:-1}" -eq 1 ] || { df_log "watch done (daily off)"; return 0; }
  while :; do
    sleep "${WATCH_INTERVAL:-3600}"     # validated: never below 60 seconds
    day=$(df_today_int)
    if [ "$day" != "$(cat "$DF_LASTDAY" 2>/dev/null)" ]; then
      df_run_reveal --silent; rc=$?
      [ "$rc" -eq 2 ] || echo "$day" > "$DF_LASTDAY"
    fi
  done
}

df_diag() {
  local gid lid sys idx ann kind path count base clean flags n s cand
  echo "Dripfeed diagnostics"
  echo "  DF_ROOT     : $DF_ROOT   (exists: $([ -d "$DF_ROOT" ] && echo yes || echo NO))"
  echo "  GAMES_DIR   : $GAMES_DIR (exists: $([ -d "$GAMES_DIR" ] && echo yes || echo NO))"
  echo "  QUEUE_ROOT  : $STAGING_ROOT (exists: $([ -d "$STAGING_ROOT" ] && echo yes || echo no))"
  df_fs_id "$GAMES_DIR"; gid="$DF_FSID"; df_fs_id "$STAGING_ROOT"; lid="$DF_FSID"
  if [ -n "$gid" ] && [ "$gid" = "$lid" ]; then
    echo "  drives      : games and waiting library on the same drive (device:mount $gid) - moves are instant renames"
  else
    echo "  drives      : DIFFERENT DRIVES or mounts (games ${gid:-?}, library ${lid:-?}; device:mount)"
    echo "                Dripfeed never copies games between drives: these moves are HELD, not copied."
  fi
  echo "  STATE       : $DF_STATE  (exists: $([ -d "$DF_STATE" ] && echo yes || echo NO))"
  echo "  config.ini  : $([ -f "$DF_CONFIG" ] && echo present || echo MISSING)"
  if grep -q DRIPFEED_AUTORUN "$DF_USERSTARTUP" 2>/dev/null; then
    if grep -q 'in start|' "$DF_USERSTARTUP" 2>/dev/null; then
      echo "  boot hook   : present (starts at boot only) in $DF_USERSTARTUP"
    else
      echo "  boot hook   : present but OUTDATED (also runs at shutdown) - open Dripfeed.sh once to update it"
    fi
  else
    echo "  boot hook   : MISSING in $DF_USERSTARTUP"
  fi
  echo "  lock        : $(df_lock_describe)"
  echo "  clock       : $(date '+%Y-%m-%d %H:%M') $(df_clock_ok && echo '(OK)' || echo '(NOT SET - reveals paused)')"
  echo "  today       : $(df_today_int)"
  echo "  showcase    : $(cat "$DF_SHOWNAME" 2>/dev/null || echo '(not stamped yet)')  (renames only when a game unlocks)"
  echo "  options     : SYSTEM_SHORTCUTS=$SYSTEM_SHORTCUTS ($SYSTEM_SHORTCUTS_DIR)  TOUCH_ON_REVEAL=$TOUCH_ON_REVEAL  POST_REVEAL_CMD=$([ -n "$POST_REVEAL_CMD" ] && echo set || echo none)  FAVORITES_MIRROR=$FAVORITES_MIRROR"
  echo "  queue (due shown first):"
  df_find_due | sort | while IFS=$'\t' read -r d s path; do base="${path##*/}"; echo "    DUE  $d  $s/${base:11}"; done
  # Full queue from ONE index walk; duplicate counts come from one awk pass.
  idx="$DF_STATE/.diag-index.$$"; ann="$DF_STATE/.diag.$$"
  [ -d "$DF_STATE" ] || mkdir -p "$DF_STATE" 2>/dev/null
  df_index_write "$idx"
  LC_ALL=C awk -F'\t' 'FNR == 1 { pass++ } pass == 1 { c[$1 FS $2]++; next } { print $4 "\t" $1 "\t" c[$1 FS $2] "\t" $3 }' "$idx" "$idx" > "$ann"
  for kind in new legacy; do
    if [ "$kind" = new ]; then echo "  full queue:"; else echo "  legacy queue (upgrade-safe):"; fi
    while IFS=$'\t' read -r n sys count path; do
      [ "$n" = "$kind" ] || continue
      base="${path##*/}"; clean="${base:11}"; flags=""
      if [ -f "$path" ] && [ ! -s "$path" ]; then flags="$flags EMPTY-FILE-HOLD"
      elif ! df_queue_entry_complete "$path"; then flags="$flags INCOMPLETE-HOLD"; fi
      [ -e "$GAMES_DIR/$sys/$clean" ] && flags="$flags VISIBLE-COLLISION"
      [ "$count" -gt 1 ] && flags="$flags DUPLICATE-$count"
      echo "    $base   [$sys]$flags"
    done < "$ann"
  done
  n=0
  for path in "$STAGING_ROOT"/*/*.[Cc][Rr][Ss][Ww][Aa][Pp] "$GAMES_DIR"/*/"$STAGE_DIRNAME"/*.[Cc][Rr][Ss][Ww][Aa][Pp]; do
    [ -e "$path" ] || continue
    [ "$n" -eq 1 ] || { echo "  browser leftovers (ignored):"; n=1; }
    s="${path%/*}"; s="${s%/"$STAGE_DIRNAME"}"; s="${s##*/}"
    echo "    ${path##*/}   [$s] BROWSER-SWAP-FILE (an interrupted browser copy; never revealed)"
  done
  n=$(grep -c . "$DF_SCHEDULE_REQUESTS" 2>/dev/null); s=$(grep -c . "$DF_UNSCHEDULE_REQUESTS" 2>/dev/null)
  echo "  browser move requests: schedule=${n:-0}, unschedule=${s:-0}"
  # Storage layout: MiSTer opens the FIRST matching system folder (USB, network,
  # cifs, card root) before games/ on the SD card, and moves must stay on one drive.
  echo "  storage checks:"
  local warned=0
  while IFS= read -r sys; do
    [ -n "$sys" ] || continue
    if ! df_same_fs "$GAMES_DIR/$sys" "$STAGING_ROOT/$sys"; then
      warned=1
      echo "    WARNING: $GAMES_DIR/$sys and the waiting library are on different drives."
      echo "             Dripfeed holds these moves (it never copies games between drives)."
    fi
    for cand in "$DF_MEDIA"/usb0 "$DF_MEDIA"/usb1 "$DF_MEDIA"/usb2 "$DF_MEDIA"/usb3 "$DF_MEDIA"/usb4 "$DF_MEDIA"/usb5 "$DF_MEDIA/network" "$DF_ROOT/cifs"; do
      for path in "$cand/$sys" "$cand/games/$sys"; do
        [ -d "$path" ] || continue
        warned=1
        echo "    WARNING: $path exists. MiSTer opens it for $sys instead of $GAMES_DIR/$sys,"
        echo "             so games Dripfeed reveals on the SD card may not appear in that core's browser."
      done
    done
    if [ "$GAMES_DIR" = "$DF_ROOT/games" ] && [ -d "$DF_ROOT/$sys" ]; then
      warned=1
      echo "    WARNING: $DF_ROOT/$sys exists. MiSTer opens it for $sys instead of $GAMES_DIR/$sys."
    fi
  done <<EOF_SYS
$(awk -F'\t' '!seen[$1]++ { print $1 }' "$idx" 2>/dev/null)
EOF_SYS
  [ "$warned" -eq 1 ] || echo "    ok (every system with queued games uses this card's games folder)"
  n=$(grep -c 'CROSS-DEVICE HOLD' "$DF_LOG" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] && echo "  log         : ${n} cross-device hold(s) recorded - see 'CROSS-DEVICE HOLD' lines"
  rm -f "$idx" "$ann" 2>/dev/null
  echo "  (log: $DF_LOG)"
  df_log "diag run"
}

# Stop a running boot watcher (only used by Undrip, which removes everything).
df_stop_watcher() {
  local pid="" boot=""
  [ -f "$DF_WATCHPID" ] || return 0
  { read -r pid; read -r boot; } < "$DF_WATCHPID"
  df_boot_id
  case "$pid" in ''|*[!0-9]*) return 0 ;; esac
  [ "$boot" = "$DF_BOOT_ID" ] && [ "$pid" != "$$" ] && df_pid_alive "$pid" || return 0
  # A pid can be reused after the watcher ended: only signal a process that is
  # still the Dripfeed engine.
  if [ -r "/proc/$pid/cmdline" ]; then
    local cmd
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmd" in *dripfeed-engine*) ;; *) return 0 ;; esac
  fi
  kill "$pid" 2>/dev/null
  return 0
}

# UNDRIP — full clean reset. Un-hide every staged game (regardless of date) back into
# its system folder, delete every Dripfeed folder/file (showcase folders, staging
# folders, state, boot hook, helpers) — keeping ONLY /media/fat/Scripts/Dripfeed.sh so
# the user can cleanly reinstall. It removes exactly what Dripfeed created, never a
# user's own folders or favorites, and never copies a game between drives.
DF_UNDRIP_N=0; DF_UNDRIP_HELD=0
df_undrip_quarantine() {   # $1 entry  $2 system  $3 message
  local entry="$1" qsys="$2" stamp root="$STAGING_ROOT/.conflicts"
  df_strftime stamp '%Y%m%d-%H%M%S'
  [ -d "$root/$qsys" ] || mkdir -p "$root/$qsys" 2>/dev/null
  if df_rename "$entry" "$root/$qsys/${stamp}_${entry##*/}"; then
    echo "  $3: $qsys/${4:-${entry##*/}}"
  else
    echo "  $3 (left where it is): ${entry}"
  fi
  DF_UNDRIP_HELD=$((DF_UNDRIP_HELD+1))
}
df_undrip_entry() {        # $1 entry  $2 system folder (with trailing /)  $3 system
  local entry="$1" sysdir="$2" qsys="$3" base clean rc
  base="${entry##*/}"
  case "$base" in
    *.[Cc][Rr][Ss][Ww][Aa][Pp]) df_undrip_quarantine "$entry" "$qsys" "INTERRUPTED BROWSER COPY HELD (never revealed)"; return ;;
  esac
  if df_is_valid_prefix "$base"; then clean="${base:11}"; else clean="$base"; fi
  if ! df_queue_entry_complete "$entry"; then
    df_undrip_quarantine "$entry" "$qsys" "INCOMPLETE COPY HELD (never revealed)" "$clean"
  elif [ -e "$sysdir$clean" ]; then
    df_undrip_quarantine "$entry" "$qsys" "CONFLICT HELD (nothing deleted)" "$clean"
  else
    df_rename "$entry" "$sysdir$clean"; rc=$?
    case "$rc" in
      0) DF_UNDRIP_N=$((DF_UNDRIP_N+1)) ;;
      2) echo "  DIFFERENT DRIVE - left in the waiting library: $qsys/$clean"; DF_UNDRIP_HELD=$((DF_UNDRIP_HELD+1)) ;;
      *) echo "  could not restore (left where it is): $qsys/$clean"; DF_UNDRIP_HELD=$((DF_UNDRIP_HELD+1)) ;;
    esac
  fi
}
# Remove every menu folder Dripfeed created: What's New folders (recorded names,
# legacy defaults, and configured-prefix folders holding only Dripfeed shortcuts),
# Game of the Month folders, the Favorites mirror, and per-system shortcut folders.
df_undrip_folders() {
  local d n gbase sbase
  for d in "$DF_ROOT"/_*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; n="${d##*/}"
    df_showcase_kind "$n" || continue
    if [ "$DF_SHOWCASE_KIND" = prefix ]; then df_dir_only_shortcuts "$d" strict || continue; fi
    df_remove_shortcut_dir "$d"
  done
  gbase="$(df_showcase_sanitize "${GOTM_DIRNAME:-_Game of the Month}")"
  sbase="$(df_showcase_sanitize "${GOTM_SRC_DIRNAME:-_Discord GOTM}")"
  df_gotm_clear "$DF_ROOT/$gbase" "$DF_ROOT/$gbase - "* "$DF_ROOT/$sbase" "$DF_ROOT/$sbase - "*
  df_gotm_clear "$DF_ROOT/_Game of the Month" "$DF_ROOT/_Game of the Month - "* \
                "$DF_ROOT/_Discord GOTM" "$DF_ROOT/_Discord GOTM - "*   # default names, in case config changed
  if [ -f "$DF_GOTM_NAMES" ]; then
    while IFS= read -r n || [ -n "$n" ]; do
      case "$n" in _*) ;; *) continue ;; esac
      case "$n" in */*) continue ;; esac
      df_gotm_clear "$DF_ROOT/$n"
    done < "$DF_GOTM_NAMES"
  fi
  # Favorites: our stable subfolder plus old Dripfeed-only mirror folders.
  FAVORITES_MIRROR=0; df_mirror_favorites ""
  # Per-system shortcut folders (switched "off" removes every one of them).
  SYSTEM_SHORTCUTS=0; df_system_shortcuts_finalize
}
df_undrip() {
  [ -n "$DF_ROOT" ] && [ -d "$GAMES_DIR" ] || { echo "Undrip: bad paths, aborting."; return 1; }
  if ! df_lock_wait; then
    echo "  $DF_BUSY_MSG"
    df_log "UNDRIP refused: another Dripfeed process holds the lock"
    return 1
  fi
  df_stop_watcher
  df_log "UNDRIP start"
  local sysdir stage entry qsys conflict_root="$STAGING_ROOT/.conflicts"
  DF_UNDRIP_N=0; DF_UNDRIP_HELD=0
  # 1) Reveal ALL staged games (ignore dates) so no ROM is left hidden.
  for stage in "$STAGING_ROOT"/*/; do
    [ -d "$stage" ] || continue
    qsys="${stage%/}"; qsys="${qsys##*/}"; sysdir="$GAMES_DIR/$qsys/"
    [ -d "$sysdir" ] || { echo "  held queue for missing system: $qsys"; DF_UNDRIP_HELD=$((DF_UNDRIP_HELD+1)); continue; }
    for entry in "$stage"*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      df_undrip_entry "$entry" "$sysdir" "$qsys"
    done
    rmdir "$stage" 2>/dev/null
  done
  for sysdir in "$GAMES_DIR"/*/; do
    stage="$sysdir$STAGE_DIRNAME"; [ -d "$stage" ] || continue
    qsys="${sysdir%/}"; qsys="${qsys##*/}"
    for entry in "$stage"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      df_undrip_entry "$entry" "$sysdir" "$qsys"
    done
    rm -f "$stage"/.DS_Store "$stage"/._* 2>/dev/null
    rmdir "$stage" 2>/dev/null            # remove the now-empty hidden staging folder
  done
  echo "  restored $DF_UNDRIP_N staged game(s)."
  [ "$DF_UNDRIP_HELD" -eq 0 ] || echo "  held $DF_UNDRIP_HELD item(s) safely (see above; $conflict_root holds quarantined copies)."
  # 2) Remove every menu folder Dripfeed created.
  df_undrip_folders
  # 3) Remove the boot hook.
  "$DF_HELP/dripfeed-install.sh" --uninstall >/dev/null 2>&1
  # 4) Remove the visible Undrip launcher and all state + helper scripts. Only
  #    Scripts/Dripfeed.sh survives (it lives outside the .dripfeed folder).
  rm -f "$DF_SCRIPTS/Undrip.sh" 2>/dev/null
  rm -rf "$DF_STATE" 2>/dev/null
  DF_LOCK_HELD=0                          # the lock went with the state folder
  if [ "$DF_UNDRIP_HELD" -eq 0 ]; then
    rmdir "$STAGING_ROOT" 2>/dev/null || true
    echo "  removed all Dripfeed folders, files, and the boot hook."
  else
    echo "  removed the engine and boot hook; kept the waiting library so no game was deleted."
  fi
  echo "  kept: Scripts/Dripfeed.sh  (open it any time to reinstall clean)."
  return 0
}

case "${1:-}" in
  --watch)            df_watch ;;
  --auto|--silent)    df_run_reveal --silent ;;
  --pending)          df_announce_pending ;;
  --migrate)          df_migrate_only ;;
  --reveal|"")        df_run_reveal ;;
  --tidy|--gotm)     # these change menu folders too: never beside a running pass
                      df_lock_wait || { echo "$DF_BUSY_MSG"; exit 1; }
                      if [ "$1" = --tidy ]; then df_showcase_prepare; df_write_gamelist "$SHOWCASE_DIR"
                      else df_gotm_update; fi
                      df_unlock ;;
  --undrip)           df_undrip ;;
  --diag)             df_diag ;;
  -h|--help)          echo "usage: dripfeed-engine.sh [--watch|--auto|--reveal|--pending|--migrate|--tidy|--undrip|--diag]" ;;
  *)                  echo "unknown option: $1"; exit 1 ;;
esac
__DF_ENGINE__
  cat > "$EXNEW/dripfeed-install.sh" <<'__DF_INSTALL__'
#!/bin/bash
# dripfeed-install.sh — one-time setup (and uninstall). Safe to re-run.
# Hardcoded /media/fat paths (no $0). Creates the ACTIVE boot hook
# /media/fat/linux/user-startup.sh (the underscore _user-startup.sh is only a
# dormant template and is never executed by MiSTer).

DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh" 2>/dev/null || {
  echo "Dripfeed ERROR: cannot load common library"; exit 1; }

US="$DF_USERSTARTUP"
TEMPLATE="$DF_ROOT/linux/_user-startup.sh"
HOOK_BEGIN="#=====DRIPFEED_AUTORUN====="
HOOK_END="#=====DRIPFEED_AUTORUN_END====="
ENGINE="$DF_HELP/dripfeed-engine.sh"

write_config() {
  cat > "$DF_CONFIG" <<EOF
# Dripfeed configuration — KEY=value (spaces around = and "quotes" are fine)
GAMES_DIR=$DF_ROOT/games
STAGE_DIRNAME=.dripfeed
STAGING_ROOT=$DF_ROOT/.dripfeed-library   # keep on the SAME drive as GAMES_DIR (moves are renames)
REVEAL_AT_BOOT=1     # reveal due games at power-on
DAILY=1              # also reveal once per calendar day while powered on
WATCH_INTERVAL=3600  # seconds between day-change checks (minimum 60)
BOOT_DELAY=30        # seconds to wait at power-on before first reveal (avoids racing boot)
SHOWCASE=1           # build the "What's New" menu folder of .mgl shortcuts
SHOWCASE_PREFIX="_Dripfeed - "  # folder-name prefix ("_@Dripfeed - " pins it to the top)
SHOWCASE_DATE=1      # 1 = name shows the date of the latest unlock; 0 = fixed name
SHOWCASE_MAXLEN=30   # cap the folder name length
SHOWCASE_KEEP=12     # max shortcuts kept in that folder (and in each system folder below)
GAMELIST=1           # write gamelist.xml in the showcase (full message rides here)
FAVORITES_MIRROR=0   # opt-in: also mirror shortcuts into _@Favorites/_Dripfeed New
FAVORITES_DIR=_@Favorites
SYSTEM_SHORTCUTS=0   # opt-in: also put each What's New shortcut in games/<SYSTEM>/<dir below>,
                     # for graphical frontends that build their own library from system
                     # folders (refresh that library to see them). 0 removes them again.
SYSTEM_SHORTCUTS_DIR="_Dripfeed New"
POST_REVEAL_CMD=""   # optional command run once after a pass that revealed games (120 s
                     # timeout, never at shutdown), e.g. to ask a frontend to refresh its library
TOUCH_ON_REVEAL=1    # 1 = a revealed game's file date becomes the reveal time
GOTM=1               # build the Game of the Month menu folder (from gotm.tsv)
GOTM_DIRNAME="_Game of the Month"  # "_@..." pins it to the top of the menu
GOTM_MONTH=0         # 1 = append the month to the folder name ("... - Aug")
GOTM_SOURCE=         # optional community Game of the Month feed: a file path (e.g. one an
                     # update_all custom db delivers) or an http(s) URL — builds its OWN
                     # folder alongside your pick
GOTM_SRC_DIRNAME="_Discord GOTM"   # folder name for the community pick
EOF
}

# MiSTer's S99user runs user-startup.sh with "start" at boot AND with "stop" at
# every shutdown/reboot. The watcher must start only at boot: at shutdown it would
# move games while the filesystems are being unmounted.
HOOK_LINE="case \"\$1\" in start|\"\") [ -f \"$ENGINE\" ] && \"$ENGINE\" --watch >\"$DF_STATE/boot.log\" 2>&1 & ;; esac"

hook_block() { printf '%s\n%s\n%s\n' "$HOOK_BEGIN" "$HOOK_LINE" "$HOOK_END"; }

strip_hook() {
  if sed -i "/$HOOK_BEGIN/,/$HOOK_END/d" "$US" 2>/dev/null; then :; else
    sed "/$HOOK_BEGIN/,/$HOOK_END/d" "$US" > "$US.tmp" && mv "$US.tmp" "$US"
  fi
}

add_hook() {
  mkdir -p "$DF_ROOT/linux"
  if [ ! -f "$US" ]; then
    # Seed the active hook. Start from the template if present, else a fresh shebang.
    if [ -f "$TEMPLATE" ]; then cp "$TEMPLATE" "$US"; else printf '#!/bin/sh\n' > "$US"; fi
  fi
  if grep -q "DRIPFEED_AUTORUN" "$US" 2>/dev/null; then
    if [ "$(sed -n "/$HOOK_BEGIN/,/$HOOK_END/p" "$US")" = "$(hook_block)" ]; then
      echo "  boot hook already present"
      chmod 755 "$US" 2>/dev/null
      return 0
    fi
    strip_hook                     # an older block (it also ran at shutdown): replace it
    echo "  boot hook updated (starts at boot only)"
  else
    echo "  boot hook added to $US"
  fi
  {
    [ -n "$(tail -n 1 "$US" 2>/dev/null)" ] && echo ""
    hook_block
  } >> "$US"
  chmod 755 "$US" 2>/dev/null
}

remove_hook() {
  [ -f "$US" ] || { echo "  no user-startup.sh"; return; }
  strip_hook
  echo "  boot hook removed"
}

case "${1:-}" in
  --uninstall)
    echo "Dripfeed: uninstalling..."
    remove_hook
    echo "Done. Your queue, config and games were left untouched."
    ;;
  *)
    echo "Dripfeed: installing..."
    mkdir -p "$DF_STATE"
    [ -f "$DF_CONFIG" ] && echo "  config exists, keeping it" || { write_config; echo "  wrote $DF_CONFIG"; }
    [ -f "$DF_PENDING" ] || : > "$DF_PENDING" 2>/dev/null   # an update keeps unseen announcements
    add_hook
    df_log "installed"
    echo "Done. New games reveal ~${BOOT_DELAY:-30}s after power-on and once per day."
    echo "Open Scripts > Dripfeed to see them one at a time."
    ;;
esac
__DF_INSTALL__
  cat > "$EXNEW/dripfeed-schedule.sh" <<'__DF_SCHEDULE__'
#!/bin/bash
# Dripfeed for MiSTer FPGA — GPL-3.0-or-later
# Copyright (C) 2026 MikeyVids
# See ../../LICENSE for the full license and CREDITS.md for upstream acknowledgements.
# dripfeed-schedule.sh — queue games to appear on a future date (the "parent tool").
#
# Run this from your computer (SD card mounted) or over SSH — it is a setup tool,
# not something to drive with a controller on the TV. Point it at the right games
# folder with the DRIPFEED_GAMES env var when running off-device, e.g.:
#     DRIPFEED_GAMES="/Volumes/MiSTer/games" ./dripfeed-schedule.sh list
#
# Commands:
#   add <SYSTEM> <DATE> <file>...   stage one or more files to unlock on DATE
#   list [SYSTEM]                   show the upcoming queue (DUE = ready now)
#   remove <SYSTEM> <staged-name>   pull an item back out of the queue (reveal now)
#   due                             list only items whose date has arrived
#   (no args)                       guided numbered menu
#
# DATE accepts:  YYYY-MM-DD | today | tomorrow | +N   (N days from now)
#
# "Staging" moves the file into .dripfeed-library/<SYSTEM>/ with a YYYY-MM-DD_
# prefix. This hidden library sits outside games/, so menu/library scanners cannot
# discover held-back games. To schedule a game that is ALREADY visible, just
# point "add" at its current path — it gets moved into staging (hidden) for you.

# Hardcoded library path (never $0-based); DRIPFEED_ROOT overrides for desktop use.
DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh" 2>/dev/null || {
  echo "Dripfeed ERROR: cannot load common library (set DRIPFEED_ROOT to your SD path)"; exit 1; }
df_load_config

usage() { grep '^#' "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-schedule.sh" | sed 's/^# \{0,1\}//' | sed -n '2,24p'; }

df_add() {
  local sys="$1" datetok="$2"; shift 2 2>/dev/null
  [ -n "$sys" ] && [ -n "$datetok" ] && [ "$#" -ge 1 ] || { echo "usage: add <SYSTEM> <DATE> <file>..."; return 1; }
  local d; d=$(df_resolve_date "$datetok") || { echo "Bad date: '$datetok' (use a real YYYY-MM-DD | today | tomorrow | +N)"; return 1; }
  local sysdir="$GAMES_DIR/$sys"
  [ -d "$sysdir" ] || { echo "No such system folder: $sysdir"; return 1; }
  df_lock_wait || { echo "$DF_BUSY_MSG"; return 1; }
  local stage; stage="$(df_stage_dir "$sys")"; [ -d "$stage" ] || mkdir -p "$stage"
  # Look every file up in ONE awk pass over a one-walk index of this system's
  # queue (the old per-file rescans spawned processes quadratically).
  local idx="$DF_STATE/.add-index.$$" req="$DF_STATE/.add-req.$$" ann="$DF_STATE/.add-ann.$$"
  local f base n=0 i=0 count existing first rc
  local files=() clean=() queued=()
  for f in "$@"; do
    while [ "${#f}" -gt 1 ] && [ "${f%/}" != "$f" ]; do f="${f%/}"; done   # "Game Folder/" -> "Game Folder"
    base="${f##*/}"
    df_is_valid_prefix "$base" && base="${base:11}"                         # re-dating is fine
    files[$i]="$f"; clean[$i]="$base"; queued[$i]=0; i=$((i+1))
  done
  df_index_write "$idx" "$sys"
  for base in "${clean[@]}"; do printf '%s\n' "$base"; done > "$req"
  LC_ALL=C awk -F'\t' -v US="$DF_US" '
    FILENAME == ARGV[1] { c[$2]++; if (!($2 in p)) p[$2] = $3; next }
    { k = $0; cnt = (k in c) ? c[k] : 0
      printf "%d%s%s%s%d\n", cnt, US, (cnt == 1 ? p[k] : ""), US, ((k in seen) ? seen[k] : 0)
      if (!(k in seen)) seen[k] = FNR }' "$idx" "$req" > "$ann"
  i=0
  while IFS="$DF_US" read -r count existing first; do
    f="${files[$i]}"; base="${clean[$i]}"; i=$((i+1))
    [ -e "$f" ] || [ -L "$f" ] || { echo "  skip (not found): $f"; continue; }
    if df_is_shortcut_dir "$f" && [ -d "$f" ]; then
      echo "  skip (Dripfeed's own shortcut folder, not a game): $base"; continue
    fi
    if df_support_entry "$f"; then
      echo "  skip (firmware/support, not a game): ${f##*/}"; continue
    fi
    if [ -f "$f" ] && [ ! -s "$f" ]; then
      echo "  skip (empty 0-byte file, not a game): ${f##*/}"; continue
    fi
    # The same game named twice in one command: the first one queued wins.
    if [ "$first" -gt 0 ] && [ "${queued[$((first-1))]}" = 1 ]; then
      echo "  SKIP (already queued on another date): [$sys]  $base"; continue
    fi
    if [ "$count" -gt 1 ]; then
      echo "  HOLD (duplicate queue entries need review): [$sys]  $base"; continue
    fi
    if [ "$count" -eq 1 ] && [ "$f" != "$existing" ]; then
      echo "  SKIP (already queued on another date): [$sys]  $base"; continue
    fi
    # Never overwrite a visible ROM or an existing queue entry. The old script
    # relied on mv's platform-specific behavior, which can clobber a save.
    if [ -e "$stage/${d}_${base}" ]; then
      echo "  SKIP (already queued): $d  [$sys]  $base"; continue
    fi
    df_rename "$f" "$stage/${d}_${base}"; rc=$?
    case "$rc" in
      0) echo "  scheduled $d  [$sys]  $base"; n=$((n+1)); queued[$((i-1))]=1 ;;
      2) echo "  HELD (on a different drive than the waiting library; Dripfeed never copies games): $f" ;;
      *) echo "  FAILED: $f" ;;
    esac
  done < "$ann"
  rm -f "$idx" "$req" "$ann" 2>/dev/null
  df_unlock
  echo "Done — $n item(s) queued."
}

# One line per queue entry, sorted by date (then system and name) across BOTH
# the current and the legacy queue. Builtins only per entry.
df_list() {
  local sys="$1" today stage entry base d mark s line out
  df_strftime today '%Y%m%d'
  out=$({
    for stage in "$STAGING_ROOT"/${sys:-*}/ "$GAMES_DIR"/${sys:-*}/"$STAGE_DIRNAME"/; do
      [ -d "$stage" ] || continue
      case "$stage" in
        "$STAGING_ROOT"/*) s="${stage%/}"; s="${s##*/}" ;;
        *) s="${stage%/"$STAGE_DIRNAME"/}"; s="${s##*/}" ;;
      esac
      for entry in "$stage"*; do
        [ -e "$entry" ] || continue
        base="${entry##*/}"; df_is_valid_prefix "$base" || continue
        d="${base:0:10}"
        if [ -f "$entry" ] && [ ! -s "$entry" ]; then
          printf -v line 'HOLD %s  %-12s  %s [empty file: interrupted browser copy; never revealed]' "$d" "$s" "${base:11}"
        elif ! df_queue_entry_complete "$entry"; then
          printf -v line 'HOLD %s  %-12s  %s [incomplete copy; never revealed]' "$d" "$s" "${base:11}"
        elif df_support_entry "$entry"; then
          printf -v line 'SKIP %s  %-12s  %s [firmware/support]' "$d" "$s" "${base:11}"
        else
          mark="    "; [ "${d:0:4}${d:5:2}${d:8:2}" -le "$today" ] && mark="DUE "
          printf -v line '%s%s  %-12s  %s' "$mark" "$d" "$s" "${base:11}"
        fi
        printf '%s\t%s\t%s\t%s\n' "$d" "$s" "${base:11}" "$line"
      done
    done
  } | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 | cut -f4-)
  if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "(queue is empty)"; fi
  return 0
}

df_due() { df_list "$1" | grep '^DUE ' || echo "(nothing due)"; }

# Set/clear a custom banner for a date: message <DATE> [text...]   (no text = clear)
df_message() {
  local datetok="$1"; shift 2>/dev/null
  local d; d=$(df_resolve_date "$datetok") || { echo "Bad date: '$datetok'"; return 1; }
  mkdir -p "$DF_STATE"
  touch "$DF_OCCASIONS"
  # drop any existing line for this date
  grep -v "^$d$(printf '\t')" "$DF_OCCASIONS" > "$DF_OCCASIONS.tmp" 2>/dev/null
  mv "$DF_OCCASIONS.tmp" "$DF_OCCASIONS" 2>/dev/null
  if [ "$#" -ge 1 ]; then
    printf '%s\t%s\n' "$d" "$*" >> "$DF_OCCASIONS"
    echo "Banner set for $d: $*"
  else
    echo "Banner cleared for $d"
  fi
}

df_remove() {
  local sys="$1" name="$2"
  [ -n "$sys" ] && [ -n "$name" ] || { echo "usage: remove <SYSTEM> <staged-name>"; return 1; }
  local stage entry clean dest rc today
  stage="$(df_stage_dir "$sys")"; entry="$stage/$name"
  if [ ! -e "$entry" ]; then
    stage="$(df_legacy_stage_dir "$sys")"; entry="$stage/$name"
  fi
  [ -e "$entry" ] || { echo "Not in queue: $name"; return 1; }
  clean="$name"; df_is_valid_prefix "$name" && clean="${name:11}"
  dest="$GAMES_DIR/$sys/$clean"
  [ -e "$dest" ] && { echo "Destination already exists; left queue untouched: $sys/$clean"; return 1; }
  df_lock_wait || { echo "$DF_BUSY_MSG"; return 1; }
  df_rename "$entry" "$dest"; rc=$?
  df_unlock
  if [ "$rc" -eq 2 ]; then
    echo "Held: $sys/$clean is on a different drive than games/$sys (Dripfeed never copies games)."; return 1
  fi
  if df_support_entry "$dest"; then
    [ "$rc" -eq 0 ] && { echo "Restored firmware/support entry (not a game): $sys/$clean"; return 0; }
    echo "Failed to restore firmware/support entry: $sys/$clean"; return 1
  fi
  [ "$rc" -eq 0 ] || { echo "Failed to reveal: $sys/$clean (nothing changed)"; return 1; }
  df_strftime today '%Y-%m-%d'
  df_ledger_record "$today" "$sys" "$clean"
  df_touch_revealed "$dest"
  echo "Revealed now: $sys/$clean"
}

# Guided numbered menu (no dialog dependency, works over SSH).
df_menu() {
  local i=1 systems=() d
  for d in "$GAMES_DIR"/*/; do [ -d "$d" ] && { d="${d%/}"; systems+=("${d##*/}"); }; done
  [ "${#systems[@]}" -eq 0 ] && { echo "No system folders found in $GAMES_DIR"; return 1; }
  echo "Pick a system:"; i=1
  for s in "${systems[@]}"; do printf "  %2d) %s\n" "$i" "$s"; i=$((i+1)); done
  printf "Number: "; read -r sn
  local sys="${systems[$((sn-1))]}"; [ -n "$sys" ] || { echo "cancelled"; return 1; }
  local sysdir="$GAMES_DIR/$sys" files=()
  for f in "$sysdir"/*; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = "$STAGE_DIRNAME" ] && continue
    df_is_shortcut_dir "$f" && continue
    df_support_entry "$f" && continue
    files+=("${f##*/}")
  done
  [ "${#files[@]}" -eq 0 ] && { echo "No visible games in $sys."; return 1; }
  echo "Games in $sys (space-separate several numbers):"; i=1
  for f in "${files[@]}"; do printf "  %2d) %s\n" "$i" "$f"; i=$((i+1)); done
  printf "Number(s): "; read -r picks
  printf "Reveal date (YYYY-MM-DD | today | tomorrow | +N): "; read -r datetok
  local sel=() p
  for p in $picks; do [ -n "${files[$((p-1))]}" ] && sel+=("$sysdir/${files[$((p-1))]}"); done
  [ "${#sel[@]}" -eq 0 ] && { echo "nothing selected"; return 1; }
  df_add "$sys" "$datetok" "${sel[@]}"
}

case "${1:-}" in
  add)     shift; df_add "$@" ;;
  list)    df_list "$2" ;;
  due)     df_due "$2" ;;
  remove)  df_remove "$2" "$3" ;;
  message) shift; df_message "$@" ;;
  ""|menu) df_menu ;;
  -h|--help) usage ;;
  *) echo "unknown command: $1"; usage; exit 1 ;;
esac
__DF_SCHEDULE__
  cat > "$EXNEW/Undrip.sh" <<'__DF_UNDRIP__'
#!/bin/bash
# Undrip.sh — the RESET button for Dripfeed (auto-generated by Dripfeed.sh).
# Restores every scheduled game to its normal folder, deletes all Dripfeed folders,
# shortcuts, and settings (keeping only Scripts/Dripfeed.sh), then reboots so the menu
# comes back clean. Re-run Dripfeed.sh afterwards for a clean reinstall or a fresh
# schedule. Press ANY button to confirm; doing nothing cancels safely.

DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
HELP="$DRIPFEED_ROOT/Scripts/.dripfeed"
export DRIPFEED_INTERACTIVE=1
[ -f "$HELP/dripfeed-common.sh" ] && . "$HELP/dripfeed-common.sh"

# Restart only on a real MiSTer (never a desktop test machine, even as root).
on_mister() {
  [ "${DRIPFEED_NO_REBOOT:-0}" != 1 ] && [ "$DRIPFEED_ROOT" = /media/fat ] && [ -x /media/fat/MiSTer ] &&
    case "$(uname -m 2>/dev/null)" in arm*) true ;; *) false ;; esac
}
restart() {
  sync
  if on_mister; then reboot 2>/dev/null || true
  else echo; echo "  (not running on a MiSTer: restart skipped)"; fi
}

clear 2>/dev/null || printf '\033[2J\033[H'
echo
echo "  ================  DRIPFEED  -  UNDRIP (RESET)  ================"
echo
echo "  Restores ALL scheduled games to their folders, deletes every"
echo "  Dripfeed folder / shortcut / setting (keeps Scripts/Dripfeed.sh),"
echo "  then reboots. Your ROMs and saves are NOT touched."
echo
if type df_confirm_any >/dev/null 2>&1; then
  df_ui_begin; trap 'df_ui_end' EXIT
  echo "  Press ANY button now to UNDRIP - or do nothing to cancel."
  if df_confirm_any 10; then
    echo; echo "  Resetting..."
    if "$HELP/dripfeed-engine.sh" --undrip; then
      df_menu_countdown 5 "Rebooting" >/dev/null
      restart
    else
      echo; echo "  Nothing was reset. Try again in a minute."; sleep 3
    fi
  else
    echo; echo "  Cancelled - nothing changed."; sleep 2
  fi
else
  echo "  (helpers missing) - nothing to do."; sleep 3
fi
exit 0
__DF_UNDRIP__
  # Verify every extracted script parses; only then swap them into place.
  local exf
  for exf in "$EXNEW"/*.sh; do
    if ! bash -n "$exf" 2>/dev/null; then
      echo "  ERROR: this copy of Dripfeed.sh is damaged ($(basename "$exf") failed its check)."
      echo "  Nothing was changed. Re-copy Dripfeed.sh to the card and try again."
      rm -rf "$EXNEW"
      return 1
    fi
  done
  mv -f "$EXNEW/dripfeed-common.sh" "$EXNEW/dripfeed-engine.sh" \
        "$EXNEW/dripfeed-install.sh" "$EXNEW/dripfeed-schedule.sh" "$HELP/"
  mv -f "$EXNEW/Undrip.sh" "$DRIPFEED_ROOT/Scripts/Undrip.sh"
  rm -rf "$EXNEW"
  chmod 755 "$HELP"/*.sh "$DRIPFEED_ROOT/Scripts/Undrip.sh" 2>/dev/null
  printf '%s\n' "$DRIPFEED_VERSION" > "$HELP/.version"
}
need=0
[ -f "$HELP/dripfeed-common.sh" ] || need=1
[ "$(cat "$HELP/.version" 2>/dev/null)" != "$DRIPFEED_VERSION" ] && need=1
fresh=0
scr_clear; banner
if [ "$need" = 1 ]; then
  if [ -f "$HELP/.version" ]; then echo "  Updating Dripfeed to v$DRIPFEED_VERSION, please wait..."; else echo "  Installing Dripfeed v$DRIPFEED_VERSION, please wait..."; fi
  extract_helpers || { sleep 6; exit 1; }
  . "$HELP/dripfeed-common.sh" 2>/dev/null || { echo "  ERROR: helper extract failed."; sleep 5; exit 1; }
  "$HELP/dripfeed-install.sh" >/dev/null 2>&1
  df_load_config; fresh=1
else
  . "$HELP/dripfeed-common.sh" 2>/dev/null || { echo "  ERROR: helpers missing/corrupt. Re-copy Dripfeed.sh and re-run."; sleep 5; exit 1; }
  df_load_config
fi
# Echo OFF for the whole interactive session (restored on ANY exit) so controller /
# keyboard presses can never type stray characters onto the prompt line.
df_ui_begin; trap 'df_ui_end' EXIT
echo "  Console date: $(date '+%a %b %d, %Y  %H:%M')"
df_clock_ok || echo "  * WARNING: clock not set - reveals are paused. Set time via Scripts > WiFi/timezone."
if [ "$fresh" = 1 ]; then
  echo; echo "  Installed. New games appear once the clock is network-synced after power-on"
  echo "  (and once a day), in a dated '${SHOWCASE_PREFIX:-_Dripfeed - }...' menu folder."; echo
  df_menu_countdown 5 "Restarting to finish setup" >/dev/null
  restart; exit 0
fi
echo
echo "  UP    = UNDRIP    (restore all games, remove Dripfeed, then restart)"
echo "  DOWN  = REINSTALL (repair scripts + boot hook, KEEPS your schedule, restart)"
echo "  wait  = show what's new, back to menu"
echo
c="$(df_menu_countdown 6 "Continuing")"
case "$c" in
  up)
    scr_clear; banner
    echo "  UNDRIP restores ALL scheduled games, removes every Dripfeed folder/setting"
    echo "  (keeps Dripfeed.sh), and restarts. ROMs and saves are NOT touched."; echo
    echo "  Press ANY button to confirm - or do nothing to cancel."
    if df_confirm_any 10; then
      echo; echo "  Resetting..."
      if "$HELP/dripfeed-engine.sh" --undrip; then
        df_menu_countdown 5 "Restarting" >/dev/null
        restart
      else
        echo; echo "  Nothing was reset. Try again in a minute."; sleep 3
      fi
    else
      echo; echo "  Cancelled - nothing changed."; sleep 2
    fi
    exit 0 ;;
  down)
    scr_clear; banner
    echo "  Reinstalling v$DRIPFEED_VERSION (your schedule, messages and config are kept)..."
    extract_helpers || { sleep 6; exit 1; }
    . "$HELP/dripfeed-common.sh" 2>/dev/null
    "$HELP/dripfeed-install.sh"
    echo; echo "  Reinstalled."
    df_menu_countdown 5 "Restarting" >/dev/null
    restart
    exit 0 ;;
esac
"$HELP/dripfeed-engine.sh" --pending
"$HELP/dripfeed-engine.sh" --reveal
echo
echo "  Press any button to return to the menu."
df_confirm_any 30 || true
exit 0
