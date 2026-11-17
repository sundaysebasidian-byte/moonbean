# wasm-gc host smoke

Local evidence on macOS arm64, 2026-11-16, source `90e66689dac426b3d7defc17d7f032b588e70b13`
(MoonBean 0.2.8). No runtime source or interfaces changed. No push, tag or publication.

## Reproduction

```sh
export MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH
moon build --release --target wasm-gc examples/library_demo tests/clock_host bench
export WASMTIME=/tmp/wasm-hosts/wasmtime/v50.0.2-522qxprw/wasmtime-v50.0.2-aarch64-macos/wasmtime
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node scripts/wasm-host-smoke.mjs
```

The runner writes raw per-host output, SHA-256s and `summary.json` under
`.oracle-cache/wasm-hosts/` (or its first argument). It closes its isolated Chrome
and local static server in `finally`; the existing Pages driver is `web/browser.mjs`.
The driver opens only `about:blank`; the runner evaluates the wasm smoke there.
It does not load the Pages JS build. Chrome flags, unchanged from that driver:

```text
--headless=new --remote-debugging-port=<random 9333..9832>
--user-data-dir=<output-dir>/profiles/moonbean-browser-<unique>
--hide-scrollbars --no-first-run --no-sandbox about:blank
```

No engine proposal flags are needed on Node or Chrome. Compilation uses
`{builtins: ["js-string"], importedStringConstants: "_"}`. The driver reports:

```text
moonrun 0.1.20261104 (940aa18 2026-11-04)
Node v24.18.0 / V8 13.6.233.17-node.50
Chrome/157.0.8103.79 / V8 15.7.112.43
wasmtime 50.0.2 (f9a93b049 2026-11-16)
```

