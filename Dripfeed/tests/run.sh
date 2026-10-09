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

ROOT="$(mktemp -d)"; CARDS=""; KILLS=""
trap 'for p in $KILLS; do kill "$p" 2>/dev/null; done; rm -rf "$ROOT" $CARDS' EXIT
mkdir -p "$ROOT/Scripts/.dripfeed" "$ROOT/games/GENESIS" "$ROOT/games/Saturn" "$ROOT/linux"
cp "$SRC"/*.sh "$ROOT/Scripts/.dripfeed/"
printf '#!/bin/sh\n' > "$ROOT/linux/_user-startup.sh"
export DRIPFEED_ROOT="$ROOT" DRIPFEED_INTERACTIVE=0 DRIPFEED_LOCK_WAIT=1
TODAY="$(date +%Y-%m-%d)"; MONTH_NOW="$(date +%Y-%m)"
# Helpers for the isolated fake cards used by the later sections.
scratch(){ local d; d="$(mktemp -d)"; CARDS="$CARDS $d"; eval "$1=\$d"; }
newcard(){   # $1 = variable that receives a fresh, installed fake card root
  local r; scratch r
  mkdir -p "$r/Scripts/.dripfeed" "$r/linux" "$r/games"
  cp "$SRC"/*.sh "$r/Scripts/.dripfeed/"
  printf '#!/bin/sh\n' > "$r/linux/_user-startup.sh"
  DRIPFEED_ROOT="$r" bash "$r/Scripts/.dripfeed/dripfeed-install.sh" >/dev/null 2>&1
  eval "$1=\$r"
}
eng(){ local c="$1"; shift; DRIPFEED_ROOT="$c" bash "$c/Scripts/.dripfeed/dripfeed-engine.sh" "$@"; }
sch(){ local c="$1"; shift; DRIPFEED_ROOT="$c" bash "$c/Scripts/.dripfeed/dripfeed-schedule.sh" "$@"; }
lib(){ DRIPFEED_ROOT="$1" bash -c '. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh"; df_load_config; '"$2"; }
mksparse(){ truncate -s "$2" "$1" 2>/dev/null || dd if=/dev/zero of="$1" bs=1 count=0 seek="$2" 2>/dev/null; }
inode(){ ls -di "$1" | awk '{print $1}'; }
waitfor(){ local i=0; while [ ! -e "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done; [ -e "$1" ]; }
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
chk "multi-disc shortcut launches the first disc (d1.chd), never the .m3u; Saturn delay 2" 'grep -q "path=\"[^\"]*/Shiny Forts III/d1.chd\"" "$SHOW/Saturn - Shiny Forts III.mgl" && ! grep -q "\.m3u\"" "$SHOW/Saturn - Shiny Forts III.mgl" && grep -q "delay=\"2\"" "$SHOW/Saturn - Shiny Forts III.mgl"'
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

echo "== browser leftovers: .crswap swap files and 0-byte entries are never revealed =="
newcard CA; mkdir -p "$CA/games/PSX" "$CA/.dripfeed-library/PSX"
echo partial > "$CA/.dripfeed-library/PSX/${TODAY}_Big Game.chd.crswap"
: > "$CA/.dripfeed-library/PSX/${TODAY}_Lone Placeholder.chd"
echo real > "$CA/.dripfeed-library/PSX/${TODAY}_Real Game.chd"
eng "$CA" --auto >/dev/null 2>&1
chk ".crswap swap file is skipped (never revealed, left in the library)" '[ ! -e "$CA/games/PSX/Big Game.chd.crswap" ] && [ ! -e "$CA/games/PSX/Big Game.chd" ] && [ -f "$CA/.dripfeed-library/PSX/${TODAY}_Big Game.chd.crswap" ]'
chk "0-byte queue entry is held, never revealed as a playable-looking game" '[ ! -e "$CA/games/PSX/Lone Placeholder.chd" ] && [ -e "$CA/.dripfeed-library/PSX/${TODAY}_Lone Placeholder.chd" ] && grep -q "RECOVERY HOLD.*Lone Placeholder" "$CA/Scripts/.dripfeed/dripfeed.log"'
: > "$CA/games/PSX/Empty Visible.chd"
printf '2099-01-01\tPSX\tEmpty Visible.chd\n' > "$CA/Scripts/.dripfeed/schedule-requests.tsv"
EOUT="$(sch "$CA" add PSX 2099-01-02 "$CA/games/PSX/Empty Visible.chd" 2>&1)"; eng "$CA" --auto >/dev/null 2>&1
chk "an empty (0-byte) file is never scheduled by the CLI or a browser request" '[ -f "$CA/games/PSX/Empty Visible.chd" ] && printf "%s\n" "$EOUT" | grep -q "empty 0-byte file" && [ ! -s "$CA/Scripts/.dripfeed/schedule-requests.tsv" ] && ! ls "$CA/.dripfeed-library/PSX" | grep -q "Empty Visible"'
chk "a complete game beside them still reveals; the ledger records no leftover" '[ -f "$CA/games/PSX/Real Game.chd" ] && ! grep -Eq "crswap|Lone Placeholder" "$CA/Scripts/.dripfeed/revealed.tsv"'
DIAG="$(eng "$CA" --diag 2>&1)"
chk "--diag labels the swap file and the empty entry" 'printf "%s\n" "$DIAG" | grep -q "Big Game.chd.crswap.*BROWSER-SWAP-FILE" && printf "%s\n" "$DIAG" | grep -q "Lone Placeholder.chd.*EMPTY-FILE-HOLD"'
eng "$CA" --undrip >/dev/null 2>&1
chk "Undrip quarantines leftovers instead of restoring them into games/" '[ ! -e "$CA/games/PSX/${TODAY}_Big Game.chd.crswap" ] && [ ! -e "$CA/games/PSX/Big Game.chd.crswap" ] && [ ! -e "$CA/games/PSX/Lone Placeholder.chd" ] && find "$CA/.dripfeed-library/.conflicts/PSX" -name "*Lone Placeholder.chd" | grep -q .'

echo "== same-drive guard: moves are renames, never copy+delete =="
newcard CB; mkdir -p "$CB/games/PSX/Big Set (USA)"
mksparse "$CB/games/PSX/Big Set (USA)/Big Set (USA).chd" 5368709120
INO1="$(inode "$CB/games/PSX/Big Set (USA)")"
sch "$CB" add PSX today "$CB/games/PSX/Big Set (USA)" >/dev/null 2>&1
eng "$CB" --auto >/dev/null 2>&1
chk "a 5 GB sparse disc set schedules and reveals as a rename (same inode, nothing copied)" '[ "$(inode "$CB/games/PSX/Big Set (USA)")" = "$INO1" ] && [ -f "$CB/games/PSX/Big Set (USA)/Big Set (USA).chd" ]'
# A second filesystem: tmpfs when available, otherwise a stat shim that reports a
# different device for the "other drive" (the guard must refuse before any mv).
XLIB=""; XSHIM=""
if [ -d /dev/shm ] && [ -w /dev/shm ]; then
  XLIB="$(mktemp -d /dev/shm/dripfeed-xdev.XXXXXX 2>/dev/null)"
  if [ -n "$XLIB" ] && [ "$(stat -c %d "$XLIB" 2>/dev/null || stat -f %d "$XLIB")" = "$(stat -c %d "$ROOT" 2>/dev/null || stat -f %d "$ROOT")" ]; then rm -rf "$XLIB"; XLIB=""; fi
fi
if [ -z "$XLIB" ]; then
  scratch XLIB; scratch XSHIM; REAL_STAT="$(command -v stat)"
  printf '#!/bin/sh\nfor a in "$@"; do last="$a"; done\ncase "$last" in "%s"*) echo 4242; exit 0 ;; esac\nexec "%s" "$@"\n' "$XLIB" "$REAL_STAT" > "$XSHIM/stat"
  chmod +x "$XSHIM/stat"
