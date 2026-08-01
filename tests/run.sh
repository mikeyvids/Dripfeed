#!/bin/bash
# Full disposable-card suite. No real card, ROM, save, or credential is touched.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NODE="${NODE:-node}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok  - $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL- $1"; }
chk(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

echo "== component suites =="
bash "$HERE/Dripfeed/tests/run.sh" && ok "Dripfeed card simulation" || no "Dripfeed card simulation"
"$NODE" "$HERE/Dripfeed/tests/csv-contract.test.js" && ok "CSV/GOT'eM contract" || no "CSV/GOT'eM contract"
bash "$HERE/Wifi-Swap/tests/run.sh" && ok "Wifi-Swap card simulation" || no "Wifi-Swap card simulation"
"$NODE" "$HERE/tests/html-contract.test.js" && ok "offline HTML contracts" || no "offline HTML contracts"
find "$HERE" -type f -name '*.sh' -not -path '*/.git/*' -print0 | xargs -0 -n1 bash -n && ok "all shell syntax" || no "all shell syntax"

echo "== Profiler disposable card =="
PFROOT="$(mktemp -d)"; mkdir -p "$PFROOT/Scripts" "$PFROOT/linux" "$PFROOT/saves"
cp "$HERE/Profiler/Profiler.sh" "$PFROOT/Scripts/Profiler.sh"
echo original > "$PFROOT/saves/original.sav"
PROFILER_ROOT="$PFROOT" PROFILER_LAUNCH_ROOT=/media/fat bash "$PFROOT/Scripts/Profiler.sh" status >/dev/null
for p in "Player One" "Player Two" "Player Three"; do PROFILER_ROOT="$PFROOT" PROFILER_LAUNCH_ROOT=/media/fat bash "$PFROOT/Scripts/Profiler.sh" create "$p" >/dev/null; done
chk "three profiles created" '[ -d "$PFROOT/profiles/Player One" ] && [ -d "$PFROOT/profiles/Player Two" ] && [ -d "$PFROOT/profiles/Player Three" ]'
chk "Scripts submenu gets real executable profile switches" '[ -x "$PFROOT/Scripts/Profiler - Default/Switch to Player One.sh" ] && grep -q "Profiler.sh.*switch.*Player One" "$PFROOT/Scripts/Profiler - Default/Switch to Player One.sh"'
chk "mounted-card refresh keeps MiSTer runtime path in switch wrappers" '[ "$(sed -n "2p" "$PFROOT/Scripts/Profiler - Default/Switch to Player One.sh")" = '\''exec "/media/fat/Scripts/Profiler.sh" switch "Player One"'\'' ]'
PROFILER_ROOT="$PFROOT" bash "$PFROOT/Scripts/Profiler.sh" switch "Player One" >/dev/null
chk "switch stashes previous live saves" '[ -f "$PFROOT/profiles/Default/saves/original.sav" ] && [ "$(cat "$PFROOT/profiles/.active")" = "Player One" ]'
echo one > "$PFROOT/saves/one.sav"
PROFILER_ROOT="$PFROOT" bash "$PFROOT/Scripts/Profiler.sh" switch "Player Two" >/dev/null
PROFILER_ROOT="$PFROOT" bash "$PFROOT/Scripts/Profiler.sh" switch Default >/dev/null
chk "round-trip restores the original profile" '[ -f "$PFROOT/saves/original.sav" ] && [ -f "$PFROOT/profiles/Player One/saves/one.sav" ]'
PROFILER_ROOT="$PFROOT" bash "$PFROOT/Scripts/Profiler.sh" remove "Player Three" >/dev/null
chk "remove archives instead of deleting" 'find "$PFROOT/profiles/.archive" -maxdepth 1 -type d -name "*-Player Three" | grep -q .'
chk "Scripts submenu refreshes immediately after archive" '[ ! -f "$PFROOT/Scripts/Profiler - Default/Switch to Player Three.sh" ]'
if PROFILER_ROOT="$PFROOT" bash "$PFROOT/Scripts/Profiler.sh" create '../bad' >/dev/null 2>&1; then no "invalid profile names rejected"; else ok "invalid profile names rejected"; fi

