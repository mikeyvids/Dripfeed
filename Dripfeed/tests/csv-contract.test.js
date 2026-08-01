// Dripfeed for MiSTer FPGA — GPL-3.0-or-later
// Copyright (C) 2026 MikeyVids. See ../LICENSE and ../CREDITS.md.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const htmlPath = path.join(__dirname, "..", "Dripfeed-Scheduler.html");
const html = fs.readFileSync(htmlPath, "utf8");
const start = html.indexOf("function gotmCsvPath");
const end = html.indexOf("// ---------- File System Access ----------", start);
assert(start >= 0 && end > start, "GOT'eM path helpers must remain in the scheduler");

const context = {};
vm.runInNewContext(`${html.slice(start, end)}\nthis.contract={gotmCsvPath,gotmStatePath};`, context);
const { gotmCsvPath, gotmStatePath } = context.contract;

assert.strictEqual(gotmCsvPath("SNES/Game.sfc"), "SNES/Game.sfc");
assert.strictEqual(gotmCsvPath("games/SNES/Game.sfc"), "SNES/Game.sfc");
assert.strictEqual(gotmStatePath("SNES/Game.sfc"), "games/SNES/Game.sfc");
assert.strictEqual(gotmStatePath("games/SNES/Game.sfc"), "games/SNES/Game.sfc");
assert.strictEqual(gotmCsvPath("_Arcade/Game.mra"), "_Arcade/Game.mra");
assert.strictEqual(gotmStatePath("_Arcade/Game.mra"), "_Arcade/Game.mra");
assert(html.includes("resolvePath(row.path)"), "CSV Review must resolve the normalized GOT'eM path");
assert(html.includes("writeGotm(r.gotem, gotmStatePath(r.path)"), "CSV Apply must write MiSTer-state paths");
assert(html.includes("csvCell(gotmCsvPath(p))"), "CSV export must return canonical games-relative paths");

const csvStart = html.indexOf("function parseCsv");
const csvEnd = html.indexOf("// Resolve a games-relative path", csvStart);
const csvContext = {};
vm.runInNewContext(`function pad(n){return String(n).padStart(2,"0");}\n${html.slice(csvStart,csvEnd)}\nthis.contract={parseCsv,normMonth,normDate};`, csvContext);
const parsed = csvContext.contract.parseCsv('path,date,message\r\n"SNES/Game, Special.sfc",7/4/2027,"Happy, day"\r\n');
assert.strictEqual(parsed[1][0], "SNES/Game, Special.sfc");
assert.strictEqual(parsed[1][2], "Happy, day");
assert.strictEqual(csvContext.contract.normMonth("8/2027"), "2027-08");
assert.strictEqual(csvContext.contract.normMonth("2027-13"), null);
assert.strictEqual(csvContext.contract.normDate("2/29/2028"), "2028-02-29");
assert.strictEqual(csvContext.contract.normDate("2/29/2027"), null);

const guardStart = html.indexOf("const SYSFILE_DIRS");
const guardEnd = html.indexOf("async function inspectFolder", guardStart);
const guardContext = {};
vm.runInNewContext(`${html.slice(guardStart,guardEnd)}\nthis.contract={isFirmwareOrSupportFile,isPlayableFile,isSystemFile};`, guardContext);
const guards = guardContext.contract;
assert.strictEqual(guards.isFirmwareOrSupportFile("cd_bios.rom"), true);
assert.strictEqual(guards.isFirmwareOrSupportFile("Doom.mrq"), true);
assert.strictEqual(guards.isPlayableFile("Night Trap.chd"), true);
assert.strictEqual(guards.isPlayableFile("cd_bios.rom"), false);
assert.strictEqual(guards.isSystemFile("media", "directory"), true);
assert.strictEqual(guards.isSystemFile("Night Trap", "directory"), false);

assert(html.includes('role="tablist"'), "Scheduler sections must expose a keyboard-accessible tab list");
assert(html.includes('type="button" class="${cls}"'), "Calendar dates must render as buttons");

console.log("Dripfeed CSV/GOT'eM path contract: all tests passed");
