# R13 acceptance for MoonBean 0.2.7

## Version and source identity

Implementation is frozen at `a2f177af880ab31c4c97a8821b07f381361e0869`.
The baseline is main `89dafbbe503b6ddf41d3d87f7bdd9c58a74cad61`.
Work is on `compat-0.2.7` in the existing `moonbean-r2` worktree. Verified Git
archives of both performance inputs are retained under `.oracle-cache/r13/`.

Commands use `MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH`, Moon
0.1.20261104 / moonc v0.10.20+65efd5b93 and the pinned black-box oracle
Beancount 3.2.3 / beanquery 0.2.0. Oracle use was limited to CLI and public runtime APIs. Required unit/differential tests use `TZ=UTC` and the current
oracle date through `MOONBEAN_ORACLE_TODAY`.

## Implementation

- A per-read calendar hook supplies today, partial-date defaults and rolling
  two-digit years. The optional `host_clock` package imports
  `moonbean:clock.local_date(f64) -> i32`. Its JS adapter uses local calendar
  fields and DST rules. Invalid/unavailable results select the target default.
- Named imports must resolve before guest execution. An application opting into
  `host_clock.install()` supplies the local callback or the shipped zero callback.
  Existing moonrun programs use the default UTC path. [Integration and remaining boundary](../compatibility.md#webassembly-host-calendar-027).
- Parsing consumes lines with one lookahead. Parse-local caches share immutable
  words, exact-spelling Decimal literals and dates, bounded to 1024 items each.
  Mutable postings and metadata retain independent ownership. Regressions cover
  cache saturation, scale, expressions, CRLF, source maps, EOF and Unicode.

## Required correctness validation

Every command below exited 0. Actual output excerpts follow.

```text
$ moon info
Finished. moon: ran 14 tasks, now up to date
$ git diff --exit-code -- '*.mbti'
$ moon check --deny-warn
Finished. moon: ran 15 tasks, now up to date
$ moon fmt --check
Finished. moon: ran 82 tasks, now up to date
$ moon test --target native
Total tests: 193, passed: 193, failed: 0.
$ moon test --target wasm-gc
Total tests: 193, passed: 193, failed: 0.
$ moon test --target js
Total tests: 193, passed: 193, failed: 0.
$ moon build --release --target native cmd/main
Finished. moon: ran 11 tasks, now up to date
$ moon build --release --target wasm-gc tests/clock_host
Finished. moon: ran 6 tasks, now up to date
$ node scripts/wasm-clock-test.mjs
Wasm host clock: 99/99 checks passed
$ python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin --ours <repo>/_build/native/release/build/cmd/main/main.exe
BQL differential: 20549/20549 checks passed
```

Regenerated interfaces are committed. Experimental async dependency notices
remain in the full logs. All 20549 differential records pass, retaining the R12
corpus and its distinctions between conformance, explicit rejections and parser
robustness. [Commands, versions and raw-log hashes](r13-execution.json) pin the
release CLI. Full logs remain in `.oracle-cache/r13/acceptance/`.

The imported Wasm fixture checks UTC, Los Angeles and Kiritimati cross-day dates,
both DST transitions, per-read advancement, partial dates and short years,
invalid/unavailable/uninstalled-provider fallback and import resolution. Public
Python datetime calls independently check each instant in the pinned oracle
environment. [Raw host-clock output](r13-clock.log).

## Memory diagnosis

Main failed during the first repeated parse while retaining source, parsed and
validated ledgers. Sampled RSS peaks were 903.8 MiB during initial parse,
1103.6 MiB during initial validation and 1391.3 MiB during the failing repeated
parse. Fatal GC output reported 1383.6 MB live near the default V8 limit.
Streaming alone still failed. Streaming plus shared literals completed all
existing 1M FIFO measurement stages, both warmups and all 15 measurements, in
the diagnostic run. Its sampled peak was 1299.4 MiB during repeated parse.
[Per-stage RSS and source fingerprints](r13-memory.json), [limits and reproduction](../performance.md#r13-retained-ledger-memory).

RSS samples use `ps` every 100 ms and can miss brief peaks. Values include
retained objects and runtime residency. The instrumented runs provide stage
memory evidence. The uninstrumented standard pair and short A/B runs supply timing evidence.

## Performance gate

**Full 30% matrix gate is pending idle-host rerun by Lead.** Lead stopped the
72-call matrix after eight invocations and authorized shared-GUI-load scoped
measurements. The initial records, load traces and partial comparison remain in
`.oracle-cache/r13/performance-v2/`. Its native 10k FIFO format sample exceeded
the threshold (0.015 s versus 0.009667 s), and the paired baseline process saw
load reach 10.43.

The replacement plan runs one baseline/candidate wasm-gc 1M FIFO pair through the
unchanged standard runner with two warmups and 15 measurements. The short native
and JS comparison uses 100k and 1M FIFO, three separate process rounds per side,
two warmups and one measured sample per stage per round. Whole-case A/B order
alternates. Default heaps, source/archive/artifact hashes, process RSS and load
traces are retained.

### Wasm-gc 1M FIFO standard pair

Main failed with default V8 heap exhaustion, process exit -5, and peak RSS 1,462,255,616 bytes. The candidate completed all 11 measured stages, two warmups and 15 measurements each, with peak RSS 1,390,510,080 bytes. The existing large ORDER BY skip is retained.

| Stage | Candidate p50 (s) |
| --- | ---: |
| parse | 1.445000 |
| booking_FIFO | 0.316000 |
| validate_pad_FIFO | 0.619000 |
| realize | 0.125000 |
| format | 1.501000 |
| aggregate | 0.399000 |
| group | 0.681000 |
| regex | 0.503000 |
| transactions | 0.241000 |
| length | 0.467000 |
| substr | 0.609000 |

Main produced zero completed timed samples. Its earlier memory-stage diagnostics remain above. The standard case records retain every candidate sample and the baseline fatal stderr.

### Three short interleaved A/B rounds

Each cell below is the median of the three independent measured stage times. Ratios divide candidate median by main median. All three rounds are retained, with paired round ratios, process RSS, artifact hashes and load traces in [the performance packet](r13-performance.json). The short harness initially counted the skipped ORDER BY stage when classifying completion. Status was corrected against exit 0 and the 11 captured stages, preserving every timing and RSS value.

#### native 100,000 FIFO

| Stage | Main (s) | Candidate (s) | Ratio |
| --- | ---: | ---: | ---: |
| parse | 0.186000 | 0.110000 | 0.591 |
| booking_FIFO | 0.049000 | 0.056000 | 1.143 |
| validate_pad_FIFO | 0.089000 | 0.082000 | 0.921 |
| realize | 0.019500 | 0.016500 | 0.846 |
| format | 0.098000 | 0.096000 | 0.980 |
| aggregate | 0.037000 | 0.033000 | 0.892 |
| group | 0.069000 | 0.060000 | 0.870 |
| regex | 0.046000 | 0.035000 | 0.761 |
| transactions | 0.026000 | 0.022000 | 0.846 |
| length | 0.036000 | 0.031000 | 0.861 |
| substr | 0.056000 | 0.050000 | 0.893 |

#### js 100,000 FIFO

| Stage | Main (s) | Candidate (s) | Ratio |
| --- | ---: | ---: | ---: |
| parse | 0.293000 | 0.120000 | 0.410 |
| booking_FIFO | 0.042000 | 0.041000 | 0.976 |
| validate_pad_FIFO | 0.084000 | 0.083000 | 0.988 |
| realize | 0.013500 | 0.013000 | 0.963 |
| format | 0.241000 | 0.270000 | 1.120 |
| aggregate | 0.025000 | 0.023000 | 0.920 |
| group | 0.067000 | 0.061000 | 0.910 |
| regex | 0.036000 | 0.032000 | 0.889 |
| transactions | 0.017500 | 0.016500 | 0.943 |
| length | 0.032000 | 0.032000 | 1.000 |
| substr | 0.050000 | 0.052000 | 1.040 |

#### native 1,000,000 FIFO

| Stage | Main (s) | Candidate (s) | Ratio |
| --- | ---: | ---: | ---: |
| parse | 2.496000 | 1.112000 | 0.446 |
| booking_FIFO | 0.508000 | 0.500000 | 0.984 |
| validate_pad_FIFO | 0.914000 | 0.868000 | 0.950 |
| realize | 0.195000 | 0.174000 | 0.892 |
| format | 1.008000 | 1.349000 | 1.338 |
| aggregate | 0.371000 | 0.350000 | 0.943 |
| group | 0.825000 | 0.663000 | 0.804 |
| regex | 0.484000 | 0.380000 | 0.785 |
| transactions | 0.259000 | 0.240000 | 0.927 |
| length | 0.349000 | 0.336000 | 0.963 |
| substr | 0.564000 | 0.620000 | 1.099 |

#### js 1,000,000 FIFO

| Stage | Main (s) | Candidate (s) | Ratio |
| --- | ---: | ---: | ---: |
| parse | 3.814000 | 1.595000 | 0.418 |
| booking_FIFO | 0.484000 | 0.502000 | 1.037 |
| validate_pad_FIFO | 0.937000 | 0.983000 | 1.049 |
| realize | 0.151000 | 0.134000 | 0.887 |
| format | 3.936000 | 3.720000 | 0.945 |
| aggregate | 0.559000 | 0.376000 | 0.673 |
| group | 0.711000 | 0.740000 | 1.041 |
| regex | 0.463000 | 0.612000 | 1.322 |
| transactions | 0.250000 | 0.223000 | 0.892 |
| length | 0.682000 | 0.458000 | 0.672 |
| substr | 0.611000 | 0.674000 | 1.103 |

| Workload | Main median peak RSS (bytes) | Candidate median peak RSS (bytes) | Ratio |
| --- | ---: | ---: | ---: |
| native 100,000 | 151,388,160 | 106,659,840 | 0.705 |
| js 100,000 | 1,036,877,824 | 788,135,936 | 0.760 |
| native 1,000,000 | 1,465,679,872 | 1,172,111,360 | 0.800 |
| js 1,000,000 | 2,641,297,408 | 2,440,888,320 | 0.924 |

Short-run sampled one-minute load ranged from 4.271 to 9.886. Whole-case order alternated across rounds on the same shared GUI host. Exact per-invocation uptime/load samples are retained.

The unchanged comparator was also run separately on each short round. These outputs apply to four workload pairs with one measured sample per stage per process. [Exact comparator outputs](r13-bench-compare.log).

```text
Round 1, exit 0
PASS: all baseline stage medians and RSS within tolerance
Round 2, exit 1
native-1000000-FIFO.json/booking_FIFO: p50 64.691, baseline 0.508000s
native-1000000-FIFO.json/format: p50 1.508, baseline 1.008000s
native-1000000-FIFO.json/regex: p50 1.047, baseline 0.484000s
Round 3, exit 1
js-1000000-FIFO.json/regex: p50 0.751, baseline 0.463000s
native-100000-FIFO.json/regex: p50 0.069, baseline 0.047000s
```



Native 1M format has a candidate/main median ratio of 1.338294 (1.349 s /
1.008 s). JS 1M regex has ratio 1.321814 (0.612 s / 0.463 s). Round two's
native 1M FIFO booking measurement was 64.691 s versus main 0.508 s. The other
two candidate booking measurements were 0.486 s and 0.500 s. All values are
retained. The cause of the isolated long sample remains unconfirmed. Native/JS
30% acceptance remains pending the Lead idle-host full-matrix rerun.

## Remaining boundaries

The toolchain's core clock API supplies epoch time. Host-local WebAssembly
behavior requires the optional callback integration. UTC remains the safe
fallback and bare moonrun behavior. Exhaustive timezone databases, dateutil and
locale grammar, randomized Python set iteration, Python regex extensions and
the existing Decimal/BQL and non-BQL exclusions retain their documented scope.

## Closeout

The closeout packet is `.oracle-cache/r13/closeout/`. It retains the final source archive, verified Git bundle, native CLI backup, Git/process/task inventory, evidence hashes, manifest, execution receipt and restore map. All current source, benchmark inputs/artifacts and evidence are retained. Zero Trash moves and zero moved bytes are recorded. Disk free-space snapshots are recorded separately. The restore map contains zero moved items.