echo "== Backup disposable card =="
BKROOT="$(mktemp -d)"; BKOUT="$(mktemp -d)"
mkdir -p "$BKROOT/Scripts" "$BKROOT/Scripts/.dripfeed" "$BKROOT/saves" "$BKROOT/savestates" "$BKROOT/wallpapers" "$BKROOT/config" "$BKROOT/profiles/Player_One/saves" "$BKROOT/profiles/Player_One/savestates" "$BKROOT/profiles/Player_One/wallpapers" "$BKROOT/profiles/Player_Two/saves" "$BKROOT/games/NES"
cp -R "$HERE/Backup/Scripts/.backthefup" "$BKROOT/Scripts/.backthefup"
cp "$HERE/Backup/Scripts/backtheFup.sh" "$BKROOT/Scripts/backtheFup.sh"
echo save > "$BKROOT/saves/live.sav"; echo savestate > "$BKROOT/savestates/live.ss"; echo config > "$BKROOT/config/core.cfg"
mkdir -p "$BKROOT/config/library/cache" "$BKROOT/config/library/thumbnails"
dd if=/dev/zero of="$BKROOT/config/library/catalog.sqlite" bs=1024 count=4096 2>/dev/null
dd if=/dev/zero of="$BKROOT/config/library/cache/rebuild.bin" bs=1024 count=4096 2>/dev/null
dd if=/dev/zero of="$BKROOT/config/library/thumbnails/rebuild.png" bs=1024 count=4096 2>/dev/null
echo wallpaper > "$BKROOT/wallpapers/active.png"; echo menu > "$BKROOT/menu.png"
echo ra > "$BKROOT/retroachievements.cfg"; echo ini > "$BKROOT/MiSTer.ini"
echo state > "$BKROOT/profiles/Player_One/saves/profile.sav"; echo slot > "$BKROOT/profiles/Player_One/savestates/profile.ss"; echo art > "$BKROOT/profiles/Player_One/wallpapers/profile.png"; echo profile-ra > "$BKROOT/profiles/Player_One/retroachievements.cfg"
echo second > "$BKROOT/profiles/Player_Two/saves/second.sav"; echo second-ra > "$BKROOT/profiles/Player_Two/retroachievements.cfg"; echo 'Player One' > "$BKROOT/profiles/.active"
echo dripfeed > "$BKROOT/Scripts/.dripfeed/revealed.tsv"; echo rom > "$BKROOT/games/NES/example.nes"
BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" all >/dev/null
LIVE="$(find "$BKOUT" -maxdepth 1 -name 'MiSTer_Live_*.zip' | head -1)"
PROF="$(find "$BKOUT" -maxdepth 1 -name '*_Player_One_Profiler.zip' | head -1)"
chk "separate verified ZIP archives created" '[ -f "$LIVE" ] && [ -f "$PROF" ] && unzip -tq "$LIVE" >/dev/null && unzip -tq "$PROF" >/dev/null'
chk "live archive contains its six fixed roots, including Dripfeed state" 'unzip -Z1 "$LIVE" | grep -q "saves/live.sav" && unzip -Z1 "$LIVE" | grep -q "savestates/live.ss" && unzip -Z1 "$LIVE" | grep -q "retroachievements.cfg" && unzip -Z1 "$LIVE" | grep -q "config/core.cfg" && unzip -Z1 "$LIVE" | grep -q "MiSTer.ini" && unzip -Z1 "$LIVE" | grep -q "Scripts/.dripfeed/revealed.tsv"'
chk "large rebuildable config databases, caches, and thumbnails stay out" '! unzip -Z1 "$LIVE" | grep -Eq "config/library/(catalog\\.sqlite|cache/|thumbnails/)"'
chk "ROMs and profiles stay out of live" '! unzip -Z1 "$LIVE" | grep -Eq "(^|/)(games|profiles)(/|$)"'
chk "profile archive contains every stored profile and its owned files" 'unzip -Z1 "$PROF" | grep -q "profiles/Player_One/saves/profile.sav" && unzip -Z1 "$PROF" | grep -q "profiles/Player_One/savestates/profile.ss" && unzip -Z1 "$PROF" | grep -q "profiles/Player_One/wallpapers/profile.png" && unzip -Z1 "$PROF" | grep -q "profiles/Player_One/retroachievements.cfg" && unzip -Z1 "$PROF" | grep -q "profiles/Player_Two/saves/second.sav"'
chk "profile archive also carries the active profile's complete live-owned set" 'unzip -Z1 "$PROF" | grep -q "^saves/live.sav" && unzip -Z1 "$PROF" | grep -q "^savestates/live.ss" && unzip -Z1 "$PROF" | grep -q "^wallpapers/active.png" && unzip -Z1 "$PROF" | grep -q "^retroachievements.cfg" && unzip -Z1 "$PROF" | grep -q "^menu.png"'
chk "checksum and manifest accompany each ZIP" '[ -s "$LIVE.sha256" ] && [ -s "$LIVE.manifest.txt" ] && [ -s "$PROF.sha256" ] && [ -s "$PROF.manifest.txt" ]'