fi
CARDS="$CARDS $XLIB"; XPATH="${XSHIM:+$XSHIM:}$PATH"
newcard CX; mkdir -p "$CX/games/SNES"
printf 'STAGING_ROOT=%s\n' "$XLIB" >> "$CX/Scripts/.dripfeed/config.ini"
mksparse "$CX/games/SNES/Huge Game.sfc" 67108864
XOUT="$(PATH="$XPATH" sch "$CX" add SNES 2099-01-01 "$CX/games/SNES/Huge Game.sfc" 2>&1)"
chk "CLI add across drives is held: game untouched, nothing copied" '[ -f "$CX/games/SNES/Huge Game.sfc" ] && [ -z "$(ls -A "$XLIB/SNES" 2>/dev/null)" ] && printf "%s\n" "$XOUT" | grep -q "different drive"'
printf '2099-01-01\tSNES\tHuge Game.sfc\n' > "$CX/Scripts/.dripfeed/schedule-requests.tsv"
PATH="$XPATH" eng "$CX" --auto >/dev/null 2>&1
chk "browser request across drives is held and kept for a later pass" '[ -f "$CX/games/SNES/Huge Game.sfc" ] && [ -s "$CX/Scripts/.dripfeed/schedule-requests.tsv" ] && grep -q "CROSS-DEVICE HOLD" "$CX/Scripts/.dripfeed/dripfeed.log" && [ -z "$(ls -A "$XLIB/SNES" 2>/dev/null)" ]'
mkdir -p "$XLIB/SNES"; echo due > "$XLIB/SNES/${TODAY}_Due Across.sfc"
PATH="$XPATH" eng "$CX" --auto >/dev/null 2>&1
chk "reveal across drives is held: no partial game, no journal, queue intact" '[ ! -e "$CX/games/SNES/Due Across.sfc" ] && [ -f "$XLIB/SNES/${TODAY}_Due Across.sfc" ] && [ ! -f "$CX/Scripts/.dripfeed/transactions/current.tsv" ] && ! grep -q "Due Across" "$CX/Scripts/.dripfeed/revealed.tsv" 2>/dev/null'
chk "--diag says the games and the library are on different drives" 'PATH="$XPATH" eng "$CX" --diag 2>&1 | grep -q "DIFFERENT DRIVES"'
mkdir -p "$CX/games/SNES/.dripfeed"; echo leg > "$CX/games/SNES/.dripfeed/2099-02-02_Legacy Across.sfc"
PATH="$XPATH" eng "$CX" --migrate >/dev/null 2>&1
chk "legacy migration across drives is held in place (never copied)" '[ -f "$CX/games/SNES/.dripfeed/2099-02-02_Legacy Across.sfc" ] && [ ! -e "$XLIB/SNES/2099-02-02_Legacy Across.sfc" ] && grep -q "LEGACY MIGRATION held" "$CX/Scripts/.dripfeed/dripfeed.log"'
XOUT="$(PATH="$XPATH" eng "$CX" --undrip 2>&1)"
chk "Undrip never copies across drives: the queued game stays in its library" '[ -f "$XLIB/SNES/${TODAY}_Due Across.sfc" ] && [ ! -e "$CX/games/SNES/Due Across.sfc" ] && printf "%s\n" "$XOUT" | grep -q "DIFFERENT DRIVE"'
newcard CW; mkdir -p "$CW/games/PSX" "$CW/.dripfeed-library/PSX/${TODAY}_Usb Shadowed"
echo d > "$CW/.dripfeed-library/PSX/2099-01-01_Waiting.chd"
mkdir -p "$CW/media/usb0/games/PSX" "$CW/cifs/PSX"
chk "--diag warns when a USB or cifs PSX folder would shadow games/PSX" 'DRIPFEED_MEDIA="$CW/media" eng "$CW" --diag 2>&1 | grep -q "usb0/games/PSX exists" && DRIPFEED_MEDIA="$CW/media" eng "$CW" --diag 2>&1 | grep -q "cifs/PSX exists"'

echo "== single-runner lock: owner pid, never stolen from a live holder =="
newcard CL; mkdir -p "$CL/games/SNES"; echo a > "$CL/games/SNES/Locked Out.sfc"
DRIPFEED_ROOT="$CL" bash -c '. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh"; df_lock || exit 1; : > "$DRIPFEED_ROOT/held"; exec sleep 30' &
HOLDER=$!; KILLS="$KILLS $HOLDER"; waitfor "$CL/held"
echo 1 > "$CL/Scripts/.dripfeed/.lock/ts"          # make the live lock look ancient
LOUT="$(sch "$CL" add SNES today "$CL/games/SNES/Locked Out.sfc" 2>&1)"
chk "CLI scheduler waits briefly, then refuses with a clear message" '[ -f "$CL/games/SNES/Locked Out.sfc" ] && printf "%s\n" "$LOUT" | grep -q "Dripfeed is busy"'
LOUT="$(eng "$CL" --undrip 2>&1)"
chk "Undrip refuses while another process holds the lock (nothing removed)" 'printf "%s\n" "$LOUT" | grep -q "Dripfeed is busy" && [ -f "$CL/Scripts/.dripfeed/config.ini" ] && grep -q DRIPFEED_AUTORUN "$CL/linux/user-startup.sh"'
eng "$CL" --auto >/dev/null 2>&1
chk "a live holder is never preempted, even with an ancient timestamp" '[ "$(sed -n 1p "$CL/Scripts/.dripfeed/.lock/owner")" = "$HOLDER" ] && grep -q "reveal skipped (another pass holds the lock)" "$CL/Scripts/.dripfeed/dripfeed.log"'
lib "$CL" 'DF_LOCK_HELD=1; df_unlock'
chk "a process never removes a lock it does not own" '[ -d "$CL/Scripts/.dripfeed/.lock" ] && [ "$(sed -n 1p "$CL/Scripts/.dripfeed/.lock/owner")" = "$HOLDER" ]'
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
sch "$CL" add SNES today "$CL/games/SNES/Locked Out.sfc" >/dev/null 2>&1
eng "$CL" --auto >/dev/null 2>&1
chk "a dead holder's lock is reclaimed at once and released after the pass" '[ -f "$CL/games/SNES/Locked Out.sfc" ] && grep -q "reclaimed a stale lock" "$CL/Scripts/.dripfeed/dripfeed.log" && grep -q "Locked Out.sfc" "$CL/Scripts/.dripfeed/revealed.tsv" && [ ! -d "$CL/Scripts/.dripfeed/.lock" ]'
mkdir "$CL/Scripts/.dripfeed/.lock"; date +%s > "$CL/Scripts/.dripfeed/.lock/ts"
echo b > "$CL/games/SNES/Old Format.sfc"; LOUT="$(sch "$CL" add SNES today "$CL/games/SNES/Old Format.sfc" 2>&1)"
echo 1 > "$CL/Scripts/.dripfeed/.lock/ts"; LOUT2="$(sch "$CL" add SNES today "$CL/games/SNES/Old Format.sfc" 2>&1)"
chk "an owner-less lock from an older version keeps the 10-minute rule" 'printf "%s\n" "$LOUT" | grep -q "Dripfeed is busy" && printf "%s\n" "$LOUT2" | grep -q "scheduled" && [ ! -d "$CL/Scripts/.dripfeed/.lock" ]'

echo "== boot hook: start only (MiSTer also runs user-startup.sh with stop at shutdown) =="
newcard CH; mkdir -p "$CH/games/SNES"; echo s > "$CH/games/SNES/Shutdown Test.sfc"
sch "$CH" add SNES today "$CH/games/SNES/Shutdown Test.sfc" >/dev/null 2>&1
printf "POST_REVEAL_CMD='echo ran >> \"%s/post.out\"'\n" "$CH" >> "$CH/Scripts/.dripfeed/config.ini"
DRIPFEED_ROOT="$CH" sh "$CH/linux/user-startup.sh" stop >/dev/null 2>&1; sleep 1
chk "stop (shutdown/reboot) starts nothing: no watcher, no reveal, no command, boot.log untouched" '[ ! -e "$CH/Scripts/.dripfeed/watch.pid" ] && [ ! -e "$CH/Scripts/.dripfeed/boot.log" ] && [ ! -e "$CH/games/SNES/Shutdown Test.sfc" ] && [ ! -e "$CH/post.out" ]'
DRIPFEED_ROOT="$CH" sh "$CH/linux/user-startup.sh" start >/dev/null 2>&1
waitfor "$CH/Scripts/.dripfeed/watch.pid"; WP="$(sed -n 1p "$CH/Scripts/.dripfeed/watch.pid" 2>/dev/null)"; KILLS="$KILLS $WP"
chk "start (boot) launches the watcher" '[ -n "$WP" ] && kill -0 "$WP" 2>/dev/null'
kill "$WP" 2>/dev/null
US_CH="$CH/linux/user-startup.sh"
sed '/=====DRIPFEED_AUTORUN=====/,/=====DRIPFEED_AUTORUN_END=====/d' "$US_CH" > "$US_CH.tmp" && mv "$US_CH.tmp" "$US_CH"
printf '\n#=====DRIPFEED_AUTORUN=====\n[ -f %s ] && %s --watch >%s 2>&1 &\n#=====DRIPFEED_AUTORUN_END=====\n' "$CH/Scripts/.dripfeed/dripfeed-engine.sh" "$CH/Scripts/.dripfeed/dripfeed-engine.sh" "$CH/Scripts/.dripfeed/boot.log" >> "$US_CH"
DRIPFEED_ROOT="$CH" bash "$CH/Scripts/.dripfeed/dripfeed-install.sh" >/dev/null 2>&1
chk "reinstall replaces an older always-on hook with the start-only one, exactly once" '[ "$(grep -c "=====DRIPFEED_AUTORUN=====" "$US_CH")" = 1 ] && grep -q "in start|" "$US_CH" && ! grep -q "^\[ -f" "$US_CH"'

echo "== scale: process spawns stay linear in queue size =="
newcard CP; mkdir -p "$CP/games/SNES"; N=60; scratch SPAWN
for t in awk sed grep sort head tail cut tr wc cat date mkdir mv rm sync stat ls find touch basename dirname cp; do
  real="$(command -v "$t" 2>/dev/null)"; [ -n "$real" ] || continue
  printf '#!/bin/sh\necho %s >> "%s/count"\nexec "%s" "$@"\n' "$t" "$SPAWN" "$real" > "$SPAWN/$t"; chmod +x "$SPAWN/$t"
done
spawns(){ : > "$SPAWN/count"; PATH="$SPAWN:$PATH" "$@" >/dev/null 2>&1; wc -l < "$SPAWN/count" | tr -d ' '; }
i=1; while [ "$i" -le "$N" ]; do echo x > "$CP/games/SNES/Game $i.sfc"; printf '2099-12-31\tSNES\tGame %s.sfc\n' "$i"; i=$((i+1)); done > "$CP/Scripts/.dripfeed/schedule-requests.tsv"
S_REQ="$(spawns eng "$CP" --auto)"
i=1; while [ "$i" -le "$N" ]; do printf '2099-12-30\tSNES\tGame %s.sfc\n' "$i"; i=$((i+1)); done > "$CP/Scripts/.dripfeed/schedule-requests.tsv"
S_RED="$(spawns eng "$CP" --auto)"
S_DIAG="$(spawns eng "$CP" --diag)"
i=1; while [ "$i" -le "$N" ]; do echo x > "$CP/games/SNES/More $i.sfc"; i=$((i+1)); done
S_ADD="$(spawns sch "$CP" add SNES 2099-12-29 "$CP"/games/SNES/More*.sfc)"
echo "    (spawns for $N games: request lane $S_REQ, re-date lane $S_RED, diag $S_DIAG, CLI add $S_ADD)"
chk "request lanes, --diag and CLI add spawn O(N) processes (not one rescan per game)" '[ "$S_REQ" -le $((3*N+60)) ] && [ "$S_RED" -le $((3*N+60)) ] && [ "$S_DIAG" -le $((N+60)) ] && [ "$S_ADD" -le $((3*N+60)) ]'
chk "every game was scheduled, re-dated and added exactly once" '[ "$(ls "$CP/.dripfeed-library/SNES" | grep -c "^2099-12-30_Game ")" = "$N" ] && [ "$(ls "$CP/.dripfeed-library/SNES" | grep -c "^2099-12-29_More ")" = "$N" ] && [ ! -s "$CP/Scripts/.dripfeed/schedule-requests.tsv" ]'

