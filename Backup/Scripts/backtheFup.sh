#!/bin/bash
# Back the Files Up — visible MiSTer Scripts-menu entry.
# GPL-3.0-or-later; Copyright (C) 2026 MikeyVids.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$SELF_DIR/.backthefup/backtheFup-engine.sh"
ENGINE_URL="https://raw.githubusercontent.com/mikeyvids/Dripfeed/main/Backup/Scripts/.backthefup/backtheFup-engine.sh"

if [ ! -f "$ENGINE" ]; then
  echo "First run: the hidden Back the Files Up engine is missing."
  echo "Creating Scripts/.backthefup and fetching the current engine..."
  mkdir -p "$SELF_DIR/.backthefup" || exit 1
  tmp="$ENGINE.download.$$"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --max-time 90 "$ENGINE_URL" -o "$tmp" 2>/dev/null || true
  elif command -v wget >/dev/null 2>&1; then
    wget -T 90 -O "$tmp" "$ENGINE_URL" 2>/dev/null || true
  fi
  if [ ! -s "$tmp" ] || ! grep -q "Back the Files Up engine" "$tmp" 2>/dev/null || ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo
    echo "I could not download the engine."
    echo "Connect MiSTer to the internet, confirm its clock is correct, then run this again."
    echo "Offline option: copy the suite's Backup/Scripts/.backthefup folder onto the card."
    exit 1
  fi
  mv "$tmp" "$ENGINE" || exit 1
  sync 2>/dev/null || true
  echo "Engine installed. Continuing..."
fi
chmod 755 "$ENGINE" 2>/dev/null || true

if [ "$#" -gt 0 ]; then exec "$ENGINE" "$@"; fi

# Friendly controller menu on MiSTer; headless/redirected runs keep one-command
# behavior and back up both live data and all Profiler profiles.
if command -v dialog >/dev/null 2>&1 && { [ -t 0 ] || [ -w /dev/tty ]; }; then
  choice=$(dialog --stdout --backtitle "Back the Files Up" --cancel-label "Exit" \
    --menu "What should I do?\n\nCloud upload uses the same saved household authorization every time." 20 76 9 \
    all "Back up everything now (recommended)" \
    restore "Restore from a local backup" \
    check "Check cloud connection only" \
    status "Show exactly what is protected" \
    live "Back up live MiSTer files only" \
    profiler "Back up every complete player profile") || exit 0
  clear 2>/dev/null || true
  case "$choice" in
    all) exec "$ENGINE" all;;
    restore) exec "$ENGINE" restore;;
    check) exec "$ENGINE" --check-cloud;;
    status) exec "$ENGINE" --status;;
    live) exec "$ENGINE" live;;
    profiler) exec "$ENGINE" profiler;;
  esac
fi

exec "$ENGINE" all