echo changed-live > "$BKROOT/saves/live.sav"
echo changed-profile > "$BKROOT/profiles/Player_Two/saves/second.sav"
BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$PROF" profiles all >/dev/null
chk "all-profile restore returns both active and stored player data" '[ "$(cat "$BKROOT/saves/live.sav")" = save ] && [ "$(cat "$BKROOT/profiles/Player_Two/saves/second.sav")" = second ] && [ "$(cat "$BKROOT/profiles/.active")" = "Player One" ]'

echo changed-profile > "$BKROOT/profiles/Player_Two/saves/second.sav"
echo keep-this-ra-change > "$BKROOT/profiles/Player_Two/retroachievements.cfg"
BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$PROF" 'profile:Player_Two' saves >/dev/null
chk "one-profile one-aspect restore leaves its other aspects alone" '[ "$(cat "$BKROOT/profiles/Player_Two/saves/second.sav")" = second ] && [ "$(cat "$BKROOT/profiles/Player_Two/retroachievements.cfg")" = keep-this-ra-change ]'

echo changed-config > "$BKROOT/config/core.cfg"; echo changed-ini > "$BKROOT/MiSTer.ini"
BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$LIVE" live config >/dev/null
chk "one-aspect live restore does not overwrite unselected settings" '[ "$(cat "$BKROOT/config/core.cfg")" = config ] && [ "$(cat "$BKROOT/MiSTer.ini")" = changed-ini ]'

echo changed-dripfeed > "$BKROOT/Scripts/.dripfeed/revealed.tsv"
BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$LIVE" live dripfeed >/dev/null
chk "Dripfeed state can be selectively restored" '[ "$(cat "$BKROOT/Scripts/.dripfeed/revealed.tsv")" = dripfeed ]'

echo changed-state-again > "$BKROOT/savestates/live.ss"
BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$LIVE" live savestates >/dev/null
chk "restore creates a verified Before Restore safety archive" '[ "$(cat "$BKROOT/savestates/live.ss")" = savestate ] && find "$BKOUT" -maxdepth 1 -name "MiSTer_Live_*_Before_Restore.zip" | grep -q .'

echo must-survive-rollback > "$BKROOT/profiles/Player_Two/saves/second.sav"
if BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_TEST_FAIL_AFTER=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$PROF" profiles all >/dev/null 2>&1; then
  no "interrupted restore reports failure"
else
  ok "interrupted restore reports failure"
fi
chk "interrupted restore rolls the replaced data back" '[ "$(cat "$BKROOT/profiles/Player_Two/saves/second.sav")" = must-survive-rollback ]'

BAD="$BKOUT/tampered.zip"; cp "$PROF" "$BAD"; cp "$PROF.sha256" "$BAD.sha256"; printf x >> "$BAD"
if BACKTHEFUP_ASSUME_YES=1 BACKTHEFUP_SKIP_RESTORE_SAFETY=1 BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$BKOUT" \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" restore "$BAD" profiles all >/dev/null 2>&1; then
  no "tampered restore archive is rejected before changes"
else
  ok "tampered restore archive is rejected before changes"
fi
TAROUT="$(mktemp -d)"
BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$TAROUT" BACKTHEFUP_FORCE_TAR=1 bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" profiler "Player Tar" >/dev/null
TARFILE="$(find "$TAROUT" -maxdepth 1 -name '*_Player_Tar_Profiler.tar.gz' | head -1)"
chk "tar fallback is genuinely verified and finalized" '[ -f "$TARFILE" ] && tar -tzf "$TARFILE" | grep -q "profiles/Player_One/saves/profile.sav" && [ -s "$TARFILE.sha256" ]'
for label in Retain_One Retain_Two Retain_Three; do
  BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$TAROUT" BACKTHEFUP_FORCE_TAR=1 BACKTHEFUP_KEEP_PROFILER=2 \
    bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" profiler "$label" >/dev/null
done
chk "tar fallback obeys rolling retention with matching sidecars" '[ "$(find "$TAROUT" -maxdepth 1 -name "*_Profiler.tar.gz" | wc -l | tr -d "[:space:]")" -eq 2 ] && [ "$(find "$TAROUT" -maxdepth 1 -name "*_Profiler.tar.gz.sha256" | wc -l | tr -d "[:space:]")" -eq 2 ] && [ "$(find "$TAROUT" -maxdepth 1 -name "*_Profiler.tar.gz.manifest.txt" | wc -l | tr -d "[:space:]")" -eq 2 ]'