echo "== multi-disc shortcut target (MiSTer mounts .cue/.chd, never .m3u) =="
scratch MG; mkdir -p "$MG/out"
FQ="$MG/PSX/Final Quest (USA)"; mkdir -p "$FQ"
for n in 1 2; do printf 'FILE "Final Quest (USA) (Disc %s).bin" BINARY\n  TRACK 01 MODE2/2352\n' "$n" > "$FQ/Final Quest (USA) (Disc $n).cue"; echo b > "$FQ/Final Quest (USA) (Disc $n).bin"; done
printf '\357\273\277Final Quest (USA) (Disc 1).cue\r\nFinal Quest (USA) (Disc 2).cue\r\n' > "$FQ/FQ.m3u"     # sorts BEFORE the discs
ND="$MG/Saturn/Natural Order"; mkdir -p "$ND"; for n in 11 10 2; do echo c > "$ND/Disc $n.chd"; done
IS="$MG/PSX/Iso First"; mkdir -p "$IS"; printf 'Iso First.iso\n' > "$IS/Iso First.m3u"; echo i > "$IS/Iso First.iso"; echo c > "$IS/Track Disc 1.chd"
IO="$MG/PSX/Iso Only"; mkdir -p "$IO"; echo i > "$IO/Iso Only.iso"
mglpath(){ sed -n 's/.*path="\([^"]*\)".*/\1/p' "$1"; }
DRIPFEED_ROOT="$MG" bash -c '. "$0/dripfeed-common.sh"; df_make_mgl "$1/out" PSX "$2"; df_make_mgl "$1/out" Saturn "$3"; df_make_mgl "$1/out" PSX "$4"; df_make_mgl "$1/out" PSX "$5" && echo LAUNCHABLE' "$SRC" "$MG" "$FQ" "$ND" "$IS" "$IO" > "$MG/res.txt" 2>&1
chk "playlist with BOM/CRLF: shortcut launches its first entry, (Disc 1).cue" '[ "$(mglpath "$MG/out/PSX - Final Quest (USA).mgl")" = "$FQ/Final Quest (USA) (Disc 1).cue" ]'
chk "no playlist: first .chd in natural order (Disc 2 before Disc 10)" '[ "$(mglpath "$MG/out/Saturn - Natural Order.mgl")" = "$ND/Disc 2.chd" ]'
chk "a playlist that starts with an .iso is ignored for CD cores (.chd used)" '[ "$(mglpath "$MG/out/PSX - Iso First.mgl")" = "$IS/Track Disc 1.chd" ]'
chk "nothing launchable (.iso only): no shortcut, logged" '[ ! -e "$MG/out/PSX - Iso Only.mgl" ] && ! grep -q LAUNCHABLE "$MG/res.txt" && grep -q "no launchable disc.*Iso Only" "$MG/Scripts/.dripfeed/dripfeed.log"'
newcard CM; mkdir -p "$CM/games/PSX"; cp -R "$FQ" "$CM/games/PSX/"
printf '%s\tgames/PSX/Final Quest (USA)\n' "$MONTH_NOW" > "$CM/Scripts/.dripfeed/gotm.tsv"
eng "$CM" --gotm >/dev/null 2>&1
chk "GOT'eM multi-disc pick launches (Disc 1).cue too" '[ "$(mglpath "$CM/_Game of the Month/PSX - Final Quest (USA).mgl")" = "$CM/games/PSX/Final Quest (USA)/Final Quest (USA) (Disc 1).cue" ]'

echo "== What's New pruner reads escaped paths (& ' stay; nothing pruned) =="
newcard CG; mkdir -p "$CG/games/SNES" "$CG/games/GENESIS"
echo k > "$CG/games/SNES/Kirby's Dream Course (USA).sfc"; echo t > "$CG/games/GENESIS/ToeJam & Earl, Panic on Funkotron.gen"
sch "$CG" add SNES today "$CG/games/SNES/Kirby's Dream Course (USA).sfc" >/dev/null 2>&1
sch "$CG" add GENESIS today "$CG/games/GENESIS/ToeJam & Earl, Panic on Funkotron.gen" >/dev/null 2>&1
eng "$CG" --auto >/dev/null 2>&1; eng "$CG" --auto >/dev/null 2>&1; eng "$CG" --auto >/dev/null 2>&1
SG="$CG/$(cat "$CG/Scripts/.dripfeed/showcase_name")"
chk "shortcuts for names with an apostrophe or ampersand survive later passes" '[ -f "$SG/SNES - Kirby'"'"'s Dream Course (USA).mgl" ] && [ -f "$SG/GENESIS - ToeJam & Earl, Panic on Funkotron.mgl" ] && ! grep -q "pruned orphan" "$CG/Scripts/.dripfeed/dripfeed.log"'
UNESC="$(printf '%s' '&quot;&apos;&lt;&gt;&amp;amp;' | bash -c '. "$0/dripfeed-common.sh"; df_xml_unescape' "$SRC")"
chk "df_xml_unescape decodes all five entities, &amp; last" '[ "$UNESC" = "\"'"'"'<>&amp;" ]'
chk "gamelist.xml escapes every field (no bare &)" '! sed "s/&amp;//g; s/&lt;//g; s/&gt;//g; s/&quot;//g; s/&apos;//g" "$SG/gamelist.xml" | grep -q "&" && grep -q "<path>./GENESIS - ToeJam &amp; Earl, Panic on Funkotron.mgl</path>" "$SG/gamelist.xml"'
awk -F'\t' -v OFS='\t' '$3 ~ /^ToeJam/ { $4 = "2026-01-02 03:04:05" } 1' "$CG/Scripts/.dripfeed/revealed.tsv" > "$CG/led.tmp" && mv "$CG/led.tmp" "$CG/Scripts/.dripfeed/revealed.tsv"
eng "$CG" --auto >/dev/null 2>&1
chk "gamelist releasedate comes from the reveal ledger, not today" 'grep -A3 "<path>./GENESIS - ToeJam" "$SG/gamelist.xml" | grep -q "<releasedate>20260102T030405</releasedate>"'

echo "== disc-set completeness tolerates real-world playlists =="
newcard CD; mkdir -p "$CD/games/PSX"; L="$CD/.dripfeed-library/PSX"
mkset(){ mkdir -p "$L/${TODAY}_$1"; shift; local s="$1"; shift; for f in "$@"; do echo disc > "$L/${TODAY}_$s/$f"; done; }
mkset "Bom Set" "Bom Set" "Disc 1.chd" "Disc 2.chd"; printf '\357\273\277Disc 1.chd\r\nDisc 2.chd\r\n' > "$L/${TODAY}_Bom Set/Bom Set.m3u"
mkset "Trail Set" "Trail Set" "Disc 1.chd" "Disc 2.chd"; printf 'Disc 1.chd \nDisc 2.chd\t\n' > "$L/${TODAY}_Trail Set/Trail Set.m3u"
mkset "Abs Set" "Abs Set" "Disc 1.chd" "Disc 2.chd"; printf '/media/fat/games/PSX/Abs Set/Disc 1.chd\nC:\\Games\\Abs Set\\Disc 2.chd\n' > "$L/${TODAY}_Abs Set/Abs Set.m3u"
mkset "Cue Bom" "Cue Bom" "Track 01.bin"; printf '\357\273\277FILE "Track 01.bin" BINARY\r\n  TRACK 01 MODE2/2352\r\n' > "$L/${TODAY}_Cue Bom/Cue Bom.cue"
mkset "Comment Only" "Comment Only" "Game.chd"; printf '#EXTM3U\n# made by a playlist tool\n' > "$L/${TODAY}_Comment Only/Comment Only.m3u"
mkset "Missing Disc" "Missing Disc" "Disc 1.chd"; printf 'Disc 1.chd\nDisc 2.chd\n' > "$L/${TODAY}_Missing Disc/Missing Disc.m3u"
mkset "Empty Disc" "Empty Disc" "Disc 1.chd"; : > "$L/${TODAY}_Empty Disc/Disc 2.chd"; printf 'Disc 1.chd\nDisc 2.chd\n' > "$L/${TODAY}_Empty Disc/Empty Disc.m3u"
eng "$CD" --auto >/dev/null 2>&1
chk "BOM+CRLF, trailing-space, absolute-path, BOM .cue and comment-only playlists reveal" '[ -d "$CD/games/PSX/Bom Set" ] && [ -d "$CD/games/PSX/Trail Set" ] && [ -d "$CD/games/PSX/Abs Set" ] && [ -d "$CD/games/PSX/Cue Bom" ] && [ -d "$CD/games/PSX/Comment Only" ]'
chk "a set with a genuinely missing disc stays held" '[ ! -e "$CD/games/PSX/Missing Disc" ] && [ -d "$L/${TODAY}_Missing Disc" ]'
chk "a set whose disc is a 0-byte placeholder stays held" '[ ! -e "$CD/games/PSX/Empty Disc" ] && [ -d "$L/${TODAY}_Empty Disc" ]'

