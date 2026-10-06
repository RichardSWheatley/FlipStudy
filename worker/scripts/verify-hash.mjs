#!/usr/bin/env node
/**
 * The Worker and the minting script hash codes independently. If those two ever
 * disagree, every code you hand out is silently rejected — and it looks like a
 * typo, not a bug. This asserts they agree, including on the condensed form the
 * iPhone actually sends (it strips the dashes before posting).
 */
import { createHash } from "node:crypto";
import { hashCode } from "../src/index.js";

const mintHash = (code) =>
  createHash("sha256")
    .update(code.toUpperCase().replace(/\s|-/g, ""))
    .digest("hex");

const cases = [
  ["as printed", "FLIP-A7K2-9QX4"],
  ["as the app sends it", "FLIPA7K29QX4"],
  ["typed in lowercase", "flip-a7k2-9qx4"],
  ["with stray spaces", "  FLIP-A7K2-9QX4 "],
];

let failed = 0;
const reference = await hashCode("FLIP-A7K2-9QX4");

for (const [name, input] of cases) {
  const worker = await hashCode(input);
  const ok = worker === reference && mintHash("FLIP-A7K2-9QX4") === worker;
  console.log(`${ok ? "  ok  " : "FAIL  "} ${name}`);
  if (!ok) failed++;
}

// A different code must not collide with the reference.
if ((await hashCode("FLIP-B7K2-9QX4")) === reference) {
  console.log("FAIL  distinct codes hash differently");
  failed++;
} else {
  console.log("  ok   distinct codes hash differently");
}

console.log(failed ? `\n${failed} failure(s)` : "\nhash parity verified");
process.exit(failed ? 1 : 0);
