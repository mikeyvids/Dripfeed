// Dripfeed for MiSTer FPGA — GPL-3.0-or-later
// Copyright (C) 2026 MikeyVids. See ../LICENSE and ../CREDITS.md.
//
// Browser-logic tests for Dripfeed-Scheduler.html. The scheduler's own source is
// sliced out of the page (as csv-contract.test.js does) and run in a vm context
// against small in-memory stand-ins for the File System Access handles, so these
// tests exercise exactly the code the browser runs. No card, ROM or network.
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "..", "Dripfeed-Scheduler.html"), "utf8");
const scriptStart = html.indexOf("<script>"), scriptEnd = html.indexOf("</script>", scriptStart);
const script = html.slice(scriptStart, scriptEnd);
function slice(from, to) {
  const a = html.indexOf(from), b = html.indexOf(to, a + 1);
  assert(a >= 0 && b > a, `scheduler section markers moved: ${from} .. ${to}`);
  return html.slice(a, b);
}
const tests = [];
const test = (name, fn) => tests.push([name, fn]);

// ---------------------------------------------------------------------------
// In-memory File System Access stand-ins (Chromium semantics where it matters:
// file handles have move(); directory handles do not).
// ---------------------------------------------------------------------------
function domErr(name, message) { const e = new Error(message || name); e.name = name; return e; }
const tick = () => new Promise(r => setTimeout(r, 1));
function makeFs(opts = {}) {
  const io = { createWritable: 0, writes: 0, getFile: 0, moves: 0, removes: 0, entries: 0, created: 0 };
  class FileH {
    constructor(dir, name) { this.kind = "file"; this.dir = dir; this.name = name;
      if (opts.moveMode !== "absent") this.move = this._move; }
    async getFile() {
      io.getFile++; await tick();
      const fail = opts.failRead && opts.failRead(this.name);
      if (fail) throw domErr(fail, "simulated read failure");
      if (!this.dir.files.has(this.name)) throw domErr("NotFoundError");
      const data = this.dir.files.get(this.name);
      return { size: Buffer.byteLength(data), text: async () => data, stream() { throw new Error("game data must never be streamed"); } };
    }
    async createWritable() {
      io.createWritable++;
      let buf = ""; const dir = this.dir, name = this.name;
      return { write: async d => { io.writes++; await tick(); buf += d; }, close: async () => { await tick(); dir.files.set(name, buf); } };
    }
    async _move(destDir, newName) {
      io.moves++;
      if (opts.moveMode === "throw") throw domErr("NoModificationAllowedError", "simulated sharing violation (file open in another program)");
      if (destDir.files.has(newName) || destDir.dirs.has(newName)) throw domErr("InvalidModificationError");
      destDir.files.set(newName, this.dir.files.get(this.name)); this.dir.files.delete(this.name);
      this.dir = destDir; this.name = newName;
    }
  }
  class DirH {
    constructor(name) { this.kind = "directory"; this.name = name; this.files = new Map(); this.dirs = new Map(); }
    async getFileHandle(name, o = {}) {
      if (opts.failLookup) throw domErr(opts.failLookup);
      if (this.dirs.has(name)) throw domErr("TypeMismatchError");
      if (!this.files.has(name)) { if (!o.create) throw domErr("NotFoundError"); io.created++; this.files.set(name, ""); }
      return new FileH(this, name);
    }
    async getDirectoryHandle(name, o = {}) {
      if (opts.failLookup) throw domErr(opts.failLookup);
      if (this.files.has(name)) throw domErr("TypeMismatchError");
      if (!this.dirs.has(name)) { if (!o.create) throw domErr("NotFoundError"); this.dirs.set(name, new DirH(name)); }
      return this.dirs.get(name);
    }
    async removeEntry(name) { io.removes++; if (!this.files.delete(name) && !this.dirs.delete(name)) throw domErr("NotFoundError"); }
    async *entries() {
      for (const [n, d] of this.dirs) { io.entries++; yield [n, d]; }
      for (const n of this.files.keys()) { io.entries++; yield [n, new FileH(this, n)]; }
    }
    // Chromium 141: FileSystemDirectoryHandle has no move().
  }
  return { DirH, FileH, io };
}