CLOUDOUT="$(mktemp -d)"; mkdir -p "$BKROOT/Scripts/.backthefup/bin"
RLOG="$CLOUDOUT/rclone.log"
cat > "$BKROOT/Scripts/.backthefup/bin/rclone" <<'EOF_RCLONE'
#!/bin/sh
case "$1" in
  listremotes) echo 'gdrive:';;
  lsd) printf '%s\n' "$*" >> "$FAKE_RCLONE_LOG";;
  copy) printf '%s\n' "$*" >> "$FAKE_RCLONE_LOG";;
esac
EOF_RCLONE
chmod 755 "$BKROOT/Scripts/.backthefup/bin/rclone"
printf '[gdrive]\ntype = drive\ntoken = test-fixture-only\n' > "$BKROOT/Scripts/.backthefup/rclone.conf"
FAKE_RCLONE_LOG="$RLOG" BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$CLOUDOUT" BACKTHEFUP_RCLONE_REMOTE='gdrive:MiSTerBackups' bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" live >/dev/null
chk "cloud handoff includes archive, checksum, and manifest" '[ "$(wc -l < "$RLOG" | tr -d "[:space:]")" -eq 3 ]'
FAKE_RCLONE_LOG="$RLOG" BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$CLOUDOUT" BACKTHEFUP_RCLONE_REMOTE='gdrive:NotCreatedYet' bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" --check-cloud >/dev/null
chk "cloud check tests the remote root before destination exists" 'tail -1 "$RLOG" | grep -q "^lsd gdrive: --max-depth 1$"'

NOCLOUDOUT="$(mktemp -d)"
rm -f "$BKROOT/Scripts/.backthefup/bin/rclone" "$BKROOT/Scripts/.backthefup/rclone.conf"
if BACKTHEFUP_ROOT="$BKROOT" BACKTHEFUP_DIR_OVERRIDE="$NOCLOUDOUT" BACKTHEFUP_RCLONE_REMOTE='gdrive:MiSTerBackups' \
  bash "$BKROOT/Scripts/.backthefup/backtheFup-engine.sh" live >"$NOCLOUDOUT/output.txt" 2>&1; then
  no "configured-but-unready cloud reports a partial failure"
else
  RC=$?
  if [ "$RC" -eq 4 ]; then ok "configured-but-unready cloud reports a partial failure"; else no "configured-but-unready cloud reports a partial failure"; fi
fi
chk "cloud setup failure keeps a verified local archive and says so plainly" 'find "$NOCLOUDOUT" -maxdepth 1 -name "MiSTer_Live_*.zip" | grep -q . && grep -q "LOCAL BACKUP SAVED; CLOUD COPY FAILED" "$NOCLOUDOUT/output.txt"'

LEGROOT="$(mktemp -d)"; LEGOUT="$(mktemp -d)"; mkdir -p "$LEGROOT/Scripts/.backup" "$LEGROOT/Scripts" "$LEGROOT/games/NES" "$LEGROOT/saves"
cp -R "$HERE/Backup/Scripts/.backthefup" "$LEGROOT/Scripts/.backthefup"
printf 'RCLONE_REMOTE=gdrive:OldFolder\nLIVE_INCLUDE=saves games\n' > "$LEGROOT/Scripts/.backup/backup.conf"
echo safe > "$LEGROOT/saves/safe.sav"; echo excluded > "$LEGROOT/games/NES/example.nes"
LEGDRY="$(BACKTHEFUP_ROOT="$LEGROOT" BACKTHEFUP_DIR_OVERRIDE="$LEGOUT" bash "$LEGROOT/Scripts/.backthefup/backtheFup-engine.sh" --dry-run live)"
chk "legacy destination migrates but unsafe include lists do not" 'grep -q "RCLONE_REMOTE=gdrive:OldFolder" "$LEGROOT/Scripts/.backthefup/backtheFup.conf" && printf "%s" "$LEGDRY" | grep -q "saves" && ! printf "%s" "$LEGDRY" | grep -q "games"'

echo "== public-boundary scan =="
BANNED_NAME="zapa""roo"
if grep -RniI --exclude-dir=.git "$BANNED_NAME" "$HERE" >/dev/null; then
  no "unapproved integration references are absent"
else
  ok "unapproved integration references are absent"
fi
if grep -RniE --exclude=LICENSE --exclude=run.sh --exclude='*.md' --exclude-dir=.git \
  '/Users/|\.obsidian|retroachievements\.cfg.*password=.+|^RCLONE_REMOTE=[A-Za-z0-9._-]+:.+' "$HERE" >/dev/null; then
  no "no vault, host path, or credential leaked"
else
  ok "no vault, host path, or credential leaked"
fi

rm -rf "$PFROOT" "$BKROOT" "$BKOUT" "$TAROUT" "$CLOUDOUT" "$NOCLOUDOUT" "$LEGROOT" "$LEGOUT"
echo
echo "SUITE RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
