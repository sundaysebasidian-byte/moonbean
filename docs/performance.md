# Performance

2026-10-31, macOS 27.2 arm64, MoonBit 0.1.20261028, native release.
Same independently generated 100,000 transactions, one warmup and five measured
runs per command; wall-clock median, including process start and file I/O.
Another task used CPU during both measurements; these are local observations,
not a cross-machine guarantee. The previous 0.63s check result used a different
single-run fixture and is not the baseline below.

| Command | Before (s) | After (s) |
| --- | ---: | ---: |
| check | 0.632673 | 0.588531 |
| bal | 0.686044 | 0.636865 |
| query | 0.754790 | 0.972858 |

CPU profiling: `sample` at 1ms for 1 second during a 300k check run. The sample
contains ledger parsing, posting parsing and decimal literal parsing. It samples
an early execution interval, not the whole execution; it does not establish a
whole-program percentage or prove inventory merging is the bottleneck.

The measured change uses one decimal digit buffer and a scale counter instead
of separate integer/fraction buffers and intermediate concatenated strings.
Decimal precision, scale and rounding remain unchanged. Inventory uses a linear
lot scan; no inventory indexing or parser architecture change was made without
measurements on a many-lot workload.

Reproduce (run timing without concurrent oracle tests):

```sh
export PATH="$HOME/.moon/bin:$PATH"
moon build --target native --release
python3 scripts/performance.py --out .oracle-cache/performance
python3 scripts/performance.py --count 300000 --runs 1 --sample --out .oracle-cache/profile
```

The controlled comparison uses the same final query/CLI source in both builds.
For before, only `decimal/decimal.mbt` is taken from `e7c98b1` (keeping the
precision constant private); after uses the single-buffer implementation from
`5dd6b0c`. A local try/finally driver restored the final source after comparison.
Do not reset a working tree containing user changes.
Full timing arrays and the sample are retained locally under
`.oracle-cache/perf-controlled-before`, `.oracle-cache/perf-controlled-after`, `.oracle-cache/profile-before`.

The controlled query median increased from 0.755s to 0.973s, with after samples
0.829–1.963s. This result does **not** demonstrate a query speedup. Concurrent
CPU contention and allocation/GC effects remain unisolated; check/bal improved
in this measurement, but the query observation must be retained as a limitation.

A follow-up five-run query-only measurement on the final binary returned
0.684s median (0.670–0.705s), retained in `.oracle-cache/query-followup.json`.
Both measurements are reported; this variation prevents a stable query-speedup
claim from these wall-clock runs.