// ---------------------------------------------------------------------------
// Load the scheduler's File System Access + state-ledger section.
// ---------------------------------------------------------------------------
function loadFsSection() {
  const ctx = { console, Promise, Error, Map, Set, JSON, Object, String, Array, setTimeout };
  vm.runInNewContext(`
    const DATE_RE=/^\\d{4}-\\d{2}-\\d{2}_/;
    let STAGE=".dripfeed", stageRoot=null, stateDir=null, stateIsConsole=false, revealedKeys=new Set();
    const keyOf=(s,n)=>s+String.fromCharCode(31)+n;
    ${slice("// ---------- File System Access ----------", "// ---------- connection-loss recovery")}
    this.api={moveFile,moveDir,moveStopsBatch,mergeMoveRequests,applyMoveRequests,requestSchedule,requestUnschedule,
      cancelScheduleRequest,readMoveRequests,writeOccasions,writeOccasion,readOccasions,
      set:o=>{if("stateDir" in o)stateDir=o.stateDir;if("stateIsConsole" in o)stateIsConsole=o.stateIsConsole;}};`, ctx,
    { filename: "Dripfeed-Scheduler.fs-section.js" });
  return ctx.api;
}
function loadIcsSection() {
  const ctx = {};
  vm.runInNewContext(`function pad(n){return String(n).padStart(2,"0");}
    ${slice("// ---------- export .ics ----------", "async function exportIcs")}
    this.api={buildIcs,icsFold,icsEscape,icsUid,icsSequence,icsStamp,stableHash};`, ctx,
    { filename: "Dripfeed-Scheduler.ics-section.js" });
  return ctx.api;
}
function loadGuards() {
  const ctx = { Promise, Set };
  vm.runInNewContext(`${slice("let showSysFiles=false;", "// Scan one system into a NEW array")}
    this.api={isPlayableFile,isSystemFile,inspectFolder,classifyEntry,INSPECT_BUDGET,setShortcutDir:v=>{SYS_SHORTCUTS_DIR=v;}};`, ctx, { filename: "Dripfeed-Scheduler.guards.js" });
  return ctx.api;
}
const ledgerText = (dir, name) => dir.files.has(name) ? dir.files.get(name) : null;
const ledgerRows = (dir, name) => (ledgerText(dir, name) || "").split("\n").filter(Boolean);

// ===========================================================================
// ICS builder
// ===========================================================================
const ics = loadIcsSection();
const NOW = new Date(Date.UTC(2026, 9, 9, 12, 34, 56));
const unfold = t => t.replace(/\r\n /g, "");
const events = t => unfold(t).split("BEGIN:VEVENT").slice(1).map(e => e.split("END:VEVENT")[0]);
const prop = (ev, key) => { const m = ev.match(new RegExp("\\r\\n" + key + "[:;]([^\\r]*)")); return m ? m[1] : null; };
const sampleItems = [
  { date: "2027-01-10", sys: "NES", clean: "Shiny Forts.nes" },
  { date: "2027-02-14", sys: "PSX", clean: "Shiny Forts III (Disc Set)" },
  { date: "2027-02-14", sys: "SNES", clean: "Forts, Moats; and \\Walls.sfc" },
];

test("ics: UID is stable for a game across re-dating and reordering", () => {
  const a = ics.buildIcs(sampleItems, {}, { now: NOW }).text;
  const moved = [sampleItems[2], { ...sampleItems[0], date: "2027-03-01" }, sampleItems[1]];
  const b = ics.buildIcs(moved, {}, { now: new Date(NOW.getTime() + 3600e3) }).text;
  const uidsBy = t => Object.fromEntries(events(t).map(e => [prop(e, "SUMMARY"), prop(e, "UID")]));
  assert.deepStrictEqual(uidsBy(a), uidsBy(b));
  const nes = events(b).find(e => prop(e, "SUMMARY").includes("Shiny Forts.nes"));
  assert.strictEqual(prop(nes, "DTSTART"), "VALUE=DATE:20270301");
  for (const e of events(a)) assert.match(prop(e, "UID"), /^dripfeed-[A-Za-z0-9._-]+-[0-9a-f]{14}@dripfeed$/);
  assert.strictEqual(ics.icsUid("NES", "Shiny Forts.nes"), ics.icsUid("NES", "Shiny Forts.nes"));
  assert.notStrictEqual(ics.icsUid("NES", "Shiny Forts.nes"), ics.icsUid("SNES", "Shiny Forts.nes"));
  assert.match(ics.icsUid("NES", "x"), /^dripfeed-NES-/);
  // NFC and NFD spellings of the same name are the same game.
  assert.strictEqual(ics.icsUid("PSX", "Pokémon"), ics.icsUid("PSX", "Pokémon"));
  // A system name that needs cleaning still yields a valid, distinct UID.
  assert.match(ics.icsUid("Game Boy", "x"), /^dripfeed-Game_Boy\.[0-9a-f]{6}-[0-9a-f]{14}@dripfeed$/);
  assert.notStrictEqual(ics.icsUid("Game Boy", "x"), ics.icsUid("Game_Boy", "x"));
});

