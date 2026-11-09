# Performance (0.2.2)

## Current library-stage evidence

Measured locally on Apple M4 (Mac16,12), 10 logical cores, 16 GiB RAM,
macOS 27.2 arm64, MoonBit 0.1.20261104, Node 24.18.0. Release builds use
engine commit `2cd1a2047511d51c59db3d4902a68423def64d3c` plus the committed
benchmark driver; no engine optimization is included. Timing-round runner source:
`503635d:scripts/bench-matrix.py`; the current runner additionally retains partial
samples and full stderr on failure. JSON records retain exact
compiler/runtime versions, driver/runner and executable SHA-256 fingerprints.
This shared host was not reserved. Benchmarks run sequentially, without oracle, MoonBit or web suites concurrently;
lightweight comparator self-checks and file inspection occurred. External load
and thermal state are uncontrolled.

The offline `bench/main.mbt` generator uses a 32-bit LCG (seed 20261101,
multiplier 1664525, increment 1013904223). Counts are **source postings**, not
transactions: 1k/10k/100k/1m postings, each with half as many transactions,
plus one generated two-posting pad. There are three accounts and one costed
commodity. Each cycle opens two different cost lots and fully reduces them;
FIFO uses empty-cost selection, AVERAGE uses average cost, STRICT explicit lot
selection. Live stock inventory is bounded to two cost lots. This does not characterize
large persistent inventories, many accounts, plugins, includes or a Fava workload.
Entries are chronological; reverse-date validation sorting is not characterized.
Narrations are ASCII and the regex is a simple account-name search; Unicode-heavy
strings and complex regex patterns are not characterized.
No network or upstream fixture is used. The input is generated before timing;
large source files are regenerated rather than committed.

Fixture setup first parses and validates the source once (untimed), then
each stage records **two warmup samples and 21 measured samples**. A sample
batches whole API calls until at least 20 ms, then divides by its batch count.
The core clock has millisecond resolution, so batching reduces short-call
quantization; samples include allocation/GC effects and output objects, but not
ledger generation, process startup, filesystem I/O or JSON/text rendering.
The same process retains the source, parsed ledger and validated ledger. `parse`
is parsing alone; `booking_*` books source transaction postings into a fresh
state (pad excluded); `validate_pad_*` is validation including booking and pad,
starting from the parsed ledger. `realize` starts from the validated ledger;
`format` processes source lines directly. BQL starts from that validated ledger, including its
internal realization. Stage times **must not be added as disjoint CPU shares**.

The [baseline stage profile](evidence/performance/baseline/stage-profile.json)
provides p50/p95/p99, posting throughput and maximum/p50 for every measured stage.
Sibling case JSON files retain every warmup/sample, batch count and checksum.
Percentiles use the empirical nearest rank; with 21 samples p99 is the maximum,
not a reliable production tail estimate. Throughput divides source postings by
p50; transaction-source queries examine approximately half as many rows.
`peak_rss_bytes` is macOS `/usr/bin/time -l` **whole-process** peak RSS, including
fixture/setup, retained objects, runtime/JIT and every stage. It cannot attribute
memory to a particular stage and is not retained heap size.

