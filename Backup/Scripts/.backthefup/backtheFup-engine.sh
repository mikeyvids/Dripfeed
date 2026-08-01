#!/bin/bash
# Back the Files Up engine v1.5.0 for MiSTer FPGA.
# GPL-3.0-or-later; Copyright (C) 2026 MikeyVids.
#
# Exact archive boundary:
#   live     = saves, savestates, RetroAchievements, config, MiSTer.ini,
#              and Dripfeed schedule/state
#   profiler = every stored profile plus the active profile's live-owned files
# Nothing else is accepted from configuration.

set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SELF_DIR/.." && pwd)"
BTFU_ROOT="${BACKTHEFUP_ROOT:-${BACKUP_ROOT:-/media/fat}}"
CONFIG="$SELF_DIR/backtheFup.conf"
LEGACY_DIR="$SCRIPTS_DIR/.backup"
MIGRATION_MARKER="$SELF_DIR/.legacy-settings-imported"

BACKUP_DIR=/media/fat/_Backups
KEEP_LIVE=8
KEEP_PROFILER=8
BACKUP_SCOPE=all-profiles
RCLONE_REMOTE=""
RCLONE_LIVE_DIR=live
RCLONE_PROFILER_DIR=profiler

# Deliberately fixed. Do not make these user-editable without changing the
# documented privacy boundary and tests.
readonly LIVE_INCLUDE="saves savestates retroachievements.cfg config MiSTer.ini Scripts/.dripfeed"
readonly PROFILE_INCLUDE="profiles saves savestates wallpapers retroachievements.cfg menu.png menu.jpg"
config_value(){
  local key="$1" file="$2"
  [ -f "$file" ] || return 1
  awk -F= -v wanted="$key" '
    $1 == wanted {
      value=substr($0,index($0,"=")+1)
      sub(/\r$/, "", value)
      print value
      exit
    }
  ' "$file"
}