test("ics: UIDs do not collide across a large library", () => {
  const seen = new Set();
  for (let i = 0; i < 50000; i++) seen.add(ics.icsUid("NES", `Game Title Number ${i} (USA).nes`));
  assert.strictEqual(seen.size, 50000);
});

test("ics: output never depends on input order; a duplicate game keeps its earliest date", () => {
  const dup = [...sampleItems, { date: "2026-12-01", sys: "NES", clean: "Shiny Forts.nes" }];
  const a = ics.buildIcs(dup, {}, { now: NOW }), b = ics.buildIcs(dup.slice().reverse(), {}, { now: NOW });
  assert.strictEqual(a.text, b.text);
  assert.strictEqual(a.count, 3);
  const nes = events(a.text).filter(e => prop(e, "SUMMARY").includes("Shiny Forts.nes"));
  assert.strictEqual(nes.length, 1);
  assert.strictEqual(prop(nes[0], "DTSTART"), "VALUE=DATE:20261201");
});

test("ics: SEQUENCE rises with every later export; DTSTAMP is the export time in UTC", () => {
  assert.strictEqual(ics.icsSequence(new Date(Date.UTC(2026, 0, 1))), 0);
  assert.strictEqual(ics.icsSequence(new Date(Date.UTC(2025, 5, 1))), 0);
  const s1 = ics.icsSequence(NOW), s2 = ics.icsSequence(new Date(NOW.getTime() + 60e3)), s3 = ics.icsSequence(new Date(NOW.getTime() + 86400e3));
  assert.strictEqual(s1, Math.floor((NOW - Date.UTC(2026, 0, 1)) / 60000));
  assert(s2 > s1 && s3 > s2, "SEQUENCE must increase");
  assert(Number.isSafeInteger(ics.icsSequence(new Date(Date.UTC(2999, 0, 1)))) && ics.icsSequence(new Date(Date.UTC(2999, 0, 1))) < 2 ** 31);
  const t = ics.buildIcs(sampleItems, {}, { now: NOW }).text;
  for (const e of events(t)) {
    assert.strictEqual(prop(e, "SEQUENCE"), String(s1));
    assert.strictEqual(prop(e, "DTSTAMP"), "20261009T123456Z");
  }
  const later = ics.buildIcs(sampleItems, {}, { now: new Date(NOW.getTime() + 5 * 60e3) }).text;
  assert(Number(prop(events(later)[0], "SEQUENCE")) > s1);
});

test("ics: RFC 5545 escaping of backslash, comma, semicolon and newlines", () => {
  assert.strictEqual(ics.icsEscape("a\\b,c;d\ne\r\nf\rg"), "a\\\\b\\,c\\;d\\ne\\nf\\ng");
  // Control characters other than HTAB are not allowed in TEXT values.
  assert.strictEqual(ics.icsEscape("a\x00b\x1fc\x7fd\te"), "abcd\te");
  const t = ics.buildIcs(sampleItems, { "2027-02-14": "Happy, day;\nsee you" }, { now: NOW }).text;
  const snes = events(t).find(e => prop(e, "SUMMARY").includes("Walls"));
  assert.strictEqual(prop(snes, "SUMMARY"), "🎮 Forts\\, Moats\\; and \\\\Walls.sfc (SNES)");
  assert(prop(snes, "DESCRIPTION").startsWith("Happy\\, day\\;\\nsee you\\n\\nSystem: SNES"));
  assert(!/[^\r]\n|\r[^\n]/.test(t), "only CRLF line breaks");
});

test("ics: lines fold at 75 octets with CRLF + space and never split a UTF-8 character", () => {
  const long = { date: "2027-05-25", sys: "Saturn", clean: "🎮🎮 Ünïcödé — " + "日本語のタイトル".repeat(12) + " (Disc 1).chd" };
  const t = ics.buildIcs([long], { "2027-05-25": "Ω".repeat(90) }, { now: NOW, alarm: true }).text;
  assert(t.endsWith("\r\n"));
  const lines = t.split("\r\n"); lines.pop();
  let continuations = 0;
  for (const l of lines) {
    assert(Buffer.byteLength(l, "utf8") <= 75, "line longer than 75 octets: " + l);
    assert(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(l), "split surrogate pair");
    if (l.startsWith(" ")) continuations++;
  }
  assert(continuations > 5, "long values must fold");
  assert(unfold(t).includes("SUMMARY:🎮 🎮🎮 Ünïcödé — " + "日本語のタイトル".repeat(12) + " (Disc 1).chd (Saturn)"));
  // Folding exactly at the limit: 75 ASCII octets stay on one line, 76 fold.
  assert.strictEqual(ics.icsFold("X".repeat(75)), "X".repeat(75));
  assert.strictEqual(ics.icsFold("X".repeat(76)), "X".repeat(75) + "\r\n X");
  // A 3-octet character that would straddle octet 75 moves whole to the next line.
  assert.strictEqual(ics.icsFold("X".repeat(73) + "語"), "X".repeat(73) + "\r\n 語");
});

