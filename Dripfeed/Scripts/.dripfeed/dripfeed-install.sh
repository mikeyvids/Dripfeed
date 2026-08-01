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