| Backend | Source postings | Parse p50 (s) | Validate+pad p50 (s) | GROUP BY p50 (s) | Process peak RSS (GiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 1,000 | 0.001818 | 0.000690 | 0.000513 | 0.005 |
| native | 10,000 | 0.018500 | 0.008000 | 0.005250 | 0.016 |
| native | 100,000 | 0.190000 | 0.096000 | 0.072000 | 0.136 |
| native | 1,000,000 | 1.931000 | 1.017000 | 0.812000 | 1.548 |
| js | 1,000 | 0.002333 | 0.000833 | 0.000455 | 0.203 |
| js | 10,000 | 0.027000 | 0.008667 | 0.005500 | 0.359 |
| js | 100,000 | 0.329000 | 0.085000 | 0.067000 | 0.979 |
| js | 1,000,000 | 3.444000 | 0.880000 | 0.692000 | 3.185 |
| wasm-gc | 1,000 | 0.001909 | 0.000541 | 0.000426 | 0.063 |
| wasm-gc | 10,000 | 0.024000 | 0.005750 | 0.005000 | 0.111 |
| wasm-gc | 100,000 | 0.267000 | 0.061000 | 0.066000 | 0.397 |
| wasm-gc | 1,000,000 | incomplete | incomplete | incomplete | 1.445 (failed process) |

## Query scaling and variation

The ungrouped `SELECT narration ORDER BY narration` reproduces quadratic scaling:
10x input costs roughly 100x time on native at 1k/10k postings. The implementation
uses insertion sorting, evaluating expressions in its comparison loop; LIMIT is
applied afterwards. [Minimal reproduction and source location](evidence/performance/order-repro.md).
**This ORDER BY scene is not completed at 100k or 1m on any backend**, explicitly
listed in `skipped_stages`. All other requested scenes are attempted at every
size. The first wasm-gc million-posting FIFO process exited with signal 5
before a complete measurement set; its JSON is explicitly incomplete. The
million-posting AVERAGE/STRICT booking and validation processes completed.
A [separate reproduction](evidence/performance/wasm-repro/wasm-gc-1000000-FIFO.json)
retains full stderr: `Fatal JavaScript out of memory: Ineffective mark-compacts near heap limit`,
with V8 heap around 1.4 GB. No first warmup sample completed. This confirms heap
exhaustion in the default `moonrun` process for this retained-object harness,
not a measured timing, an engine leak diagnosis or a universal wasm ledger limit.
The original two timing-round failure records retain only error tails; no missing
samples are reconstructed. The diagnostic reproduction is separate from the gate.

```sh
python3 scripts/bench-matrix.py --targets wasm-gc --sizes 1000000 --methods FIFO --out .oracle-cache/wasm-million-repro
```

No runtime heap settings or engine code were changed to bypass the failure. The presence of this separate scaling limitation does not establish the
cause of the historical grouped-query slowdown. No speculative engine fix or
pure performance optimization was made.

| Backend | Source postings | GROUP BY first p50 (s) | Second p50 (s) | Change | Largest BQL p50 increase |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 1,000 | 0.000513 | 0.000556 | +8.3% | +23.8% |
| native | 10,000 | 0.005250 | 0.005750 | +9.5% | +16.7% |
| native | 100,000 | 0.072000 | 0.079000 | +9.7% | +10.9% |
| native | 1,000,000 | 0.812000 | 0.845000 | +4.1% | +7.1% |
| js | 1,000 | 0.000455 | 0.000541 | +18.9% | +18.9% |
| js | 10,000 | 0.005500 | 0.005750 | +4.5% | +13.1% |
| js | 100,000 | 0.067000 | 0.072000 | +7.5% | +16.0% |
| js | 1,000,000 | 0.692000 | 0.799000 | +15.5% | +17.4% |
| wasm-gc | 1,000 | 0.000426 | 0.000426 | +0.0% | +10.1% |
| wasm-gc | 10,000 | 0.005000 | 0.005250 | +5.0% | +9.1% |
| wasm-gc | 100,000 | 0.066000 | 0.082000 | +24.2% | +24.2% |
| wasm-gc | 1,000,000 | incomplete | incomplete | not compared | not compared |

Across the 11 complete FIFO backend/scale pairs, GROUP BY p50 changed by
0.0–24.2%; the largest increase among the measured BQL medians was 24.2%.
This does not reproduce the old large query-only slowdown on this new fixture;
it does not resolve its historical cause or imply stable tail latency.

[Second-run profile and arrays](evidence/performance/repeat/stage-profile.json)
are committed separately; the baseline is not overwritten by a later run.

These two independently collected runs establish an initial local comparison,
not a long-term trend, confidence interval or general speed guarantee. Within-run maxima and cross-run ratios are retained;
the exact cause of the historical query slowdown remains unconfirmed. The old
blanket statement “query fluctuates” is replaced by workload-specific evidence:
ungrouped sorting has deterministic scaling risk; grouped-query variation must
be assessed from these arrays rather than attributed to GC or scheduler load.

[Local acceptance](evidence/performance/acceptance.json): `moon check --deny-warn --target all`,
`moon fmt --check`, `moon info` (existing interfaces unchanged; new bench interface
is empty), 132 tests on each of four backends, 112/112 ledger comparisons, 92/92 BQL
checks, both 1000-input seeds (858 matched / 142 AVERAGE-only / zero other differences),
29 Node and 8 DOM checks. The local comparison passed 35 complete baseline cases;
wasm-gc million-posting FIFO remains NOT GATED. No new CI/deployment/publication.

## Local regression check and baseline updates

```sh
export MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH
python3 scripts/bench-matrix.py --out .oracle-cache/performance-new
python3 scripts/bench-summary.py .oracle-cache/performance-new
python3 scripts/bench-compare.py .oracle-cache/performance-new
python3 -m unittest discover -s scripts -p test_bench_compare.py
```

The checker defaults to `docs/evidence/performance/baseline`, compares every
completed baseline stage's **p50** and each process peak RSS, and exits nonzero
for >30% regression, missing/incomplete cases/stages or incompatible host/runtime
and measurement settings. Exact executable/driver hashes and commit are evidence,
not equality requirements: engine changes need to be measurable. Incomplete
baseline cases are printed as NOT GATED and excluded from comparison; they do
not provide performance acceptance. At least one complete baseline case is
required, and documented skipped stages must match. p95/p99 stay visible but are not gates because 21
samples and millisecond clocks cannot provide stable extreme-tail estimates.

30% is a deliberately coarse local alert threshold: it tolerates clock granularity,
GC/JIT and shared-host noise while detecting material sustained changes. It is
not a statistical significance test or a guarantee against smaller regressions.
If it trips, rerun on an idle machine and inspect the arrays; do not automatically
raise the threshold. No CI gate is added because runner hardware/load varies.

To update the baseline, retain the existing committed directory until a full
new measurement and comparison have been reviewed. Record any intentional
host/toolchain changes; compare matching environments rather than treating an
incompatible run as a pass. Copy only reviewed case JSON files and regenerate
`stage-profile.json` with `bench-summary.py`; review all omissions, source/version
fingerprints and rationale in the commit. Keep historical evidence available in
Git. Use `--sizes`/`--targets` for diagnosis, not for a full baseline gate.
Large runs have a 600-second per-case timeout; failure records are explicit,
and timed-out process groups are stopped. The runner records incomplete cases
and continues; its successful exit does not certify every case. Use the comparator
as the gate for complete baseline cases and review NOT GATED omissions separately. The runner currently requires macOS
for peak RSS collection; native/JS/wasm-gc here all run on that host.

# Historical CLI evidence (2026-11-01)

Measured 2026-11-01 on Apple M4, macOS 27.2 arm64, MoonBit
0.1.20261028 (moonc v0.10.18+6c83a7f62), native release. Fixed Python RNG
seed 20261101, 100,000 transactions / 200,000 postings. Each command has
one warmup and seven measured runs; commands alternate forward/reverse order
per round. Wall time includes startup, ledger read/parse/validation and output
rendering (stdout redirected to the null device). `realize` measures CLI `bal`,
including realization and trial-balance rendering, not an isolated API call.
No oracle or test suite was launched by this task during the timing rounds;
this shared machine was not reserved, so external load remains uncontrolled.
The fixture has two accounts, one currency and no cost lots, plugins or includes;
it does not characterize a complex portfolio or an entire Fava workload.

| Command | Median (s) | Min–max (s) |
| --- | ---: | ---: |
| check | 0.563524 | 0.558459–0.587087 |
| realize | 0.602720 | 0.601914–0.616943 |
| query | 0.665322 | 0.652536–0.690696 |
| fmt | 0.234537 | 0.229992–0.237070 |
| query_old_decimal | 0.683218 | 0.671131–0.705867 |

Input: 8,069,150 bytes, SHA-256
`0bdf3c5087e09f0cde21889ecd26b3c350b6d5155e501cc151bbdb492a7a5ab0`.
The generated input stays locally in `docs/evidence/performance/ledger.beancount`
(ignored); the committed generator reproduces it without upstream test data.

[Raw timings and environment](evidence/performance/results.json) include all
arrays, exact commands, CPU/OS/toolchain/Python, input and executable fingerprints.
[Query profile](evidence/performance/query-sample.txt) and
[old-decimal query profile](evidence/performance/query_old_decimal-sample.txt)
are separate from timings; sampling overhead is not included in the table.
The profiler samples an early interval and can miss the end of a short process.
In the current profile, 49 of 455 main-thread samples lie in `run_query`;
the majority lie in the ledger loading/checking call chain. The old-decimal
profile ends in checking/cleanup and does not capture query evaluation, so these
profiles do not support a precise whole-program query-stage ratio comparison.

## Query regression investigation

The historical observation was check 0.632673 → 0.588531 s, bal
0.686044 → 0.636865 s, query 0.754790 → 0.972858 s. Its original arrays were
recovered unchanged from local `perf-controlled-before/after/results.json` and
are now [committed](evidence/performance/historical-before.json),
[including the slow after run](evidence/performance/historical-after.json).
Those older records lack CPU/executable/input fingerprints and contemporaneous
scheduler evidence. The previously documented query-only 0.684 s follow-up has
no retained raw array and is not used as a baseline here.

We isolated the source change suspected in that comparison: the decimal parser
from `e7c98b1:decimal/decimal.mbt` versus the current single-buffer parser.
The script archives HEAD, overlays tracked working edits, and substitutes only
the old decimal file (keeping its precision constant private). Both binaries
use the same seeded ledger and query, one warmup each and seven interleaved
measurements. The current query median is 0.665322 s versus 0.683218 s with the
old parser: the historical 0.755 → 0.973 s regression is **not reproduced** by
this isolated change. This small difference is not a general speedup guarantee.

An [exploratory first run](evidence/performance/exploratory.json) is also retained:
current query median 0.661665 s with a 1.952493 s outlier, old decimal median
0.670035 s with a 1.228308 s outlier. Its baseline used HEAD before overlaying
tracked edits, so the second, strictly controlled run above is the primary
comparison. The historical after array also varied 0.829–1.963 s. This is
consistent with transient system/allocation effects, but does not prove CPU
contention, GC or a specific scheduler cause. **The exact historical slowdown
cause remains unconfirmed** because no contemporaneous profile exists; the
available controlled comparison gives no basis for changing correct query logic.
No speculative performance fix was made.

## Reproduce

```sh
export MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH
python3 scripts/performance.py --compare-decimal --sample
```

macOS `sample` is required only for `--sample`; omit it elsewhere. Every run
retains an isolated baseline under `.oracle-cache/performance-baseline-*` and
writes evidence under `--out` (default `docs/evidence/performance`). Choose a new
`--out` to preserve previous evidence. The parser comparison requires the local
Git history containing `e7c98b1`; ordinary timing does not. No working source is
rewritten. Minimum five measured runs is enforced.

## 0.2.3 return round 2

The insertion-sort limitation described above belongs to the old baseline. The candidate now caches ORDER BY keys, reuses projected columns and sorts indices in O(n log n), with original indices preserving ties. `bql_sort_differential.py` compares 100,000 native postings row by row with the oracle; it is functional evidence, not a large-order throughput/RSS gate. The unchanged baseline driver still skips ORDER BY at 100k/1M to retain comparable stage metadata. Its skip text is historical, not a description of the new algorithm.

The first full candidate matrix failed several gates and is preserved at `.oracle-cache/r2-last/verified-2/performance`. Follow-up changes keep optional provenance in a lazy record, fuse signed-zero detection into lexing, remove tolerance-cache closures/unused collections and cache sort keys. Small matrices are retained at `.oracle-cache/r2-last/perf-probe` and `perf-order-probe`. [Final acceptance](evidence/r2-final-acceptance.md) records the actual final full matrix/gate; no gate tolerance or baseline samples were changed. Existing wasm-gc 1M FIFO baseline incompleteness remains excluded by the established comparator. New large source/function workloads beyond the stated tests have not received a separate peak-memory profile.

The final source full matrix attempted all 36 cases (35 complete), but initially exceeded four stage gates in three scenarios. A predeclared three-repeat plan for all three scenarios passed every unchanged limit in every round, with identical artifacts. The confirmed comparison uses the last repeat for those scenarios and the original records elsewhere; it passes. Original failures and all repeats are retained. Timing variation has no established cause. See the [acceptance record](evidence/r2-final-acceptance.md) and [measurement summaries](evidence/r2-final-performance.json); this is not a claim that the first full matrix passed.