test("ics: 9 AM alert is opt-in and is a DISPLAY alarm at PT9H on each all-day event", () => {
  const off = ics.buildIcs(sampleItems, {}, { now: NOW }).text;
  assert(!off.includes("VALARM"), "no alarm unless asked");
  const on = ics.buildIcs(sampleItems, {}, { now: NOW, alarm: true }).text;
  for (const e of events(on)) {
    assert.strictEqual((e.match(/BEGIN:VALARM/g) || []).length, 1);
    assert(/\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nDESCRIPTION:Unlocks today: [^\r]+\r\nTRIGGER:PT9H\r\nEND:VALARM\r\n$/.test(e), e);
    assert(/^VALUE=DATE:\d{8}$/.test(prop(e, "DTSTART")));
  }
  assert(/<input id="icsAlarm" type="checkbox">/.test(html), "alert checkbox must default to off");
  assert(html.includes("Add a 9 AM alert on the day"));
});

test("ics: all-day DTEND is the next calendar day across month, year and leap boundaries", () => {
  const t = ics.buildIcs([
    { date: "2026-12-31", sys: "A", clean: "a" }, { date: "2028-02-28", sys: "B", clean: "b" }, { date: "2027-02-28", sys: "C", clean: "c" },
  ], {}, { now: NOW }).text;
  const ends = Object.fromEntries(events(t).map(e => [prop(e, "DTSTART"), prop(e, "DTEND")]));
  assert.strictEqual(ends["VALUE=DATE:20261231"], "VALUE=DATE:20270101");
  assert.strictEqual(ends["VALUE=DATE:20280228"], "VALUE=DATE:20280229");
  assert.strictEqual(ends["VALUE=DATE:20270228"], "VALUE=DATE:20270301");
});

// ===========================================================================
// Request ledgers (whole-card mode)
// ===========================================================================
test("ledger merge: later rows win, schedule and return cancel each other, cancel adds no return", () => {
  const api = loadFsSection();
  const sOld = [{ date: "2027-01-01", sys: "NES", name: "A.nes" }, { date: "2027-01-01", sys: "NES", name: "B.nes" }];
  const uOld = [{ sys: "NES", name: "C.nes" }];
  const m = api.mergeMoveRequests(sOld, uOld, {
    schedule: [{ date: "2027-02-01", sys: "NES", name: "A.nes" }, { date: "2027-03-01", sys: "NES", name: "A.nes" }, { date: "2027-04-01", sys: "NES", name: "C.nes" }],
    unschedule: [{ sys: "NES", name: "B.nes" }],
    cancel: [{ sys: "NES", name: "Z.nes" }],
  });
  const plain = o => JSON.parse(JSON.stringify(o));
  assert.deepStrictEqual(plain(m.schedule), [{ date: "2027-03-01", sys: "NES", name: "A.nes" }, { date: "2027-04-01", sys: "NES", name: "C.nes" }]);
  assert.deepStrictEqual(plain(m.unschedule), [{ sys: "NES", name: "B.nes" }]);
  assert.deepStrictEqual(plain(m.rejected), []);
  const c = api.mergeMoveRequests(sOld, [], { cancel: [{ sys: "NES", name: "A.nes" }] });
  assert.deepStrictEqual(plain(c.schedule), [sOld[1]]);
  assert.deepStrictEqual(plain(c.unschedule), []);
  assert.strictEqual(c.unscheduleChanged, false);
  const same = api.mergeMoveRequests(sOld, uOld, {});
  assert.strictEqual(same.scheduleChanged || same.unscheduleChanged, false);
  const bad = api.mergeMoveRequests([], [], { schedule: [{ date: "2027-01-01", sys: "NES", name: "Bad\tName.nes" },
    { date: "1/2/2027", sys: "NES", name: "BadDate.nes" }, { date: "2027-01-01", sys: "NE/S", name: "x" },
    { date: "2027-01-01", sys: "NES", name: "Good.nes" }], unschedule: [{ sys: "NES", name: "Line\nBreak" }] });
  assert.deepStrictEqual(plain(bad.schedule), [{ date: "2027-01-01", sys: "NES", name: "Good.nes" }]);
  assert.strictEqual(bad.rejected.length, 4);
});