set_config_value(){
  local key="$1" value="$2" file="$3" tmp
  tmp="${file}.tmp.$$"
  awk -v wanted="$key" -v replacement="$value" '
    BEGIN { done=0 }
    $0 ~ "^" wanted "=" {
      if (!done) print wanted "=" replacement
      done=1
      next
    }
    { print }
    END { if (!done) print wanted "=" replacement }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

migrate_legacy_settings(){
  local key value
  [ -e "$MIGRATION_MARKER" ] && return 0
  if [ -d "$LEGACY_DIR" ]; then
    for key in BACKUP_DIR KEEP_LIVE KEEP_PROFILER RCLONE_REMOTE RCLONE_LIVE_DIR RCLONE_PROFILER_DIR; do
      value="$(config_value "$key" "$LEGACY_DIR/backup.conf" 2>/dev/null || true)"
      [ -n "$value" ] && set_config_value "$key" "$value" "$CONFIG"
    done
    if [ ! -f "$SELF_DIR/rclone.conf" ] && [ -f "$LEGACY_DIR/rclone.conf" ]; then
      cp "$LEGACY_DIR/rclone.conf" "$SELF_DIR/rclone.conf"
      chmod 600 "$SELF_DIR/rclone.conf" 2>/dev/null || true
    fi
    if [ ! -f "$SELF_DIR/bin/rclone" ] && [ -f "$LEGACY_DIR/bin/rclone" ]; then
      mkdir -p "$SELF_DIR/bin"
      cp "$LEGACY_DIR/bin/rclone" "$SELF_DIR/bin/rclone"
      chmod 755 "$SELF_DIR/bin/rclone" 2>/dev/null || true
    fi
    echo "Imported compatible settings from Scripts/.backup; archive contents use the new fixed boundary."
  fi
  : > "$MIGRATION_MARKER"
}

mkdir -p "$SELF_DIR"
[ -f "$CONFIG" ] || {
  cat > "$CONFIG" <<'EOF_CONFIG'
BACKUP_DIR=/media/fat/_Backups
KEEP_LIVE=8
KEEP_PROFILER=8
BACKUP_SCOPE=all-profiles
RCLONE_REMOTE=
RCLONE_LIVE_DIR=live
RCLONE_PROFILER_DIR=profiler
EOF_CONFIG
}
migrate_legacy_settings
# shellcheck source=/dev/null
. "$CONFIG"
[ -f "$SELF_DIR/rclone.conf" ] && chmod 600 "$SELF_DIR/rclone.conf" 2>/dev/null || true

# Desktop/CI overrides. Normal MiSTer use should use backtheFup.conf.
[ -n "${BACKTHEFUP_DIR_OVERRIDE:-${BACKUP_DIR_OVERRIDE:-}}" ] && BACKUP_DIR="${BACKTHEFUP_DIR_OVERRIDE:-$BACKUP_DIR_OVERRIDE}"
[ -n "${BACKTHEFUP_RCLONE_REMOTE:-${BACKUP_RCLONE_REMOTE:-}}" ] && RCLONE_REMOTE="${BACKTHEFUP_RCLONE_REMOTE:-$BACKUP_RCLONE_REMOTE}"
[ -n "${BACKTHEFUP_KEEP_LIVE:-${BACKUP_KEEP_LIVE:-}}" ] && KEEP_LIVE="${BACKTHEFUP_KEEP_LIVE:-$BACKUP_KEEP_LIVE}"
[ -n "${BACKTHEFUP_KEEP_PROFILER:-${BACKUP_KEEP_PROFILER:-}}" ] && KEEP_PROFILER="${BACKTHEFUP_KEEP_PROFILER:-$BACKUP_KEEP_PROFILER}"

resolve_path(){
  case "$1" in
    /media/fat) printf '%s' "$BTFU_ROOT";;
    /media/fat/*) printf '%s/%s' "$BTFU_ROOT" "$(printf '%s' "$1" | sed 's#^/media/fat/##')";;
    /*) printf '%s' "$1";;
    *) printf '%s/%s' "$BTFU_ROOT" "$1";;
  esac
}

BACKUP_DIR="$(resolve_path "$BACKUP_DIR")"
mkdir -p "$BACKUP_DIR" || { echo "Cannot create backup directory: $BACKUP_DIR" >&2; exit 1; }
LOCK="$BACKUP_DIR/.backthefup.lock"
if ! mkdir "$LOCK" 2>/dev/null; then echo "Back the Files Up is already running."; exit 1; fi
RESTORE_WORK=""
RESTORE_LOG=""
RESTORE_ACTIVE=0
rollback_restore(){
  local tab id had destination saved
  [ -n "$RESTORE_LOG" ] && [ -f "$RESTORE_LOG" ] || return 0
  tab="$(printf '\t')"
  while IFS="$tab" read -r id had destination; do
    [ -n "$id" ] || continue
    saved="$RESTORE_WORK/rollback/$id"
    rm -rf "$destination" 2>/dev/null || true
    if [ "$had" = 1 ] && [ -e "$saved" ]; then
      mkdir -p "$(dirname "$destination")"
      mv "$saved" "$destination" 2>/dev/null || true
    fi
  done < "$RESTORE_LOG"
}
cleanup(){
  if [ "$RESTORE_ACTIVE" = 1 ]; then
    echo "Restore did not finish; returning the original data." >&2
    rollback_restore
  fi
  [ -z "$RESTORE_WORK" ] || rm -rf "$RESTORE_WORK" 2>/dev/null || true
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

active_label(){
  local p
  p="$(cat "$BTFU_ROOT/profiles/.active" 2>/dev/null || true)"
  [ -n "$p" ] || p=Profile
  p="$(printf '%s' "$p" | tr -cd '[:alnum:]_ -' | sed 's/[[:space:]]\+/ /g;s/^ *//;s/ *$//')"
  [ -n "$p" ] || p=Profile
  printf '%s' "$p"
}

archive_name(){
  local kind="$1" label="" stamp
  [ "$#" -gt 1 ] && label="$2"
  stamp="$(date '+%Y_%m_%d_%H%M%S')"
  if [ "$kind" = profiler ]; then
    [ -n "$label" ] || label="$(active_label)"
    label="$(printf '%s' "$label" | tr -cd '[:alnum:]_ -' | tr '[:space:]' '_' | tr -s '_')"
    [ -n "$label" ] || label=Profile
    printf '%s/%s_%s_Profiler.zip' "$BACKUP_DIR" "$stamp" "$label"
  else
    if [ -n "$label" ]; then
      label="$(printf '%s' "$label" | tr -cd '[:alnum:]_ -' | tr '[:space:]' '_' | tr -s '_')"
      [ -n "$label" ] || label=Safety
      printf '%s/MiSTer_Live_%s_%s.zip' "$BACKUP_DIR" "$stamp" "$label"
    else
      printf '%s/MiSTer_Live_%s.zip' "$BACKUP_DIR" "$stamp"
    fi
  fi
}

