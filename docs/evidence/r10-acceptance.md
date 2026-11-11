# R10 aggregate-clause repair acceptance

Verified implementation revision `52c76962258f6e7e99a15038c51eb657541a8193`, branch `compat-0.2.3`. The documentation/evidence commit follows. No push, tag, publish or remote CI run.

Initial HEAD was detached at f24a65c, but all 454 working files matched b61fdc3 byte for byte. A normal switch refused to overwrite that state. After saving status/patch and verifying no staged changes, the index was aligned to the already-present target contents and `git switch compat-0.2.3` succeeded with clean status at b61fdc3. No stash/reset or working-file replacement was used. [Restoration record](r10-worktree-restore.json).

The temporary toolchain/oracle directories were absent on arrival. They were restored independently of the global installation and verified: moon 0.1.20261104 / moonc v0.10.20+65efd5b93, CPython 3.14.6, beancount 3.2.3 / beanquery 0.2.0. All checks use MOON_HOME=/tmp/moon-new and its bin first in PATH. Only public black-box oracle APIs were used; upstream source/fixtures were not inspected.

| Item | Result |
| --- | --- |
| B2 | Fixed. In aggregate queries, nonaggregate SELECT/ORDER BY targets must match a grouping expression. Derived expressions such as account_sortkey(account) are not automatically covered by account. Uncovered ordinary order targets raise Compilation, including pure aggregates and HAVING/LIMIT combinations |
| B3 | Fixed. HAVING needs explicit GROUP BY and an aggregate expression. Nonaggregate group-key regex/constant predicates raise Compilation |
| I3 | Implemented. Implicit tags/links grouping on notes/transactions uses membership equality, combines equal sets spelled in different orders, groups empty sets and retains first-encounter output order. Explicit GROUP BY rejection categories still match the oracle |
| S5 | count(DISTINCT x) now fails as Syntax, matching the oracle instead of the old Unsupported diagnostic |
| S6 | Boolean operator/comparison projections, including implicit grouping keys, remain unimplemented and explicitly documented. Boolean literals and bool() calls are distinct supported cases |
| S7 | Unit tests confirm LIMIT -1 is Syntax in the public failure() API, matching the oracle. The legacy CLI-only classifier's Evaluation label was incorrect; the classifier now follows the public prefix contract |

The systematic audit generates 2444 calls: a Cartesian grid of SELECT/projection, DISTINCT, grouping, WHERE, HAVING, ORDER BY and LIMIT, targeted order cases, OFFSET, plus set grouping cases. 2433 compare values/order or shared error categories; 11 are explicit rejection-boundary checks, not supported features. Six computed-key aggregate DISTINCT queries, two Boolean/comparison projections, two mixed HAVING queries and one mixed ORDER BY query remain oracle-supported rejections. The mixed row/aggregate cases exposed incorrect row-reference binding; they now reject explicitly instead of producing approximated values. No oracle-error/MoonBean-success case remains in this bounded audit. It is not a completeness claim for all language combinations.

| Command | Actual result |
| --- | --- |
| moon check --deny-warn --target all | PASS; existing experimental async-package notices remain |
| moon fmt --check | PASS |
| moon info; git diff --exit-code -- '*.mbti' | PASS; zero interface changes |
| moon test --target all | native / wasm / wasm-gc / js: 153/153 each |
| scripts/conformance.py, all ledgers | 120 ledgers: 118 comparable PASS, 2 declared extensions |
| scripts/bql_differential.py | 3156 checks PASS, including the 2444 R10 audit/boundary calls |
| random_differential.py, seeds 7 and 20261101, count 1000, --allow-known-extensions | Each: 858 matches, 142 existing AVERAGE extension differences, 0 other differences, 468 clean query/report cases |
| bash scripts/build-web.sh | PASS |
| node web/smoke.mjs; node web/dom-smoke.mjs | 29 + 8 PASS |
| bench-matrix.py, one complete default matrix | 36 scenarios attempted, 35 complete; existing wasm-gc 1M FIFO default-heap failure remains incomplete |
| bench-compare.py | FAIL: seven wasm-gc stage limits below. Native and JS have no exceeded limits. No load-driven repeats |

Performance ran after all task differential processes exited. Pre-run load averages were 35.22 / 44.54 / 27.02. A snapshot during measurement showed load 13.07 and CPU 27–50% busy, including this benchmark. These are snapshots, not continuous stage utilization; the machine was not established idle. Per user instruction, the matrix was run once without modifying baselines/thresholds or repeating due to load. This run does not certify no regression and does not establish the cause of exceeded limits.

| Exceeded wasm-gc stage | p50 seconds | Baseline seconds |
| --- | --- | --- |
| 1000 FIFO format | 0.001667 | 0.001176 |
| 10000 AVERAGE validate_pad_AVERAGE | 0.009 | 0.006667 |
| 100000 AVERAGE validate_pad_AVERAGE | 0.092 | 0.070 |
| 100000 FIFO validate_pad_FIFO | 0.103 | 0.061 |
| 100000 FIFO realize | 0.018 | 0.0125 |
| 100000 FIFO regex | 0.063 | 0.040 |
| 100000 FIFO transactions | 0.031 | 0.019 |

The unchanged comparator retains the incomplete wasm-gc 1M FIFO baseline exclusion. Raw samples, logs, failed/provisional probes, load snapshots and setup recipe remain in `.oracle-cache/r10/`. CLI SHA-256 stayed identical before/after random tests and at completion of performance. Implementation sources were unchanged throughout final verification.

Evidence: [BQL audit/classifications](r10-bql.json), [ledger results](r10-conformance.json), [tests](r10-tests.log), [checks/web](r10-checks.log), [random summaries](r10-random.json), [execution](r10-execution.json), [performance summaries/load](r10-performance.json), [gate output](r10-bench-compare.log), [closeout](r10-closeout.json). Exported evidence is normalized after comparison; raw paths and original source-dependent fingerprints remain available locally.

Remaining: the eleven audit boundaries above; previously listed scalar/type/operator/statement/option/diagnostic gaps in [compatibility.md](../compatibility.md); performance certification under an idle host. No full-compatibility or performance-PASS claim. The reviewer's separate 100k stress corpus was not reproduced here; this acceptance covers the named regression commands and authored R10 fixtures.

Closeout: original workspace/proposal fingerprint preserved, no user application stopped, no known task process left. No cleanup moves, no space-release claim. Two previously blocked temporary helper paths were already absent in this run; this task did not remove them. Current source, raw evidence, shared environments, installer recipe, prior backups and unknown files are retained. A complete verified local bundle and clean delivery receipt are saved after the documentation commit.
