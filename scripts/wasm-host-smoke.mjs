#!/usr/bin/env node
// Build first: moon build --release --target wasm-gc examples/library_demo tests/clock_host bench
// Optional: WASMTIME=/absolute/path/to/wasmtime node scripts/wasm-host-smoke.mjs [output-dir]
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { clockImports } from "../host_clock/imports.mjs";
import { launch } from "../web/browser.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
process.chdir(root);
const out = resolve(process.argv[2] ?? ".oracle-cache/wasm-hosts");
mkdirSync(out, { recursive: true });
const artifacts = {
  demo: "_build/wasm-gc/release/build/examples/library_demo/library_demo.wasm",
  bench: "_build/wasm-gc/release/build/bench/bench.wasm",
  clock: "_build/wasm-gc/release/build/tests/clock_host/clock_host.wasm",
};
const bytes = Object.fromEntries(Object.entries(artifacts).map(([name, path]) => [name, [...readFileSync(path)]]));
const save = (name, text) => writeFileSync(join(out, name), text);
function command(exe, args, env = {}) {
  const result = spawnSync(exe, args, {
    encoding: "utf8", timeout: 120000, env: { ...process.env, ...env },
  });
  return { status: result.status, stdout: result.stdout ?? "", stderr: result.stderr ?? "", error: result.error?.code };
}
function successful(result) {
  assert.equal(result.status, 0, result.stderr || result.error);
  return result.stdout;
}

// Serialized unchanged into Chrome. No Node dependencies or filesystem access.
function exercise(bytes, clockImports) {
  function instance(name, clock = () => 1704069000000n, extra = {}) {
    let output = "";
    const imports = {
      "moonbitlang/async": { "runtime/get_platform": () => 1 },
      __moonbit_time_unstable: { now: clock },
      __moonbit_fs_unstable: {
        begin_create_string: () => [],
        string_append_char: (handle, code) => { handle.push(code); },
        finish_create_string: handle => String.fromCharCode(...handle),
        get_env_var: key => ({ BENCH_COUNT: "8", BENCH_RUNS: "1", BENCH_METHOD: "FIFO" })[key] ?? "",
        get_env_var_exists: key => ["BENCH_COUNT", "BENCH_RUNS", "BENCH_METHOD"].includes(key),
        begin_read_string: text => ({ text, index: 0 }),
        string_read_char(handle) {
          if (handle.index >= handle.text.length) return -1;
          const code = handle.text.codePointAt(handle.index);
          handle.index += code > 0xffff ? 2 : 1;
          return code;
        },
        finish_read_string: () => {},
      },
      spectest: { print_char: code => { output += String.fromCodePoint(code); } },
      ...extra,
    };
    const module = new WebAssembly.Module(new Uint8Array(bytes[name]), {
      builtins: ["js-string"], importedStringConstants: "_",
    });
    return { exports: new WebAssembly.Instance(module, imports).exports, output: () => output };
  }
  const demo = instance("demo");
  demo.exports._start();
  // Synthetic monotonic clock forces one action per batch. This is correctness
  // evidence only: these seconds must never be used as performance measurements.
  let tick = 0n;
  const bench = instance("bench", () => { tick += 20n; return tick; });
  bench.exports._start();
  const clock = {};
  for (const [mode, provider, install] of [
    ["local", () => 20231231, true],
    ["unavailable", null, true],
    ["invalid", () => 20240230, true],
    ["uninstalled", () => 20231231, false],
  ]) {
    const guest = instance("clock", undefined, clockImports(provider));
    if (install) guest.exports.install();
    clock[mode] = JSON.parse(guest.exports.probe());
  }
  return { demo: demo.output(), bench: bench.output(), clock };
}

