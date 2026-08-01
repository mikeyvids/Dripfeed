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

DRIPFEED_VERSION="1.3.2"
DRIPFEED_ROOT="${DRIPFEED_ROOT:-/media/fat}"
HELP="$DRIPFEED_ROOT/Scripts/.dripfeed"
export DRIPFEED_INTERACTIVE=1
scr_clear(){ clear 2>/dev/null || printf '\033[2J\033[H'; }
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
#   --watch     boot daemon (from user-startup.sh): wait BOOT_DELAY, reveal, then
#               re-check once per calendar day. Silent. Logs to dripfeed.log.
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
# performs every file/folder move with same-filesystem mv. A request is removed
# only after its requested state is true on disk.
df_migrate_legacy_queues() {
  local sysdir legacy stage entry base moved=0 held=0 sys
  # Both defaults live on the SD card. Refuse custom paths outside that root so
  # migration can never degrade into a copy/delete across filesystems.
  case "$GAMES_DIR:$STAGING_ROOT" in "$DF_ROOT"/*:"$DF_ROOT"/*) ;; *)
    df_log "LEGACY MIGRATION held: queue paths are outside the MiSTer root"
    return 1 ;;
  esac
  for sysdir in "$GAMES_DIR"/*/; do
    [ -d "$sysdir" ] || continue
    legacy="$sysdir$STAGE_DIRNAME"; [ -d "$legacy" ] || continue
    sys=$(basename "$sysdir"); stage="$(df_stage_dir "$sys")"
    mkdir -p "$stage" 2>/dev/null || { df_log "LEGACY MIGRATION held: cannot create $stage"; continue; }
    for entry in "$legacy"/*; do
      [ -e "$entry" ] || continue
      base=$(basename "$entry")
      if [ -e "$stage/$base" ]; then
        held=$((held+1)); df_log "LEGACY MIGRATION held (destination exists): $sys/$base"; continue
      fi
      if mv "$entry" "$stage/$base" 2>/dev/null; then
        moved=$((moved+1)); df_log "LEGACY MIGRATION moved outside games/: $sys/$base"
      else
        held=$((held+1)); df_log "LEGACY MIGRATION failed: $sys/$base"
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
  if ! df_lock; then
    echo "Dripfeed is busy; no queue entries were moved."
    return 1
  fi
  trap 'df_unlock' RETURN
  df_migrate_legacy_queues
}

df_request_fields_ok() {
  [ -n "$1" ] && [ -n "$2" ] &&
    case "$1$2" in *$'\t'*|*$'\r'*|*$'\n'*|*/*|*\\*) false;; *) true;; esac
}

df_process_unschedule_requests() {
  [ -s "$DF_UNSCHEDULE_REQUESTS" ] || return 0
  local tmp="$DF_UNSCHEDULE_REQUESTS.tmp.$$" sys name staged dest lookup
  : > "$tmp"
  while IFS=$'\t' read -r sys name extra || [ -n "$sys$name${extra:-}" ]; do
    if [ -n "${extra:-}" ] || ! df_request_fields_ok "$sys" "$name"; then
      df_log "BAD browser unschedule request ignored: $sys/$name"; continue
    fi
    dest="$GAMES_DIR/$sys/$name"
    staged=$(df_find_staged_clean "$sys" "$name" 2>/dev/null); lookup=$?
    if [ "$lookup" -eq 2 ]; then
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
    mkdir -p "$(dirname "$dest")" 2>/dev/null || { printf '%s\t%s\n' "$sys" "$name" >> "$tmp"; continue; }
    if mv "$staged" "$dest" 2>/dev/null; then df_log "BROWSER UNSCHEDULE applied: $sys/$name"
    else printf '%s\t%s\n' "$sys" "$name" >> "$tmp"; fi
  done < "$DF_UNSCHEDULE_REQUESTS"
  mv "$tmp" "$DF_UNSCHEDULE_REQUESTS"; sync
}

