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