echo "== robustness: config validation, --diag counts, list order, no dead code =="
newcard CR; mkdir -p "$CR/games/SNES"
printf 'WATCH_INTERVAL=0\nBOOT_DELAY=soon\nSHOWCASE_KEEP=-3\nSYSTEM_SHORTCUTS=maybe\nSYSTEM_SHORTCUTS_DIR="../escape"\n' >> "$CR/Scripts/.dripfeed/config.ini"
VALS="$(lib "$CR" 'echo "$WATCH_INTERVAL|$BOOT_DELAY|$SHOWCASE_KEEP|$SYSTEM_SHORTCUTS|$SYSTEM_SHORTCUTS_DIR"')"
chk "settings are validated (WATCH_INTERVAL never below 60; bad values and unsafe folder names fall back)" '[ "$VALS" = "60|30|12|0|_Dripfeed New" ]'
: > "$CR/Scripts/.dripfeed/schedule-requests.tsv"; : > "$CR/Scripts/.dripfeed/unschedule-requests.tsv"
DIAG="$(eng "$CR" --diag 2>&1)"
chk "--diag prints request counts once (no stray 0 line)" 'printf "%s\n" "$DIAG" | grep -q "schedule=0, unschedule=0" && ! printf "%s\n" "$DIAG" | grep -qx "0"'
chk "dead WAIT_BUTTON code is gone" '! grep -Eq "WAIT_BUTTON|WAIT_TIMEOUT|df_wait_button" "$SRC"/*.sh'
mkdir -p "$CR/.dripfeed-library/SNES" "$CR/games/SNES/.dripfeed"
echo a > "$CR/.dripfeed-library/SNES/2099-03-01_Third.sfc"; echo b > "$CR/.dripfeed-library/SNES/2099-01-01_First.sfc"; echo c > "$CR/games/SNES/.dripfeed/2099-02-01_Second.sfc"
LIST="$(sch "$CR" list 2>&1 | awk '{print $NF}' | tr '\n' ' ')"
chk "list is sorted by date across the current and legacy queues" '[ "$LIST" = "First.sfc Second.sfc Third.sfc " ]'
scratch NOBOOT; printf '#!/bin/sh\n: > "%s/rebooted"\n' "$NOBOOT" > "$NOBOOT/reboot"; chmod +x "$NOBOOT/reboot"
newcard CZ; rm -rf "$CZ/Scripts/.dripfeed"; cp "$HERE/../Scripts/Dripfeed.sh" "$CZ/Scripts/Dripfeed.sh"
LOUT="$(PATH="$NOBOOT:$PATH" DRIPFEED_ROOT="$CZ" bash "$CZ/Scripts/Dripfeed.sh" </dev/null 2>&1)"
LVER="$(grep -m1 '^DRIPFEED_VERSION=' "$HERE/../Scripts/Dripfeed.sh" | cut -d'"' -f2)"
chk "launcher outside MiSTer installs but never reboots the computer" '[ ! -e "$NOBOOT/rebooted" ] && [ "$(cat "$CZ/Scripts/.dripfeed/.version")" = "$LVER" ] && printf "%s\n" "$LOUT" | grep -q "restart skipped"'
LOUT="$(printf x | PATH="$NOBOOT:$PATH" DRIPFEED_ROOT="$CZ" bash "$CZ/Scripts/Undrip.sh" 2>&1)"
chk "Undrip.sh outside MiSTer resets but never reboots the computer" '[ ! -e "$NOBOOT/rebooted" ] && [ ! -d "$CZ/Scripts/.dripfeed" ] && printf "%s\n" "$LOUT" | grep -q "restart skipped"'
scratch NOCARD; NOWHERE="$NOCARD/not-a-card"
PATH="$NOBOOT:$PATH" DRIPFEED_ROOT="$NOWHERE" bash "$HERE/../Scripts/Dripfeed.sh" </dev/null >/dev/null 2>&1; RC=$?
chk "launcher refuses a root without Scripts/ and creates nothing there" '[ "$RC" -ne 0 ] && [ ! -e "$NOWHERE" ] && [ ! -e "$NOBOOT/rebooted" ]'

echo "== MGL map re-synced with the current mrext catalog =="
ML(){ bash -c '. "$0/dripfeed-common.sh"; df_mgl_lookup "$1" "$2" || { echo none; exit 0; }; echo "$RBF|$MTYPE|$MINDEX|$DELAY|$SETNAME|$RESET_DELAY"' "$SRC" "$1" "$2"; }
chk "Jaguar cart: f/0 plus a reset; Jaguar CD .cdi: s/1" '[ "$(ML Jaguar .jag)" = "_Console/Jaguar|f|0|1||1" ] && [ "$(ML Jaguar .cdi)" = "_Console/Jaguar|s|1|1||1" ]'
chk "NeoGeo Pocket: JTNGP core with its set name, delay 2" '[ "$(ML NGP .ngp)" = "_Arcade/JTNGP|f|1|2|NeoGeoPocket|0" ]'
chk "Saturn: s/0 with delay 2; MegaCD stays s/0 delay 1" '[ "$(ML Saturn .chd)" = "_Console/Saturn|s|0|2||0" ] && [ "$(ML MegaCD .cue)" = "_Console/MegaCD|s|0|1||0" ]'
chk ".gg in the SMS folder: Game Gear slot, no set name; GameGear folder keeps it" '[ "$(ML SMS .gg)" = "_Console/SMS|f|2|1||0" ] && [ "$(ML SMS .sms)" = "_Console/SMS|f|1|1||0" ] && [ "$(ML GameGear .GG)" = "_Console/SMS|f|2|1|GameGear|0" ]'
chk "PSX: .cue/.chd s/1, .exe f/1; .iso and .m3u refused" '[ "$(ML PSX .cue)" = "_Console/PSX|s|1|1||0" ] && [ "$(ML PSX .exe)" = "_Console/PSX|f|1|1||0" ] && [ "$(ML PSX .iso)" = none ] && [ "$(ML PSX .m3u)" = none ]'
chk "ZX Spectrum: disk s/0, tape f/2, snapshot f/4" '[ "$(ML Spectrum .trd)" = "_Computer/ZX-Spectrum|s|0|1||0" ] && [ "$(ML Spectrum .tzx)" = "_Computer/ZX-Spectrum|f|2|1||0" ] && [ "$(ML Spectrum .z80)" = "_Computer/ZX-Spectrum|f|4|1||0" ]'
chk ".zip, unknown extensions and unknown systems are refused (shortcut skipped)" '[ "$(ML SNES .zip)" = none ] && [ "$(ML NES .txt)" = none ] && [ "$(ML Vectrex .vec)" = none ] && [ "$(ML SNES .sfc)" = "_Console/SNES|f|0|2||0" ]'
newcard CJ; mkdir -p "$CJ/games/Jaguar" "$CJ/games/SNES"; echo j > "$CJ/games/Jaguar/Cart.jag"; echo z > "$CJ/games/SNES/Zipped.zip"
sch "$CJ" add Jaguar today "$CJ/games/Jaguar/Cart.jag" >/dev/null 2>&1; sch "$CJ" add SNES today "$CJ/games/SNES/Zipped.zip" >/dev/null 2>&1
eng "$CJ" --auto >/dev/null 2>&1; SJ="$CJ/$(cat "$CJ/Scripts/.dripfeed/showcase_name")"
chk "Jaguar shortcut carries <reset delay=1 hold=1>; a .zip gets no shortcut (logged)" 'grep -q "<reset delay=\"1\" hold=\"1\"/>" "$SJ/Jaguar - Cart.mgl" && [ ! -e "$SJ/SNES - Zipped.mgl" ] && [ -f "$CJ/games/SNES/Zipped.zip" ] && grep -q "no MGL slot for SNES (.zip)" "$CJ/Scripts/.dripfeed/dripfeed.log"'

echo "== GOT'eM arcade core lookup matches the firmware's rule =="
newcard CK; mkdir -p "$CK/_Arcade/cores"
for c in jtcps1_20240101 jtcps15_20260101 jtcps1_20250301 Arcade-jtcps1_20230101 Arcade-JTX_20240101; do echo core > "$CK/_Arcade/cores/$c.rbf"; done
printf '<misterromdescription><rbf>jtcps1</rbf></misterromdescription>\n' > "$CK/_Arcade/Final Fight.mra"
printf '<misterromdescription><rbf>jtx</rbf></misterromdescription>\n' > "$CK/_Arcade/Arcade Form.mra"
printf '<misterromdescription><rbf>nosuchcore</rbf></misterromdescription>\n' > "$CK/_Arcade/No Core.mra"
printf '%s\t_Arcade/Final Fight.mra\n' "$MONTH_NOW" > "$CK/Scripts/.dripfeed/gotm.tsv"; eng "$CK" --gotm >/dev/null 2>&1
chk "exact core name wins over a longer one (jtcps1, not jtcps15), newest version" '[ "$(ls "$CK/_Game of the Month/cores")" = "jtcps1_20250301.rbf" ]'
printf '%s\t_Arcade/Arcade Form.mra\n' "$MONTH_NOW" > "$CK/Scripts/.dripfeed/gotm.tsv"; eng "$CK" --gotm >/dev/null 2>&1
chk "the 'Arcade-<rbf>' form is found, case-insensitively" '[ "$(ls "$CK/_Game of the Month/cores")" = "Arcade-JTX_20240101.rbf" ]'
printf '%s\t_Arcade/No Core.mra\n' "$MONTH_NOW" > "$CK/Scripts/.dripfeed/gotm.tsv"; eng "$CK" --gotm >/dev/null 2>&1
chk "a missing core is logged (and nothing wrong is copied)" '[ ! -d "$CK/_Game of the Month/cores" ] && grep -q "no core named .nosuchcore." "$CK/Scripts/.dripfeed/dripfeed.log"'