collect(){
  local list="$1" path absolute
  for path in $list; do
    absolute="$(resolve_path "$path")"
    [ -e "$absolute" ] && printf '%s\n' "$path"
  done
}

hash_file(){
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"
  else return 1
  fi
}

verify_archive(){
  case "$2" in
    zip) command -v unzip >/dev/null 2>&1 && unzip -tq "$1" >/dev/null;;
    tar) tar -tzf "$1" >/dev/null 2>&1;;
    *) return 1;;
  esac
}

archive_format(){
  case "$1" in
    *.zip) printf zip;;
    *.tar.gz|*.tgz) printf tar;;
    *) return 1;;
  esac
}

archive_entries(){
  case "$2" in
    zip) unzip -Z1 "$1";;
    tar) tar -tzf "$1";;
    *) return 1;;
  esac
}

verify_restore_source(){
  local archive="$1" format="$2" expected actual
  [ -f "$archive" ] || { echo "Backup archive not found: $archive" >&2; return 1; }
  verify_archive "$archive" "$format" || { echo "Backup archive failed its integrity check." >&2; return 1; }
  if [ -s "$archive.sha256" ]; then
    expected="$(awk 'NR==1 {print $1}' "$archive.sha256")"
    actual="$(hash_file "$archive" 2>/dev/null | awk 'NR==1 {print $1}')"
    if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
      echo "Backup checksum does not match; restore stopped before changing anything." >&2
      return 1
    fi
  fi
  if archive_entries "$archive" "$format" | grep -Eq '(^/|(^|/)\.\.(/|$)|\\)'; then
    echo "Backup contains an unsafe path; restore stopped." >&2
    return 1
  fi
}

extract_restore_source(){
  local archive="$1" format="$2" stage="$3" entry base
  mkdir -p "$stage" || return 1
  case "$format" in
    zip) unzip -q "$archive" -d "$stage" || return 1;;
    tar) tar -xzf "$archive" -C "$stage" || return 1;;
  esac
  if find "$stage" -type l -print 2>/dev/null | grep -q .; then
    echo "Backup contains a symbolic link; restore stopped." >&2
    return 1
  fi
  for entry in "$stage"/* "$stage"/.[!.]* "$stage"/..?*; do
    [ -e "$entry" ] || continue
    base="${entry##*/}"
    case "$base" in
      saves|savestates|wallpapers|retroachievements.cfg|menu.png|menu.jpg|config|MiSTer.ini|profiles|Scripts) ;;
      *) echo "Backup contains an unexpected top-level item: $base" >&2; return 1;;
    esac
  done
  if [ -d "$stage/Scripts" ]; then
    for entry in "$stage/Scripts"/* "$stage/Scripts"/.[!.]* "$stage/Scripts"/..?*; do
      [ -e "$entry" ] || continue
      [ "${entry##*/}" = .dripfeed ] || { echo "Backup contains an unexpected Scripts item: ${entry##*/}" >&2; return 1; }
    done
  fi
}

valid_restore_profile(){
  case "$1" in ""|.|..|.*|*/*|*\\*) return 1;; esac
  [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" -eq 0 ] 2>/dev/null
}

prepend_restore_log(){
  local id="$1" had="$2" destination="$3" tmp="$RESTORE_LOG.tmp"
  { printf '%s\t%s\t%s\n' "$id" "$had" "$destination"; [ ! -f "$RESTORE_LOG" ] || cat "$RESTORE_LOG"; } > "$tmp" && mv "$tmp" "$RESTORE_LOG"
}

restore_replace(){
  local source="$1" destination="$2" id had=0 saved
  [ -e "$source" ] || { echo "  skipped missing ${source##*/}"; return 0; }
  id="$(date '+%s')_$$_${RESTORE_COUNT}"
  RESTORE_COUNT=$((RESTORE_COUNT + 1))
  saved="$RESTORE_WORK/rollback/$id"
  mkdir -p "$RESTORE_WORK/rollback" "$(dirname "$destination")" || return 1
  if [ -e "$destination" ]; then
    had=1
    mv "$destination" "$saved" || return 1
  fi
  if ! prepend_restore_log "$id" "$had" "$destination"; then
    [ "$had" = 0 ] || mv "$saved" "$destination" 2>/dev/null || true
    return 1
  fi
  mv "$source" "$destination" || return 1
  echo "  restored $destination"
  if [ "${BACKTHEFUP_TEST_FAIL_AFTER:-0}" -eq "$((RESTORE_COUNT - 1))" ] 2>/dev/null; then
    echo "Test-only restore interruption after replacement $((RESTORE_COUNT - 1))." >&2
    return 1
  fi
}

