# R11 BQL relation and scalar acceptance (0.2.5)

Status: **functional checks PASS; performance acceptance FAIL; full compatibility endpoint not reached.**

Implementation: `e01667e` on `compat-0.2.4`, based on `d53b8b5`. Version is **0.2.5**, per the updated brief; the branch name is unchanged. All work was confined to the existing `moonbean-r2` worktree. The main checkout and its local contact lines were not read/copied or modified. No push, publication, tag, remote CI or sub-delegation.

Toolchain: `MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH`; moon `0.1.20261104 (940aa18 2026-11-04)`. Oracle: `/tmp/moonbean-r4-oracle/bin`, beancount **3.2.3**, beanquery **0.2.0**, through public cursor/CLI execution only. No upstream Beancount/beanquery implementation or fixtures were inspected.

## Implemented and bounded scope

- Recursive materialized SELECT relations carry column names/types into outer filtering, projection, grouping and ordering. AS declarations, quoted alias declarations, and one-based GROUP BY/ORDER BY references follow the tested oracle rules. Aliases inside expressions and WHERE/HAVING remain ordinary source lookups. General quoted-identifier lookup and mixed star lists remain unsupported.
- PIVOT BY builds dynamic sorted headers, multiple measures and sparse NULL cells after LIMIT; duplicate cells keep the last value, equal axis keys keep the first representation. Ungrouped/incomparable-key failures match normalized oracle Evaluation categories. The oracle also rejects pivot-as-subquery at evaluation time.
- 25 of 31 previously missing scalar signatures now have full or bounded evaluators: convert/getprice/value, possign, date_part/date_trunc, maxwidth, joinstr, grep/grepn/findfirst/has_account/subst. Prices are query-local direct/inverse quotes with exact Decimal repr probes, dated precedence and cost-currency bridging; report multi-edge conversion was not substituted.
- Boolean/comparison, IS [NOT] NULL and regex SELECT expressions retain NULL and short-circuit behavior, support aggregate expressions and implicit grouping, and preserve the oracle Inventory truth error.
- Six signatures still have no evaluator: date_bin's two overloads, interval(str), parse_date's two overloads and today(). Python dateutil/strptime/relativedelta parsing and a portable clock are absent. Valid oracle examples are retained as explicit capability rejections. Python-only regex constructs/replacement escapes and empty-match substitution, multi-element joinstr or ambiguous findfirst, and maxwidth hyphen wrapping also remain explicit boundaries.
- Signed-zero round remains Unsupported because the Decimal core loses the sign. PRINT remains unimplemented: cursor directive rows and CLI ledger serialization require a distinct result/renderer contract. No table-rendered approximation or full-compatibility claim.

## Actual verification

All commands below use the toolchain environment above. Experimental async-package notices are pre-existing resolver notices; compilation/check commands exited successfully.

| Command | Observed result |
| --- | --- |
| `moon info` | `Finished. moon: ran 13 tasks, now up to date`; generated interfaces unchanged |
| `git diff --exit-code -- '*.mbti'` | exit 0, no interface diff to commit |
| `moon check --deny-warn --target all` | exit 0; `Finished. moon: ran 26 tasks, now up to date` |
| `moon fmt --check` | exit 0 |
| `moon test --target all` | 162/162 on native, wasm-gc, js, and additional wasm target |
| Initial `python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin` | unmodified baseline 3156/3156 PASS |
| Final `python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin` | 4030/4030 checks PASS (3156 original checks + 25 new signature checks + 849 R11 probes) |
| `python3 scripts/bql_r11_differential.py` | 849/849 checks PASS: 811 value/schema/shared-error comparisons and 38 explicit capability-boundary checks |
| `python3 scripts/bench-matrix.py --out .oracle-cache/r11/performance-release --runs 21` | 36 attempted; 35 complete, wasm-gc 1M FIFO incomplete (fatal default-heap OOM) |
| `python3 scripts/bench-compare.py .oracle-cache/r11/performance-release` | FAIL, exit 1: initial matrix exceeded three JS stages; final whole-case selection below still exceeds two |

Real test output:

```text
Total tests: 162, passed: 162, failed: 0. [wasm]
Total tests: 162, passed: 162, failed: 0. [wasm-gc]
Total tests: 162, passed: 162, failed: 0. [js]
Total tests: 162, passed: 162, failed: 0. [native]
```

