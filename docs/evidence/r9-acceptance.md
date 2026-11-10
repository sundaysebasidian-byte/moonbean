# R9 defect repair acceptance

Code revision `c115e9487cf6fc8e2af5dd4c6053e0960c0b8f3a`, branch `compat-0.2.3`. Documentation/evidence commit follows. No push, tag, publish or remote CI run. Toolchain: MOON_HOME=/tmp/moon-new, new bin first in PATH; oracle beancount 3.2.3 / beanquery 0.2.0, public black-box APIs only.

B1: SELECT aggregate/nonaggregate projections now infer grouping from nonaggregate projections, including supported OPEN/CLOSE ON sources. Groups preserve first encounter order and NULL keys; pure aggregates produce one row on nonempty input and no rows on empty input. WHERE aggregates and mixed aggregate/nonaggregate expressions raise Compilation. HAVING without explicit GROUP BY is a Syntax failure in the oracle and here. ORDER BY aggregates alone do not implicitly group. The new 55-case corpus (`tests/r9/`, `bql_r9_differential.py`) compares values/order/shared errors, including periods, HAVING, ordering, NULLs and empty input.

I1: bool(Inventory) now raises Evaluation, matching oracle NotImplementedError. The 1822-query per-argument audit covers all 105 advertised scalar signatures; zero oracle-error/MoonBean-success cases. It is not a Cartesian product or full value-domain proof. A list expression is a NULL proxy, not proof for real lists. Classification outcomes: 1634 matches, 152 error-category differences, 36 oracle-success/MoonBean-rejection cases. Of those 36, five are date/decimal/int(NULL) and getitem(Inventory,...) compilation rejections; 31 are explicit unsupported capabilities. Full classifications remain visible in [type matrix](r9-type-matrix.json), and restrictive gaps are disclosed in compatibility.md. Audit mismatches are not counted as conformance passes.

I2/S1–S4: README stars/object columns now agree with the matrix. IS [NOT] NULL and regex predicate support is distinguished from rejected projections. Malformed ledger salvage versus oracle empty results is explicit. S1's proposed universal negative-digit rejection is disproved: round(125.0,-1) succeeds in both; any signed-zero-producing row rejects the whole query. The function row now states this actual boundary. Exported evidence paths are normalized after comparison by `scripts/normalize_evidence.py`; current tracked content has no machine-home paths. Original source-dependent fingerprints remain unchanged; normalized filename tokens are not new hash inputs. Historical receipts are normalized too; original Git history/raw evidence remain intact.

| Command | Actual result |
| --- | --- |
| moon check --deny-warn --target all | PASS; existing experimental async-package notices |
| moon fmt --check | PASS |
| moon info; git diff --exit-code -- '*.mbti' | PASS; zero interface differences |
| moon test --target all | native / wasm / wasm-gc / js: 151/151 each |
| scripts/conformance.py, all ledgers | 120 ledgers; 118 comparable PASS, 2 declared extensions |
| scripts/bql_differential.py | 712 checks PASS, including 55 R9 cases; no unexpected mismatch in covered positive/shared-error cases. Explicit rejection checks are not implemented features |
| random_differential.py, seeds 7 and 20261101, count 1000, --allow-known-extensions | Each: 858 matches, 142 existing AVERAGE differences, 0 other differences, 468 clean query/report cases |
| bash scripts/build-web.sh | PASS |
| node web/smoke.mjs; node web/dom-smoke.mjs | 29 + 8 checks PASS |
| Original external review corpus, current CLI | 139 PASS / 1 FAIL / 6 SKIP. Remaining FAIL is the explicitly disclosed signed-zero round boundary; original runner/log retained, not relabeled as PASS |
| bench-matrix.py, authorized host-load run | 36 attempted, 35 complete; wasm-gc 1M FIFO retains default-heap failure |
| Initial bench-compare | FAIL: 13 limit violations in 8 scenarios |
| Fixed three repeats of all eight scenarios | Round 1: 6 violations; round 2: 1; round 3: 4. Same artifacts, samples, warmups, baseline and limits |
| bench-compare, originals plus third repeat for the eight scenarios | FAIL: four JS 1M FIFO stages below; not replaced with faster rounds |

Performance was first stopped when host load reached 187.73. The user then explicitly authorized measurement under the current background load without interfering with user applications, with a fixed three-repeat/third-result policy. Authorized start snapshots show load 4.05 and about 30% CPU busy; third-round start snapshots show load 3.92–3.93 and about 23–32% CPU busy. These are pre-run snapshots, not continuous per-stage utilization. All task differential processes had exited. No user applications were stopped. Raw interrupted/initial/repeat records are retained under `.oracle-cache/r9/final/`.

| Remaining third-round gate failure | p50 seconds | Baseline seconds |
| --- | --- | --- |
| JS 1M FIFO validate_pad_FIFO | 1.235 | 0.880 |
| JS 1M FIFO realize | 0.188 | 0.141 |
| JS 1M FIFO aggregate | 0.579 | 0.321 |
| JS 1M FIFO group | 1.030 | 0.692 |

The unchanged comparator excludes the pre-existing incomplete wasm-gc 1M FIFO baseline. It still fails the four stages above. No fourth repeat, tolerance increase or best-of selection was used. The observed variation does not establish its cause; this run cannot certify no performance regression. Independent idle-host review remains required. CLI SHA-256 was identical before/after random tests and at the end of performance.

Evidence: [BQL](r9-bql.json), [ledgers](r9-conformance.json), [tests](r9-tests.log), [checks/web](r9-checks.log), [random](r9-random.json), [review corpus log](r9-review-corpus.log), [execution](r9-execution.json), [performance summaries and all repeat outcomes](r9-performance.json), [final gate](r9-bench-compare.log), [closeout](r9-closeout.json). Raw inputs, sample arrays and logs stay in the ignored run directory.

Unresolved: performance under an idle host; restrictive type/error-category gaps above; signed-zero/nonfinite representation and malformed-ledger salvage differences; previously listed 31 scalar signatures, arbitrary-object/operator domains, subqueries/PIVOT/FROM combinations/PRINT/explain, rounding/document callback/rendering/diagnostic gaps. See [compatibility.md](../compatibility.md). No full compatibility claim.

Closeout preserves the original workspace/proposal and all evidence/shared environments. No cleanup moves or released-space claim; the two prior temporary helpers remain blocked by the previously denied Trash destination verification, with no retry. A complete verified local Git bundle and clean-status receipt are retained after the documentation commit.