restore_items(){
  local source_root="$1" destination_root="$2" aspect="$3" item
  case "$aspect" in
    all)
      for item in saves savestates retroachievements.cfg wallpapers menu.png menu.jpg config MiSTer.ini Scripts/.dripfeed; do
        if [ -e "$source_root/$item" ]; then
          restore_replace "$source_root/$item" "$destination_root/$item" || return 1
        fi
      done
      ;;
    saves|savestates|wallpapers|config) restore_replace "$source_root/$aspect" "$destination_root/$aspect";;
    retroachievements) restore_replace "$source_root/retroachievements.cfg" "$destination_root/retroachievements.cfg";;
    mister-ini) restore_replace "$source_root/MiSTer.ini" "$destination_root/MiSTer.ini";;
    dripfeed) restore_replace "$source_root/Scripts/.dripfeed" "$destination_root/Scripts/.dripfeed";;
    menu)
      if [ -e "$source_root/menu.png" ]; then restore_replace "$source_root/menu.png" "$destination_root/menu.png" || return 1; fi
      if [ -e "$source_root/menu.jpg" ]; then restore_replace "$source_root/menu.jpg" "$destination_root/menu.jpg" || return 1; fi
      ;;
    *) echo "Unknown restore aspect: $aspect" >&2; return 2;;
  esac
}

profile_source_root(){
  local stage="$1" name="$2" backup_active="$3"
  if [ "$name" = "$backup_active" ]; then printf '%s' "$stage"; else printf '%s/profiles/%s' "$stage" "$name"; fi
}

profile_destination_root(){
  local name="$1" current_active="$2"
  if [ "$name" = "$current_active" ]; then printf '%s' "$BTFU_ROOT"; else printf '%s/profiles/%s' "$BTFU_ROOT" "$name"; fi
}

restore_one_profile(){
  local stage="$1" name="$2" aspect="$3" backup_active="$4" current_active="$5" source destination
  valid_restore_profile "$name" || { echo "Unsafe profile name in restore request." >&2; return 1; }
  source="$(profile_source_root "$stage" "$name" "$backup_active")"
  [ -d "$source" ] || { echo "Profile '$name' is not in this backup." >&2; return 1; }
  destination="$(profile_destination_root "$name" "$current_active")"
  restore_items "$source" "$destination" "$aspect"
}

restore_archived_profile_aspect(){
  local stage="$1" aspect="$2" archived name destination
  [ -d "$stage/profiles/.archive" ] || return 0
  for archived in "$stage/profiles/.archive"/*; do
    [ -d "$archived" ] || continue
    name="${archived##*/}"
    destination="$BTFU_ROOT/profiles/.archive/$name"
    restore_items "$archived" "$destination" "$aspect" || return 1
  done
}

restore_every_profile_aspect(){
  local stage="$1" aspect="$2" backup_active="$3" current_active="$4" profile name
  restore_one_profile "$stage" "$backup_active" "$aspect" "$backup_active" "$current_active" || return 1
  if [ -d "$stage/profiles" ]; then
    for profile in "$stage/profiles"/*; do
      [ -d "$profile" ] || continue
      name="${profile##*/}"
      [ "$name" = "$backup_active" ] && continue
      restore_one_profile "$stage" "$name" "$aspect" "$backup_active" "$current_active" || return 1
    done
  fi
  restore_archived_profile_aspect "$stage" "$aspect"
}

restore_safety_backup(){
  local kind="$1" RCLONE_REMOTE="" KEEP_LIVE=999999 KEEP_PROFILER=999999 label
  [ "${BACKTHEFUP_SKIP_RESTORE_SAFETY:-0}" = 1 ] && return 0
  label="Before_Restore_$(active_label)"
  echo "Making a local before-restore safety backup..."
  if [ "$kind" = profiler ]; then make_archive profiler "$label"; else make_archive live Before_Restore; fi
}

