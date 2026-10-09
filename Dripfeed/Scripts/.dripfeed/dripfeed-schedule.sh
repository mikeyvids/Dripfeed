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
