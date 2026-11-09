# Return round 2: implementation and acceptance

Verified code: `5f0bec90c88aeb48a3ab0825181649d65956d930`, branch `compat-0.2.3`. The documentation/evidence commit follows. This is an incremental implementation; the beanquery endpoint remains incomplete. No push, tag, publish or remote CI run.

Design preceded the value/type and performance changes in [query-values.md](../design/query-values.md). All ten advertised tables and 87 columns now have typed adapters and per-column oracle cases, including dict/directive/id/discrepancy, nested NULLs, generated annotations and assertion-time discrepancies. Exact projections on signed-zero-bearing sources still reject explicitly. The compiler registers 105 scalar and 11 aggregate signatures; 74 scalar signatures have evaluators, 31 remain unimplemented. Any-object aggregate/type domains are not complete Python semantics. Position DISTINCT preserves exact representation; integer arithmetic/sums preserve arbitrary precision. Stable cached ORDER BY uses O(n log n), with native 100k-posting row-by-row differential evidence.

All commands below ran after the final source commit using `MOON_HOME=/tmp/moon-new` and `/tmp/moon-new/bin` first in PATH. Oracle: beancount 3.2.3 / beanquery 0.2.0, CPython 3.14.6 / Unicode 16. Public runtime descriptors/APIs and independently authored inputs were used; upstream source/fixtures were not read or copied.

| Command | Actual result |
| --- | --- |
| `moon check --deny-warn --target all` | PASS; existing experimental async-package notices remain |
| `moon fmt --check` | PASS |
| `moon info`; `git diff --exit-code -- '*.mbti'` | PASS; zero further interface diff after intentional public additions were committed |
| `moon test --target all` | native / wasm / wasm-gc / js: 150/150 each |
| `moon build --target native` | PASS |
| `python3 scripts/conformance.py --ours _build/native/debug/build/cmd/main/main.exe --oracle /tmp/moonbean-r4-oracle/bin --ledgers tests/ledgers --oracle-version 3.2.3` | 120 ledgers: 118 comparable pass, 2 declared extensions |
| `python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin` | 657 checks PASS; covered positive/shared-error cases have zero mismatches. Count includes explicit rejection/capability checks, not 657 implemented features. Unicode query contains 7196 rows |
| `python3 scripts/random_differential.py --oracle /tmp/moonbean-r4-oracle/bin --seed 7 --count 1000 --allow-known-extensions` | 858 matches; 142 existing AVERAGE extension differences; 0 other differences; 468 clean query/report cases |
| Same command with `--seed 20261101` | Same counts; 0 other differences |
| `bash scripts/build-web.sh` | PASS |
| `node web/smoke.mjs` | 29 checks PASS |
| `node web/dom-smoke.mjs` | 8 checks PASS |
| `python3 scripts/bench-matrix.py --out .oracle-cache/r2-last/verified-4/performance` | All 36 default scenarios attempted, 35 complete; existing wasm-gc 1M FIFO default-heap OOM remains incomplete |
| `python3 scripts/bench-compare.py .oracle-cache/r2-last/verified-4/performance` | First full matrix FAIL: four stage p50 gates in three scenarios; records retained |
| Three predeclared repeats of those scenarios, same `bench-matrix.py`, 21 measurements / 2 warmups | All three rounds PASS unchanged baseline stage/RSS limits, with identical per-target artifact SHA-256 |
| `python3 scripts/bench-compare.py .oracle-cache/r2-last/verified-4/performance-confirmed` | PASS; unchanged 30% gate and unchanged incomplete-baseline exclusion |

The first matrix exceeded booking_AVERAGE for JS 1M and wasm-gc 1k, validate_pad_AVERAGE for wasm-gc 1k, and booking_STRICT for wasm-gc 1k. A fixed three-repeat plan was declared before repeating all three scenarios; every repeat passed. JS 1M booking p50 was 0.992 s initially, then 0.597 / 0.629 / 0.688 s (baseline 0.681 s). The confirmed directory retains all original scenarios except those three, for which it uses the **last** predeclared repeat, not the fastest. Original files were not overwritten. This is a confirmed comparison assembled from the full matrix plus repeats, not a claim that the first full matrix passed. The cause of timing variation is not established. Baseline samples, gate tolerance, benchmark driver and skip metadata were unchanged. Full repeat commands and results are in [execution](r2-final-execution.json) and [performance summaries](r2-final-performance.json).

CLI SHA-256 was unchanged before, after and at completion of both random runs. Performance ran after all differential processes exited. Earlier failed candidates and interrupted matrices remain under `.oracle-cache/r2-last/`; verified-3 was superseded by the integer precision fix. No failed/interrupted run is represented as final acceptance. New source/function workloads have not received million-row backend memory profiles. The baseline driver retains historical large ORDER BY timing skips; the new 100k native sorting evidence is functional, not a large-order performance gate.

Evidence: [BQL](r2-final-bql.json), [ledgers](r2-final-conformance.json), [tests](r2-final-tests.log), [check/web logs](r2-final-checks.log), [random summaries](r2-final-random.json), [94 independent grammar probes](r2-final-grammar.json), [confirmed gate output](r2-final-bench-compare.log), [full execution](r2-final-execution.json). Raw inputs, timing samples, failures and logs remain at `.oracle-cache/r2-last/verified-4/`.

Remaining scope is enumerated in [compatibility.md](../compatibility.md): 31 scalar signatures; full arbitrary-object aggregate/type/operator rules; subqueries/PIVOT/aliases/positional references; FROM filters and OPEN/CLOSE/CLEAR/accounts combinations; PRINT and shell .explain/.run; rounding-account postings; document stat/discovery callback; oracle display-context/multi-currency rendering; complete option/directive diagnostic parity. These are unfinished implementations, not claims of impossibility. Signed zero/nonfinite representation and uninspected malformed-object domains remain explicit limits. LIKE/JOIN and the tested FLATTEN/EXPLAIN keyword forms are rejected by the pinned oracle too. The 94 probes do not prove exhaustive grammar coverage.

[Closeout manifest](r2-final-closeout.json): original workspace/proposal preserved, no known task process left, no cleanup moves, no space-release claim. Two temporary generation helpers remain blocked because read-only Trash destination verification returned Operation not permitted; no move or retry was attempted. Current source, all evidence, shared toolchains and unknown files are retained. A verified local Git bundle and final clean-status receipt are retained in the ignored final run directory after the documentation commit.

Conclusion: the implemented increment passes correctness checks and the confirmed performance comparison; the full BQL/Beancount compatibility endpoint has not been reached.