archive_kind(){
  local archive="$1" manifest="$archive.manifest.txt" value
  value="$(config_value kind "$manifest" 2>/dev/null || true)"
  case "$value" in live|profiler) printf '%s' "$value"; return 0;; esac
  case "${archive##*/}" in *_Profiler.zip|*_Profiler.tar.gz) printf profiler;; *) printf live;; esac
}

choose_restore_archive(){
  local archive args=()
  for archive in "$BACKUP_DIR"/*.zip "$BACKUP_DIR"/*.tar.gz "$BACKUP_DIR"/*.tgz; do
    [ -f "$archive" ] || continue
    args+=("$archive" "${archive##*/}")
  done
  [ "${#args[@]}" -gt 0 ] || { dialog --msgbox "No local backup archives were found in _Backups." 8 58; return 1; }
  dialog --stdout --backtitle "Back the Files Up" --menu "Choose a local backup to restore:" 21 90 14 "${args[@]}"
}

choose_profile_scope(){
  local stage="$1" backup_active="$2" profile name args=()
  args+=(profiles "Every player in this backup")
  args+=("profile:$backup_active" "$backup_active (active when backed up)")
  if [ -d "$stage/profiles" ]; then
    for profile in "$stage/profiles"/*; do
      [ -d "$profile" ] || continue
      name="${profile##*/}"
      [ "$name" = "$backup_active" ] && continue
      args+=("profile:$name" "$name")
    done
  fi
  dialog --stdout --backtitle "Back the Files Up" --menu "Restore every player or only one?" 20 72 12 "${args[@]}"
}

choose_restore_aspect(){
  local kind="$1" args=()
  if [ "$kind" = live ]; then
    args=(all "Everything in this live backup" saves "Game saves" savestates "Save states" retroachievements "RetroAchievements settings" dripfeed "Dripfeed schedule and state" config "MiSTer config folder" mister-ini "MiSTer.ini")
  else
    args=(all "Everything for the selected player(s)" saves "Game saves" savestates "Save states" retroachievements "RetroAchievements settings" wallpapers "Wallpapers" menu "Menu image")
  fi
  dialog --stdout --backtitle "Back the Files Up" --menu "Which part should be restored?" 20 72 12 "${args[@]}"
}