The expanded differential retains the original 3156 checks, converts the former subquery/pivot rejection tests into success checks, adds evaluator-signature checks, and adds the R11 corpus. CLI status and normalized error categories are compared; diagnostic prose is not claimed identical. Thirty-eight R11 checks confirm explicit restrictions, including six oracle-error/MoonBean-Unsupported category differences; they are not counted as conformance successes.

A final schema audit retained a real failing counterexample before repair: currency/number pivot headers were `-1.0,1.0` instead of oracle `-1.00,1.00`. Three schema cases failed before; all six new axis-representation cases pass after. Relation metadata probes also exposed missing entry/meta dependencies and record-field lookup; their before/after evidence and fallback regression are retained. The fixture and four-backend unit regression are committed; raw before/after results remain in `.oracle-cache/r11/`.

## Performance and evidence

Performance acceptance is **not met**. The unchanged historical baseline and 30% tolerance were retained. The initial full matrix completed 35/36 scenarios; wasm-gc 1M FIFO exited -5 with `Fatal JavaScript out of memory: Ineffective mark-compacts near heap limit`, matching the existing excluded baseline scenario.

The initial JS 1M FIFO record exceeded regex (0.625 vs 0.413 s), transactions (0.308 vs 0.214 s) and length (0.594 vs 0.374 s). A separate 21-sample rerun started after all other task tests exited; the pre-run snapshot showed approximately 82% CPU idle. That complete rerun still exceeded four stages, including aggregate. A fixed `d53b8b5` source archive was then built/measured inside this worktree, without touching the main checkout. Its source tree/archive hashes are recorded; the runner's enclosing Git HEAD is explicitly distinguished from the archived source revision.

A third/final candidate run was declared before measurement. The final selection uses that entire latest JS case and every other case from the initial matrix; it never combines individual best stage values. All raw runs are retained. Final historical gate output:

```text
NOT GATED (incomplete baseline): wasm-gc-1000000-FIFO.json
js-1000000-FIFO.json/format: p50 3.708, baseline 2.771000s
js-1000000-FIFO.json/aggregate: p50 0.509, baseline 0.321000s
```

All other comparable stage medians and RSS satisfy that gate. Against the fresh same-machine main reference, aggregate still exceeds 30% (0.509 vs 0.356 s); all other stages/RSS are within tolerance. Aggregate was 0.361 s in the first candidate matrix, so measurements varied materially, but the cause is not established. These data do not certify absence of a performance regression. No performance PASS or complete release acceptance is claimed.

Reproduce the single-case repeat with `python3 scripts/bench-matrix.py --out <new-output> --targets js --sizes 1000000 --methods FIFO --runs 21`. Final combined comparison: `python3 scripts/bench-compare.py .oracle-cache/r11/performance-selected`; same-machine diagnostic: `python3 scripts/bench-compare.py .oracle-cache/r11/performance-final-retest --baseline .oracle-cache/r11/main-reference-d53b8b5/results`. Both exit 1. Snapshot loads are observations, not proof of continuous/exclusive host idleness.

Raw logs, provisional runs, exact oracle inputs/results and performance samples remain in ignored `.oracle-cache/r11/`. Earlier interrupted benchmark attempts are provisional evidence only. The final recorded matrix is identified above; no threshold or baseline was changed. Exported JSON evidence is normalized after comparison; source-dependent fingerprints are not recalculated from normalized paths.

Current evidence: [BQL](r11-bql.json), [R11 classifications](r11-probes.json), [checks/tests](r11-checks.log), [execution](r11-execution.json), [performance](r11-performance.json), [gate](r11-bench-compare.log), [same-machine gate](r11-main-bench-compare.log), [counterexamples](r11-counterexamples.json), [closeout](r11-closeout.json).

## Closeout

No cleanup moves: moved 0 bytes, retained current source, authored fixtures, all evidence and provisional runs, the fixed-version performance reference, shared toolchain/oracle environments, and unknown files. No verified disposable candidate was selected; no Trash target or restore move is needed. No task browser tabs/services were started; superseded task benchmarks were stopped, and the final process snapshot has no related test/benchmark process remaining.

The candidate/retention manifest and empty restore map are in [r11-closeout.json](r11-closeout.json). Branch/history bundle and raw-evidence archive are saved under `.oracle-cache/r11-closeout/`; `receipt.json` records final commit, clean Git status, backup hashes, verification and df values after the documentation commit. Compiler output for the frozen main-reference tester is retained locally and reproducible from its recorded source/toolchain; it is excluded from the compressed raw-evidence backup. No files were trashed/deleted and no freed-space claim is made.