Wasmtime came from the [official v50.0.2 release](https://github.com/bytecodealliance/wasmtime/releases/tag/v50.0.2).
The download was extracted in a fresh `/tmp/wasm-hosts/wasmtime/` directory with
Python tarfile's `filter="data"`; all execution used the repository working
directory, outside the untrusted extraction directory. Its archive SHA-256 matched
the digest published by the GitHub release assets API:

```text
wasmtime-v50.0.2-aarch64-macos.tar.xz
42b066764fb5ccd92f4378375202627b457be8ef0e85806784304ce9b07a721a
```

## Identical demo output

Actual commands (the Node runner performs the equivalent WebAssembly instantiation):

```sh
moonrun _build/wasm-gc/release/build/examples/library_demo/library_demo.wasm
node scripts/wasm-host-smoke.mjs
"$WASMTIME" run -W gc=y -W function-references=y -W exceptions=y \
  --preload moonbitlang/async=scripts/wasmtime-smoke.wat \
  --preload __moonbit_time_unstable=scripts/wasmtime-smoke.wat \
  --preload spectest=scripts/wasmtime-smoke.wat \
  _build/wasm-gc/release/build/examples/library_demo/library_demo.wasm
```

All four hosts exit 0 and the runner asserts byte-identical demo output,
including these raw lines (trailing spaces omitted here):

```text
errors: 0
Assets:Cash inventory:
  92.00 USD
account         sum_units
--------------  -----------
Assets:Cash     92.00 USD
Equity:Opening  -100.00 USD
Expenses:Food   8.00 USD
```

Full output includes the formatted ledger. SHA-256 of the complete stdout,
including original spaces and newlines, on every passing demo host:

```text
20fc3e6fbbee3aa1fe11489cd4a797d66a2a77f9df373c591d32eab5539e3239
```

Test-only WAT adapter: platform marker 1 (as in the Node harness), WASI realtime
converted to milliseconds, ASCII `fd_write`; printing above U+007F traps.
This is not a general MoonBit Wasmtime runtime.

## Booking/balance and clock checks

```sh
BENCH_COUNT=8 BENCH_RUNS=1 BENCH_METHOD=FIFO \
  moonrun _build/wasm-gc/release/build/bench/bench.wasm
```

The existing benchmark validates its ledger, books FIFO stock lots and checks
balance/pad before executing its BQL stages. There are 36 output records, including
two warmups per stage. Expected action results asserted by the runner:

```json
{"parse":9,"booking_FIFO":4,"validate_pad_FIFO":10,"realize":3,"format":493,"aggregate":1,"group":3,"order":10,"regex":1,"transactions":1,"length":5,"substr":5}
```

Node and Chrome run the identical benchmark bytes with the same environment
imports as `scripts/wasm-bench-host.mjs`. A synthetic clock advances 20 ms per
read, forcing one action per batch. Their complete output is identical. Raw
excerpts (synthetic seconds are **not measurements**):

```json
{"stage":"parse","warmup":true,"seconds":0.04,"batch":1,"sink":9}
{"stage":"parse","warmup":true,"seconds":0.04,"batch":1,"sink":0}
{"stage":"parse","warmup":false,"seconds":0.04,"batch":1,"sink":9}
{"stage":"booking_FIFO","warmup":true,"seconds":0.04,"batch":1,"sink":4}
```

Moonrun uses its real clock, so seconds/batches differ. Every record's actual
batch parity is checked against the same action result and cumulative XOR sink;
no byte equality or timing comparison is claimed for real-clock benchmark output.

The unchanged `tests/clock_host` module runs on Node and Chrome at epoch
`1704069000000` (2024-01-01T00:30Z). Both use the shipped `clockImports` adapter.
A custom provider returns 20231231. The zero, invalid (20240230), and uninstalled
modes select UTC. All result JSON is identical between Node and Chrome. Raw rows:

```json
["2023-12-31","2023-03-31","2050-06-15","2029-06-15"]
["2024-01-01","2024-03-01","2050-06-15","2029-06-15"]
```

The second row repeats for all three fallback modes. This does not repeat the
Node-only Python/dateutil timezone/DST and rolling-century oracle suite on Chrome.

## Bare Wasmtime failures and remaining limits

For each of the three artifacts:

```sh
"$WASMTIME" run -W gc=y -W function-references=y -W exceptions=y <artifact.wasm>
```

All exit 1 after compilation, at instantiation. Raw error excerpts:

```text
# examples/library_demo/library_demo.wasm
1: unknown import: `moonbitlang/async::runtime/get_platform` has not been defined
# bench/bench.wasm
1: unknown import: `__moonbit_fs_unstable::get_env_var` has not been defined
# tests/clock_host/clock_host.wasm
1: unknown import: `moonbean:clock::local_date` has not been defined
```

These failures are missing MoonBit host integrations. They do not establish a
GC/exception incompatibility: the adapted demo compiles and runs with the same
flags. No unknown-import default/trap flag was used to disguise a missing import.
Wasmtime's benchmark environment and calendar integration remain unverified;
the test adapter does not implement them. Non-ASCII printing through that adapter,
other browsers/architectures, larger workloads and non-GC wasm were not tested.
`command -v wasmer` found no executable; the optional host was not downloaded.

Artifact SHA-256s:

```text
library_demo.wasm f15ae780eb4274dcd9ccbf47bf92cd58e4015e54b6fa7c59ce4898deb48def48
bench.wasm        8f56baca4c3b51c7dab3341186295b89cf656433233eee01f69ecc86b87dae51
clock_host.wasm   b0c2fbb42666e02641a5194a27f1df09c10476250efeccf29a2605f746fd1d52
```

Acceptance commands all exit 0; native, JS and wasm-gc each print:

```text
Total tests: 207, passed: 207, failed: 0.
```

Commands: `moon test --target native`, `moon test --target js`,
`moon test --target wasm-gc`, `moon fmt --check`, `moon check --deny-warn`.
The existing CLI experimental-core-async notices remain unchanged. Unit tests,
generated interfaces, package versions, benchmark source and timing gates are unchanged.
