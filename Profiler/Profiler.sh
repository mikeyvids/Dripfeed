#!/bin/bash
# Profiler.sh — simple player profiles for MiSTer FPGA (v0.5.0)
#
# One MiSTer, several players: each profile owns its own game saves, save states,
# RetroAchievements login, and wallpapers. Switching profiles atomically swaps
# those in/out with plain renames on the same filesystem — no symlinks (FAT/exFAT
# cards can't do them), no copies of big files, nothing ever deleted.
#
# Layout:
#   /media/fat/profiles/<Name>/            stored items of an INACTIVE profile
#   /media/fat/profiles/.active            name of the ACTIVE profile
#   /media/fat/profiles/.archive/          removed profiles (recoverable, never wiped)
#   /media/fat/_Profiler - <Name>/         read-only top-level active-player indicator
#   /media/fat/Scripts/Profiler - <Name>/  real executable "Switch to <Other>.sh"
#                                          entries in MiSTer's Scripts menu.
#
# Older builds tried to treat an .mgl selection as a shell command by watching
# /tmp/STARTPATH. MiSTer does not guarantee that behavior. This build uses actual
# Scripts-menu shell files, so pressing Switch always executes the profile swap.
#
# The ACTIVE profile's items live in their normal places (saves/, savestates/,
# retroachievements.cfg, wallpapers/) so every core & tool behaves 100% stock.

PF_ROOT="${PROFILER_ROOT:-/media/fat}"
# A computer repairs the card through /Volumes/... while MiSTer later mounts it
# at /media/fat. Keep generated launch commands independent from the repair path.
PF_LAUNCH_ROOT="${PROFILER_LAUNCH_ROOT:-$PF_ROOT}"
PF_DIR="$PF_ROOT/profiles"
PF_ACTIVE="$PF_DIR/.active"
PF_LOG="$PF_DIR/.profiler.log"
PF_LOCK="$PF_DIR/.lock"
# What travels with a profile (edit here to add more):
SWAP_DIRS="saves savestates wallpapers"
SWAP_FILES="retroachievements.cfg menu.png menu.jpg"
OSD_PREFIX="_Profiler - "
SCRIPT_PREFIX="Profiler - "

log(){ mkdir -p "$PF_DIR"; printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$PF_LOG" 2>/dev/null; }
sane(){ printf '%s' "$1" | tr -d '<>:"/\\|?*' | tr -cd '\40-\176' | sed 's/^ *//;s/ *$//' | cut -c1-20; }
valid_name(){
  local raw="$1" clean; clean="$(sane "$raw")"
  case "$raw" in *[!A-Za-z0-9_\ -]*) return 1;; esac
  [ -n "$clean" ] && [ "$clean" = "$raw" ] && [ "$clean" != "." ] && [ "$clean" != ".." ] && [ "${clean#.}" = "$clean" ]
}
active(){ cat "$PF_ACTIVE" 2>/dev/null || echo "Default"; }

