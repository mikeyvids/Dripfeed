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
DF_GOTM="$DF_STATE/gotm.tsv"             # Game of the Month schedule: YYYY-MM<TAB>path
                                         # (path relative to /media/fat, e.g.
                                         #  games/SNES/Chrono Trigger (USA).sfc or
                                         #  _Arcade/Robotron 2084.mra)
DF_GOTM_LAST="$DF_STATE/.gotm_built"     # what's currently built (month|path), so the
                                         # folder is only rebuilt when the pick changes
DF_USERSTARTUP="$DF_ROOT/linux/user-startup.sh"   # active boot hook (NOT _user-startup.sh)

# ---- Defaults (config.ini overrides these) ----------------------------------
GAMES_DIR="$DF_ROOT/games"
STAGE_DIRNAME=".dripfeed"
# New queues live outside games/. This prevents library scanners from seeing
# held-back titles and keeps a complete multi-disc folder together as one atomic
# rename. STAGE_DIRNAME remains supported as a read-only legacy location so an
# existing queue is never stranded after upgrading.
STAGING_ROOT="$DF_ROOT/.dripfeed-library"
WAIT_BUTTON=1
WAIT_TIMEOUT=0
REVEAL_AT_BOOT=1
DAILY=1
WATCH_INTERVAL=3600
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
SHOWCASE_MAXLEN=30     # cap the folder name to the OSD's visible width (incl. prefix)
SHOWCASE_KEEP=12       # max shortcuts kept in the folder (oldest pruned)
GAMELIST=1             # also write gamelist.xml — the FULL custom message rides here for
                       # graphical frontends (the MiSTer menu can't show .txt files).
FAVORITES_MIRROR=0     # (opt-in) also copy shortcuts into the mrext/stock-menu Favorites
                       # folder (a frontend's in-app Favorites is separate). See INTEGRATION.md.
FAVORITES_DIR="_@Favorites"
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

# Tolerant config reader: handles "KEY = value", comments, surrounding quotes, and
# only assigns whitelisted keys (no arbitrary code execution, unlike sourcing).
df_load_config() {
  if [ -f "$DF_CONFIG" ]; then
    local line key val
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"                       # strip trailing comment
      case "$line" in *=*) ;; *) continue ;; esac
      key="${line%%=*}"; val="${line#*=}"
      key="$(printf '%s' "$key" | tr -d '[:space:]')"            # trim spaces in key
      val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"  # trim val
      case "$val" in                                            # strip ONE layer of quotes
        \"*\") val="${val#\"}"; val="${val%\"}" ;;
        \'*\') val="${val#\'}"; val="${val%\'}" ;;
      esac
      case "$key" in
        GAMES_DIR|STAGE_DIRNAME|STAGING_ROOT|WAIT_BUTTON|WAIT_TIMEOUT|REVEAL_AT_BOOT|DAILY|\
        WATCH_INTERVAL|BOOT_DELAY|SHOWCASE|SHOWCASE_PREFIX|SHOWCASE_MAXLEN|SHOWCASE_KEEP|\
        GAMELIST|FAVORITES_MIRROR|FAVORITES_DIR|GOTM|GOTM_DIRNAME|GOTM_MONTH|SHOWCASE_DATE|GOTM_SOURCE|GOTM_SRC_DIRNAME)
          eval "$key=\$val" ;;
      esac
    done < "$DF_CONFIG"
  fi
  [ -n "$DRIPFEED_GAMES" ] && GAMES_DIR="$DRIPFEED_GAMES"
  [ -n "${DRIPFEED_STAGING:-}" ] && STAGING_ROOT="$DRIPFEED_STAGING"
}

df_stage_dir() { printf '%s/%s' "$STAGING_ROOT" "$1"; }
df_legacy_stage_dir() { printf '%s/%s/%s' "$GAMES_DIR" "$1" "$STAGE_DIRNAME"; }