restore_archive(){
  local archive="${1:-}" scope="${2:-}" aspect="${3:-}" format kind stage backup_active current_active confirm_text profile
  if [ -z "$archive" ]; then
    command -v dialog >/dev/null 2>&1 || { echo "Restore needs an archive, scope, and aspect over SSH." >&2; return 2; }
    archive="$(choose_restore_archive)" || return 0
  fi
  format="$(archive_format "$archive")" || { echo "Restore accepts .zip, .tar.gz, or .tgz backups." >&2; return 2; }
  verify_restore_source "$archive" "$format" || return 1
  RESTORE_WORK="$BTFU_ROOT/.backthefup-restore.$$"
  stage="$RESTORE_WORK/stage"
  rm -rf "$RESTORE_WORK" 2>/dev/null || true
  mkdir -p "$RESTORE_WORK"
  extract_restore_source "$archive" "$format" "$stage" || return 1
  kind="$(archive_kind "$archive")"
  backup_active="$(cat "$stage/profiles/.active" 2>/dev/null || true)"
  [ -n "$backup_active" ] || backup_active="$(active_label)"
  valid_restore_profile "$backup_active" || { echo "Backup has an unsafe active-profile marker." >&2; return 1; }
  current_active="$(active_label)"
  if [ -z "$scope" ]; then
    if [ "$kind" = profiler ]; then scope="$(choose_profile_scope "$stage" "$backup_active")" || return 0; else scope=live; fi
  fi
  case "$scope" in
    live) [ "$kind" = live ] || { echo "Use profile scope with a Profiler backup." >&2; return 2; };;
    profiles|profile:*) [ "$kind" = profiler ] || { echo "Profile restore needs a Profiler backup." >&2; return 2; };;
    *) echo "Unknown restore scope: $scope" >&2; return 2;;
  esac
  if [ -z "$aspect" ]; then aspect="$(choose_restore_aspect "$kind")" || return 0; fi
  case "$kind:$aspect" in
    live:all|live:saves|live:savestates|live:retroachievements|live:dripfeed|live:config|live:mister-ini|profiler:all|profiler:saves|profiler:savestates|profiler:retroachievements|profiler:wallpapers|profiler:menu) ;;
    *) echo "'$aspect' is not available for a $kind backup." >&2; return 2;;
  esac
  confirm_text="Restore ${aspect} from\n${archive##*/}\n\nScope: $scope\n\nA local Before Restore safety backup is made first."
  if command -v dialog >/dev/null 2>&1 && [ -z "${BACKTHEFUP_ASSUME_YES:-}" ]; then
    dialog --yesno "$confirm_text" 14 76 || return 0
    clear 2>/dev/null || true
  elif [ -z "${BACKTHEFUP_ASSUME_YES:-}" ] && [ "${BACKTHEFUP_SKIP_RESTORE_SAFETY:-0}" != 1 ]; then
    echo "Headless restore requires BACKTHEFUP_ASSUME_YES=1." >&2
    return 2
  fi
  restore_safety_backup "$kind" || { echo "Safety backup failed; restore stopped." >&2; return 1; }
  RESTORE_LOG="$RESTORE_WORK/rollback.log"
  : > "$RESTORE_LOG"
  RESTORE_COUNT=1
  RESTORE_ACTIVE=1
  echo "Restoring from ${archive##*/}..."
  case "$scope" in
    live) restore_items "$stage" "$BTFU_ROOT" "$aspect" || return 1;;
    profiles)
      if [ "$aspect" = all ]; then
        restore_replace "$stage/profiles" "$BTFU_ROOT/profiles" || return 1
        for profile in saves savestates wallpapers retroachievements.cfg menu.png menu.jpg; do
          if [ -e "$stage/$profile" ]; then restore_replace "$stage/$profile" "$BTFU_ROOT/$profile" || return 1; fi
        done
      else
        restore_every_profile_aspect "$stage" "$aspect" "$backup_active" "$current_active" || return 1
      fi
      ;;
    profile:*)
      profile="${scope#profile:}"
      restore_one_profile "$stage" "$profile" "$aspect" "$backup_active" "$current_active" || return 1
      ;;
  esac
  sync
  RESTORE_ACTIVE=0
  rm -rf "$RESTORE_WORK"
  RESTORE_WORK=""
  echo "Restore complete. Restart MiSTer before playing so menus and cores reopen the restored data cleanly."
}