osd_folder(){  # rebuild active indicator + executable Scripts submenu
  local cur want scripts_want d p wrapper
  cur="$(active)"
  want="$PF_ROOT/${OSD_PREFIX}$(sane "$cur")"
  scripts_want="$PF_ROOT/Scripts/${SCRIPT_PREFIX}$(sane "$cur")"
  for d in "$PF_ROOT/${OSD_PREFIX}"*; do
    [ -d "$d" ] || continue
    [ "$d" = "$want" ] && continue
    rm -rf "$d" 2>/dev/null
  done
  for d in "$PF_ROOT/Scripts/${SCRIPT_PREFIX}"*; do
    [ -d "$d" ] || continue
    [ "$d" = "$scripts_want" ] && continue
    rm -rf "$d" 2>/dev/null
  done
  mkdir -p "$want" 2>/dev/null
  rm -f "$want"/*.mgl 2>/dev/null
  mkdir -p "$scripts_want" 2>/dev/null
  rm -f "$scripts_want"/*.sh 2>/dev/null
  while IFS= read -r p; do
    [ -n "$p" ] && [ "$p" != "$cur" ] || continue
    wrapper="$scripts_want/Switch to $(sane "$p").sh"
    {
      printf '#!/bin/bash\n'
      printf 'exec "%s/Scripts/Profiler.sh" switch "%s"\n' "$PF_LAUNCH_ROOT" "$p"
    } > "$wrapper"
    chmod 755 "$wrapper" 2>/dev/null
  done <<EOF3
$(list_profiles)
EOF3
}

HOOK_BEGIN="#=====PROFILER_AUTORUN====="
HOOK_END="#=====PROFILER_AUTORUN_END====="
US="$PF_ROOT/linux/user-startup.sh"
remove_legacy_hook(){
  local tmp
  [ -f "$US" ] || return 0
  grep -q "PROFILER_AUTORUN" "$US" 2>/dev/null || return 0
  tmp="$US.profiler-new.$$"
  awk -v b="$HOOK_BEGIN" -v e="$HOOK_END" '$0==b{skip=1;next}$0==e{skip=0;next}!skip{print}' "$US" > "$tmp" &&
    mv "$tmp" "$US" && chmod 755 "$US" 2>/dev/null
  log "removed obsolete STARTPATH watcher hook"
}

lock(){ mkdir -p "$PF_DIR"; if ! mkdir "$PF_LOCK" 2>/dev/null; then echo "Another switch is running."; exit 1; fi; trap 'rmdir "$PF_LOCK" 2>/dev/null' EXIT; }

ensure_init(){
  mkdir -p "$PF_DIR" "$PF_DIR/.archive"
  if [ ! -f "$PF_ACTIVE" ]; then
    printf 'Default' > "$PF_ACTIVE"
    mkdir -p "$PF_DIR/Default"
    log "initialized; current setup registered as profile 'Default'"
  fi
  osd_folder
  remove_legacy_hook
}

list_profiles(){
  local cur; cur="$(active)"
  { echo "$cur"; ls -1 "$PF_DIR" 2>/dev/null | grep -v '^\.'; } | sort -u
}

stash_item(){ # $1=profile dir  $2=item name  (live -> stored)
  if [ -e "$PF_ROOT/$2" ]; then mkdir -p "$1"; mv "$PF_ROOT/$2" "$1/$2" || return 1; fi
}
restore_item(){ # $1=profile dir  $2=item  $3=dir|file  (stored -> live)
  if [ -e "$1/$2" ]; then mv "$1/$2" "$PF_ROOT/$2" || return 1
  elif [ "$3" = dir ]; then mkdir -p "$PF_ROOT/$2"; fi
}

do_switch(){
  local new="$1" cur; cur="$(active)"
  [ -n "$new" ] || { echo "usage: switch <profile>"; return 1; }
  valid_name "$new" || { echo "Invalid profile name."; return 1; }
  [ "$new" = "$cur" ] && { echo "'$new' is already active."; return 0; }
  [ -d "$PF_DIR/$new" ] || { echo "No such profile: $new"; return 1; }
  lock
  log "SWITCH $cur -> $new : begin"
  local it stashed="" restored=""
  for it in $SWAP_DIRS $SWAP_FILES; do
    if [ -e "$PF_ROOT/$it" ]; then
      stash_item "$PF_DIR/$cur" "$it" || { log "FAILED stashing $it - rolling back"; rollback_switch "$cur" "$new" "$stashed" ""; echo "Failed on '$it' — switch rolled back; check $PF_LOG"; return 1; }
      stashed="$stashed $it"
    fi
  done
  for it in $SWAP_DIRS; do
    if [ -e "$PF_DIR/$new/$it" ]; then
      restore_item "$PF_DIR/$new" "$it" dir || { log "FAILED restoring $it - rolling back"; rollback_switch "$cur" "$new" "$stashed" "$restored"; echo "Switch failed and was rolled back; check $PF_LOG"; return 1; }
      restored="$restored $it"
    else
      restore_item "$PF_DIR/$new" "$it" dir || { rollback_switch "$cur" "$new" "$stashed" "$restored"; echo "Switch failed and was rolled back."; return 1; }
    fi
  done
  for it in $SWAP_FILES; do
    if [ -e "$PF_DIR/$new/$it" ]; then
      restore_item "$PF_DIR/$new" "$it" file || { log "FAILED restoring $it - rolling back"; rollback_switch "$cur" "$new" "$stashed" "$restored"; echo "Switch failed and was rolled back; check $PF_LOG"; return 1; }
      restored="$restored $it"
    fi
  done
  printf '%s' "$new" > "$PF_ACTIVE"
  osd_folder
  sync
  log "SWITCH $cur -> $new : done"
  echo "Now playing as: $new"
}

rollback_switch(){
  local cur="$1" new="$2" stashed="$3" restored="$4" it
  for it in $restored; do [ -e "$PF_ROOT/$it" ] && stash_item "$PF_DIR/$new" "$it"; done
  for it in $stashed; do
    case " $SWAP_DIRS " in *" $it "*) restore_item "$PF_DIR/$cur" "$it" dir;; *) restore_item "$PF_DIR/$cur" "$it" file;; esac
  done
}

do_create(){
  local name="$1"
  valid_name "$name" || { echo "Invalid profile name (use letters, numbers, spaces, _ or -; max 20 chars)."; return 1; }
  [ -d "$PF_DIR/$name" ] && { echo "Profile exists: $name"; return 1; }
  mkdir -p "$PF_DIR/$name/saves" "$PF_DIR/$name/savestates" "$PF_DIR/$name/wallpapers"
  # fresh RA file (fill in via the Profiler Manager web page, or edit by hand)
  printf '# RetroAchievements configuration file\nusername=\npassword=\n' > "$PF_DIR/$name/retroachievements.cfg"
  log "created profile $name"
  osd_folder
  echo "Created: $name  (empty saves; set RA login via the Profiler Registry)"
}

do_remove(){ # non-destructive: archived, never deleted
  local name="$1" cur; cur="$(active)"
  [ -n "$name" ] || { echo "usage: remove <name>"; return 1; }
  valid_name "$name" || { echo "Invalid profile name."; return 1; }
  [ "$name" = "$cur" ] && { echo "Can't remove the ACTIVE profile. Switch away first."; return 1; }
  [ -d "$PF_DIR/$name" ] || { echo "No such profile: $name"; return 1; }
  mkdir -p "$PF_DIR/.archive"
  mv "$PF_DIR/$name" "$PF_DIR/.archive/$(date +%Y%m%d-%H%M%S)-$name"
  log "archived profile $name"
  osd_folder
  echo "Archived (recoverable in profiles/.archive): $name"
}

menu(){
  ensure_init
  command -v dialog >/dev/null 2>&1 || { echo "Active: $(active)"; echo "Profiles:"; list_profiles | sed 's/^/  /'; echo "usage: Profiler.sh [switch|create|remove|status] <name>"; return 0; }
  while :; do
    local cur items p n=1
    cur="$(active)"; items=""
    for p in $(list_profiles | tr ' ' '\1'); do :; done   # names may contain spaces; use file list below
    local args=() name
    while IFS= read -r name; do
      [ "$name" = "$cur" ] && args+=("$name" "ACTIVE") || args+=("$name" "")
    done <<EOF2
$(list_profiles)
EOF2
    args+=("+ New profile" "" "- Remove a profile" "" "Exit" "")
    local pick
    pick=$(dialog --title "Profiler — active: $cur" --menu "Pick a profile to switch to:" 20 50 12 "${args[@]}" 3>&1 1>&2 2>&3) || return 0
    case "$pick" in
      "Exit") return 0 ;;
      "+ New profile")
        local nn; nn=$(dialog --inputbox "New profile name:" 8 40 3>&1 1>&2 2>&3) || continue
        do_create "$nn"; sleep 1 ;;
      "- Remove a profile")
        local rn; rn=$(dialog --inputbox "Profile name to archive:" 8 40 3>&1 1>&2 2>&3) || continue
        do_remove "$rn"; sleep 1 ;;
      "$cur") ;;
      *)
        if dialog --yesno "Switch to '$pick'?\n\nSaves, save states, RetroAchievements login and wallpapers will swap over. A reboot keeps everything clean." 10 50 3>&1 1>&2 2>&3; then
          clear; do_switch "$pick"
          if dialog --yesno "Reboot now? (recommended)" 7 40 3>&1 1>&2 2>&3; then sync; reboot; fi
          return 0
        fi ;;
    esac
  done
}

ensure_init
case "${1:-}" in
  switch)  shift; do_switch "$*";;
  create)  shift; do_create "$*";;
  remove)  shift; do_remove "$*";;
  watch)   echo "Profiler no longer needs a background watcher. Use Scripts > Profiler - $(active) > Switch to [name].";;
  status)  echo "Active profile: $(active)"; echo "Profiles:"; list_profiles | sed 's/^/  /';;
  "")      menu;;
  *)       echo "usage: Profiler.sh [switch|create|remove|status|watch] <name>"; exit 1;;
esac
