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