newcard CV; mkdir -p "$CV/_Arcade/cores" "$CV/games/SNES"
echo core > "$CV/_Arcade/cores/mycore_20240101.rbf"; printf '<misterromdescription><rbf>mycore</rbf></misterromdescription>\n' > "$CV/_Arcade/My Game.mra"
echo g > "$CV/games/SNES/Pick.sfc"
printf 'GOTM_DIRNAME="_Arcade"\n' >> "$CV/Scripts/.dripfeed/config.ini"
printf '%s\tgames/SNES/Pick.sfc\n' "$MONTH_NOW" > "$CV/Scripts/.dripfeed/gotm.tsv"
eng "$CV" --gotm >/dev/null 2>&1; eng "$CV" --undrip >/dev/null 2>&1
chk "GOTM_DIRNAME naming a MiSTer folder (_Arcade) never wipes it, not even on Undrip" '[ -f "$CV/_Arcade/My Game.mra" ] && [ -f "$CV/_Arcade/cores/mycore_20240101.rbf" ] && [ ! -e "$CV/_Arcade/SNES - Pick.mgl" ]'

echo "== stale menu folders: custom prefix, Favorites mirror, exact Undrip =="
newcard CS; mkdir -p "$CS/games/SNES" "$CS/_@Favorites/My Faves" "$CS/_@Favorites/_Dripfeed - New Mon Jan 5, 26" "$CS/_New Games - New Mon Oct 5, 26" "$CS/_New Games - Mine"
printf 'SHOWCASE_PREFIX="_New Games - "\nFAVORITES_MIRROR=1\n' >> "$CS/Scripts/.dripfeed/config.ini"
echo o > "$CS/games/SNES/Old Pick.sfc"; echo m > "$CS/games/SNES/Mine.sfc"; echo n > "$CS/games/SNES/New Pick.sfc"
printf '2026-01-05\tSNES\tOld Pick.sfc\t2026-01-05 10:00:00\n' > "$CS/Scripts/.dripfeed/revealed.tsv"
printf '_New Games - New Mon Oct 5, 26\n' > "$CS/Scripts/.dripfeed/showcase_names"
mkmgl(){ printf '<mistergamedescription>\n\t<rbf>_Console/SNES</rbf>\n\t<file delay="2" type="f" index="0" path="%s"/>\n</mistergamedescription>\n' "$2" > "$1"; }
mkmgl "$CS/_New Games - New Mon Oct 5, 26/SNES - Old Pick.mgl" "$CS/games/SNES/Old Pick.sfc"
mkmgl "$CS/_New Games - Mine/Mine.mgl" "$CS/games/SNES/Mine.sfc"
mkmgl "$CS/_@Favorites/_Dripfeed - New Mon Jan 5, 26/SNES - Old Pick.mgl" "$CS/games/SNES/Old Pick.sfc"
mkmgl "$CS/_@Favorites/My Faves/Mine.mgl" "$CS/games/SNES/Mine.sfc"; mkmgl "$CS/_@Favorites/Top Pick.mgl" "$CS/games/SNES/Mine.sfc"
sch "$CS" add SNES today "$CS/games/SNES/New Pick.sfc" >/dev/null 2>&1; eng "$CS" --auto >/dev/null 2>&1
CUR="$(cat "$CS/Scripts/.dripfeed/showcase_name")"
chk "a stale custom-prefix folder is consolidated into the one current folder" '[ "$CUR" != "_New Games - New Mon Oct 5, 26" ] && [ ! -d "$CS/_New Games - New Mon Oct 5, 26" ] && [ -f "$CS/$CUR/SNES - Old Pick.mgl" ] && [ -f "$CS/$CUR/SNES - New Pick.mgl" ]'
chk "a user folder that shares the prefix is left alone" '[ -f "$CS/_New Games - Mine/Mine.mgl" ]'
chk "every stamped folder name is recorded" 'grep -qxF "$CUR" "$CS/Scripts/.dripfeed/showcase_names" && grep -qxF "_New Games - New Mon Oct 5, 26" "$CS/Scripts/.dripfeed/showcase_names"'
chk "Favorites mirror uses ONE stable subfolder (_@Favorites/_Dripfeed New)" '[ -f "$CS/_@Favorites/_Dripfeed New/SNES - New Pick.mgl" ] && [ "$(ls -d "$CS/_@Favorites"/*/ | wc -l | tr -d " ")" -eq 2 ]'
chk "an older dated mirror folder of Dripfeed shortcuts is removed; user favorites stay" '[ ! -d "$CS/_@Favorites/_Dripfeed - New Mon Jan 5, 26" ] && [ -f "$CS/_@Favorites/My Faves/Mine.mgl" ] && [ -f "$CS/_@Favorites/Top Pick.mgl" ]'
eng "$CS" --undrip >/dev/null 2>&1
chk "Undrip removes exactly what Dripfeed created (user folders and favorites stay)" '[ ! -d "$CS/$CUR" ] && [ ! -d "$CS/_@Favorites/_Dripfeed New" ] && [ -f "$CS/_New Games - Mine/Mine.mgl" ] && [ -f "$CS/_@Favorites/My Faves/Mine.mgl" ] && [ -f "$CS/_@Favorites/Top Pick.mgl" ] && [ -f "$CS/games/SNES/New Pick.sfc" ]'

KINDS="$(DRIPFEED_ROOT="$CS" bash -c '. "$DRIPFEED_ROOT/Scripts/.dripfeed/dripfeed-common.sh"; SHOWCASE_PREFIX="_@Fav"; for n in "_@Favorites" "_Game of the Month"; do df_showcase_kind "$n" && echo "$n"; done; SHOWCASE_PREFIX="_Game"; DF_SHOWCASE_PRE=""; df_showcase_kind "_Game of the Month - Aug" && echo gotm; SHOWCASE_PREFIX="_"; DF_SHOWCASE_PRE=""; df_showcase_kind "_Arcade" && echo arcade; true')"
chk "an unusual prefix can never claim the Favorites root, a GOT'eM folder or every _ folder" '[ -z "$KINDS" ]'
scratch MV; mkdir -p "$MV/src/Set" "$MV/dst"; echo keep > "$MV/dst/Taken.sfc"
for mode in gnu posix; do echo "$mode" > "$MV/src/$mode.sfc"; echo new > "$MV/src/Taken-$mode.sfc"; mkdir -p "$MV/src/Set-$mode"; echo d > "$MV/src/Set-$mode/Disc 1.chd"; done
MVRES="$(DRIPFEED_ROOT="$MV" bash -c '. "$0/dripfeed-common.sh"; for mode in gnu posix; do DF_MV_MODE=$mode
  df_rename "$1/src/$mode.sfc" "$1/dst/$mode.sfc" && printf "file-ok "
  df_rename "$1/src/Taken-$mode.sfc" "$1/dst/Taken.sfc" || printf "clobber-refused "
  df_rename "$1/src/Set-$mode" "$1/dst/Set-$mode" && [ -f "$1/dst/Set-$mode/Disc 1.chd" ] && printf "dir-ok "
done' "$SRC" "$MV")"
chk "df_rename renames files and folders and never clobbers, with GNU and POSIX mv" '[ "$MVRES" = "file-ok clobber-refused dir-ok file-ok clobber-refused dir-ok " ] && [ "$(cat "$MV/dst/Taken.sfc")" = keep ] && [ -f "$MV/src/Taken-gnu.sfc" ] && [ -f "$MV/src/Taken-posix.sfc" ]'

