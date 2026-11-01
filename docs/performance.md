# Performance

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
export PATH="$HOME/.moon/bin:$PATH"
python3 scripts/performance.py --compare-decimal --sample
```

macOS `sample` is required only for `--sample`; omit it elsewhere. Every run
retains an isolated baseline under `.oracle-cache/performance-baseline-*` and
writes evidence under `--out` (default `docs/evidence/performance`). Choose a new
`--out` to preserve previous evidence. The parser comparison requires the local
Git history containing `e7c98b1`; ordinary timing does not. No working source is
rewritten. Minimum five measured runs is enforced.
