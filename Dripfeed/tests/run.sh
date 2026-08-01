#!/bin/bash
# Dripfeed for MiSTer FPGA — GPL-3.0-or-later
# Copyright (C) 2026 MikeyVids
# See ../LICENSE for the full license and CREDITS.md for upstream acknowledgements.
# Dripfeed conformance + regression harness.
# Seeds a fake card under a temp DRIPFEED_ROOT, drives the CLI scheduler + engine,
# and asserts the staging spec (STAGING_SPEC.md) holds. Exit non-zero on any failure.
#
# Run:  bash tests/run.sh      (from the Dripfeed folder, or anywhere — it finds itself)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../Scripts/.dripfeed"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok  - $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL- $1"; }
chk(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }
sed_in_place(){
  local expr="$1" file="$2"
  sed -i '' "$expr" "$file" 2>/dev/null && return 0   # BSD/macOS
  sed -i "$expr" "$file"                              # GNU
}

ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/Scripts/.dripfeed" "$ROOT/games/GENESIS" "$ROOT/games/Saturn" "$ROOT/linux"
cp "$SRC"/*.sh "$ROOT/Scripts/.dripfeed/"
printf '#!/bin/sh\n' > "$ROOT/linux/_user-startup.sh"
export DRIPFEED_ROOT="$ROOT" DRIPFEED_INTERACTIVE=0
ENG="$ROOT/Scripts/.dripfeed/dripfeed-engine.sh"
SCH="$ROOT/Scripts/.dripfeed/dripfeed-install.sh"
SC="$ROOT/Scripts/.dripfeed/dripfeed-schedule.sh"

echo "== syntax =="
for f in "$SRC"/*.sh; do bash -n "$f" && ok "syntax $(basename "$f")" || no "syntax $(basename "$f")"; done

echo "== install =="
bash "$SCH" >/dev/null 2>&1
chk "config written to Scripts/.dripfeed (no _Dripfeed root folder)" '[ -f "$ROOT/Scripts/.dripfeed/config.ini" ] && [ ! -d "$ROOT/_Dripfeed" ]'
chk "active user-startup.sh created with hook" 'grep -q DRIPFEED_AUTORUN "$ROOT/linux/user-startup.sh"'

echo "== schedule (CLI) =="
echo a > "$ROOT/games/GENESIS/Shiny Forts.md"
echo b > "$ROOT/games/GENESIS/Shiny Forts 2.md"
mkdir -p "$ROOT/games/Saturn/Shiny Forts III"; echo d1.chd > "$ROOT/games/Saturn/Shiny Forts III/Shiny Forts 3.m3u"; echo d > "$ROOT/games/Saturn/Shiny Forts III/d1.chd"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Shiny Forts.md" >/dev/null
bash "$SC" add GENESIS +5    "$ROOT/games/GENESIS/Shiny Forts 2.md" >/dev/null
bash "$SC" add Saturn  today "$ROOT/games/Saturn/Shiny Forts III" >/dev/null
bash "$SC" message today "Happy Birthday Player One" >/dev/null
chk "staged entry has YYYY-MM-DD_ prefix outside games/" 'ls "$ROOT/.dripfeed-library/GENESIS/" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}_Shiny Forts.md$"'
chk "scheduled game hidden from system folder" '[ ! -e "$ROOT/games/GENESIS/Shiny Forts.md" ]'
chk "occasions.tsv in state dir, date<TAB>message" 'TAB="$(printf "\t")"; grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}${TAB}Happy Birthday Player One$" "$ROOT/Scripts/.dripfeed/occasions.tsv"'
echo duplicate-source > "$ROOT/games/GENESIS/Shiny Forts 2.md"
bash "$SC" add GENESIS +6 "$ROOT/games/GENESIS/Shiny Forts 2.md" >/dev/null
chk "CLI refuses a second queued copy of the same clean game name" '[ -f "$ROOT/games/GENESIS/Shiny Forts 2.md" ] && [ "$(find "$ROOT/.dripfeed-library/GENESIS" -maxdepth 1 -name "*_Shiny Forts 2.md" | wc -l | tr -d " ")" = 1 ]'
rm -f "$ROOT/games/GENESIS/Shiny Forts 2.md"

echo "== firmware/support guards =="
mkdir -p "$ROOT/games/MegaCD/USA" "$ROOT/games/MegaCD/Night Trap" "$ROOT/games/Jaguar"
echo bios > "$ROOT/games/MegaCD/USA/cd_bios.rom"
echo m3u > "$ROOT/games/MegaCD/Night Trap/Night Trap.m3u"
echo marquee > "$ROOT/games/Jaguar/Doom (World).mrq"
bash "$SC" add MegaCD today "$ROOT/games/MegaCD/USA" >/dev/null 2>&1
bash "$SC" add MegaCD today "$ROOT/games/MegaCD/Night Trap" >/dev/null 2>&1
bash "$SC" add Jaguar today "$ROOT/games/Jaguar/Doom (World).mrq" >/dev/null 2>&1
chk "MegaCD firmware region folder remains visible and unqueued" '[ -f "$ROOT/games/MegaCD/USA/cd_bios.rom" ] && [ ! -e "$ROOT/games/MegaCD/.dripfeed/$(date +%Y-%m-%d)_USA" ]'
chk "MegaCD multi-disc folder queues as one folder outside games/" '[ -e "$ROOT/.dripfeed-library/MegaCD/$(date +%Y-%m-%d)_Night Trap" ]'
chk "Jaguar .mrq marquee remains visible and unqueued" '[ -f "$ROOT/games/Jaguar/Doom (World).mrq" ] && [ ! -e "$ROOT/games/Jaguar/.dripfeed/$(date +%Y-%m-%d)_Doom (World).mrq" ]'
mkdir -p "$ROOT/games/MegaCD/.dripfeed/2000-01-01_Europe"; echo legacy > "$ROOT/games/MegaCD/.dripfeed/2000-01-01_Europe/cd_bios.rom"
echo finder > "$ROOT/games/MegaCD/.dripfeed/._2000-01-01_Europe"
echo not-yet > "$ROOT/games/GENESIS/Migrate Only Test.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Migrate Only Test.md" >/dev/null
# Put that due entry back in the old layout to prove migration alone never
# reveals it, even though its date has arrived.
mkdir -p "$ROOT/games/GENESIS/.dripfeed"
mv "$ROOT/.dripfeed-library/GENESIS/$(date +%Y-%m-%d)_Migrate Only Test.md" "$ROOT/games/GENESIS/.dripfeed/"
bash "$ENG" --migrate >/dev/null 2>&1
chk "upgrade moves the legacy queue outside games/" '[ -f "$ROOT/.dripfeed-library/MegaCD/2000-01-01_Europe/cd_bios.rom" ] && [ ! -d "$ROOT/games/MegaCD/.dripfeed" ]'
chk "migration-only mode does not reveal a due game" '[ -f "$ROOT/.dripfeed-library/GENESIS/$(date +%Y-%m-%d)_Migrate Only Test.md" ] && [ ! -e "$ROOT/games/GENESIS/Migrate Only Test.md" ]'
chk "legacy queued firmware stays hidden from automatic reveal" '[ -f "$ROOT/.dripfeed-library/MegaCD/2000-01-01_Europe/cd_bios.rom" ] && [ ! -e "$ROOT/games/MegaCD/Europe" ]'
bash "$SC" remove MegaCD 2000-01-01_Europe >/dev/null 2>&1
chk "legacy queued firmware can be explicitly restored" '[ -f "$ROOT/games/MegaCD/Europe/cd_bios.rom" ] && [ ! -e "$ROOT/.dripfeed-library/MegaCD/2000-01-01_Europe" ]'

echo "== reveal (silent) =="
bash "$ENG" --auto >/dev/null 2>&1
chk "due game revealed to its system folder (clean name)" '[ -f "$ROOT/games/GENESIS/Shiny Forts.md" ]'
chk "future game still staged outside games/ (held back)" 'ls "$ROOT/.dripfeed-library/GENESIS/" | grep -q "Shiny Forts 2.md"'
chk "multi-disc folder revealed intact (m3u present)" '[ -f "$ROOT/games/Saturn/Shiny Forts III/Shiny Forts 3.m3u" ]'

echo "== punctuation path safety =="
echo tj > "$ROOT/games/GENESIS/ToeJam & Earl, Panic on Funkotron.gen"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/ToeJam & Earl, Panic on Funkotron.gen" >/dev/null
bash "$ENG" --auto >/dev/null 2>&1
chk "comma and ampersand survive schedule + reveal exactly" '[ -f "$ROOT/games/GENESIS/ToeJam & Earl, Panic on Funkotron.gen" ]'

echo "== browser request ledger -> card-side atomic moves =="
mkdir -p "$ROOT/games/PSX/Request Disc Set"
printf 'Disc 1.chd\nDisc 2.chd\n' > "$ROOT/games/PSX/Request Disc Set/Request Disc Set.m3u"
echo one > "$ROOT/games/PSX/Request Disc Set/Disc 1.chd"
echo two > "$ROOT/games/PSX/Request Disc Set/Disc 2.chd"
printf '2099-12-31\tPSX\tRequest Disc Set\n' > "$ROOT/Scripts/.dripfeed/schedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
chk "web request moves a complete multi-disc folder atomically on card" '[ ! -e "$ROOT/games/PSX/Request Disc Set" ] && [ -f "$ROOT/.dripfeed-library/PSX/2099-12-31_Request Disc Set/Disc 1.chd" ] && [ -f "$ROOT/.dripfeed-library/PSX/2099-12-31_Request Disc Set/Disc 2.chd" ] && [ ! -s "$ROOT/Scripts/.dripfeed/schedule-requests.tsv" ]'
printf '%s\tPSX\tRequest Disc Set\n' "$(date +%Y-%m-%d)" > "$ROOT/Scripts/.dripfeed/schedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
chk "web re-date request renames the staged set then reveals it intact" '[ -f "$ROOT/games/PSX/Request Disc Set/Request Disc Set.m3u" ] && [ -f "$ROOT/games/PSX/Request Disc Set/Disc 2.chd" ]'
echo later > "$ROOT/games/GENESIS/Return Request Test.md"
printf '2099-12-31\tGENESIS\tReturn Request Test.md\n' > "$ROOT/Scripts/.dripfeed/schedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
printf 'GENESIS\tReturn Request Test.md\n' > "$ROOT/Scripts/.dripfeed/unschedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
chk "web unschedule request returns a queued item without browser copying" '[ -f "$ROOT/games/GENESIS/Return Request Test.md" ] && [ ! -s "$ROOT/Scripts/.dripfeed/unschedule-requests.tsv" ]'
mkdir -p "$ROOT/.dripfeed-library/PSX" "$ROOT/games/PSX/.dripfeed"
echo one > "$ROOT/.dripfeed-library/PSX/2099-12-30_Ambiguous Disc Set"
echo two > "$ROOT/games/PSX/.dripfeed/2099-12-31_Ambiguous Disc Set"
printf '2099-12-29\tPSX\tAmbiguous Disc Set\n' > "$ROOT/Scripts/.dripfeed/schedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
chk "web re-date request holds after legacy duplicate is migrated outside games/" '[ -s "$ROOT/Scripts/.dripfeed/schedule-requests.tsv" ] && [ -e "$ROOT/.dripfeed-library/PSX/2099-12-30_Ambiguous Disc Set" ] && [ -e "$ROOT/.dripfeed-library/PSX/2099-12-31_Ambiguous Disc Set" ] && [ ! -d "$ROOT/games/PSX/.dripfeed" ]'
printf 'PSX\tAmbiguous Disc Set\n' > "$ROOT/Scripts/.dripfeed/unschedule-requests.tsv"
bash "$ENG" --auto >/dev/null 2>&1
chk "web return request holds when old queue has duplicate game names" '[ -s "$ROOT/Scripts/.dripfeed/unschedule-requests.tsv" ] && [ ! -e "$ROOT/games/PSX/Ambiguous Disc Set" ]'
rm -f "$ROOT/.dripfeed-library/PSX/2099-12-30_Ambiguous Disc Set" "$ROOT/.dripfeed-library/PSX/2099-12-31_Ambiguous Disc Set" "$ROOT/Scripts/.dripfeed/schedule-requests.tsv" "$ROOT/Scripts/.dripfeed/unschedule-requests.tsv"

echo "== incomplete multi-disc recovery hold =="
mkdir -p "$ROOT/games/PSX" "$ROOT/.dripfeed-library/PSX/2000-01-01_Partial Disc Set"
echo marker > "$ROOT/.dripfeed-library/PSX/2000-01-01_Partial Disc Set/.dripfeed-incomplete"
echo disc1 > "$ROOT/.dripfeed-library/PSX/2000-01-01_Partial Disc Set/Disc 1.chd"
bash "$ENG" --auto >/dev/null 2>&1
chk "marked incomplete folder is never revealed as a game" '[ ! -e "$ROOT/games/PSX/Partial Disc Set" ] && [ -e "$ROOT/.dripfeed-library/PSX/2000-01-01_Partial Disc Set/.dripfeed-incomplete" ]'

echo "== interrupted reveal recovery =="
echo p > "$ROOT/games/GENESIS/Power Cut Test.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Power Cut Test.md" >/dev/null
DRIPFEED_TEST_INTERRUPT_AFTER_MOVE=1 bash "$ENG" --auto >/dev/null 2>&1
chk "interrupted move leaves game intact at destination" '[ -f "$ROOT/games/GENESIS/Power Cut Test.md" ]'
chk "interrupted move leaves a durable recovery journal" '[ -f "$ROOT/Scripts/.dripfeed/transactions/current.tsv" ]'
chk "ledger is not falsely recorded before recovery" '! grep -q "Power Cut Test.md" "$ROOT/Scripts/.dripfeed/revealed.tsv" 2>/dev/null'
bash "$ENG" --auto >/dev/null 2>&1
chk "next pass repairs interrupted reveal ledger" 'grep -q "Power Cut Test.md" "$ROOT/Scripts/.dripfeed/revealed.tsv"'
chk "next pass clears recovery journal" '[ ! -f "$ROOT/Scripts/.dripfeed/transactions/current.tsv" ]'
chk "recovered reveal is restored to What's New" 'find "$ROOT" -maxdepth 2 -type f -name "GENESIS - Power Cut Test.mgl" | grep -q .'

echo "== showcase (single dated/message folder) =="
SHOW="$(ls -d "$ROOT"/_Dripfeed\ -\ * 2>/dev/null | head -1)"
chk "exactly ONE showcase folder" '[ -n "$SHOW" ] && [ "$(ls -d "$ROOT"/_Dripfeed* "$ROOT"/_@Dripfeed* 2>/dev/null | wc -l)" -eq 1 ]'
chk "folder name carries the custom message" 'echo "$SHOW" | grep -q "Happy Birthday"'
chk "folder name capped to OSD width (<=30 after leading _)" '[ "$(printf %s "$(basename "$SHOW")" | wc -c)" -le 31 ]'
chk ".mgl shortcut names show the system" 'ls "$SHOW" | grep -q "^GENESIS - Shiny Forts.mgl$"'
chk ".mgl points at the current default core (MegaDrive)" 'grep -q "<rbf>_Console/MegaDrive</rbf>" "$SHOW/GENESIS - Shiny Forts.mgl"'
chk "gamelist.xml written (no leftover .tmp)" '[ -f "$SHOW/gamelist.xml" ] && [ ! -e "$SHOW/gamelist.xml.tmp" ]'
chk "gamelist desc carries the FULL message" 'grep -q "Happy Birthday Player One" "$SHOW/gamelist.xml"'

echo "== foolproof: consolidate stray showcase folders =="
mkdir -p "$ROOT/_Dripfeed - Old Stray"; : > "$ROOT/_Dripfeed - Old Stray/SNES - Foo.mgl"
mkdir -p "$ROOT/_Dripfeed"   # old empty state-era folder
echo z > "$ROOT/games/GENESIS/Shiny Forts Seedy.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Shiny Forts Seedy.md" >/dev/null
bash "$ENG" --auto >/dev/null 2>&1
chk "strays merged into the one folder; empty _Dripfeed removed" '[ "$(ls -d "$ROOT"/_Dripfeed* "$ROOT"/_@Dripfeed* 2>/dev/null | wc -l)" -eq 1 ] && [ -f "$SHOW/SNES - Foo.mgl" ]'

echo "== core resolver (renamed/deprecated cores) =="
mkdir -p "$ROOT/_Console"
chk "no core installed -> falls back to default MegaDrive" 'bash -c ". \"$SRC/dripfeed-common.sh\"; DRIPFEED_ROOT=\"$ROOT\"; [ \"\$(df_resolve_rbf _Console/MegaDrive)\" = _Console/MegaDrive ]"'
: > "$ROOT/_Console/Genesis_20260101.rbf"
chk "only deprecated Genesis core present -> resolver switches to it" 'bash -c ". \"$SRC/dripfeed-common.sh\"; DRIPFEED_ROOT=\"$ROOT\"; [ \"\$(df_resolve_rbf _Console/MegaDrive)\" = _Console/Genesis ]"'
: > "$ROOT/_Console/MegaDrive_20260615.rbf"
chk "MegaDrive core present -> resolver prefers it" 'bash -c ". \"$SRC/dripfeed-common.sh\"; DRIPFEED_ROOT=\"$ROOT\"; [ \"\$(df_resolve_rbf _Console/MegaDrive)\" = _Console/MegaDrive ]"'
rm -rf "$ROOT/_Console"

echo "== no-overwrite safety =="
echo existing > "$ROOT/games/GENESIS/Shiny Forts 2.md"   # collision with the future game's clean name
# fast-forward: schedule a past-dated dup and confirm reveal SKIPS rather than clobbers
bash "$SC" add GENESIS 2000-01-01 "$ROOT/games/GENESIS/Shiny Forts 2.md" >/dev/null 2>&1
echo keep > "$ROOT/games/GENESIS/Shiny Forts 2.md"
bash "$ENG" --auto >/dev/null 2>&1
chk "existing visible game not overwritten by reveal" '[ "$(cat "$ROOT/games/GENESIS/Shiny Forts 2.md")" = keep ]'

echo "== config tolerance (stray spaces / quotes) =="
printf 'SHOWCASE_KEEP = 3\nSHOWCASE_PREFIX="_Dripfeed - "\n' >> "$ROOT/Scripts/.dripfeed/config.ini"
chk "tolerant parser reads 'KEY = value' and quoted spaces" 'bash -c ". \"$SRC/dripfeed-common.sh\"; DRIPFEED_ROOT=\"$ROOT\" df_load_config; [ \"\$SHOWCASE_KEEP\" = 3 ] && [ \"\$SHOWCASE_PREFIX\" = \"_Dripfeed - \" ]"'

echo "== idempotent install =="
bash "$SCH" >/dev/null 2>&1
chk "boot hook present exactly once" '[ "$(grep -c "=====DRIPFEED_AUTORUN=====" "$ROOT/linux/user-startup.sh")" = 1 ]'

echo "== self-heal: strays consolidate even with NO games due =="
mkdir -p "$ROOT/games/SNES" "$ROOT/_Dripfeed - Leftover 2.4"; : > "$ROOT/_Dripfeed - Leftover 2.4/SNES - Bar.mgl"
echo bar > "$ROOT/games/SNES/Bar.sfc"   # so the merged shortcut isn't pruned as orphan
sed_in_place 's|path="[^"]*Bar[^"]*"|path="'"$ROOT"'/games/SNES/Bar.sfc"|' "$ROOT/_Dripfeed - Leftover 2.4/SNES - Bar.mgl" 2>/dev/null || printf '<mistergamedescription><rbf>_Console/SNES</rbf><file path="%s"/></mistergamedescription>' "$ROOT/games/SNES/Bar.sfc" > "$ROOT/_Dripfeed - Leftover 2.4/SNES - Bar.mgl"
bash "$ENG" --auto >/dev/null 2>&1   # queue is empty -> no games due, but tidy must still run
chk "leftover folder merged into the one canonical folder (no due games needed)" '[ ! -d "$ROOT/_Dripfeed - Leftover 2.4" ] && [ -f "$SHOW/SNES - Bar.mgl" ] && [ "$(ls -d "$ROOT"/_Dripfeed* 2>/dev/null | wc -l)" -eq 1 ]'

echo "== sticky showcase name (renames ONLY when a game unlocks) =="
CUR="$(cat "$ROOT/Scripts/.dripfeed/showcase_name")"
OLD="_Dripfeed - New Mon Jan 5, 26"
mv "$ROOT/$CUR" "$ROOT/$OLD"
printf '%s' "$OLD" > "$ROOT/Scripts/.dripfeed/showcase_name"
bash "$ENG" --auto >/dev/null 2>&1     # queue is empty -> a plain boot
chk "plain boot keeps the saved folder name (no daily rename)" '[ -d "$ROOT/$OLD" ] && [ "$(ls -d "$ROOT"/_Dripfeed* 2>/dev/null | wc -l)" -eq 1 ] && [ "$(cat "$ROOT/Scripts/.dripfeed/showcase_name")" = "$OLD" ]'
echo s > "$ROOT/games/GENESIS/Sticky Forts.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Sticky Forts.md" >/dev/null
bash "$ENG" --auto >/dev/null 2>&1     # a REAL unlock -> re-stamp + rename
NEWNAME="$(cat "$ROOT/Scripts/.dripfeed/showcase_name")"
chk "real unlock re-stamps the folder name (old folder replaced)" '[ "$NEWNAME" != "$OLD" ] && [ -d "$ROOT/$NEWNAME" ] && [ ! -d "$ROOT/$OLD" ] && [ "$(ls -d "$ROOT"/_Dripfeed* 2>/dev/null | wc -l)" -eq 1 ]'
chk "unlocked game's shortcut landed in the renamed folder" 'ls "$ROOT/$NEWNAME" | grep -q "Sticky Forts.mgl"'

echo "== default label + countdown UI channel =="
LBL="$(bash -c ". \"$SRC/dripfeed-common.sh\"; df_showcase_default_label")"
DOM="$(date +%d)"; DOM="${DOM#0}"
chk "default label = 'New Www Mmm D, YY' with non-padded day" '[ "$LBL" = "New $(date +%a) $(date +%b) $DOM, $(date +%y)" ]'
CERR="$(bash -c ". \"$SRC/dripfeed-common.sh\"; df_menu_countdown 1 PROMPTTEST >/dev/null" </dev/null 2>&1)"
COUT="$(bash -c ". \"$SRC/dripfeed-common.sh\"; df_menu_countdown 1 PROMPTTEST 2>/dev/null" </dev/null)"
chk "countdown prompt drawn on stderr (visible on screen, never captured)" 'echo "$CERR" | grep -q PROMPTTEST && [ -z "$(echo "$COUT" | tr -d "[:space:]")" ]'

echo "== folder-name customization (sanitizer + fixed-name toggle) =="
chk "sanitizer strips emojis/illegal chars + adds leading _" 'bash -c ". \"$SRC/dripfeed-common.sh\"; [ \"\$(df_showcase_sanitize \"Drip🔥feed<>:*|name\")\" = \"_Dripfeedname\" ]"'
CFG="$ROOT/Scripts/.dripfeed/config.ini"
printf 'SHOWCASE_DATE=0\n' >> "$CFG"
bash "$SC" message today >/dev/null            # clear today's banner so the fixed name applies
echo f1 > "$ROOT/games/GENESIS/Fixed Name Test.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Fixed Name Test.md" >/dev/null
bash "$ENG" --auto >/dev/null 2>&1     # unlock with SHOWCASE_DATE=0 and no message today
chk "SHOWCASE_DATE=0: unlock renames to the FIXED name (no date)" '[ "$(cat "$ROOT/Scripts/.dripfeed/showcase_name")" = "_Dripfeed" ] && [ -d "$ROOT/_Dripfeed" ]'
echo f2 > "$ROOT/games/GENESIS/Fixed Name Test 2.md"
bash "$SC" add GENESIS today "$ROOT/games/GENESIS/Fixed Name Test 2.md" >/dev/null
bash "$ENG" --auto >/dev/null 2>&1
chk "SHOWCASE_DATE=0: further unlocks keep the same fixed name" '[ "$(cat "$ROOT/Scripts/.dripfeed/showcase_name")" = "_Dripfeed" ] && [ "$(ls -d "$ROOT"/_Dripfeed* 2>/dev/null | wc -l)" -eq 1 ]'
sed_in_place 's/^SHOWCASE_DATE=0$/SHOWCASE_DATE=1/' "$CFG" 2>/dev/null || true

echo "== game of the month =="
MONTH=$(date +%Y-%m)
echo g > "$ROOT/games/SNES/GOTM Game.sfc"
printf '%s\tgames/SNES/GOTM Game.sfc\n' "$MONTH" > "$ROOT/Scripts/.dripfeed/gotm.tsv"
bash "$ENG" --gotm >/dev/null 2>&1
chk "GOTM console pick -> folder with .mgl" '[ -f "$ROOT/_Game of the Month/SNES - GOTM Game.mgl" ]'
mkdir -p "$ROOT/_Arcade/cores"
printf '<misterromdescription><rbf>testcore</rbf></misterromdescription>\n' > "$ROOT/_Arcade/Test Game.mra"
: > "$ROOT/_Arcade/cores/testcore_20260101.rbf"
printf '%s\t_Arcade/Test Game.mra\n' "$MONTH" > "$ROOT/Scripts/.dripfeed/gotm.tsv"
bash "$ENG" --gotm >/dev/null 2>&1
chk "GOTM arcade pick -> .mra + core copied in" '[ -f "$ROOT/_Game of the Month/Test Game.mra" ] && ls "$ROOT/_Game of the Month/cores/"testcore*.rbf >/dev/null 2>&1'
chk "GOTM rebuild replaced previous pick" '[ ! -f "$ROOT/_Game of the Month/SNES - GOTM Game.mgl" ]'
printf '%s\tgames/SNES/Not Revealed Yet.sfc\n' "$MONTH" > "$ROOT/Scripts/.dripfeed/gotm.tsv"
bash "$ENG" --gotm >/dev/null 2>&1
chk "GOTM hidden/missing pick: keeps old folder, retries later" '[ -f "$ROOT/_Game of the Month/Test Game.mra" ]'
echo cg > "$ROOT/games/SNES/Community Pick.sfc"
printf '%s\tgames/SNES/Community Pick.sfc\tDiscord GOTM - Community Pick\n' "$MONTH" > "$ROOT/community-gotm.tsv"
echo ug > "$ROOT/games/SNES/User Pick.sfc"
printf '%s\tgames/SNES/User Pick.sfc\tUser GOTM - My Pick\n' "$MONTH" > "$ROOT/Scripts/.dripfeed/gotm.tsv"
rm -f "$ROOT/Scripts/.dripfeed/.gotm_built"
printf 'GOTM_SOURCE=%s\n' "$ROOT/community-gotm.tsv" >> "$ROOT/Scripts/.dripfeed/config.ini"
bash "$ENG" --gotm >/dev/null 2>&1
chk "GOTM: user + community picks build PARALLEL folders" '[ -d "$ROOT/_Game of the Month" ] && [ -d "$ROOT/_Discord GOTM" ]'
chk "GOTM: custom labels name the shortcuts" '[ -f "$ROOT/_Game of the Month/User GOTM - My Pick.mgl" ] && [ -f "$ROOT/_Discord GOTM/Discord GOTM - Community Pick.mgl" ]'
sed_in_place '/^GOTM_SOURCE=/d' "$ROOT/Scripts/.dripfeed/config.ini"
rm -f "$ROOT/Scripts/.dripfeed/gotm.tsv"

echo "== damaged launcher can never brick a working install =="
LAUNCH="$HERE/../Scripts/Dripfeed.sh"
# Corrupt ONE embedded helper (heredoc bodies are literal, so the launcher itself
# still parses) and force an update by faking an old installed version.
sed 's/--watch)            df_watch ;;/--watch)            df_watch ;; ((((/' "$LAUNCH" > "$ROOT/Dripfeed-damaged.sh"
cp "$ROOT/Scripts/.dripfeed/dripfeed-engine.sh" "$ROOT/engine.bak"
echo "0.0.0" > "$ROOT/Scripts/.dripfeed/.version"
DRIPFEED_ROOT="$ROOT" bash "$ROOT/Dripfeed-damaged.sh" </dev/null >/dev/null 2>&1
RC=$?
chk "damaged launcher exits non-zero (refuses to install)" '[ "$RC" -ne 0 ]'
chk "live helpers left untouched" 'cmp -s "$ROOT/Scripts/.dripfeed/dripfeed-engine.sh" "$ROOT/engine.bak"'
chk "version NOT stamped (next good launcher will retry)" '[ "$(cat "$ROOT/Scripts/.dripfeed/.version")" = "0.0.0" ]'
chk "no staging leftovers (.new cleaned up)" '[ ! -d "$ROOT/Scripts/.dripfeed/.new" ]'
rm -f "$ROOT/Dripfeed-damaged.sh" "$ROOT/engine.bak"
printf '%s\n' "$(grep -m1 '^DRIPFEED_VERSION=' "$LAUNCH" | cut -d'"' -f2)" > "$ROOT/Scripts/.dripfeed/.version"

echo "== undrip (full reset) =="
: > "$ROOT/Scripts/Dripfeed.sh"; : > "$ROOT/Scripts/Undrip.sh"
mkdir -p "$ROOT/games/SNES"; echo r > "$ROOT/games/SNES/Restore Me.sfc"
mkdir -p "$ROOT/games/Saturn/.dripfeed/2027-01-01_Incomplete Legacy Set"
printf 'Disc 1.chd\nDisc 2.chd\n' > "$ROOT/games/Saturn/.dripfeed/2027-01-01_Incomplete Legacy Set/Incomplete Legacy Set.m3u"
echo one > "$ROOT/games/Saturn/.dripfeed/2027-01-01_Incomplete Legacy Set/Disc 1.chd"
bash "$SC" add SNES 2027-01-01 "$ROOT/games/SNES/Restore Me.sfc" >/dev/null   # future -> stays staged
chk "game is staged outside games/ before undrip" '[ -e "$ROOT/.dripfeed-library/SNES" ] && [ ! -e "$ROOT/games/SNES/Restore Me.sfc" ]'
bash "$ENG" --undrip >/dev/null 2>&1
chk "undrip restored the staged game to its folder" '[ -f "$ROOT/games/SNES/Restore Me.sfc" ]'
chk "undrip quarantined incomplete legacy multi-disc set instead of revealing it" '[ ! -e "$ROOT/games/Saturn/Incomplete Legacy Set" ] && find "$ROOT/.dripfeed-library/.conflicts/Saturn" -maxdepth 1 -name "*_2027-01-01_Incomplete Legacy Set" | grep -q .'
chk "undrip removed all showcase folders" '[ -z "$(ls -d "$ROOT"/_Dripfeed* "$ROOT"/_@Dripfeed* 2>/dev/null)" ]'
chk "undrip removed the Game of the Month folder" '[ ! -d "$ROOT/_Game of the Month" ]'
chk "undrip removed staging folders" '[ ! -d "$ROOT/games/SNES/.dripfeed" ]'
chk "undrip removed state (Scripts/.dripfeed) and Undrip.sh" '[ ! -d "$ROOT/Scripts/.dripfeed" ] && [ ! -f "$ROOT/Scripts/Undrip.sh" ]'
chk "undrip removed the boot hook" '! grep -q DRIPFEED_AUTORUN "$ROOT/linux/user-startup.sh"'
chk "undrip KEPT Scripts/Dripfeed.sh" '[ -f "$ROOT/Scripts/Dripfeed.sh" ]'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