test("ledger: a 5,000-game batch is one read and ONE write, in TSV form", async () => {
  const api = loadFsSection(); const { DirH, io } = makeFs();
  const state = new DirH(".dripfeed"); api.set({ stateDir: state, stateIsConsole: true });
  const batch = []; for (let i = 0; i < 5000; i++) batch.push({ date: "2026-12-25", sys: "PSX", name: `Game ${i} (USA).chd` });
  const r = await api.applyMoveRequests({ schedule: batch });
  assert.strictEqual(r.rejected.length, 0);
  assert.strictEqual(io.createWritable, 1, "one ledger write for the whole batch");
  const rows = ledgerRows(state, "schedule-requests.tsv");
  assert.strictEqual(rows.length, 5000);
  assert.strictEqual(rows[0], "2026-12-25\tPSX\tGame 0 (USA).chd");
  assert(ledgerText(state, "schedule-requests.tsv").endsWith("\n"));
  assert.strictEqual(ledgerText(state, "unschedule-requests.tsv"), null, "untouched ledger is not written");
  // Re-dating the same batch rewrites the same single ledger once more.
  await api.applyMoveRequests({ schedule: batch.map(b => ({ ...b, date: "2027-01-01" })) });
  assert.strictEqual(io.createWritable, 2);
  assert.strictEqual(ledgerRows(state, "schedule-requests.tsv").length, 5000);
  // A no-op batch writes nothing.
  await api.applyMoveRequests({ cancel: [{ sys: "PSX", name: "Not Scheduled.chd" }] });
  assert.strictEqual(io.createWritable, 2);
});

test("ledger: a return request replaces a pending schedule in one call", async () => {
  const api = loadFsSection(); const { DirH } = makeFs();
  const state = new DirH(".dripfeed"); api.set({ stateDir: state, stateIsConsole: true });
  await api.requestSchedule("2027-01-01", "NES", "A.nes");
  await api.requestUnschedule("NES", "A.nes");
  assert.deepStrictEqual(ledgerRows(state, "schedule-requests.tsv"), []);
  assert.deepStrictEqual(ledgerRows(state, "unschedule-requests.tsv"), ["NES\tA.nes"]);
  await api.requestSchedule("2027-02-02", "NES", "A.nes");
  assert.deepStrictEqual(ledgerRows(state, "schedule-requests.tsv"), ["2027-02-02\tNES\tA.nes"]);
  assert.deepStrictEqual(ledgerRows(state, "unschedule-requests.tsv"), []);
  await api.cancelScheduleRequest("NES", "A.nes");
  assert.deepStrictEqual(ledgerRows(state, "schedule-requests.tsv"), []);
  assert.deepStrictEqual(ledgerRows(state, "unschedule-requests.tsv"), []);
  await assert.rejects(api.requestSchedule("2027-01-01", "NES", "Tab\there"), /unsupported tab, slash, or newline/);
});

test("ledger: quick concurrent clicks never lose a request", async () => {
  const api = loadFsSection(); const { DirH } = makeFs();
  const state = new DirH(".dripfeed"); api.set({ stateDir: state, stateIsConsole: true });
  await Promise.all([1, 2, 3, 4, 5, 6].map(i => api.requestUnschedule("NES", `Game ${i}.nes`)));
  assert.strictEqual(ledgerRows(state, "unschedule-requests.tsv").length, 6);
  await Promise.all([
    api.requestSchedule("2027-01-01", "NES", "X.nes"), api.writeOccasion("2027-01-01", "Hello"),
    api.requestSchedule("2027-01-02", "NES", "Y.nes"), api.writeOccasions({ "2027-01-02": "World", "2027-01-03": "Again" }),
  ]);
  assert.strictEqual(ledgerRows(state, "schedule-requests.tsv").length, 2);
  assert.deepStrictEqual(ledgerRows(state, "occasions.tsv"), ["2027-01-01\tHello", "2027-01-02\tWorld", "2027-01-03\tAgain"]);
});

test("ledger: an unreadable ledger is never overwritten as if it were empty", async () => {
  let failing = true;
  const api = loadFsSection(); const { DirH, io } = makeFs({ failRead: n => failing && n === "schedule-requests.tsv" ? "NotReadableError" : null });
  const state = new DirH(".dripfeed"); api.set({ stateDir: state, stateIsConsole: true });
  state.files.set("schedule-requests.tsv", "2027-01-01\tNES\tKeep Me.nes\n");
  await assert.rejects(api.requestSchedule("2027-02-02", "NES", "New.nes"), e => e.name === "NotReadableError");
  assert.strictEqual(io.createWritable, 0);
  assert.strictEqual(ledgerText(state, "schedule-requests.tsv"), "2027-01-01\tNES\tKeep Me.nes\n");
  failing = false;   // the queue keeps working after a failed write
  await api.requestSchedule("2027-02-02", "NES", "New.nes");
  assert.deepStrictEqual(ledgerRows(state, "schedule-requests.tsv"), ["2027-01-01\tNES\tKeep Me.nes", "2027-02-02\tNES\tNew.nes"]);
});

