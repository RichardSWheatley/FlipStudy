#!/usr/bin/env node
/**
 * Mint a family code and store its HASH in the CODES namespace.
 *
 * The plaintext code is printed once, here, and never stored anywhere — which
 * is the point: a dump of the KV namespace cannot be turned back into a working
 * code. If you lose the code, mint a new one and revoke the old.
 *
 *   node scripts/mint-code.mjs "Mum's iPhone"
 *   node scripts/mint-code.mjs "Sam" --devices 2 --daily 100
 */
import { createHash, randomInt } from "node:crypto";
import { execFileSync } from "node:child_process";

// No 0/O/1/I/L: these codes get read aloud and typed by hand.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

const group = () =>
  Array.from({ length: 4 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");

const args = process.argv.slice(2);
const label = args.find((a) => !a.startsWith("--")) || "FlipStudy Cloud";
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : parseInt(args[i + 1], 10);
};

const code = `FLIP-${group()}-${group()}`;
// Must match hashCode() in src/index.js exactly.
const normalized = code.toUpperCase().replace(/\s|-/g, "");
const hash = createHash("sha256").update(normalized).digest("hex");

const record = {
  label,
  active: true,
  devices: [],
  deviceLimit: flag("devices", 5),
  dailyRequests: flag("daily", 50),
  created: new Date().toISOString(),
};

execFileSync(
  "npx",
  [
    "wrangler", "kv", "key", "put", `code:${hash}`,
    JSON.stringify(record),
    "--binding", "CODES", "--remote",
  ],
  { stdio: "inherit" },
);

console.log(`\n  Code:   ${code}`);
console.log(`  For:    ${label}`);
console.log(`  Limits: ${record.deviceLimit} devices, ${record.dailyRequests} requests/day`);
console.log(`\n  QR:     node scripts/make-qr.swift ${code} ~/Desktop/${label.replace(/\W+/g, "-")}.png\n`);