prune_archives(){
  local kind="$1" keep="$2" old count=0
  [ "$keep" -gt 0 ] 2>/dev/null || return 0
  if [ "$kind" = profiler ]; then
    set -- "$BACKUP_DIR"/*_Profiler.zip "$BACKUP_DIR"/*_Profiler.tar.gz
  else
    set -- "$BACKUP_DIR"/MiSTer_Live_*.zip "$BACKUP_DIR"/MiSTer_Live_*.tar.gz
  fi
  for old in $(ls -1t "$@" 2>/dev/null | tail -n +$((keep + 1))); do
    [ -f "$old" ] || continue
    rm -f "$old" "$old.sha256" "$old.manifest.txt"
    count=$((count + 1))
  done
  [ "$count" -eq 0 ] || echo "  removed $count expired local $kind archive(s)"
}

rclone_path(){
  local binary=""
  command -v rclone >/dev/null 2>&1 && binary="$(command -v rclone)"
  if [ -f "$SELF_DIR/bin/rclone" ]; then
    chmod 755 "$SELF_DIR/bin/rclone" 2>/dev/null || true
    [ -x "$SELF_DIR/bin/rclone" ] && binary="$SELF_DIR/bin/rclone"
  fi
  printf '%s' "$binary"
}

cloud_status(){
  local binary remote_name
  binary="$(rclone_path)"
  echo "Cloud destination scope: whole MiSTer + all Profiler profiles"
  [ "$BACKUP_SCOPE" = all-profiles ] || echo "Warning: unsupported BACKUP_SCOPE='$BACKUP_SCOPE'; this release uses all-profiles."
  if [ -z "$RCLONE_REMOTE" ]; then
    echo "Cloud upload: off (local verified archives still work)"
    return 2
  fi
  if ! printf '%s' "$RCLONE_REMOTE" | grep -Eq '^[A-Za-z0-9._-]+:.+'; then
    echo "Cloud upload: destination must look like gdrive:MiSTerBackups"
    return 2
  fi
  if [ -z "$binary" ]; then
    echo "Cloud upload: needs the Linux ARMv7 rclone binary"
    return 2
  fi
  if [ ! -f "$SELF_DIR/rclone.conf" ] && [ -z "${RCLONE_CONFIG:-}" ]; then
    echo "Cloud upload: needs rclone.conf from the setup wizard"
    return 2
  fi
  [ -f "$SELF_DIR/rclone.conf" ] && export RCLONE_CONFIG="$SELF_DIR/rclone.conf"
  remote_name="${RCLONE_REMOTE%%:*}:"
  if ! "$binary" listremotes 2>/dev/null | grep -Fxq "$remote_name"; then
    echo "Cloud upload: '$remote_name' is not present in rclone.conf"
    return 2
  fi
  echo "Cloud upload: configured for $RCLONE_REMOTE"
  return 0
}

check_cloud(){
  local binary remote_root
  cloud_status || return $?
  binary="$(rclone_path)"
  remote_root="${RCLONE_REMOTE%%:*}:"
  echo "Checking read access over the current network..."
  # Check the authorized remote itself. The configured backup folder may not
  # exist until the first upload, which should not make setup look broken.
  if "$binary" lsd "$remote_root" --max-depth 1 >/dev/null; then
    echo "Cloud check passed. Future backups reuse this authorization automatically."
    return 0
  fi
  echo "Cloud check failed. The local backup feature is still safe." >&2
  echo "Check WiFi/Ethernet, date and time, destination spelling, or replace expired OAuth in Back the Files Up - Setup." >&2
  return 1
}

upload(){
  local output="$1" destination="$2" binary item failed=0
  if [ -z "$RCLONE_REMOTE" ]; then
    echo "  cloud: off (local backup only)"
    return 0
  fi
  if ! cloud_status >/dev/null; then
    echo "  CLOUD COPY NOT MADE: setup is incomplete; verified archive kept locally" >&2
    echo "  Run backtheFup.sh -> Check cloud connection after using the setup page." >&2
    return 4
  fi
  binary="$(rclone_path)"
  [ -f "$SELF_DIR/rclone.conf" ] && export RCLONE_CONFIG="$SELF_DIR/rclone.conf"
  echo "  cloud: uploading over the current network to $RCLONE_REMOTE/$destination"
  for item in "$output" "$output.sha256" "$output.manifest.txt"; do
    [ -f "$item" ] || continue
    "$binary" copy "$item" "$RCLONE_REMOTE/$destination" || failed=1
  done
  [ "$failed" -eq 0 ] || { echo "  cloud: upload failed; verified local archive is safe" >&2; return 1; }
  echo "  cloud: uploaded"
}

make_archive(){
  local kind="$1" label="" list output partial manifest format found estimate absolute size upload_status=0
  [ "$#" -gt 1 ] && label="$2"
  [ "$kind" = profiler ] && list="$PROFILE_INCLUDE" || list="$LIVE_INCLUDE"
  found="$(collect "$list")"
  if [ -z "$found" ]; then
    echo "Nothing found for $kind backup under $BTFU_ROOT; skipped."
    return 3
  fi
  output="$(archive_name "$kind" "$label")"
  estimate=0
  for path in $found; do
    absolute="$(resolve_path "$path")"
    size=$(du -sk "$absolute" 2>/dev/null | awk 'NR==1{print $1+0}')
    estimate=$((estimate + size))
    echo "  source: $path  (~${size} KiB before compression)"
  done
  echo "  estimated source total: ~${estimate} KiB"
  [ "$kind" != live ] || echo "  note: rebuildable config databases/caches/logs are excluded"
  if [ "${BACKTHEFUP_FORCE_TAR:-${BACKUP_FORCE_TAR:-0}}" != 1 ] && command -v zip >/dev/null 2>&1; then
    format=zip
  else
    format=tar
    output="${output%.zip}.tar.gz"
  fi
  partial="$output.partial.$$"
  manifest="$output.manifest.txt"
  echo "Creating $(basename "$output")"
  {
    echo "tool=Back the Files Up"
    echo "kind=$kind"
    echo "scope=all-profiles"
    echo "created=$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "root=$BTFU_ROOT"
    echo "included:"
    printf '%s\n' "$found"
  } > "$manifest"
  if [ "$format" = zip ]; then
    # shellcheck disable=SC2046
    ( cd "$BTFU_ROOT" && zip -r -q "$partial" $(printf '%s\n' "$found") -x \
      '*.DS_Store' 'config/*.db' 'config/*.db-*' 'config/*.sqlite' 'config/*.sqlite-*' \
      'config/*.sqlite3' 'config/*.sqlite3-*' 'config/*.log' 'config/*cache*/*' \
      'config/*Cache*/*' 'config/*thumbnail*/*' 'config/*Thumbnail*/*' ) || {
      rm -f "$partial" "$manifest"; echo "Archive failed; old backups retained." >&2; return 1;
    }
  else
    # shellcheck disable=SC2046
    ( cd "$BTFU_ROOT" && tar -czf "$partial" --exclude='*.DS_Store' \
      --exclude='config/*.db' --exclude='config/*.db-*' --exclude='config/*.sqlite' \
      --exclude='config/*.sqlite-*' --exclude='config/*.sqlite3' --exclude='config/*.sqlite3-*' \
      --exclude='config/*.log' --exclude='config/*cache*/*' --exclude='config/*Cache*/*' \
      --exclude='config/*thumbnail*/*' --exclude='config/*Thumbnail*/*' $(printf '%s\n' "$found") ) || {
      rm -f "$partial" "$manifest"; echo "Archive failed; old backups retained." >&2; return 1;
    }
  fi
  verify_archive "$partial" "$format" || {
    rm -f "$partial" "$manifest"; echo "Archive verification failed; old backups retained." >&2; return 1;
  }
  mv "$partial" "$output"
  hash_file "$output" > "$output.sha256" 2>/dev/null || true
  echo "  wrote $output ($(du -h "$output" 2>/dev/null | cut -f1))"
  if [ "$kind" = profiler ]; then
    upload "$output" "$RCLONE_PROFILER_DIR" || upload_status=$?
    prune_archives profiler "$KEEP_PROFILER"
  else
    upload "$output" "$RCLONE_LIVE_DIR" || upload_status=$?
    prune_archives live "$KEEP_LIVE"
  fi
  [ "$upload_status" -eq 0 ] || {
    echo "RESULT: LOCAL BACKUP SAVED; CLOUD COPY FAILED OR IS NOT READY." >&2
    return "$upload_status"
  }
  echo "RESULT: LOCAL BACKUP SAVED$([ -n "$RCLONE_REMOTE" ] && echo ' AND COPIED TO CLOUD' || true)."
  return 0
}