test("ledger: games-folder-only (limited) mode refuses to write card-side requests", async () => {
  const api = loadFsSection(); const { DirH, io } = makeFs();
  api.set({ stateDir: new DirH(".dripfeed_state"), stateIsConsole: false });
  await assert.rejects(api.applyMoveRequests({ schedule: [{ date: "2027-01-01", sys: "NES", name: "A.nes" }] }), /whole SD card required/);
  assert.strictEqual(io.createWritable, 0);
});

test("ledger: names the engine would refuse are never written (unit separator, . and ..)", () => {
  const api = loadFsSection();
  const m = api.mergeMoveRequests([], [], {
    schedule: [{ date: "2027-01-01", sys: "NES", name: "Unit\x1fSep.nes" }, { date: "2027-01-01", sys: "NES", name: ".." },
      { date: "2027-01-01", sys: ".", name: "x.nes" }, { date: "2027-01-01", sys: "NES", name: "Fine.nes" }],
    unschedule: [{ sys: "NES", name: "." }, { sys: "NES", name: "" }],
  });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(m.schedule)), [{ date: "2027-01-01", sys: "NES", name: "Fine.nes" }]);
  assert.strictEqual(m.rejected.length, 5);
});

test("ledger: browser and engine read the same rows from the same file", async () => {
  // The engine's own parser (df_annotate_requests) is run on what the browser
  // wrote, and the browser re-reads hand-edited ledgers the way the engine does.
  const engine = fs.readFileSync(path.join(__dirname, "..", "Scripts", ".dripfeed", "dripfeed-engine.sh"), "utf8");
  const fn = engine.match(/^df_annotate_requests\(\) \{[\s\S]*?\n\}\n/m);
  assert(fn, "df_annotate_requests not found in dripfeed-engine.sh");
  const os = require("os"), { execFileSync } = require("child_process");
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dripfeed-ledger-"));
  try {
    const annotate = (text, nf) => {
      fs.writeFileSync(path.join(tmp, "ledger"), text); fs.writeFileSync(path.join(tmp, "index"), "");
      const out = execFileSync("bash", ["-c", "DF_US=$'\\037'\n" + fn[0] + "\ndf_annotate_requests \"$1\" \"$2\" \"$3\"", "x",
        path.join(tmp, "ledger"), path.join(tmp, "index"), String(nf)], { encoding: "utf8" });
      return out.split("\n").filter(Boolean).map(l => l.split("\x1f"));
    };
    const api = loadFsSection(); const { DirH } = makeFs();
    const state = new DirH(".dripfeed"); api.set({ stateDir: state, stateIsConsole: true });
    const names = ["Shiny Forts (USA).nes", "Forts, Moats; & 'Walls' (Disc Set)", "Pokémon — 日本語.gb", "  spaced  .sfc"];
    await api.applyMoveRequests({ schedule: names.map((name, i) => ({ date: "2027-0" + (i + 1) + "-15", sys: "NES", name })) });
    await api.applyMoveRequests({ unschedule: [{ sys: "SNES", name: names[1] }] });
    const s = annotate(state.files.get("schedule-requests.tsv"), 3);
    assert.deepStrictEqual(s.map(f => [f[0], f[1], f[2], f[3], f[4]]), names.map((n, i) => ["", "", "2027-0" + (i + 1) + "-15", "NES", n]));
    const u = annotate(state.files.get("unschedule-requests.tsv"), 2);
    assert.deepStrictEqual(u.map(f => [f[0], f[1], f[3], f[4]]), [["", "", "SNES", names[1]]]);
    // Hand-edited ledger: outer tabs, a doubled tab, CRLF, an extra field.
    const odd = "\t2027-01-01\tNES\tA.nes\t\r\n2027-01-02\t\tNES\tB.nes\n2027-01-03\tNES\tC.nes\textra\n";
    state.files.set("schedule-requests.tsv", odd);
    const rows = await api.readMoveRequests("schedule-requests.tsv", true, true);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(rows)), [{ date: "2027-01-01", sys: "NES", name: "A.nes" }, { date: "2027-01-02", sys: "NES", name: "B.nes" }]);
    const e = annotate(odd.replace(/\r/g, ""), 3);
    assert.deepStrictEqual(e.map(f => [f[0], f[2], f[3], f[4]]), [["", "2027-01-01", "NES", "A.nes"], ["", "2027-01-02", "NES", "B.nes"], ["x", "2027-01-03", "NES", "C.nes"]]);
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
});

