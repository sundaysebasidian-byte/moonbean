#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { clockImports } from "../host_clock/imports.mjs";

const path = process.argv[2] ?? "_build/wasm-gc/release/build/tests/clock_host/clock_host.wasm";
const module = new WebAssembly.Module(readFileSync(path), {
  builtins: ["js-string"],
  importedStringConstants: "_",
});
const imports = WebAssembly.Module.imports(module);
assert(imports.some(item => item.module === "moonbean:clock" && item.name === "local_date"));
const fixtures = [
  ["UTC", "2024-01-01T00:30:00Z"],
  ["America/Los_Angeles", "2024-01-01T00:30:00Z"],
  ["Pacific/Kiritimati", "2024-12-31T12:30:00Z"],
  ["America/Los_Angeles", "2024-03-10T09:59:00Z"],
  ["America/Los_Angeles", "2024-03-10T10:01:00Z"],
  ["America/Los_Angeles", "2024-11-03T08:59:00Z"],
  ["America/Los_Angeles", "2024-11-03T09:01:00Z"],
];
assert.throws(() => new WebAssembly.Instance(module, {
  "moonbitlang/async": { "runtime/get_platform": () => 1 },
  __moonbit_time_unstable: { now: () => 0n },
}), TypeError);
let checks = 1;
for (const [zone, instant] of fixtures) {
  process.env.TZ = zone;
  const milliseconds = Date.parse(instant);
  const dateText = date => `${date.getFullYear().toString().padStart(4, "0")}-${(date.getMonth() + 1).toString().padStart(2, "0")}-${date.getDate().toString().padStart(2, "0")}`;
  const utc = instant.slice(0, 10);
  const local = dateText(new Date(milliseconds));
  const oracle = execFileSync(process.argv[3] ?? "/tmp/moonbean-r4-oracle/bin/python", [
    "-c", "import datetime,sys; print(datetime.datetime.fromtimestamp(float(sys.argv[1])/1000).date())", String(milliseconds),
  ], { encoding: "utf8" }).trim();
  assert.equal(local, oracle);
  checks += 1;
  const base = { "moonbitlang/async": { "runtime/get_platform": () => 1 }, __moonbit_time_unstable: { now: () => BigInt(milliseconds) } };
  for (const [mode, clock, expected, install] of [
    ["local", clockImports(), local, true],
    ["unavailable", clockImports(null), utc, true],
    ["invalid", clockImports(() => 20240230), utc, true],
    ["uninstalled", clockImports(), utc, false],
  ]) {
    const instance = new WebAssembly.Instance(module, { ...base, ...clock });
    if (install) instance.exports.install();
    const result = JSON.parse(instance.exports.probe());
    assert(result.error == null, JSON.stringify(result));
    assert.equal(result.rows[0][0], expected, JSON.stringify(result));
    const day = Math.min(Number(expected.slice(8)), 31);
    assert.equal(result.rows[0][1], `${expected.slice(0, 4)}-03-${day.toString().padStart(2, "0")}`);
    assert.equal(result.rows[0][2], "2050-06-15");
    checks += 3;
    console.log(JSON.stringify({ zone, instant, mode, expected, result: result.rows[0] }));
  }
  // The provider receives the epoch on each read, allowing date/DST changes.
  let now = milliseconds;
  const changing = new WebAssembly.Instance(module, {
    "moonbitlang/async": { "runtime/get_platform": () => 1 },
    __moonbit_time_unstable: { now: () => BigInt(now) },
    ...clockImports(),
  });
  changing.exports.install();
  now += 86400000;
  assert.equal(JSON.parse(changing.exports.probe()).rows[0][0], dateText(new Date(now)));
  checks += 1;
}
console.log(`Wasm host clock: ${checks}/${checks} checks passed`);