const moonrun = process.env.MOONRUN ?? join(process.env.MOON_HOME ?? "/tmp/moon-new", "bin/moonrun");
const reference = successful(command(moonrun, [artifacts.demo]));
assert.match(reference, /^errors: 0\nAssets:Cash inventory:\n  92\.00 USD\n/);
assert.match(reference, /Equity:Opening  -100\.00 USD/);
assert.match(reference, /Expenses:Food   8\.00 USD/);
save("moonrun-demo.txt", reference);
const moonBench = successful(command(moonrun, [artifacts.bench], {
  BENCH_COUNT: "8", BENCH_RUNS: "1", BENCH_METHOD: "FIFO",
}));
save("moonrun-bench.txt", moonBench);
const node = exercise(bytes, clockImports);
assert.equal(node.demo, reference);
const stages = ["parse", "booking_FIFO", "validate_pad_FIFO", "realize", "format", "aggregate", "group", "order", "regex", "transactions", "length", "substr"];
const records = text => text.trim().split("\n").map(line => JSON.parse(line));
const nodeRecords = records(node.bench);
assert.deepEqual(nodeRecords.map(r => r.stage), stages.flatMap(stage => [stage, stage, stage]));
const counts = Object.fromEntries(stages.map((stage, i) => [stage, nodeRecords[i * 3].sink]));
assert.deepEqual(counts, {
  parse: 9, booking_FIFO: 4, validate_pad_FIFO: 10, realize: 3, format: 493,
  aggregate: 1, group: 3, order: 10, regex: 1, transactions: 1, length: 5, substr: 5,
});
nodeRecords.forEach((record, i) => {
  assert.equal(record.batch, 1);
  assert.equal(record.warmup, i % 3 < 2);
  assert.equal(record.sink, i % 3 === 1 ? 0 : counts[record.stage]);
});
const moonRecords = records(moonBench);
assert.equal(moonRecords.length, nodeRecords.length);
let sink = 0;
for (let i = 0; i < moonRecords.length; i++) {
  const record = moonRecords[i];
  if (i % 3 === 0) sink = 0;
  assert.equal(record.stage, nodeRecords[i].stage);
  assert.equal(record.warmup, i % 3 < 2);
  sink ^= record.batch % 2 ? counts[record.stage] : 0;
  assert.equal(record.sink, sink);
}
for (const [mode, result] of Object.entries(node.clock)) {
  assert.equal(result.error, undefined);
  assert.deepEqual(result.rows, [mode === "local"
    ? ["2023-12-31", "2023-03-31", "2050-06-15", "2029-06-15"]
    : ["2024-01-01", "2024-03-01", "2050-06-15", "2029-06-15"]]);
}
save("node.json", JSON.stringify(node, null, 2) + "\n");
const summary = {
  demoStdoutSha256: createHash("sha256").update(reference).digest("hex"),
  artifacts: Object.fromEntries(Object.entries(artifacts).map(([name, path]) => [name, {
    path, sha256: createHash("sha256").update(readFileSync(path)).digest("hex"),
  }])),
  moonrun: { version: successful(command(moonrun, ["--version"])).trim(), result: "passes", benchmarkActions: counts },
  node: { version: process.version, v8: process.versions.v8, result: "passes" },
};

let browser;
const originalTmp = process.env.TMPDIR;
try {
  // Keep the isolated test profile with this run's evidence, never the user's profile.
  process.env.TMPDIR = join(out, "profiles");
  mkdirSync(process.env.TMPDIR, { recursive: true });
  browser = await launch();
  const version = await browser.send("Browser.getVersion");
  const adapter = readFileSync(join(root, "host_clock/imports.mjs")).toString("base64");
  const chrome = await browser.evaluate(`(async () => {
    const { clockImports } = await import("data:text/javascript;base64,${adapter}");
    return (${exercise.toString()})(${JSON.stringify(bytes)}, clockImports);
  })()`);
  assert.deepEqual(chrome, node);
  assert.deepEqual(browser.exceptions, []);
  summary.chrome = { version: version.product, v8: version.jsVersion, result: "passes" };
  save("chrome.json", JSON.stringify(chrome, null, 2) + "\n");
} finally {
  if (originalTmp === undefined) delete process.env.TMPDIR;
  else process.env.TMPDIR = originalTmp;
  if (browser) await browser.close();
}

const wasmtime = process.env.WASMTIME ?? "wasmtime";
const version = command(wasmtime, ["--version"]);
if (version.error === "ENOENT") {
  summary.wasmtime = { result: "not runnable", reason: "wasmtime executable not found; set WASMTIME" };
} else {
  successful(version);
  const flags = ["run", "-W", "gc=y", "-W", "function-references=y", "-W", "exceptions=y"];
  const bare = {};
  for (const [name, path] of Object.entries(artifacts)) {
    const result = command(wasmtime, [...flags, path]);
    bare[name] = { status: result.status, error: result.error };
    save(`wasmtime-bare-${name}.txt`, result.stdout + result.stderr);
  }
  const adapter = "scripts/wasmtime-smoke.wat";
  const preloads = ["moonbitlang/async", "__moonbit_time_unstable", "spectest"].flatMap(name => ["--preload", `${name}=${adapter}`]);
  const demo = successful(command(wasmtime, [...flags, ...preloads, artifacts.demo]));
  assert.equal(demo, reference);
  save("wasmtime-demo.txt", demo);
  summary.wasmtime = { version: version.stdout.trim(), result: "passes library_demo with test adapter", bare };
}
save("summary.json", JSON.stringify(summary, null, 2) + "\n");
console.log(JSON.stringify(summary, null, 2));