echo "== opt-in SYSTEM_SHORTCUTS: standard .mgl files inside games/<SYSTEM> =="
newcard CN; mkdir -p "$CN/games/SNES" "$CN/games/GENESIS"
chk "config template carries the new options with their defaults" 'grep -q "^SYSTEM_SHORTCUTS=0" "$CN/Scripts/.dripfeed/config.ini" && grep -q "^SYSTEM_SHORTCUTS_DIR=\"_Dripfeed New\"" "$CN/Scripts/.dripfeed/config.ini" && grep -q "^POST_REVEAL_CMD=\"\"" "$CN/Scripts/.dripfeed/config.ini" && grep -q "^TOUCH_ON_REVEAL=1" "$CN/Scripts/.dripfeed/config.ini" && [ "$(lib "$CN" "echo \"\$SYSTEM_SHORTCUTS|\$SYSTEM_SHORTCUTS_DIR|\$POST_REVEAL_CMD|\$TOUCH_ON_REVEAL\"")" = "0|_Dripfeed New||1" ]'
printf 'SYSTEM_SHORTCUTS = 1\nSHOWCASE_KEEP=2\n' >> "$CN/Scripts/.dripfeed/config.ini"
for g in "Alpha" "Bravo" "Charlie"; do echo "$g" > "$CN/games/SNES/$g.sfc"; sch "$CN" add SNES today "$CN/games/SNES/$g.sfc" >/dev/null 2>&1; done
echo s > "$CN/games/GENESIS/Sonic Test.md"; sch "$CN" add GENESIS today "$CN/games/GENESIS/Sonic Test.md" >/dev/null 2>&1
eng "$CN" --auto >/dev/null 2>&1
SD="_Dripfeed New"
chk "SYSTEM_SHORTCUTS=1: shortcut in games/<SYS>/_Dripfeed New, named without the system prefix" '[ -f "$CN/games/GENESIS/$SD/Sonic Test.mgl" ] && ! ls "$CN/games/GENESIS/$SD" "$CN/games/SNES/$SD" | grep -q " - " && grep -q "path=\"$CN/games/GENESIS/Sonic Test.md\"" "$CN/games/GENESIS/$SD/Sonic Test.mgl"'
chk "each system shortcut folder keeps SHOWCASE_KEEP, with no gamelist.xml" '[ "$(ls "$CN/games/SNES/$SD" | wc -l | tr -d " ")" -eq 2 ] && [ ! -e "$CN/games/SNES/$SD/gamelist.xml" ]'
printf '2099-01-01\tSNES\t_Dripfeed New\n' > "$CN/Scripts/.dripfeed/schedule-requests.tsv"; eng "$CN" --auto >/dev/null 2>&1
NOUT="$(sch "$CN" add SNES 2099-01-01 "$CN/games/SNES/$SD" 2>&1)"
chk "the shortcut folder is never scheduled (browser request or CLI)" '[ -d "$CN/games/SNES/$SD" ] && [ ! -e "$CN/.dripfeed-library/SNES/2099-01-01_$SD" ] && printf "%s\n" "$NOUT" | grep -q "shortcut folder"'
sed_in_place 's/^SYSTEM_SHORTCUTS = 1$/SYSTEM_SHORTCUTS = 0/' "$CN/Scripts/.dripfeed/config.ini"
eng "$CN" --auto >/dev/null 2>&1
chk "switching SYSTEM_SHORTCUTS off removes the folders on the next run (games untouched)" '[ ! -d "$CN/games/SNES/$SD" ] && [ ! -d "$CN/games/GENESIS/$SD" ] && [ -f "$CN/games/SNES/Alpha.sfc" ] && [ -f "$CN/games/GENESIS/Sonic Test.md" ]'
sed_in_place 's/^SYSTEM_SHORTCUTS = 0$/SYSTEM_SHORTCUTS = 1/' "$CN/Scripts/.dripfeed/config.ini"
eng "$CN" --auto >/dev/null 2>&1
SC_N="$(ls "$CN/$(cat "$CN/Scripts/.dripfeed/showcase_name")"/*.mgl | wc -l | tr -d ' ')"
chk "switching it on again backfills from What's New" '[ "$(ls "$CN"/games/*/"$SD"/*.mgl 2>/dev/null | wc -l | tr -d " ")" -eq "$SC_N" ] && [ "$SC_N" -gt 0 ]'
eng "$CN" --undrip >/dev/null 2>&1
chk "Undrip removes the per-system shortcut folders" '[ -z "$(ls -d "$CN"/games/*/"$SD" 2>/dev/null)" ] && [ -f "$CN/games/SNES/Charlie.sfc" ]'

echo "== SYSTEM_SHORTCUTS also mirrors GOT'eM picks into their system folder =="
newcard CG; mkdir -p "$CG/games/SNES" "$CG/games/NES" "$CG/_Arcade/cores"
G="_Game of the Month"; GREC="$CG/Scripts/.dripfeed/gotm_system_shortcuts"
echo p > "$CG/games/SNES/Pick One.sfc"; echo q > "$CG/games/NES/Pick Two.nes"
printf '%s\tgames/SNES/Pick One.sfc\n' "$MONTH_NOW" > "$CG/Scripts/.dripfeed/gotm.tsv"
eng "$CG" --gotm >/dev/null 2>&1
chk "SYSTEM_SHORTCUTS=0 (default): GOT'eM stays a top-level folder only" '[ -f "$CG/$G/SNES - Pick One.mgl" ] && [ ! -e "$CG/games/SNES/$G" ]'
printf 'SYSTEM_SHORTCUTS=1\n' >> "$CG/Scripts/.dripfeed/config.ini"
eng "$CG" --gotm >/dev/null 2>&1
chk "switching it on backfills this month's pick without waiting for a new month" '[ -f "$CG/games/SNES/$G/Pick One.mgl" ] && grep -q "path=\"$CG/games/SNES/Pick One.sfc\"" "$CG/games/SNES/$G/Pick One.mgl" && grep -qF "$CG/games/SNES/$G/Pick One.mgl" "$GREC"'
printf '%s\tgames/NES/Pick Two.nes\tFamily Pick\n' "$MONTH_NOW" > "$CG/Scripts/.dripfeed/gotm.tsv"
eng "$CG" --gotm >/dev/null 2>&1
chk "a new pick replaces the old system shortcut (and its emptied folder); a custom label names it" '[ ! -e "$CG/games/SNES/$G" ] && [ -f "$CG/games/NES/$G/Family Pick.mgl" ] && [ -f "$CG/games/SNES/Pick One.sfc" ]'
echo '<misterromdescription><rbf>testcore</rbf></misterromdescription>' > "$CG/_Arcade/Arc Pick.mra"; echo c > "$CG/_Arcade/cores/testcore_20240101.rbf"
printf '%s\t_Arcade/Arc Pick.mra\n' "$MONTH_NOW" > "$CG/Scripts/.dripfeed/gotm.tsv"
eng "$CG" --gotm >/dev/null 2>&1
chk "an arcade pick has no system folder: none is made, and the previous console shortcut is removed" '[ -f "$CG/$G/Arc Pick.mra" ] && [ -z "$(ls -d "$CG"/games/*/"$G" 2>/dev/null)" ]'
mkdir -p "$CG/games/SNES/$G"; printf 'mine\n' > "$CG/games/SNES/$G/Keep Me.mgl"; echo k > "$CG/games/SNES/Keep Me.sfc"
printf '%s\tgames/SNES/Keep Me.sfc\n' "$MONTH_NOW" > "$CG/Scripts/.dripfeed/gotm.tsv"
eng "$CG" --gotm >/dev/null 2>&1
chk "a same-named file Dripfeed did not write is never replaced or recorded" '[ "$(cat "$CG/games/SNES/$G/Keep Me.mgl")" = mine ] && ! grep -qF "Keep Me.mgl" "$GREC" 2>/dev/null && [ -f "$CG/$G/SNES - Keep Me.mgl" ]'
printf '%s\tgames/NES/Pick Two.nes\n' "$MONTH_NOW" > "$CG/Scripts/.dripfeed/gotm.tsv"
printf '%s\tgames/SNES/Pick One.sfc\n' "$MONTH_NOW" > "$CG/community.tsv"; printf 'GOTM_SOURCE=%s\n' "$CG/community.tsv" >> "$CG/Scripts/.dripfeed/config.ini"
eng "$CG" --gotm >/dev/null 2>&1
chk "the community pick gets its own folder name in its system folder" '[ -f "$CG/games/NES/$G/Pick Two.mgl" ] && [ -f "$CG/games/SNES/_Discord GOTM/Pick One.mgl" ]'
GOUT="$(sch "$CG" add NES 2099-01-01 "$CG/games/NES/$G" 2>&1)"
printf '2099-01-01\tNES\t%s\n' "$G" > "$CG/Scripts/.dripfeed/schedule-requests.tsv"; eng "$CG" --auto >/dev/null 2>&1
chk "a GOT'eM system folder is never scheduled (browser request or CLI)" '[ -f "$CG/games/NES/$G/Pick Two.mgl" ] && [ ! -e "$CG/.dripfeed-library/NES/2099-01-01_$G" ] && printf "%s\n" "$GOUT" | grep -q "shortcut folder"'
sed_in_place 's/^SYSTEM_SHORTCUTS=1$/SYSTEM_SHORTCUTS=0/' "$CG/Scripts/.dripfeed/config.ini"
eng "$CG" --auto >/dev/null 2>&1
chk "switching SYSTEM_SHORTCUTS off removes Dripfeed's GOT'eM shortcuts only (top-level GOT'eM and user files stay)" '[ ! -e "$CG/games/NES/$G" ] && [ ! -e "$CG/games/SNES/_Discord GOTM" ] && [ "$(cat "$CG/games/SNES/$G/Keep Me.mgl")" = mine ] && [ -d "$CG/$G" ] && [ ! -e "$GREC" ]'
sed_in_place 's/^SYSTEM_SHORTCUTS=0$/SYSTEM_SHORTCUTS=1/' "$CG/Scripts/.dripfeed/config.ini"
eng "$CG" --auto >/dev/null 2>&1
chk "switching it on again restores them on the next pass" '[ -f "$CG/games/NES/$G/Pick Two.mgl" ] && [ -f "$CG/games/SNES/_Discord GOTM/Pick One.mgl" ]'
eng "$CG" --undrip >/dev/null 2>&1
chk "Undrip removes GOT'eM system shortcuts and leaves games and the user's file" '[ ! -e "$CG/games/NES/$G" ] && [ ! -e "$CG/games/SNES/_Discord GOTM" ] && [ "$(cat "$CG/games/SNES/$G/Keep Me.mgl")" = mine ] && [ -f "$CG/games/NES/Pick Two.nes" ] && [ -f "$CG/games/SNES/Pick One.sfc" ]'