test("csv apply: a banner is saved only for rows whose request was written", () => {
  const body = slice("async function csvApplyRows", "csvRows=[]; $(\"#csvTable\")");
  assert(/reqs\.push\(\{[^}]*message:r\.message\}\)/.test(body), "whole-card rows carry their banner into the batch");
  assert(/new Set\(rejected\)[\s\S]*!bad\.has\(q\)\)occ\[q\.date\]=q\.message/.test(body), "rejected rows add no banner");
});

// ===========================================================================
// moveFile / moveDir: rename or refuse, never copy
// ===========================================================================
function stagedCard(opts) {
  const f = makeFs(opts);
  const sys = new f.DirH("PSX"), stage = new f.DirH(".dripfeed");
  sys.files.set("Big Game.chd", "GAME-DATA");
  return { ...f, sys, stage };
}
test("no copy fallback: move() missing -> NotSupportedError, nothing read, written or deleted", async () => {
  const api = loadFsSection(); const c = stagedCard({ moveMode: "absent" });
  await assert.rejects(api.moveFile(c.sys, "Big Game.chd", c.stage, "2026-12-25_Big Game.chd"),
    e => e.name === "NotSupportedError" && /was not changed/.test(e.message) && /whole SD card/.test(e.message));
  assert.deepStrictEqual([c.io.getFile, c.io.createWritable, c.io.removes, c.io.created], [0, 0, 0, 0]);
  assert.deepStrictEqual([...c.stage.files.keys()], []);
  assert.strictEqual(c.sys.files.get("Big Game.chd"), "GAME-DATA");
  assert.strictEqual(api.moveStopsBatch({ name: "NotSupportedError" }), true);
});

test("no copy fallback: a refused move() shows the real error and leaves the game alone", async () => {
  const api = loadFsSection(); const c = stagedCard({ moveMode: "throw" });
  await assert.rejects(api.moveFile(c.sys, "Big Game.chd", c.stage, "2026-12-25_Big Game.chd"),
    e => e.name === "NoModificationAllowedError" && e.message.includes("simulated sharing violation") && e.cause && e.cause.name === "NoModificationAllowedError");
  assert.strictEqual(c.io.moves, 1);
  assert.deepStrictEqual([c.io.getFile, c.io.createWritable, c.io.removes, c.io.created], [0, 0, 0, 0]);
  assert.deepStrictEqual([...c.stage.files.keys()], [], "no placeholder, no .crswap, no copy");
  assert.strictEqual(c.sys.files.get("Big Game.chd"), "GAME-DATA");
  assert.strictEqual(api.moveStopsBatch({ name: "NoModificationAllowedError" }), false, "a per-file lock does not stop the batch");
});

test("moveFile renames with move(), refuses collisions, and lets connection errors through", async () => {
  const api = loadFsSection();
  const ok = stagedCard();
  await api.moveFile(ok.sys, "Big Game.chd", ok.stage, "2026-12-25_Big Game.chd");
  assert.strictEqual(ok.stage.files.get("2026-12-25_Big Game.chd"), "GAME-DATA");
  assert(!ok.sys.files.has("Big Game.chd"));
  assert.deepStrictEqual([ok.io.getFile, ok.io.createWritable], [0, 0]);
  for (const occupy of ["file", "dir"]) {
    const c = stagedCard();
    if (occupy === "file") c.stage.files.set("2026-12-25_Big Game.chd", "OTHER"); else c.stage.dirs.set("2026-12-25_Big Game.chd", new c.DirH("x"));
    await assert.rejects(api.moveFile(c.sys, "Big Game.chd", c.stage, "2026-12-25_Big Game.chd"), /destination already exists/);
    assert.strictEqual(c.io.moves, 0);
  }
  const lost = stagedCard({ failLookup: "NotAllowedError" });
  await assert.rejects(api.moveFile(lost.sys, "Big Game.chd", lost.stage, "2026-12-25_Big Game.chd"), e => e.name === "NotAllowedError");
  assert.strictEqual(lost.io.moves, 0);
});

test("moveDir never copies a multi-disc folder (directory handles have no move())", async () => {
  const api = loadFsSection(); const f = makeFs();
  const sys = new f.DirH("Saturn"), stage = new f.DirH(".dripfeed"), game = new f.DirH("Shiny Forts III");
  game.files.set("Disc 1.chd", "D1"); sys.dirs.set("Shiny Forts III", game);
  await assert.rejects(api.moveDir(sys, "Shiny Forts III", stage, "2027-05-25_Shiny Forts III"), /whole SD card/);
  assert.deepStrictEqual([f.io.getFile, f.io.createWritable, f.io.removes], [0, 0, 0]);
  assert(sys.dirs.has("Shiny Forts III") && stage.dirs.size === 0);
});

