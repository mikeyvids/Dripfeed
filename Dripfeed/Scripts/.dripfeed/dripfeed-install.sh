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
SYSTEM_SHORTCUTS=0   # opt-in: also put each What's New shortcut in games/<SYSTEM>/<dir below>
                     # and a console GOT'eM pick in games/<SYSTEM>/<GOT'eM folder name>,
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