echo "== GOT'eM folder renames, month tags and switches keep both folders in step =="
newcard CR; mkdir -p "$CR/games/NES"; RC="$CR/Scripts/.dripfeed/config.ini"; RREC="$CR/Scripts/.dripfeed/gotm_system_shortcuts"
echo q > "$CR/games/NES/Pick Two.nes"; printf '%s\tgames/NES/Pick Two.nes\n' "$MONTH_NOW" > "$CR/Scripts/.dripfeed/gotm.tsv"
printf 'SYSTEM_SHORTCUTS=1\nGOTM_DIRNAME="_Old Picks"\n' >> "$RC"
eng "$CR" --gotm >/dev/null 2>&1
sed_in_place 's/^GOTM_DIRNAME="_Old Picks"$/GOTM_DIRNAME="_New Picks"/' "$RC"
ROUT="$(sch "$CR" add NES 2099-01-01 "$CR/games/NES/_Old Picks" 2>&1)"
chk "right after a rename the old system folder is still never scheduled" '[ -f "$CR/games/NES/_Old Picks/Pick Two.mgl" ] && printf "%s\n" "$ROUT" | grep -q "shortcut folder" && [ ! -e "$CR/.dripfeed-library/NES/2099-01-01__Old Picks" ]'
eng "$CR" --gotm >/dev/null 2>&1
chk "renaming the GOT'eM folder moves the menu folder and its system shortcut together" '[ ! -e "$CR/_Old Picks" ] && [ ! -e "$CR/games/NES/_Old Picks" ] && [ -f "$CR/_New Picks/NES - Pick Two.mgl" ] && [ -f "$CR/games/NES/_New Picks/Pick Two.mgl" ] && ! grep -q "_Old Picks" "$RREC"'
printf 'GOTM_MONTH=1\nSHOWCASE_MAXLEN=12\n' >> "$RC"
eng "$CR" --gotm >/dev/null 2>&1
chk "a month tag cut short by SHOWCASE_MAXLEN (\"<name> -\") is built in step and still guarded" '[ -f "$CR/_New Picks -/NES - Pick Two.mgl" ] && [ -f "$CR/games/NES/_New Picks -/Pick Two.mgl" ] && [ ! -e "$CR/games/NES/_New Picks" ] && lib "$CR" "df_is_gotm_dir \"_New Picks -\""'
sed_in_place '/^SHOWCASE_MAXLEN=12$/d' "$RC"; printf 'GOTM=0\n' >> "$RC"
eng "$CR" --gotm >/dev/null 2>&1
chk "GOTM=0 leaves the GOT'eM menu folder and its system shortcut as they were (it stops building)" '[ -f "$CR/_New Picks -/NES - Pick Two.mgl" ] && [ -f "$CR/games/NES/_New Picks -/Pick Two.mgl" ]'
sed_in_place '/^GOTM=0$/d' "$RC"; printf 'GOTM_DIRNAME="_Picks #1"   # a quoted # is part of the name\n' >> "$RC"
eng "$CR" --gotm >/dev/null 2>&1
ROUT="$(sch "$CR" add NES 2099-01-01 "$CR/games/NES/_Picks #1 - $(date +%b)" 2>&1)"
chk "a GOT'eM name with # is built and guarded under its full name" '[ -f "$CR/games/NES/_Picks #1 - $(date +%b)/Pick Two.mgl" ] && [ -z "$(ls -d "$CR"/games/NES/_New* 2>/dev/null)" ] && [ -z "$(ls -d "$CR"/_New* 2>/dev/null)" ] && printf "%s\n" "$ROUT" | grep -q "shortcut folder"'

echo "== POST_REVEAL_CMD: once per pass that revealed games, with a timeout =="
newcard CQ; mkdir -p "$CQ/games/SNES" "$CQ/games/NES"
printf "POST_REVEAL_CMD = 'echo \"#\$DRIPFEED_REVEALED_COUNT \$DRIPFEED_REVEALED_SYSTEMS\" >> \"%s/post.out\"'\n" "$CQ" >> "$CQ/Scripts/.dripfeed/config.ini"
chk "a quoted command may contain # (it is not a comment there)" 'lib "$CQ" "printf %s \"\$POST_REVEAL_CMD\"" | grep -q "echo \"#"'
eng "$CQ" --auto >/dev/null 2>&1
chk "not run on a pass that revealed nothing" '[ ! -e "$CQ/post.out" ]'
echo a > "$CQ/games/SNES/One.sfc"; echo b > "$CQ/games/NES/Two.nes"
sch "$CQ" add SNES today "$CQ/games/SNES/One.sfc" >/dev/null 2>&1; sch "$CQ" add NES today "$CQ/games/NES/Two.nes" >/dev/null 2>&1
eng "$CQ" --auto >/dev/null 2>&1
chk "run exactly once at the end of a pass that revealed games; exit status logged" '[ "$(wc -l < "$CQ/post.out" | tr -d " ")" = 1 ] && grep -Eq "^#2 (NES SNES|SNES NES)$" "$CQ/post.out" && grep -q "POST_REVEAL_CMD exit status 0" "$CQ/Scripts/.dripfeed/dripfeed.log"'
echo c > "$CQ/games/SNES/Three.sfc"; sch "$CQ" add SNES today "$CQ/games/SNES/Three.sfc" >/dev/null 2>&1
DRIPFEED_ROOT="$CQ" sh "$CQ/linux/user-startup.sh" stop >/dev/null 2>&1; sleep 1
chk "never run from the shutdown hook" '[ "$(wc -l < "$CQ/post.out" | tr -d " ")" = 1 ] && [ ! -e "$CQ/games/SNES/Three.sfc" ]'
printf 'POST_REVEAL_CMD="sleep 5"\n' >> "$CQ/Scripts/.dripfeed/config.ini"
DRIPFEED_POST_REVEAL_TIMEOUT=1 eng "$CQ" --auto >/dev/null 2>&1
chk "a slow command is stopped by the timeout and logged" 'grep -q "POST_REVEAL_CMD timed out after 1s" "$CQ/Scripts/.dripfeed/dripfeed.log" && [ -f "$CQ/games/SNES/Three.sfc" ]'

echo "== TOUCH_ON_REVEAL: the reveal time becomes the file date; contents unchanged =="
newcard CT; mkdir -p "$CT/games/SNES" "$CT/games/PSX/Old Set"
printf 'precious bytes\001\002\n' > "$CT/games/SNES/Old Stamp.sfc"; cp "$CT/games/SNES/Old Stamp.sfc" "$CT/reference.sfc"
echo disc > "$CT/games/PSX/Old Set/Disc 1.chd"; printf 'Disc 1.chd\n' > "$CT/games/PSX/Old Set/Old Set.m3u"
touch -t 200001010000 "$CT/games/SNES/Old Stamp.sfc" "$CT/games/PSX/Old Set/Disc 1.chd" "$CT/games/PSX/Old Set/Old Set.m3u" "$CT/games/PSX/Old Set"
touch -t 200101010000 "$CT/marker-2001"
sch "$CT" add SNES today "$CT/games/SNES/Old Stamp.sfc" >/dev/null 2>&1; sch "$CT" add PSX today "$CT/games/PSX/Old Set" >/dev/null 2>&1
eng "$CT" --auto >/dev/null 2>&1
chk "revealed file is dated at the reveal, byte-for-byte unchanged" '[ "$CT/games/SNES/Old Stamp.sfc" -nt "$CT/marker-2001" ] && cmp -s "$CT/games/SNES/Old Stamp.sfc" "$CT/reference.sfc"'
chk "a revealed folder and its top-level files are dated at the reveal" '[ "$CT/games/PSX/Old Set" -nt "$CT/marker-2001" ] && [ "$CT/games/PSX/Old Set/Disc 1.chd" -nt "$CT/marker-2001" ] && [ "$CT/games/PSX/Old Set/Old Set.m3u" -nt "$CT/marker-2001" ]'
printf 'TOUCH_ON_REVEAL=0\n' >> "$CT/Scripts/.dripfeed/config.ini"
echo k > "$CT/games/SNES/Keep Stamp.sfc"; touch -t 200001010000 "$CT/games/SNES/Keep Stamp.sfc"
sch "$CT" add SNES today "$CT/games/SNES/Keep Stamp.sfc" >/dev/null 2>&1; eng "$CT" --auto >/dev/null 2>&1
chk "TOUCH_ON_REVEAL=0 keeps the original file date" '[ -f "$CT/games/SNES/Keep Stamp.sfc" ] && [ "$CT/marker-2001" -nt "$CT/games/SNES/Keep Stamp.sfc" ]'

echo "== console summary: neutral hint for graphical frontends =="
newcard CF; mkdir -p "$CF/games/SNES"; echo h > "$CF/games/SNES/Hint.sfc"
sch "$CF" add SNES today "$CF/games/SNES/Hint.sfc" >/dev/null 2>&1
HOUT="$(DRIPFEED_INTERACTIVE=1 eng "$CF" --reveal </dev/null 2>&1)"; HOUT2="$(DRIPFEED_INTERACTIVE=1 eng "$CF" --reveal </dev/null 2>&1)"
chk "after a pass that revealed games the summary adds the frontend refresh hint (and not otherwise)" 'printf "%s\n" "$HOUT" | grep -qF "Using a graphical frontend with its own game library? Refresh its library to see the new games." && ! printf "%s\n" "$HOUT2" | grep -qF "Refresh its library"'

echo "== review hardening: symlinks, bind mounts, user files, stuck commands =="
# mv as MiSTer ships it (coreutils 8.32: no --no-copy), so only the guard can stop a copy.
scratch MV832; printf '#!/bin/sh\nif [ "$1" = --help ]; then "%s" --help | grep -v -- --no-copy; exit 0; fi\nexec "%s" "$@"\n' "$(command -v mv)" "$(command -v mv)" > "$MV832/mv"; chmod +x "$MV832/mv"
# A system folder that is a SYMLINK to another drive must be judged by where it
# really lives (stat of the link itself reports the SD card, and mv would copy).
XSYM=""
if [ -d /dev/shm ] && [ -w /dev/shm ]; then
  XSYM="$(mktemp -d /dev/shm/dripfeed-sym.XXXXXX 2>/dev/null)"
  if [ -n "$XSYM" ] && [ "$(stat -c %d "$XSYM/." 2>/dev/null)" = "$(stat -c %d "$ROOT/." 2>/dev/null)" ]; then rm -rf "$XSYM"; XSYM=""; fi
