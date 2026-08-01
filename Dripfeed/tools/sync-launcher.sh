#!/bin/bash
# Rebuild the self-installing launcher's embedded helper bodies from Scripts/.
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCH="$HERE/Scripts/Dripfeed.sh"

replace_section(){
  local needle="$1" marker="$2" body="$3" tmp="$LAUNCH.tmp.$$"
  awk -v needle="$needle" -v marker="$marker" -v body="$body" '
    index($0, needle) { print; while ((getline line < body) > 0) print line; close(body); skip=1; next }
    skip && $0 == marker { print; skip=0; next }
    !skip { print }
  ' "$LAUNCH" > "$tmp"
  mv "$tmp" "$LAUNCH"
}

replace_section 'dripfeed-common.sh" <<' '__DF_COMMON__' "$HERE/Scripts/.dripfeed/dripfeed-common.sh"
replace_section 'dripfeed-engine.sh" <<' '__DF_ENGINE__' "$HERE/Scripts/.dripfeed/dripfeed-engine.sh"
replace_section 'dripfeed-install.sh" <<' '__DF_INSTALL__' "$HERE/Scripts/.dripfeed/dripfeed-install.sh"
replace_section 'dripfeed-schedule.sh" <<' '__DF_SCHEDULE__' "$HERE/Scripts/.dripfeed/dripfeed-schedule.sh"
replace_section 'Undrip.sh" <<' '__DF_UNDRIP__' "$HERE/Scripts/Undrip.sh"
chmod 755 "$LAUNCH"
echo "Synced embedded helpers into $LAUNCH"