# Print every queued entry for one clean game name. Both the current queue and
# the older per-system queue are searched because an interrupted browser copy
# can leave the same title in more than one dated folder.
df_staged_clean_paths() {
  local sys="$1" clean="$2" stage entry base
  for stage in "$(df_stage_dir "$sys")" "$(df_legacy_stage_dir "$sys")"; do
    [ -d "$stage" ] || continue
    for entry in "$stage"/*; do
      [ -e "$entry" ] || continue
      base=$(basename "$entry")
      df_is_valid_prefix "$base" || continue
      [ "$(df_strip_prefix "$base")" = "$clean" ] && printf '%s\n' "$entry"
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

# A browser interrupted during an old copy-based folder move could leave this
# marker behind. Such a directory is a recovery artifact, never a runnable game.
df_queue_entry_complete() {
  [ -e "$1" ] || return 1
  [ ! -d "$1" ] || {
    [ ! -e "$1/.dripfeed-incomplete" ] && df_disc_manifests_complete "$1"
  }
}

# Catch the most dangerous old-browser failure: a copied CUE/BIN or M3U folder
# whose playlist/control file arrived but one of its referenced discs did not.
df_disc_manifests_complete() {
  local dir="$1" manifest refs ref seen bad=0
  for manifest in "$dir"/*.m3u "$dir"/*.M3U; do
    [ -f "$manifest" ] || continue
    refs=$(sed 's/\r$//;/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$manifest")
    seen=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      seen=1
      [ -e "$(dirname "$manifest")/$ref" ] || bad=1
    done <<EOF_REFS
$refs
EOF_REFS
    [ "$seen" -eq 1 ] && [ "$bad" -eq 0 ] || return 1
  done
  for manifest in "$dir"/*.cue "$dir"/*.CUE; do
    [ -f "$manifest" ] || continue
    refs=$(awk '/^[[:space:]]*[Ff][Ii][Ll][Ee][[:space:]]+/ {
      line=$0; sub(/^[[:space:]]*[Ff][Ii][Ll][Ee][[:space:]]+/, "", line)
      if (substr(line,1,1)=="\"") { sub(/^"/, "", line); sub(/"[[:space:]].*$/, "", line) }
      else sub(/[[:space:]].*$/, "", line)
      print line
    }' "$manifest")
    seen=0; bad=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      seen=1
      [ -e "$(dirname "$manifest")/$ref" ] || bad=1
    done <<EOF_REFS
$refs
EOF_REFS
    [ "$seen" -eq 1 ] && [ "$bad" -eq 0 ] || return 1
  done
  return 0
}

# ---- Single-runner lock (mdkir is atomic) so the boot daemon and a manual launch
# can't reveal the same queue at once. Self-heals a stale lock after 10 minutes.
DF_LOCK="$DF_STATE/.lock"
df_lock() {
  mkdir "$DF_STATE" 2>/dev/null
  if mkdir "$DF_LOCK" 2>/dev/null; then date +%s > "$DF_LOCK/ts" 2>/dev/null; return 0; fi
  local ts; ts=$(cat "$DF_LOCK/ts" 2>/dev/null || echo 0)
  if [ "$(( $(date +%s) - ts ))" -gt 600 ]; then
    rm -rf "$DF_LOCK" 2>/dev/null
    mkdir "$DF_LOCK" 2>/dev/null && { date +%s > "$DF_LOCK/ts" 2>/dev/null; return 0; }
  fi
  return 1
}
df_unlock() { rm -rf "$DF_LOCK" 2>/dev/null; }

# ---- Logging (always on, so we can diagnose on real hardware) ---------------
df_log() {
  mkdir -p "$DF_STATE" 2>/dev/null
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$DF_LOG" 2>/dev/null
}
# Keep the log from growing forever (called once per boot by the watch daemon).
df_log_trim() {
  [ -f "$DF_LOG" ] || return 0
  [ "$(wc -l < "$DF_LOG" 2>/dev/null || echo 0)" -gt 2000 ] || return 0
  tail -n 500 "$DF_LOG" > "$DF_LOG.tmp" 2>/dev/null && mv "$DF_LOG.tmp" "$DF_LOG"
}

# ---- Date helpers -----------------------------------------------------------
df_today_int() { date +%Y%m%d; }
df_is_valid_prefix() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_*) return 0 ;;
    *) return 1 ;;
  esac
}
df_prefix_date_int() { echo "${1:0:10}" | tr -d '-'; }
df_strip_prefix()    { echo "${1:11}"; }

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
# into .dripfeed. These checks are intentionally conservative: an unknown file is
# not classified as support, while a directory is support-only only when every
# visible file below it is known firmware/support.
df_support_file() {
  local n="$(basename "$1")" l
  l="$(printf '%s' "$n" | tr 'A-Z' 'a-z')"
  case "$l" in
    gamelist.xml|n64-database.txt|sbi.zip|000-lo.lo|sfix.sfix|uni-bios.rom|cd_bios.rom|bsx_bios.rom|neo-epo.sp1|sp-s2.sp1|eeprom.jce|memorytrack.jmc|romsets.xml|gog-romsets.xml|gog-broken-romsets.xml) return 0 ;;
    *.mrq|*.jce|*.jmc) return 0 ;;
    boot*.rom|boot*.bin|firmware*.rom|mister-boot.*|mister-demo.*) return 0 ;;
    *bios*.rom|*_bios.rom) return 0 ;;
  esac
  return 1
}
df_support_dir_only() {
  local dir="$1" f base found=0
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
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
  local path="$1" base l
  base="$(basename "$path")"
  df_is_valid_prefix "$base" && base="$(df_strip_prefix "$base")"
  l="$(printf '%s' "$base" | tr 'A-Z' 'a-z')"
  if [ -f "$path" ]; then df_support_file "$base" && return 0; fi
  if [ -d "$path" ]; then
    case "$l" in media|palettes|borders|cores) return 0 ;; esac
    df_support_dir_only "$path" && return 0
  fi
  return 1
}

df_occasion() {
  [ -f "$DF_OCCASIONS" ] || return 0
  awk -F'\t' -v d="$1" '$1==d{ print substr($0, index($0,"\t")+1); exit }' "$DF_OCCASIONS"
}

# Record a successful reveal once. The scheduler uses this ledger to distinguish
# "available" from "already unveiled" when preparing an incremental update. Fields
# are deliberately simple TSV because MiSTer ships awk/sed but not SQLite.
df_ledger_record() {
  local d="$1" sys="$2" name="$3"
  [ -n "$d" ] && [ -n "$sys" ] && [ -n "$name" ] || return 1
  mkdir -p "$DF_STATE" 2>/dev/null
  if [ -f "$DF_LEDGER" ] && awk -F '\t' -v s="$sys" -v n="$name" '$2==s && $3==n {found=1} END{exit found?0:1}' "$DF_LEDGER"; then return 0; fi
  printf '%s\t%s\t%s\t%s\n' "$d" "$sys" "$name" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$DF_LEDGER" 2>/dev/null
}

# A reveal is a same-filesystem rename, so the game itself cannot be copied only
# halfway. The small journal below closes the remaining gap: power can fail after
# the rename but before revealed.tsv and the What's New shortcut are updated.
df_tx_begin() {
  local d="$1" sys="$2" name="$3" src="$4" dest="$5" tmp
  mkdir -p "$DF_TX_DIR" 2>/dev/null || return 1
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

# ---- "What's New" showcase folder (.mgl shortcuts, Favorites-style) ----------
# Map a system folder + file extension to the MiSTer core .mgl parameters
# (rbf path, delay, type, index, setname).
#
# CREDIT: the per-core values and the SET_NAMES below are adapted from wizzo's
# (Callan Barrett) MiSTer_Favorites / mrext "MGL_MAP" — https://github.com/wizzomafizzo/mrext
# (GPL-3.0). The .mgl file format and the "_"-prefixed-folder-shows-in-menu and
# Favorites convention are from MiSTer-devel. Thank you to both.
#
# Sets RBF/DELAY/MTYPE/MINDEX/SETNAME. Returns 1 if the system/extension isn't
# mappable (caller then skips the shortcut).
df_mgl_lookup() {
  local sys="$1" ext="$2" s
  s="$(printf '%s' "$sys" | tr 'A-Z' 'a-z')"   # case-insensitive: install bases vary (GENESIS vs Genesis)
  RBF=""; DELAY=1; MTYPE="f"; MINDEX=1; SETNAME=""
  case "$s" in
    nes|famicom)                          RBF="_Console/NES"; DELAY=2; MINDEX=1 ;;
    snes|sfc|supernes)                    RBF="_Console/SNES"; DELAY=2; MINDEX=0 ;;
    megadrive|genesis|md)                 RBF="_Console/MegaDrive"; MINDEX=1 ;;  # MegaDrive (Nuked) is the current default; Genesis core is deprecated
    gameboy|gb)                           RBF="_Console/Gameboy"; DELAY=2; MINDEX=1 ;;
    gbc)                                  RBF="_Console/Gameboy"; DELAY=2; MINDEX=1; SETNAME="GBC" ;;
    gba)                                  RBF="_Console/GBA"; DELAY=2; MINDEX=1 ;;
    gamegear|gg)                          RBF="_Console/SMS"; MINDEX=2; SETNAME="GameGear" ;;
    sms|mastersystem)                     RBF="_Console/SMS"; MINDEX=1 ;;
    s32x|32x)                             RBF="_Console/S32X"; MINDEX=1 ;;
    n64)                                  RBF="_Console/N64"; MINDEX=1 ;;
    neogeo|neo)                           RBF="_Console/NeoGeo"; MINDEX=1 ;;
    saturn|sat)                           RBF="_Console/Saturn"; MTYPE="s"; MINDEX=0 ;;
    megacd|scd|segacd)                    RBF="_Console/MegaCD"; MTYPE="s"; MINDEX=0 ;;
    psx|ps1|playstation)                  RBF="_Console/PSX"; MTYPE="s"; MINDEX=1 ;;
    tgfx16|tg16|turbografx16|pce)         RBF="_Console/TurboGrafx16"; MINDEX=0 ;;
    tgfx16-cd|tgcd|turbografx16-cd|pcecd) RBF="_Console/TurboGrafx16"; MTYPE="s"; MINDEX=0 ;;
    jaguar|jag)                           RBF="_Console/Jaguar"; MTYPE="s"; MINDEX=1 ;;  # per mrext: type s
    ngpc|ngp|neogeopocket)                RBF="_Console/NeoGeoPocket"; MINDEX=1 ;;  # JTNGP core; verify on your build
    # ---- computers (per mrext systems table; used mainly by Game of the Month) ----
    amiga|minimig)                        RBF="_Computer/Minimig"; MINDEX=0 ;;          # df0: .adf
    c64)                                  RBF="_Computer/C64"; MINDEX=1 ;;              # .prg/.crt f1; disks s0 below
    ao486|pc)                             RBF="_Computer/ao486"; MTYPE="s"; MINDEX=2 ;; # IDE0-0: .vhd
    spectrum|zxspectrum)                  RBF="_Computer/ZX-Spectrum"; MINDEX=2 ;;      # tape f2; .z80/.sna f4 below
    *) return 1 ;;
  esac
  # CD images always behave as "s" index per the table even if the cart default differed.
  case "$ext" in
    .cue|.chd|.iso) MTYPE="s" ;;
  esac
  # computer-specific extension tweaks
  case "$s:$ext" in
    c64:.d64|c64:.g64|c64:.t64|c64:.d81)      MTYPE="s"; MINDEX=0 ;;
    spectrum:.z80|spectrum:.sna|zxspectrum:.z80|zxspectrum:.sna) MINDEX=4 ;;
    ao486:.img|ao486:.ima|ao486:.vfd|pc:.img) MTYPE="s"; MINDEX=0 ;;
  esac
  [ -n "$RBF" ] || return 1
  RBF="$(df_resolve_rbf "$RBF")"   # point at the core actually installed (handles renamed/deprecated cores)
  return 0
}

# Given a preferred "_Console/Name", return a core path that actually exists in
# _Console (matching by date-suffixed filename). Falls back to known alternates for
# cores that were renamed, then to the preferred name if nothing is found.
df_resolve_rbf() {
  local pref="$1" dir base
  dir="$DF_ROOT/$(dirname "$pref")"; base="$(basename "$pref")"
  ls "$dir/$base"*.rbf >/dev/null 2>&1 && { echo "$pref"; return; }
  case "$base" in
    MegaDrive) ls "$dir/Genesis"*.rbf   >/dev/null 2>&1 && { echo "_Console/Genesis";   return; } ;;
    Genesis)   ls "$dir/MegaDrive"*.rbf >/dev/null 2>&1 && { echo "_Console/MegaDrive"; return; } ;;
  esac
  echo "$pref"
}

# Write one .mgl shortcut for a revealed game into $1 (the showcase dir).
#   $1 = showcase dir   $2 = system folder name   $3 = absolute path of revealed item
df_make_mgl() {
  local outdir="$1" sys="$2" item="$3" target base ext label mgl
  if [ -d "$item" ]; then
    # multidisc folder: point at the playlist/first disc inside
    target="$(ls "$item"/*.m3u "$item"/*.cue "$item"/*.chd "$item"/*.iso 2>/dev/null | head -1)"
    [ -n "$target" ] || return 1
    base="$(basename "$item")"
  else
    target="$item"; base="$(basename "$item")"; base="${base%.*}"
  fi
  ext=".$(printf '%s' "$target" | sed 's/.*\.//' | tr 'A-Z' 'a-z')"
  df_mgl_lookup "$sys" "$ext" || { df_log "no MGL map for $sys ($ext) — showcase skipped"; return 1; }
  # Label shows the system so the player knows the platform ($4 = custom label override,
  # e.g. "User GOTM May - Plok" — used by Game of the Month).
  label="$sys - $base"
  [ -n "${4:-}" ] && label="$4"
  label="$(printf '%s' "$label" | tr -d '<>:"/\\|?*')"
  mkdir -p "$outdir"
  local xml_target xml_rbf xml_set
  xml_target="$(df_xml_attr "$target")"; xml_rbf="$(df_xml_attr "$RBF")"; xml_set="$(df_xml_attr "$SETNAME")"
  if [ -n "$SETNAME" ]; then
    mgl="<mistergamedescription>
	<rbf>$xml_rbf</rbf>
	<setname>$xml_set</setname>
	<file delay=\"$DELAY\" type=\"$MTYPE\" index=\"$MINDEX\" path=\"$xml_target\"/>
</mistergamedescription>"
  else
    mgl="<mistergamedescription>
	<rbf>$xml_rbf</rbf>
	<file delay=\"$DELAY\" type=\"$MTYPE\" index=\"$MINDEX\" path=\"$xml_target\"/>
</mistergamedescription>"
  fi
  printf '%s\n' "$mgl" > "$outdir/$label.mgl"
  df_log "showcase mgl: $label.mgl -> $target"
}

# ---- Frontend breadcrumbs (optional; we never modify the frontend itself) -----
# Write a Recalbox/EmulationStation-style gamelist.xml describing the shortcuts in
# the showcase folder. Graphical frontends that read this standard format use it for
# names, dates and a "what's new" description. Harmless to any frontend that ignores
# it. (This is a generic open format — not specific to any one frontend.)
df_write_gamelist() {
  local dir="$1" today msg gl entry name
  [ "${GAMELIST:-1}" -eq 1 ] || return 0
  [ -d "$dir" ] || return 0
  today=$(date +%Y-%m-%d); msg=$(df_occasion "$today")
  gl="$dir/gamelist.xml"
  {
    echo '<?xml version="1.0"?>'
    echo '<gameList>'
    for entry in "$dir"/*.mgl; do
      [ -e "$entry" ] || continue
      name="$(basename "$entry" .mgl)"
      echo '  <game>'
      echo "    <path>./$(basename "$entry")</path>"
      echo "    <name>$(df_xml "$name")</name>"
      echo "    <desc>$(df_xml "New on Dripfeed${msg:+ — $msg}")</desc>"
      echo "    <releasedate>$(date +%Y%m%d)T000000</releasedate>"
      echo '  </game>'
    done
    echo '</gameList>'
  } > "$gl.tmp" && mv "$gl.tmp" "$gl"   # write-then-rename so readers never see a partial file
  df_log "wrote gamelist.xml ($dir)"
}
df_xml() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
df_xml_attr() { df_xml "$1" | sed 's/"/\&quot;/g; s/'"'"'/\&apos;/g'; }

# True if the console clock looks set (year >= 2020). Reveals must never run on an
# unsynced clock (RTC/network time not up yet) — that caused 1970-dated folders.
df_clock_ok() { [ "$(date +%Y 2>/dev/null)" -ge 2020 ] 2>/dev/null; }

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

# Sanitize + cap a label into a legal, OSD-width folder name. Strips FAT-illegal
# characters AND anything non-printable-ASCII (emojis, smart quotes, …) that would
# confuse the MiSTer browser, guarantees the leading "_" a menu folder needs, and
# never returns an empty name.
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
  mkdir -p "$DF_STATE" 2>/dev/null
  printf '%s' "$name" > "$DF_SHOWNAME" 2>/dev/null
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

# (opt-in) Mirror the showcase shortcuts into a subfolder of the mrext/stock-menu
# Favorites folder. This populates the STOCK menu's favorites; a graphical frontend's
# in-app Favorites is managed by the frontend itself, not by this folder. OFF unless
# FAVORITES_MIRROR=1.
df_mirror_favorites() {
  local dir="$1" name fav
  [ "${FAVORITES_MIRROR:-0}" -eq 1 ] || return 0
  [ -d "$dir" ] || return 0
  fav="$DF_ROOT/${FAVORITES_DIR:-_@Favorites}/$(basename "$dir")"
  rm -rf "$fav" 2>/dev/null; mkdir -p "$fav"
  cp "$dir"/*.mgl "$fav"/ 2>/dev/null
  [ -f "$dir/gamelist.xml" ] && cp "$dir/gamelist.xml" "$fav"/ 2>/dev/null
  df_log "mirrored shortcuts to Favorites: $fav"
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

# Wait for a controller button (or ENTER). Never blocks on the boot/daemon path.
df_wait_button() {
  if [ "${DRIPFEED_INTERACTIVE:-0}" != "1" ] && ! df_have_tty; then return 0; fi
  local js="" d ev t v
  for d in /dev/input/js0 /dev/input/js1 /dev/input/js2; do
    [ -e "$d" ] && js="$d" && break
  done
  if [ -n "$js" ]; then
    echo "    Press any controller button to continue..."
    while :; do
      ev=$(dd if="$js" bs=8 count=1 2>/dev/null | od -An -tu1)
      # shellcheck disable=SC2086
      set -- $ev
      [ $# -lt 8 ] && continue
      t=$(( $7 & 127 )); v=$(( $5 | ($6 << 8) ))
      [ "$t" -eq 1 ] && [ "$v" -ne 0 ] && return 0
    done
  else
    # No joystick device — read a SINGLE keypress so ANY button/key advances
    # (controllers on this firmware feed the console as keystrokes; waiting for
    # ENTER made every other button just type a character).
    echo "    Press any button to continue..."
    if [ "${WAIT_TIMEOUT:-0}" -gt 0 ]; then read -rsn1 -t "$WAIT_TIMEOUT" _ 2>/dev/null || true
    else read -rsn1 _ 2>/dev/null || read -r _ 2>/dev/null || true; fi
  fi
}