df_process_schedule_requests() {
  [ -s "$DF_SCHEDULE_REQUESTS" ] || return 0
  local tmp="$DF_SCHEDULE_REQUESTS.tmp.$$" d sys name source staged stage dest lookup
  : > "$tmp"
  while IFS=$'\t' read -r d sys name extra || [ -n "$d$sys$name${extra:-}" ]; do
    if [ -n "${extra:-}" ] || ! df_valid_date "$d" || ! df_request_fields_ok "$sys" "$name"; then
      df_log "BAD browser schedule request ignored: $d $sys/$name"; continue
    fi
    source="$GAMES_DIR/$sys/$name"; stage="$(df_stage_dir "$sys")"; dest="$stage/${d}_$name"
    if [ -e "$source" ] && df_support_entry "$source"; then
      df_log "SKIP browser firmware/support request: $sys/$name"; continue
    fi
    staged=$(df_find_staged_clean "$sys" "$name" 2>/dev/null); lookup=$?
    if [ "$lookup" -eq 2 ]; then
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
    mkdir -p "$stage" 2>/dev/null || { printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"; continue; }
    if [ -n "$staged" ]; then
      if mv "$staged" "$dest" 2>/dev/null; then df_log "BROWSER REDATE applied: $d $sys/$name"
      else printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"; fi
    elif [ -e "$source" ]; then
      if mv "$source" "$dest" 2>/dev/null; then df_log "BROWSER SCHEDULE applied: $d $sys/$name"
      else printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"; fi
    else
      printf '%s\t%s\t%s\n' "$d" "$sys" "$name" >> "$tmp"
      df_log "BROWSER SCHEDULE held (source missing): $d $sys/$name"
    fi
  done < "$DF_SCHEDULE_REQUESTS"
  mv "$tmp" "$DF_SCHEDULE_REQUESTS"; sync
}

df_find_due() {
  local today sysdir stage entry base di sysname
  today=$(df_today_int)
  # Current queue: one hidden library outside games/. A staged folder can be
  # renamed into its final system folder atomically, so every disc arrives or
  # none of them does.
  for stage in "$STAGING_ROOT"/*/; do
    [ -d "$stage" ] || continue
    sysname=$(basename "$stage")
    [ -d "$GAMES_DIR/$sysname" ] || { df_log "SKIP queue for missing system: $sysname"; continue; }
    for entry in "$stage"/*; do
      [ -e "$entry" ] || continue
      base=$(basename "$entry")
      df_is_valid_prefix "$base" || continue
      if ! df_queue_entry_complete "$entry"; then
        df_log "RECOVERY HOLD: incomplete staged folder: $entry"
        continue
      fi
      if df_support_entry "$entry"; then
        df_log "SKIP firmware/support queue entry: $entry"
        continue
      fi
      di=$(df_prefix_date_int "$base")
      [ "$di" -le "$today" ] && printf '%s\t%s\t%s\n' "${base:0:10}" "$sysname" "$entry"
    done
  done
  # Legacy queue: kept readable so upgrades never strand already scheduled
  # games. New scheduling never writes here.
  for sysdir in "$GAMES_DIR"/*/; do
    stage="$sysdir$STAGE_DIRNAME"
    [ -d "$stage" ] || continue
    sysname=$(basename "$sysdir")
    for entry in "$stage"/*; do
      [ -e "$entry" ] || continue
      base=$(basename "$entry")
      df_is_valid_prefix "$base" || continue
      if ! df_queue_entry_complete "$entry"; then
        df_log "RECOVERY HOLD: incomplete legacy staged folder: $entry"
        continue
      fi
      if df_support_entry "$entry"; then
        # A legacy CSV/manual run may have queued firmware (for example
        # MegaCD/USA/cd_bios.rom). Leave it untouched and never reveal it.
        df_log "SKIP firmware/support queue entry: $entry"
        continue
      fi
      di=$(df_prefix_date_int "$base")
      [ "$di" -le "$today" ] && printf '%s\t%s\t%s\n' "${base:0:10}" "$sysname" "$entry"
    done
  done
}

df_reveal_entry() {
  local d="$1" sysname="$2" entry="$3" base clean dest
  base=$(basename "$entry")
  [ -d "$GAMES_DIR/$sysname" ] || { df_log "FAIL missing system folder: $sysname"; return 1; }
  df_queue_entry_complete "$entry" || { df_log "RECOVERY HOLD: incomplete queue entry: $entry"; return 3; }
  clean=$(df_strip_prefix "$base"); dest="$GAMES_DIR/$sysname/$clean"
  REVEAL_SYS="$sysname"; REVEAL_NAME="$clean"; REVEAL_DEST="$dest"
  if [ -e "$dest" ]; then df_log "SKIP exists: $sysname/$clean"; return 2; fi
  df_tx_begin "$d" "$sysname" "$clean" "$entry" "$dest" || { df_log "FAIL journal: $entry -> $dest"; return 1; }
  mv "$entry" "$dest" 2>/dev/null || { df_tx_clear; df_log "FAIL mv: $entry -> $dest"; return 1; }
  # Test hook: simulate power loss in the only vulnerable window. Production
  # never sets this variable; the next run repairs the ledger and shortcut.
  [ "${DRIPFEED_TEST_INTERRUPT_AFTER_MOVE:-0}" = "1" ] && return 75
  df_log "REVEAL: $sysname/$clean"; return 0
}

# Point at the ONE showcase folder (the saved STICKY name — renamed only when
# df_showcase_stamp_name was called for a real reveal), and foolproof-consolidate any
# strays into it (a leftover folder from an older version, or a second one a tinkerer
# created). Ordinary boots therefore keep the exact same folder name, so a frontend's
# entry stays stable across restarts.
df_showcase_prepare() {
  SHOWCASE_DIR=""
  [ "${SHOWCASE:-1}" -eq 1 ] || return 0
  [ -n "$DF_ROOT" ] || return 0
  local canon="$DF_ROOT/$(df_showcase_current_name)" d m target
  mkdir -p "$canon"
  # Move any OTHER _Dripfeed - * / _@Dripfeed - * folders' shortcuts into the current one,
  # then delete them. So the previous folder is REPLACED, never duplicated.
  for d in "$DF_ROOT"/_Dripfeed\ -\ * "$DF_ROOT"/_@Dripfeed\ -\ *; do
    [ -d "$d" ] && [ "$d" != "$canon" ] || continue
    cp -f "$d"/*.mgl "$canon"/ 2>/dev/null
    rm -rf "$d" 2>/dev/null
  done
  rmdir "$DF_ROOT/_Dripfeed" 2>/dev/null       # remove the old empty state-era folder if present
  # Prune shortcuts whose target game is gone (rescheduled/moved) so nothing flip-flops.
  for m in "$canon"/*.mgl; do
    [ -e "$m" ] || continue
    target="$(sed -n 's/.*path="\([^"]*\)".*/\1/p' "$m" | head -1)"
    [ -n "$target" ] && [ ! -e "$target" ] && { rm -f "$m"; df_log "pruned orphan: $(basename "$m")"; }
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

# Build ONE Game of the Month folder.  $1=folder base  $2=pick path  $3=custom label
# Returns 1 if the pick exists but its file isn't on disk yet (caller retries later).
df_gotm_build() {
  local base label dir want="$2" custom="$3" target
  base="$(df_showcase_sanitize "$1")"
  label="$base"
  [ "${GOTM_MONTH:-0}" -eq 1 ] && label="$(df_showcase_sanitize "$base - $(date +%b)")"
  dir="$DF_ROOT/$label"
  if [ -z "$want" ]; then                       # no pick: clear this folder family
    rm -rf "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "* 2>/dev/null
    return 0
  fi
  target="$DF_ROOT/$want"
  if [ ! -e "$target" ]; then
    df_log "GOTM ($base): '$want' not found yet (still scheduled?) - will retry"
    return 1
  fi
  # replace, never duplicate: clear this month's name AND any older-month leftovers
  rm -rf "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "* 2>/dev/null
  mkdir -p "$dir"
  case "$want" in
    *.mra)
      if [ -n "$custom" ]; then cp -f "$target" "$dir/$(df_showcase_sanitize "_$custom" | cut -c2-).mra" 2>/dev/null
      else cp -f "$target" "$dir/" 2>/dev/null; fi
      local rbf corefile
      rbf=$(sed -n 's/.*<rbf>\(.*\)<\/rbf>.*/\1/p' "$target" | head -1)
      if [ -n "$rbf" ]; then
        mkdir -p "$dir/cores"
        corefile=$(ls "$DF_ROOT/_Arcade/cores/$rbf"*.rbf 2>/dev/null | head -1)
        [ -z "$corefile" ] && corefile=$(find "$DF_ROOT/_Arcade/cores" -maxdepth 1 -iname "$rbf*.rbf" 2>/dev/null | head -1)
        if [ -n "$corefile" ]; then cp -f "$corefile" "$dir/cores/" 2>/dev/null
        else df_log "GOTM ($base): core '$rbf' not found in _Arcade/cores"; fi
      fi ;;
    *)
      local sys; sys=$(printf '%s' "$want" | cut -d/ -f2)
      df_make_mgl "$dir" "$sys" "$target" "$custom" || df_log "GOTM ($base): no MGL mapping for $sys" ;;
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

# Keep only the newest SHOWCASE_KEEP shortcuts, then refresh gamelist.xml.
df_showcase_finalize() {
  [ -n "$SHOWCASE_DIR" ] && [ -d "$SHOWCASE_DIR" ] || return 0
  ls -1t "$SHOWCASE_DIR"/*.mgl 2>/dev/null | tail -n +$(( ${SHOWCASE_KEEP:-12} + 1 )) | while read -r old; do rm -f "$old"; done
  df_write_gamelist "$SHOWCASE_DIR"
  df_mirror_favorites "$SHOWCASE_DIR"
}

df_run_reveal() {
  local interactive=0
  if [ "${1:-}" != "--silent" ]; then
    { [ "${DRIPFEED_INTERACTIVE:-0}" = "1" ] || df_have_tty; } && interactive=1
  fi
  # Only one reveal pass at a time (boot daemon vs. a manual launch).
  if ! df_lock; then
    df_log "reveal skipped (another pass holds the lock)"
    [ "$interactive" -eq 1 ] && df_announce "Dripfeed is busy finishing up — try again in a moment."
    return 0
  fi
  trap 'df_unlock' RETURN
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
  local count; count=$(printf '%s' "$due" | grep -c . )
  df_log "reveal pass (interactive=$interactive): $count due"
  if [ -z "$due" ] && [ "$recovered_count" -eq 0 ]; then
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
  local revealed="$recovered_count" d sys entry rc last_date="" msg
  local revlist="$DF_STATE/.revealed.$$"
  mv "$recovered" "$revlist" 2>/dev/null || : > "$revlist"
  if [ "$recovered_count" -gt 0 ]; then
    while IFS=$'\t' read -r rsys rname rdate rdest; do
      [ -n "$rname" ] || continue
      if [ "$interactive" -eq 1 ]; then
        df_announce "RECOVERED AFTER POWER LOSS:  $rname    [$rsys]"
      else
        printf '%s\t%s\t%s\n' "$rsys" "$rname" "$rdate" >> "$DF_PENDING"
      fi
    done < "$revlist"
  fi
  while IFS=$'\t' read -r d sys entry; do
    [ -e "$entry" ] || continue
    df_reveal_entry "$d" "$sys" "$entry"; rc=$?
    [ "$rc" -eq 1 ] && continue
    if [ "$rc" -eq 0 ]; then
      revealed=$((revealed+1))
      df_ledger_record "$d" "$REVEAL_SYS" "$REVEAL_NAME"
      df_tx_clear
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
    if [ -n "$SHOWCASE_DIR" ]; then
      while IFS=$'\t' read -r rsys rname rdate rdest; do
        [ -n "$rdest" ] && df_make_mgl "$SHOWCASE_DIR" "$rsys" "$rdest"
      done < "$revlist"
    fi
  else
    df_showcase_prepare
  fi
  rm -f "$revlist" 2>/dev/null
  df_showcase_finalize
  df_gotm_update
  if [ "$interactive" -eq 1 ]; then
    df_announce "All caught up. Enjoy!"
    [ -n "$SHOWCASE_DIR" ] && echo "  New games are also collected in the menu folder: $(basename "$SHOWCASE_DIR")"
    echo "  If a game isn't showing yet, back out of the folder and re-open it."
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
  : > "$DF_PENDING"
}

df_watch() {
  df_log_trim
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
  [ "${REVEAL_AT_BOOT:-1}" -eq 1 ] && df_run_reveal --silent
  date +%Y%m%d > "$DF_LASTDAY"
  [ "${DAILY:-1}" -eq 1 ] || { df_log "watch done (daily off)"; return 0; }
  local day
  while :; do
    sleep "${WATCH_INTERVAL:-3600}"
    day=$(date +%Y%m%d)
    if [ "$day" != "$(cat "$DF_LASTDAY" 2>/dev/null)" ]; then
      df_run_reveal --silent
      echo "$day" > "$DF_LASTDAY"
    fi
  done
}

df_diag() {
  echo "Dripfeed diagnostics"
  echo "  DF_ROOT     : $DF_ROOT   (exists: $([ -d "$DF_ROOT" ] && echo yes || echo NO))"
  echo "  GAMES_DIR   : $GAMES_DIR (exists: $([ -d "$GAMES_DIR" ] && echo yes || echo NO))"
  echo "  QUEUE_ROOT  : $STAGING_ROOT (exists: $([ -d "$STAGING_ROOT" ] && echo yes || echo no))"
  echo "  STATE       : $DF_STATE  (exists: $([ -d "$DF_STATE" ] && echo yes || echo NO))"
  echo "  config.ini  : $([ -f "$DF_CONFIG" ] && echo present || echo MISSING)"
  echo "  boot hook   : $(grep -q DRIPFEED_AUTORUN "$DF_USERSTARTUP" 2>/dev/null && echo present || echo MISSING) in $DF_USERSTARTUP"
  echo "  clock       : $(date '+%Y-%m-%d %H:%M') $(df_clock_ok && echo '(OK)' || echo '(NOT SET - reveals paused)')"
  echo "  today       : $(df_today_int)"
  echo "  showcase    : $(cat "$DF_SHOWNAME" 2>/dev/null || echo '(not stamped yet)')  (renames only when a game unlocks)"
  echo "  queue (due shown first):"
  df_find_due | sort | while IFS=$'\t' read -r d s e; do echo "    DUE  $d  $s/$(df_strip_prefix "$(basename "$e")")"; done
  echo "  full queue:"
  local sysdir stage entry base clean sys count flags
  for stage in "$STAGING_ROOT"/*/; do
    [ -d "$stage" ] || continue
    sys=$(basename "$stage")
    for entry in "$stage"/*; do [ -e "$entry" ] || continue; base=$(basename "$entry")
      df_is_valid_prefix "$base" || continue
      clean=$(df_strip_prefix "$base"); count=$(df_staged_clean_count "$sys" "$clean"); flags=""
      df_queue_entry_complete "$entry" || flags="$flags INCOMPLETE-HOLD"
      [ -e "$GAMES_DIR/$sys/$clean" ] && flags="$flags VISIBLE-COLLISION"
      [ "$count" -gt 1 ] && flags="$flags DUPLICATE-$count"
      echo "    $base   [$sys]$flags"
    done
  done
  echo "  legacy queue (upgrade-safe):"
  for sysdir in "$GAMES_DIR"/*/; do
    stage="$sysdir$STAGE_DIRNAME"; [ -d "$stage" ] || continue
    sys=$(basename "$sysdir")
    for entry in "$stage"/*; do [ -e "$entry" ] || continue; base=$(basename "$entry")
      df_is_valid_prefix "$base" || continue
      clean=$(df_strip_prefix "$base"); count=$(df_staged_clean_count "$sys" "$clean"); flags=""
      df_queue_entry_complete "$entry" || flags="$flags INCOMPLETE-HOLD"
      [ -e "$GAMES_DIR/$sys/$clean" ] && flags="$flags VISIBLE-COLLISION"
      [ "$count" -gt 1 ] && flags="$flags DUPLICATE-$count"
      echo "    $base   [$sys]$flags"
    done
  done
  echo "  browser move requests: schedule=$(grep -c . "$DF_SCHEDULE_REQUESTS" 2>/dev/null || echo 0), unschedule=$(grep -c . "$DF_UNSCHEDULE_REQUESTS" 2>/dev/null || echo 0)"
  echo "  (log: $DF_LOG)"
  df_log "diag run"
}

# UNDRIP — full clean reset. Un-hide every staged game (regardless of date) back into
# its system folder, delete every Dripfeed folder/file (showcase folders, staging
# folders, state, boot hook, helpers) — keeping ONLY /media/fat/Scripts/Dripfeed.sh so
# the user can cleanly reinstall. Guarded so it can never rm outside /media/fat.
df_undrip() {
  [ -n "$DF_ROOT" ] && [ -d "$GAMES_DIR" ] || { echo "Undrip: bad paths, aborting."; return 1; }
  df_log "UNDRIP start"
  local sysdir stage entry base clean n=0 held=0 qsys conflict_root="$STAGING_ROOT/.conflicts"
  # 1) Reveal ALL staged games (ignore dates) so no ROM is left hidden.
  for stage in "$STAGING_ROOT"/*/; do
    [ -d "$stage" ] || continue
    qsys=$(basename "$stage"); sysdir="$GAMES_DIR/$qsys/"
    [ -d "$sysdir" ] || { echo "  held queue for missing system: $qsys"; held=$((held+1)); continue; }
    for entry in "$stage"/*; do
      [ -e "$entry" ] || continue
      base="$(basename "$entry")"
      if df_is_valid_prefix "$base"; then clean="$(df_strip_prefix "$base")"; else clean="$base"; fi
      if ! df_queue_entry_complete "$entry"; then
        mkdir -p "$conflict_root/$qsys"
        if mv "$entry" "$conflict_root/$qsys/$(date +%Y%m%d-%H%M%S)_$base" 2>/dev/null; then
          echo "  INCOMPLETE COPY HELD (never revealed): $qsys/$clean"
          held=$((held+1))
        fi
      elif [ -e "$sysdir$clean" ]; then
        mkdir -p "$conflict_root/$qsys"
        if mv "$entry" "$conflict_root/$qsys/$(date +%Y%m%d-%H%M%S)_$base" 2>/dev/null; then
          echo "  CONFLICT HELD (nothing deleted): $qsys/$clean"
          held=$((held+1))
        fi
      else mv "$entry" "$sysdir$clean" 2>/dev/null && n=$((n+1)); fi
    done
    rmdir "$stage" 2>/dev/null
  done
  for sysdir in "$GAMES_DIR"/*/; do
    stage="$sysdir$STAGE_DIRNAME"; [ -d "$stage" ] || continue
    for entry in "$stage"/*; do
      [ -e "$entry" ] || continue
      base="$(basename "$entry")"
      if df_is_valid_prefix "$base"; then clean="$(df_strip_prefix "$base")"; else clean="$base"; fi
      if ! df_queue_entry_complete "$entry"; then
        qsys=$(basename "$sysdir"); mkdir -p "$conflict_root/$qsys"
        if mv "$entry" "$conflict_root/$qsys/$(date +%Y%m%d-%H%M%S)_$base" 2>/dev/null; then
          echo "  INCOMPLETE LEGACY COPY HELD (never revealed): $qsys/$clean"
          held=$((held+1))
        fi
      elif [ -e "$sysdir$clean" ]; then
        qsys=$(basename "$sysdir"); mkdir -p "$conflict_root/$qsys"
        if mv "$entry" "$conflict_root/$qsys/$(date +%Y%m%d-%H%M%S)_$base" 2>/dev/null; then
          echo "  CONFLICT HELD (nothing deleted): $qsys/$clean"
          held=$((held+1))
        fi
      else mv "$entry" "$sysdir$clean" 2>/dev/null && n=$((n+1)); fi
    done
    rmdir "$stage" 2>/dev/null            # remove the now-empty hidden staging folder
  done
  echo "  restored $n staged game(s)."
  [ "$held" -eq 0 ] || echo "  held $held conflict(s) safely in $conflict_root for manual comparison."
  # 2) Remove every showcase folder at the SD root (and the Game of the Month folder).
  rm -rf "$DF_ROOT"/_Dripfeed* "$DF_ROOT"/_@Dripfeed* 2>/dev/null
  local gbase; gbase="$(df_showcase_sanitize "${GOTM_DIRNAME:-_Game of the Month}")"
  local sbase; sbase="$(df_showcase_sanitize "${GOTM_SRC_DIRNAME:-_Discord GOTM}")"
  rm -rf "$DF_ROOT/$gbase" "$DF_ROOT/$gbase - "* "$DF_ROOT/$sbase" "$DF_ROOT/$sbase - "* 2>/dev/null
  rm -rf "$DF_ROOT/_Game of the Month" "$DF_ROOT/_Game of the Month - "* \
         "$DF_ROOT/_Discord GOTM" "$DF_ROOT/_Discord GOTM - "* 2>/dev/null  # default names, in case config changed
  # 3) Remove the boot hook.
  "$DF_HELP/dripfeed-install.sh" --uninstall >/dev/null 2>&1
  # 4) Remove the visible Undrip launcher and all state + helper scripts. Only
  #    Scripts/Dripfeed.sh survives (it lives outside the .dripfeed folder).
  rm -f "$DF_SCRIPTS/Undrip.sh" 2>/dev/null
  rm -rf "$DF_STATE" 2>/dev/null
  if [ "$held" -eq 0 ]; then
    rmdir "$STAGING_ROOT" 2>/dev/null || true
    echo "  removed all Dripfeed folders, files, and the boot hook."
  else
    echo "  removed the engine and boot hook; kept the conflict-hold library so no game was deleted."
  fi
  echo "  kept: Scripts/Dripfeed.sh  (open it any time to reinstall clean)."
}

case "${1:-}" in
  --watch)            df_watch ;;
  --auto|--silent)    df_run_reveal --silent ;;
  --pending)          df_announce_pending ;;
  --migrate)          df_migrate_only ;;
  --reveal|"")        df_run_reveal ;;
  --tidy)             df_showcase_prepare; df_write_gamelist "$SHOWCASE_DIR" ;;
  --gotm)             df_gotm_update ;;
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
# Dripfeed configuration — KEY=value, no spaces around =
GAMES_DIR=$DF_ROOT/games
STAGE_DIRNAME=.dripfeed
STAGING_ROOT=$DF_ROOT/.dripfeed-library
WAIT_BUTTON=1        # 1 = wait for a controller button between each new game
WAIT_TIMEOUT=0       # keyboard-only fallback timeout in seconds (0 = wait forever)
REVEAL_AT_BOOT=1     # reveal due games at power-on
DAILY=1              # also reveal once per calendar day while powered on
WATCH_INTERVAL=3600  # seconds between day-change checks
BOOT_DELAY=30        # seconds to wait at power-on before first reveal (avoids racing boot)
SHOWCASE=1           # build the "What's New" menu folder of .mgl shortcuts
SHOWCASE_PREFIX="_Dripfeed - "  # folder-name prefix ("_@Dripfeed - " pins it to the top)
SHOWCASE_DATE=1      # 1 = name shows the date of the latest unlock; 0 = fixed name
SHOWCASE_MAXLEN=30   # cap the folder name to the OSD's visible width
SHOWCASE_KEEP=12     # max shortcuts kept in that folder
GAMELIST=1           # write gamelist.xml in the showcase (full message rides here for frontends)
FAVORITES_MIRROR=0   # opt-in: also mirror shortcuts into the stock-menu Favorites folder
FAVORITES_DIR=_@Favorites
GOTM=1               # build the Game of the Month menu folder (from gotm.tsv)
GOTM_DIRNAME="_Game of the Month"  # "_@..." pins it to the top of the menu
GOTM_MONTH=0         # 1 = append the month to the folder name ("... - Aug")
GOTM_SOURCE=         # optional community Game of the Month feed: a file path (e.g. one an
                     # update_all custom db delivers) or an http(s) URL — builds its OWN
                     # folder alongside your pick
GOTM_SRC_DIRNAME="_Discord GOTM"   # folder name for the community pick
EOF
}

add_hook() {
  mkdir -p "$DF_ROOT/linux"
  if [ ! -f "$US" ]; then
    # Seed the active hook. Start from the template if present, else a fresh shebang.
    if [ -f "$TEMPLATE" ]; then cp "$TEMPLATE" "$US"; else printf '#!/bin/sh\n' > "$US"; fi
  fi
  if grep -q "DRIPFEED_AUTORUN" "$US" 2>/dev/null; then
    echo "  boot hook already present"
  else
    {
      echo ""
      echo "$HOOK_BEGIN"
      echo "[ -f $ENGINE ] && $ENGINE --watch >$DF_STATE/boot.log 2>&1 &"
      echo "$HOOK_END"
    } >> "$US"
    echo "  boot hook added to $US"
  fi
  chmod 755 "$US" 2>/dev/null
}

remove_hook() {
  [ -f "$US" ] || { echo "  no user-startup.sh"; return; }
  if sed -i "/$HOOK_BEGIN/,/$HOOK_END/d" "$US" 2>/dev/null; then :; else
    sed "/$HOOK_BEGIN/,/$HOOK_END/d" "$US" > "$US.tmp" && mv "$US.tmp" "$US"
  fi
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
    : > "$DF_PENDING" 2>/dev/null
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
  local stage; stage="$(df_stage_dir "$sys")"; mkdir -p "$stage"
  local f base n=0 count existing
  for f in "$@"; do
    [ -e "$f" ] || { echo "  skip (not found): $f"; continue; }
    if df_support_entry "$f"; then
      echo "  skip (firmware/support, not a game): $(basename "$f")"; continue
    fi
    base=$(basename "$f")
    df_is_valid_prefix "$base" && base=$(df_strip_prefix "$base")  # re-dating is fine
    count=$(df_staged_clean_count "$sys" "$base")
    if [ "$count" -gt 1 ]; then
      echo "  HOLD (duplicate queue entries need review): [$sys]  $base"; continue
    fi
    if [ "$count" -eq 1 ]; then
      existing=$(df_find_staged_clean "$sys" "$base" 2>/dev/null || true)
      if [ "$f" != "$existing" ]; then
        echo "  SKIP (already queued on another date): [$sys]  $base"; continue
      fi
    fi
    # Never overwrite a visible ROM or an existing queue entry. The old script
    # relied on mv's platform-specific behavior, which can clobber a save.
    if [ -e "$stage/${d}_${base}" ]; then
      echo "  SKIP (already queued): $d  [$sys]  $base"; continue
    fi
    if mv "$f" "$stage/${d}_${base}"; then
      echo "  scheduled $d  [$sys]  $base"; n=$((n+1))
    else
      echo "  FAILED: $f"
    fi
  done
  echo "Done — $n item(s) queued."
}

df_list() {
  local sys="$1" today sysdir stage entry base d di mark out s
  today=$(df_today_int)
  out=$(
    for stage in "$STAGING_ROOT"/${sys:-*}/; do
      [ -d "$stage" ] || continue
      s=$(basename "$stage")
      for entry in "$stage"/*; do
        [ -e "$entry" ] || continue
        base=$(basename "$entry"); df_is_valid_prefix "$base" || continue
        if ! df_queue_entry_complete "$entry"; then
          printf 'HOLD %s  %-12s  %s [incomplete browser copy; source retained]\n' "${base:0:10}" "$s" "$(df_strip_prefix "$base")"
          continue
        fi
        if df_support_entry "$entry"; then
          printf 'SKIP %s  %-12s  %s [firmware/support]\n' "${base:0:10}" "$s" "$(df_strip_prefix "$base")"
          continue
        fi
        d=${base:0:10}; di=$(echo "$d" | tr -d -)
        mark="    "; [ "$di" -le "$today" ] && mark="DUE "
        printf '%s%s  %-12s  %s\n' "$mark" "$d" "$s" "$(df_strip_prefix "$base")"
      done
    done
    # Read the old per-system queue too; upgrading never strands a schedule.
    for sysdir in "$GAMES_DIR"/${sys:-*}/; do
      [ -d "$sysdir" ] || continue
      stage="$sysdir$STAGE_DIRNAME"; [ -d "$stage" ] || continue
      for entry in "$stage"/*; do
        [ -e "$entry" ] || continue
        base=$(basename "$entry"); df_is_valid_prefix "$base" || continue
        if ! df_queue_entry_complete "$entry"; then
          printf 'HOLD %s  %-12s  %s [incomplete legacy copy; never revealed]\n' "${base:0:10}" "$(basename "$sysdir")" "$(df_strip_prefix "$base")"
          continue
        fi
        if df_support_entry "$entry"; then
          printf 'SKIP %s  %-12s  %s [firmware/support]\n' "${base:0:10}" "$(basename "$sysdir")" "$(df_strip_prefix "$base")"
          continue
        fi
        d=${base:0:10}; di=$(echo "$d" | tr -d -)
        mark="    "; [ "$di" -le "$today" ] && mark="DUE "
        printf '%s%s  %-12s  %s\n' "$mark" "$d" "$(basename "$sysdir")" "$(df_strip_prefix "$base")"
      done
    done | sort -k2
  )
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
  local stage entry
  stage="$(df_stage_dir "$sys")"; entry="$stage/$name"
  if [ ! -e "$entry" ]; then
    stage="$(df_legacy_stage_dir "$sys")"; entry="$stage/$name"
  fi
  [ -e "$entry" ] || { echo "Not in queue: $name"; return 1; }
  local clean; clean=$(df_strip_prefix "$name")
  df_is_valid_prefix "$name" || clean="$name"
  [ -e "$GAMES_DIR/$sys/$clean" ] && { echo "Destination already exists; left queue untouched: $sys/$clean"; return 1; }
  if df_support_entry "$entry"; then
    mv "$entry" "$GAMES_DIR/$sys/$clean" && { echo "Restored firmware/support entry (not a game): $sys/$clean"; return; }
    echo "Failed to restore firmware/support entry: $sys/$clean"; return 1
  fi
  mv "$entry" "$GAMES_DIR/$sys/$clean" && { df_ledger_record "$(date +%Y-%m-%d)" "$sys" "$clean"; echo "Revealed now: $sys/$clean"; }
}

# Guided numbered menu (no dialog dependency, works over SSH).
df_menu() {
  local i=1 systems=() d
  for d in "$GAMES_DIR"/*/; do [ -d "$d" ] && systems+=("$(basename "$d")"); done
  [ "${#systems[@]}" -eq 0 ] && { echo "No system folders found in $GAMES_DIR"; return 1; }
  echo "Pick a system:"; i=1
  for s in "${systems[@]}"; do printf "  %2d) %s\n" "$i" "$s"; i=$((i+1)); done
  printf "Number: "; read -r sn
  local sys="${systems[$((sn-1))]}"; [ -n "$sys" ] || { echo "cancelled"; return 1; }
  local sysdir="$GAMES_DIR/$sys" files=()
  for f in "$sysdir"/*; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "$STAGE_DIRNAME" ] && continue
    df_support_entry "$f" && continue
    files+=("$(basename "$f")")
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
    "$HELP/dripfeed-engine.sh" --undrip
    df_menu_countdown 5 "Rebooting" >/dev/null
    sync; reboot 2>/dev/null || true
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
  sync; reboot 2>/dev/null || true; exit 0
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
      "$HELP/dripfeed-engine.sh" --undrip
      df_menu_countdown 5 "Restarting" >/dev/null
      sync; reboot 2>/dev/null || true
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
    sync; reboot 2>/dev/null || true
    exit 0 ;;
esac
"$HELP/dripfeed-engine.sh" --pending
"$HELP/dripfeed-engine.sh" --reveal
echo
echo "  Press any button to return to the menu."
df_confirm_any 30 || true
exit 0