dry_run(){
  local kind="$1" list
  [ "$kind" = profiler ] && list="$PROFILE_INCLUDE" || list="$LIVE_INCLUDE"
  echo "$kind backup would include only:"
  collect "$list" | sed 's/^/  /'
}

run_all(){
  local label="$1" live_status=0 profile_status=0
  make_archive live || live_status=$?
  make_archive profiler "$label" || profile_status=$?
  [ "$live_status" -eq 0 ] || [ "$live_status" -eq 3 ] || [ "$live_status" -eq 4 ] || return "$live_status"
  [ "$profile_status" -eq 0 ] || [ "$profile_status" -eq 3 ] || [ "$profile_status" -eq 4 ] || return "$profile_status"
  [ "$live_status" -ne 4 ] && [ "$profile_status" -ne 4 ] || return 4
  [ "$live_status" -eq 0 ] || [ "$profile_status" -eq 0 ]
}

usage(){
  echo "usage: backtheFup.sh [all [label]|live|profiler [label]|restore [ARCHIVE SCOPE ASPECT]|--dry-run MODE|--status|--check-cloud]" >&2
}

mode=all
[ "$#" -gt 0 ] && mode="$1"
label=""
[ "$#" -gt 1 ] && label="$2"
case "$mode" in
  live) make_archive live;;
  profiler) make_archive profiler "$label";;
  restore)
    shift
    restore_archive "${1:-}" "${2:-}" "${3:-}"
    ;;
  all) run_all "$label";;
  --dry-run)
    kind=live
    [ "$#" -gt 1 ] && kind="$2"
    case "$kind" in live|profiler) dry_run "$kind";; *) usage; exit 2;; esac
    ;;
  --status)
    echo "Back the Files Up v1.5.0"
    dry_run live
    dry_run profiler
    cloud_status || true
    ;;
  --check-cloud) check_cloud;;
  *) usage; exit 2;;
esac
