// GPL-3.0-or-later; Copyright (C) 2026 MikeyVids.
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "..");
const pages = [
  ["Dripfeed", "Dripfeed/Dripfeed-Scheduler.html", ["Connect SD card", "GOT'eM", "Import CSV"]],
  ["Profiler", "Profiler/Profiler-Manager.html", ["Connect SD card", "Save profile", "Back the Files Up - Setup"]],
  ["Back the Files Up", "Backup/Back-the-Files-Up-Setup.html", ["Back the Files Up - Setup", "Connect SD card", "Check my setup", "Exactly what is protected", "Dripfeed:", "Restore is built in", "Before Restore safety copy", "all Profiler profiles", "Remove cloud authorization"]],
  ["Wifi-Swap", "Wifi-Swap/Wifi-Swap-Registry.html", ["Wifi-Swap Registry", "Connect SD card", "Save profile", "Separate from Profiler", "Import existing MiSTer Wi-Fi"]],
];
for (const [name, rel, expected] of pages) {
  const html = fs.readFileSync(path.join(root, rel), "utf8");
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map(m => m[1]);
  if (!scripts.length) throw new Error(`${name}: no inline script found`);
  for (const source of scripts) new Function(source);
  for (const text of expected) if (!html.includes(text)) throw new Error(`${name}: missing ${text}`);
  if (/https?:\/\/[^"']+\.(?:js|css)(?:[?"'])/i.test(html)) throw new Error(`${name}: unexpected remote runtime dependency`);
  if (name === "Wifi-Swap") {
    if (!html.includes('name:"PBKDF2"') || !html.includes("iterations:4096")) throw new Error("Wifi-Swap: missing local WPA key derivation");
    if (/\bfetch\s*\(/.test(html) || /XMLHttpRequest|WebSocket/.test(html)) throw new Error("Wifi-Swap: unexpected network API");
    if (/<script[^>]+src=/i.test(html) || /<link[^>]+href=["']https?:/i.test(html)) throw new Error("Wifi-Swap: unexpected remote resource");
    const source = scripts[0], start = source.indexOf("function decodeHexSsid"), end = source.indexOf("async function refreshImports");
    if (start < 0 || end <= start) throw new Error("Wifi-Swap: remembered-network parser missing");
    const parseRemembered = new Function(source.slice(start, end) + ";return parseRememberedNetworks;")();
    const remembered = parseRemembered(`country=US\nnetwork={\n ssid=486f6d652054657374\n psk=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n}\n# WIFI-SWAP:BEGIN:owned\nnetwork={\n ssid=4f776e6564\n key_mgmt=NONE\n}\n# WIFI-SWAP:END:owned\n`);
    if (remembered.length !== 1 || remembered[0].ssid !== "Home Test" || remembered[0].country !== "US") throw new Error("Wifi-Swap: remembered-network import parser failed");
  }
  if (name === "Back the Files Up") {
    const allFetches = [...html.matchAll(/\bfetch\s*\(/g)].length;
    if (allFetches !== 1 || !html.includes("raw.githubusercontent.com/mikeyvids/Dripfeed/main/Backup/Scripts/.backthefup/backtheFup-engine.sh") || !html.includes("raw.githubusercontent.com/mikeyvids/Dripfeed/main/Backup/Scripts/backtheFup.sh") || /XMLHttpRequest|WebSocket/.test(html)) {
      throw new Error("Back the Files Up: network access must be limited to first-run launcher/engine recovery");
    }
    if (/<script[^>]+src=/i.test(html) || /<link[^>]+href=["']https?:/i.test(html)) throw new Error("Back the Files Up: unexpected remote runtime resource");
    if (!html.includes("BACKUP_SCOPE=all-profiles") || !html.includes("Current player's complete profile") || !html.includes("isArmRclone") || !html.includes("remoteAuthReady")) throw new Error("Back the Files Up: missing complete-profile, ARM helper, or finished-auth validation boundary");
  }
  console.log(`ok - ${name} HTML syntax and offline contract`);
}