test("static: the page never streams or copies game data; state files are the only writes", () => {
  assert(!/\.stream\s*\(/.test(script), "no File.stream() in the scheduler");
  assert(!/pipeTo\s*\(/.test(script), "no pipeTo() in the scheduler");
  const allowed = new Set(["writeOccasions", "writeMoveRequests", "writeGotms", "patchConfigIni"]);
  const re = /createWritable\s*\(/g; let m, n = 0;
  while ((m = re.exec(script))) {
    const before = script.slice(0, m.index);
    const decl = [...before.matchAll(/function\s+([A-Za-z0-9_$]+)\s*\(/g)].pop();
    assert(decl && allowed.has(decl[1]), "createWritable outside a state-file writer: " + (decl && decl[1]));
    n++;
  }
  assert.strictEqual(n, 4);
  assert(!/getFileHandle\([^)]*\{\s*create\s*:\s*true\s*\}\)/.test(slice("async function moveFile", "// macOS scatters")), "moveFile must not create placeholder files");
});

// ===========================================================================
// Folder inspection
// ===========================================================================
test("folder inspection: large computer and handheld images count as games", () => {
  const g = loadGuards();
  for (const n of ["Workbench.hdf", "Disk.st", "Game.msa", "mslug.neo", "Sonic.gg", "Game.lnx", "Game.a78", "Game.col", "Game.hdi", "Game.po", "Game.atr", "Mario.n64", "Zelda.fds", "Game.vb"])
    assert.strictEqual(g.isPlayableFile(n), true, n);
  for (const n of ["cd_bios.rom", "boot.rom", "readme.txt", "cover.png", "Game.sav"]) assert.strictEqual(g.isPlayableFile(n), false, n);
});

test("folder inspection: Dripfeed's own system shortcut folder is never a game", async () => {
  const g = loadGuards(); const f = makeFs();
  const sc = new f.DirH("_Dripfeed New"); sc.files.set("Shiny Forts.mgl", "<mistergamedescription/>");
  sc.files.set("Hidden.nes", "");   // even if a game file were copied in by hand
  assert.deepStrictEqual(JSON.parse(JSON.stringify(await g.classifyEntry("_Dripfeed New", sc))), { sysfile: true, reason: "Dripfeed shortcut folder" });
  assert.strictEqual(g.isSystemFile("_dripfeed new", "directory"), true);
  assert.strictEqual(g.isSystemFile("_Dripfeed New", "file"), false);
  g.setShortcutDir("_My New Games");
  assert.strictEqual(g.isSystemFile("_My New Games", "directory"), true);
  assert.strictEqual(g.isSystemFile("_Dripfeed New", "directory"), true, "the default name stays guarded");
});

test("folder inspection stops at the first playable image and caps deep data trees", async () => {
  const g = loadGuards(); const f = makeFs();
  const game = new f.DirH("Game 1");
  for (let i = 0; i < 40; i++) game.files.set(`data${i}.dat`, "");
  game.files.set("Game 1.adf", "");
  const deep = new f.DirH("data"); game.dirs.set("data", deep);
  for (let i = 0; i < 300; i++) deep.files.set(`f${i}.dat`, "");
  let r = await g.classifyEntry("Game 1", game);
  assert.strictEqual(r.sysfile, false);
  assert(f.io.entries <= 42, "playable file at this level must stop the walk before the data tree: " + f.io.entries);
  // Playable only one level down is still found.
  const nested = new f.DirH("Disc Set"), sub = new f.DirH("CD"); sub.files.set("Disc 1.cue", ""); nested.dirs.set("CD", sub);
  assert.strictEqual((await g.classifyEntry("Disc Set", nested)).sysfile, false);
  // A BIOS-only folder is support; a huge non-game folder is capped by the budget.
  const bios = new f.DirH("USA"); bios.files.set("cd_bios.rom", "");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(await g.classifyEntry("USA", bios))), { sysfile: true, reason: "firmware folder" });
  const art = new f.DirH("Artwork"); for (let i = 0; i < 5000; i++) art.files.set(`img${i}.png`, "");
  f.io.entries = 0;
  r = await g.classifyEntry("Artwork", art);
  assert.strictEqual(r.sysfile, true);
  assert(f.io.entries <= g.INSPECT_BUDGET + 1, "budget must cap the walk: " + f.io.entries);
});

// ---------------------------------------------------------------------------
(async () => {
  let failed = 0;
  for (const [name, fn] of tests) {
    try { await fn(); console.log("  ok  - " + name); }
    catch (e) { failed++; console.log("  FAIL- " + name + "\n        " + (e && e.stack || e).toString().split("\n").slice(0, 4).join("\n        ")); }
  }
  console.log(`Dripfeed scheduler logic: ${tests.length - failed}/${tests.length} passed`);
  process.exit(failed ? 1 : 0);
})();