fi
if [ -n "$XSYM" ]; then
  CARDS="$CARDS $XSYM"; newcard CY; ln -s "$XSYM" "$CY/games/SNES"
  mkdir -p "$CY/.dripfeed-library/SNES"; echo sym > "$CY/.dripfeed-library/SNES/${TODAY}_Symlinked.sfc"
  PATH="$MV832:$PATH" eng "$CY" --auto >/dev/null 2>&1
  chk "a system folder symlinked to another drive is held (never copied through the link)" '[ -f "$CY/.dripfeed-library/SNES/${TODAY}_Symlinked.sfc" ] && [ ! -e "$XSYM/Symlinked.sfc" ] && grep -q "CROSS-DEVICE HOLD" "$CY/Scripts/.dripfeed/dripfeed.log"'
  newcard CY2; mkdir -p "$CY2/real-SNES"; ln -s "$CY2/real-SNES" "$CY2/games/SNES"
  mkdir -p "$CY2/.dripfeed-library/SNES"; echo same > "$CY2/.dripfeed-library/SNES/${TODAY}_Same Card Link.sfc"
  INO_L="$(inode "$CY2/.dripfeed-library/SNES/${TODAY}_Same Card Link.sfc")"
  PATH="$MV832:$PATH" eng "$CY2" --auto >/dev/null 2>&1
  chk "a system folder symlinked within the same card still reveals by rename" '[ -f "$CY2/real-SNES/Same Card Link.sfc" ] && [ "$(inode "$CY2/real-SNES/Same Card Link.sfc")" = "$INO_L" ]'
else
  echo "  skip - no second filesystem for the symlink check"
fi
# Two mounts of the SAME filesystem (a bind mount): rename(2) fails there too and
# mv would copy, so the move is held. Runs only where a private mount namespace
# can be made (root on Linux); nothing leaks into the host's mounts.
if command -v unshare >/dev/null 2>&1 && unshare -m true 2>/dev/null; then
  newcard CBM; mkdir -p "$CBM/bind-src/SNES" "$CBM/games/SNES" "$CBM/.dripfeed-library/SNES"
  echo bm > "$CBM/.dripfeed-library/SNES/${TODAY}_Bind Held.sfc"
  echo in > "$CBM/bind-src/SNES/Inside.sfc"
  PATH="$MV832:$PATH" unshare -m bash -c 'mount --bind "$1/bind-src/SNES" "$1/games/SNES" && DRIPFEED_ROOT="$1" bash "$1/Scripts/.dripfeed/dripfeed-engine.sh" --auto' _ "$CBM" >/dev/null 2>&1
  chk "a bind-mounted system folder on the same drive is held (rename cannot cross mounts)" '[ -f "$CBM/.dripfeed-library/SNES/${TODAY}_Bind Held.sfc" ] && [ ! -e "$CBM/bind-src/SNES/Bind Held.sfc" ] && grep -q "CROSS-DEVICE HOLD" "$CBM/Scripts/.dripfeed/dripfeed.log"'
  BOUT="$(PATH="$MV832:$PATH" unshare -m bash -c 'mount --bind "$1/bind-src/SNES" "$1/games/SNES" && DRIPFEED_ROOT="$1" bash "$1/Scripts/.dripfeed/dripfeed-schedule.sh" add SNES 2099-01-01 "$1/games/SNES/Inside.sfc"' _ "$CBM" 2>&1)"
  chk "and scheduling out of a bind-mounted folder is held too (game untouched)" '[ -f "$CBM/bind-src/SNES/Inside.sfc" ] && [ ! -e "$CBM/.dripfeed-library/SNES/2099-01-01_Inside.sfc" ] && printf "%s\n" "$BOUT" | grep -q "different drive"'
else
  echo "  skip - cannot create a private mount namespace for the bind-mount check"
fi
# SYSTEM_SHORTCUTS_DIR naming a folder the user already has: only Dripfeed's own
# shortcuts are ever pruned or removed, never the user's files.
newcard CU; mkdir -p "$CU/games/SNES/Hacks"
printf '<mistergamedescription><rbf>_Console/SNES</rbf><file delay="2" type="f" index="0" path="%s/games/SNES/Gone Hack.sfc"/></mistergamedescription>\n' "$CU" > "$CU/games/SNES/Hacks/Old Hack.mgl"
printf '<mistergamedescription><rbf>_Console/SNES</rbf><file delay="2" type="f" index="0" path="%s/games/SNES/Hacks/My Hack.sfc"/></mistergamedescription>\n' "$CU" > "$CU/games/SNES/Hacks/My Hack.mgl"
echo hack > "$CU/games/SNES/Hacks/My Hack.sfc"; echo '<gameList/>' > "$CU/games/SNES/Hacks/gamelist.xml"
touch -t 200001010000 "$CU/games/SNES/Hacks/Old Hack.mgl" "$CU/games/SNES/Hacks/My Hack.mgl"
printf 'SYSTEM_SHORTCUTS=1\nSYSTEM_SHORTCUTS_DIR="Hacks"\nSHOWCASE_KEEP=1\n' >> "$CU/Scripts/.dripfeed/config.ini"
for g in "Uno" "Dos"; do echo "$g" > "$CU/games/SNES/$g.sfc"; sch "$CU" add SNES today "$CU/games/SNES/$g.sfc" >/dev/null 2>&1; done
eng "$CU" --auto >/dev/null 2>&1
chk "SYSTEM_SHORTCUTS pruning never touches the user's own files in that folder" '[ -f "$CU/games/SNES/Hacks/Old Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/My Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/gamelist.xml" ] && [ -f "$CU/games/SNES/Hacks/My Hack.sfc" ] && [ "$(ls "$CU/games/SNES/Hacks" | grep -c -e "^Uno.mgl$" -e "^Dos.mgl$")" = 1 ]'
sed_in_place 's/^SYSTEM_SHORTCUTS=1$/SYSTEM_SHORTCUTS=0/' "$CU/Scripts/.dripfeed/config.ini"
eng "$CU" --auto >/dev/null 2>&1
chk "switching it off removes only Dripfeed's shortcuts; the user's folder and files stay" '[ -f "$CU/games/SNES/Hacks/Old Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/My Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/gamelist.xml" ] && [ ! -e "$CU/games/SNES/Hacks/Uno.mgl" ] && [ ! -e "$CU/games/SNES/Hacks/Dos.mgl" ]'
sed_in_place 's/^SYSTEM_SHORTCUTS=0$/SYSTEM_SHORTCUTS=1/' "$CU/Scripts/.dripfeed/config.ini"
eng "$CU" --auto >/dev/null 2>&1; eng "$CU" --undrip >/dev/null 2>&1
chk "Undrip leaves the user's files in a shared shortcut folder name" '[ -f "$CU/games/SNES/Hacks/Old Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/My Hack.mgl" ] && [ -f "$CU/games/SNES/Hacks/gamelist.xml" ] && [ -z "$(ls "$CU/games/SNES/Hacks" | grep -e "^Uno.mgl$" -e "^Dos.mgl$")" ]'
# A command that ignores TERM is killed, so it can never hang the pass.
newcard CK; mkdir -p "$CK/games/SNES"; echo k > "$CK/games/SNES/Stuck.sfc"
sch "$CK" add SNES today "$CK/games/SNES/Stuck.sfc" >/dev/null 2>&1
printf "POST_REVEAL_CMD='trap \"\" TERM; sleep 60'\n" >> "$CK/Scripts/.dripfeed/config.ini"
T0="$(date +%s)"; DRIPFEED_POST_REVEAL_TIMEOUT=1 eng "$CK" --auto >/dev/null 2>&1; T1="$(date +%s)"
chk "a POST_REVEAL_CMD that ignores TERM is killed (the pass ends in seconds)" '[ $((T1 - T0)) -lt 20 ] && grep -q "POST_REVEAL_CMD timed out" "$CK/Scripts/.dripfeed/dripfeed.log" && [ -f "$CK/games/SNES/Stuck.sfc" ]'
# Undrip only signals the boot watcher, never a process that reused its pid.
if [ -r /proc/self/cmdline ] && [ -r /proc/sys/kernel/random/boot_id ]; then
  newcard CV; sleep 30 & VPID=$!; KILLS="$KILLS $VPID"
  printf '%s\n%s\n' "$VPID" "$(cat /proc/sys/kernel/random/boot_id)" > "$CV/Scripts/.dripfeed/watch.pid"
  eng "$CV" --undrip >/dev/null 2>&1
  chk "Undrip never kills an unrelated process that reused the watcher's pid" 'kill -0 "$VPID" 2>/dev/null'
  kill "$VPID" 2>/dev/null; wait "$VPID" 2>/dev/null
fi
# A malformed browser request can never name a parent folder or a queue folder.
newcard CR; mkdir -p "$CR/games/SNES/.dripfeed"; echo q > "$CR/games/SNES/.dripfeed/2099-01-01_Legacy.sfc"
printf '2099-01-01\t..\tScripts\n2099-01-01\tSNES\t..\n2099-01-01\tSNES\t.dripfeed\n' > "$CR/Scripts/.dripfeed/schedule-requests.tsv"
printf '..\tScripts\n' > "$CR/Scripts/.dripfeed/unschedule-requests.tsv"
eng "$CR" --auto >/dev/null 2>&1
chk "requests naming .. or the legacy queue folder are ignored (nothing moved)" '[ -f "$CR/Scripts/.dripfeed/dripfeed-engine.sh" ] && [ -d "$CR/games/SNES" ] && [ -z "$(ls -A "$CR/.dripfeed-library" 2>/dev/null | grep -v "^SNES$")" ] && [ -z "$(ls "$CR" | grep "^2099")" ] && [ -f "$CR/.dripfeed-library/SNES/2099-01-01_Legacy.sfc" ]'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
