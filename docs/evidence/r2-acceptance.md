# 0.2.3 local candidate acceptance

Source revision: `b84a85fd0f1c9298f966205c9627384cb34c47f4` (documentation commit follows). Branch `compat-0.2.3`; baseline `86137ab`. No push, tag, publish or new CI run.

All commands ran in the isolated worktree with `MOON_HOME=/tmp/moon-new` and `/tmp/moon-new/bin` first in PATH. Oracle: beancount 3.2.3 / beanquery 0.2.0, external black-box processes only. This is bounded regression evidence, not full compatibility.

| Command | Actual result |
| --- | --- |
| `moon check --deny-warn --target all` | PASS; compiler reports zero warnings/errors. The existing async experimental-package notices remain. |
| `moon fmt --check` | PASS |
| `moon info`; `git diff --exit-code -- '*.mbti'` | PASS; no interface changes |
| `moon test --target all` | PASS; 136 tests on each of native / wasm / wasm-gc / js |
| `python3 scripts/conformance.py --ours _build/native/debug/build/cmd/main/main.exe --oracle /tmp/moonbean-r4-oracle/bin --ledgers tests/ledgers --oracle-version 3.2.3` | 116 ledgers; 114/114 compared pass, 2 known extensions |
| `python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin` | 109 output/capability/rejection checks pass; 0 failures |
| `python3 scripts/random_differential.py --oracle /tmp/moonbean-r4-oracle/bin --seed 7 --count 1000 --allow-known-extensions` | 858 matches, 142 existing AVERAGE differences, 0 other mismatches; 468 clean query/report cases |
| Same command with `--seed 20261101` | Same counts; 0 other mismatches |
| `bash scripts/build-web.sh` | PASS |
| `node web/smoke.mjs` | 29 checks PASS |
| `node web/dom-smoke.mjs` | 8 checks PASS |
| `python3 scripts/bench-matrix.py --out .oracle-cache/r2/performance-final` | Full default matrix measured after random processes completed |
| `python3 scripts/bench-compare.py .oracle-cache/r2/performance-final` | PASS with default 30% p50/RSS gate; incomplete baseline wasm-gc 1M FIFO remains excluded |
| `git diff --check` | PASS |

Committed [check/toolchain logs](r2-checks.log) and [web logs](r2-web.log).

Committed results: [BQL](r2-bql.json), [ledger comparisons](r2-conformance.json), [test output](r2-tests.log), [random summary](r2-random-summary.json), [performance summary](r2-performance-summary.json), [performance gate](r2-bench-compare.log). Benchmark artifacts retain the source revision captured when the matrix started; the subsequent OPEN/accounts rejection changes an unsupported period-query path absent from benchmark and random inputs. Four-backend and BQL checks were rerun for that guard. Full generated ledgers, measurement arrays and command logs are retained under `.oracle-cache/r2/` in the worktree. The initial benchmark run overlapped random testing and was stopped; its partial outputs under `performance/` are retained but excluded from acceptance. Only `performance-final/` is used for the gate. Its JS 100k AVERAGE case was remeasured alone after the first pass exceeded the gate during concurrent follow-up checks; the original record is retained at `.oracle-cache/r2/js-100000-AVERAGE-concurrent.json`.

Known performance boundaries are unchanged: >=100k ungrouped ORDER BY is skipped (existing insertion sort); wasm-gc 1M FIFO is not a completed baseline. Scalar/set DISTINCT currently uses a quadratic uniqueness pass and does not claim large-query scalability. Amount/position/inventory DISTINCT is explicitly rejected because oracle position deduplication does not follow ordinary numeric equality.

[Compatibility gaps](../compatibility.md) remain substantial: eight oracle tables, missing columns/signatures, subqueries, PIVOT/FLATTEN/CLEAR, Unicode casing, PRINT/EXPLAIN and multiple option/directive semantics. Language/operator enumeration and all error-category combinations are not exhaustive. This candidate does not meet full beanquery compatibility.

Closeout: [manifest and preservation record](r2-closeout.json). No files moved to Trash; no space-release claim. The worktree, original proposal modifications, toolchains and evidence are retained. No task-owned persistent server or browser tab was opened.
