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
        moved=$((moved+1)); df_pass_hidden "$sys"; df_log "LEGACY MIGRATION moved outside games/: $sys/$base"
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
  df_pass_flush
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
    if [ "$rc" -eq 0 ]; then df_pass_returned "$sys"; df_log "BROWSER UNSCHEDULE applied: $sys/$name"
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
    if df_is_generated_dir "$name"; then
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
      [ "$rc" -eq 0 ] && { df_pass_hidden "$sys"; df_log "BROWSER SCHEDULE applied: $d $sys/$name"; }
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
# A folder is rebuilt on every pass while the OTHER folder waits for its pick, so its
# system-folder shortcuts count as changed only when they really differ afterwards.
df_gotm_build() {
  local gbase before after rc line rel
  gbase="$(df_showcase_sanitize "$1")"
  before="$(df_gotm_mirror_snapshot "$gbase")"
  DF_GOTM_QUIET=1; df_gotm_build_folder "$@"; rc=$?; DF_GOTM_QUIET=0
  after="$(df_gotm_mirror_snapshot "$gbase")"
  if [ "$before" != "$after" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      rel="${line%%$'\t'*}"; rel="${rel#"$GAMES_DIR"/}"; df_pass_changed "${rel%%/*}"
    done <<EOF_GOTM_SNAP
$before
$after
EOF_GOTM_SNAP
  fi
  return "$rc"
}
df_gotm_build_folder() {
  local base label dir want="$2" custom="$3" target
  base="$(df_showcase_sanitize "$1")"
  label="$(df_gotm_label "$base")"
  dir="$DF_ROOT/$label"
  if [ -z "$want" ]; then                       # no pick: clear this folder family
    df_gotm_clear "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "*
    df_gotm_mirror_clear "$base"
    return 0
  fi
  target="$DF_ROOT/$want"
  if [ ! -e "$target" ]; then
    df_log "GOTM ($base): '$want' not found yet (still scheduled?) - will retry"
    return 1
  fi
  # replace, never duplicate: clear this month's name AND any older-month leftovers
  df_gotm_clear "$dir" "$DF_ROOT/$base" "$DF_ROOT/$base - "*
  df_gotm_mirror_clear "$base"
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
  df_gotm_mirror_add "$base" "$label" "$want" "$custom"   # SYSTEM_SHORTCUTS=1 only
  df_log "GOTM built ($base): $want"
  return 0
}

# A GOT'eM folder renamed in config.ini: remove the folders built under the old
# name (only Dripfeed-made ones) and forget them. $1/$2 = the current folder bases.
df_gotm_clear_renamed() {
  [ -f "$DF_GOTM_NAMES" ] || return 0
  local n keep=""
  while IFS= read -r n || [ -n "$n" ]; do
    [ -n "$n" ] || continue
    case "$n" in
      "$1"|"$1 - "*|"$1 -"|"$2"|"$2 - "*|"$2 -"|*/*) keep="$keep$n"$'\n'; continue ;;
      _*) ;;
      *) keep="$keep$n"$'\n'; continue ;;
    esac
    [ -e "$DF_ROOT/$n" ] && { df_gotm_clear "$DF_ROOT/$n" || keep="$keep$n"$'\n'; }
  done < "$DF_GOTM_NAMES"
  if [ -n "$keep" ]; then printf '%s' "$keep" > "$DF_GOTM_NAMES"; else rm -f "$DF_GOTM_NAMES"; fi
}

df_gotm_update() {
  [ "${GOTM:-1}" -eq 1 ] || return 0
  { [ -f "$DF_GOTM" ] || [ -n "${GOTM_SOURCE:-}" ]; } || return 0
  local gb sb
  gb="$(df_showcase_sanitize "${GOTM_DIRNAME:-_Game of the Month}")"
  sb="$(df_showcase_sanitize "${GOTM_SRC_DIRNAME:-_Discord GOTM}")"
  # System-folder shortcuts follow the GOT'eM folders: a renamed folder's go first.
  df_gotm_mirror_prune "$gb" "$sb"
  df_clock_ok || return 0                       # never act on an unsynced clock
  local month cur u s upick ulabel spick slabel TAB ok=0 key
  TAB="$(printf '\t')"
  month=$(date +%Y-%m)
  u="$(df_gotm_user_pick "$month")"; upick="${u%%$TAB*}"; ulabel="${u#*$TAB}"; [ "$ulabel" = "$u" ] && ulabel=""
  s="$(df_gotm_src_pick "$month")";  spick="${s%%$TAB*}"; slabel="${s#*$TAB}"; [ "$slabel" = "$s" ] && slabel=""
  # The folder names are part of what is built: renaming one rebuilds it now.
  key="$month|$upick|$spick|$gb|$sb|${GOTM_MONTH:-0}"
  cur=$(cat "$DF_GOTM_LAST" 2>/dev/null)
  if [ "$cur" = "$key" ]; then
    # Unchanged picks: only add system-folder shortcuts that are missing (for
    # example right after SYSTEM_SHORTCUTS was switched on).
    df_gotm_mirror_ensure "$gb" "$(df_gotm_label "$gb")" "$upick" "$ulabel"
    [ -n "${GOTM_SOURCE:-}" ] && df_gotm_mirror_ensure "$sb" "$(df_gotm_label "$sb")" "$spick" "$slabel"
    return 0
  fi
  df_gotm_clear_renamed "$gb" "$sb"
  df_gotm_build "${GOTM_DIRNAME:-_Game of the Month}" "$upick" "$ulabel" || ok=1
  if [ -n "${GOTM_SOURCE:-}" ]; then
    df_gotm_build "${GOTM_SRC_DIRNAME:-_Discord GOTM}" "$spick" "$slabel" || ok=1
  fi
  [ "$ok" -eq 0 ] && printf '%s' "$key" > "$DF_GOTM_LAST"   # else retry next pass
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
  df_reveal_pass "$interactive"; rc=$?
  df_unlock
  # Optional user command (e.g. ask a frontend to refresh its library): once per
  # pass that revealed, hid or returned games or changed shortcuts in system
  # folders, always with a timeout, and after the lock is released so a slow
  # command never blocks Dripfeed itself.
  df_pass_flush
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
  # Counted for POST_REVEAL_CMD (run once the lock is released).
  DF_PASS_REVEALED=$((DF_PASS_REVEALED + revealed))
  for rsys in $systems; do df_pass_reveal_sys "$rsys"; done
  df_showcase_finalize
  df_gotm_update
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
  # Games hidden above are refreshed together with the boot pass when it can run
  # now; otherwise (clock not set yet, or no reveal at boot) right away.
  if [ "${REVEAL_AT_BOOT:-1}" -ne 1 ] || [ ! -d "$GAMES_DIR" ] || ! df_clock_ok; then df_pass_flush; fi
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
  [ "$rc" -eq 2 ] && df_pass_flush     # the boot pass was skipped: refresh for the early hides
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
      0) DF_UNDRIP_N=$((DF_UNDRIP_N+1)); df_pass_returned "$qsys" ;;
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
  # A frontend's library needs one refresh for the games put back and the
  # shortcut folders removed; this is the last run, so it happens here, before
  # the state folder (and its log) goes.
  df_pass_flush
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
                      df_unlock; df_pass_flush ;;
  --undrip)           df_undrip ;;
  --diag)             df_diag ;;
  -h|--help)          echo "usage: dripfeed-engine.sh [--watch|--auto|--reveal|--pending|--migrate|--tidy|--undrip|--diag]" ;;
  *)                  echo "unknown option: $1"; exit 1 ;;
esac
