# R12 acceptance for the local 0.2.6 candidate

## Versions and scope

Implementation code is frozen at `3a86c51517e92191418c68b890fdb32f098708e9` on `compat-0.2.6`, based on main `992eaa2c46c2398a0cb0c456dd6b51e7d142b844`. Work stayed in the existing `moonbean-r2` worktree. No push, tag or publication was performed.

Commands use `MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH`. The black-box oracle is `/tmp/moonbean-r4-oracle/bin`, with Beancount 3.2.3 and beanquery 0.2.0. Public cursor APIs, CLI output and runtime descriptors supplied oracle evidence. Its source was never read.

## Implemented and compared

- Both date_bin and parse_date overloads, interval strings and today. Native and JS read local calendar dates. The wasm host exposes epoch milliseconds, so wasm-gc uses UTC. Cross-day Kiritimati checks verify the native/JS local date and the documented wasm UTC date.
- Query-only negative zero preserves round, Decimal-string conversions, arithmetic, safediv, rendering and tested consumers. Accounting Decimal storage retains its existing representation.
- PRINT has a distinct DirectiveText result, typed directive rows and a native CLI path. Nine statements across 118 oracle-domain ledgers produce 1062 byte-for-byte comparisons, including error-ledger recovery, predicates, OPEN/CLOSE/CLEAR, metadata, summaries and conversions. The two intentional extension ledgers are excluded.
- Unknown and shadowed transaction columns now raise Compilation. The tracked independent review corpus has 199 conformant checks and two randomized-set rejections across its 201 cases. Six of its eight documented differences are closed.
- Empty substitution, tested hyphen wrapping, capture replacements, escaped metacharacters, scoped case-insensitivity, noncapturing groups and bounded regex repetition. Lazy matches execute when they avoid an empty match before remaining input.
- IN/NOT IN, literal lists, BETWEEN, integer/Decimal remainder, Inventory getitem, source-aware quoted lookup, structural DISTINCT, mixed aggregate clauses and canonical JOURNAL/BALANCES. SELECT source transforms retain synthetic identities and original-ledger price context. Cost-bearing CLEAR transfers use cost value.

## Required commands and real results

All listed commands exited 0. Complete logs and command statuses are retained. [Logs](r12-checks.log), [execution](r12-execution.json).

```text
moon info
Finished. moon: ran 12 tasks, now up to date
moon check --deny-warn
Finished. moon: ran 13 tasks, now up to date
moon fmt --check
Finished. moon: ran 73 tasks, now up to date
moon test --target native
Total tests: 181, passed: 181, failed: 0.
moon test --target wasm-gc
Total tests: 181, passed: 181, failed: 0.
moon test --target js
Total tests: 181, passed: 181, failed: 0.
python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin
BQL differential: 7502/7502 checks passed
```

Regenerated interfaces are committed. `git diff --exit-code -- '*.mbti'` exits 0. Existing experimental async dependency notices remain in the logs.

The 7502 checks retain the original 4030, activate six additional existing signature/value cases and add 3466 R12 checks. There are 7488 value/error conformance checks and 14 explicit capability-rejection checks. The latter comprise six randomized-set cases, five conservative lazy-substitution rejections, two source-negative-zero representation cases and one nonfinite Decimal case. Rejections retain nonzero status and are separately recorded in [r12-boundaries.json](r12-boundaries.json).

The per-argument type audit reports 1822 checks, zero oracle-error/MoonBean-success cases and zero category differences. It includes historical proxy list expressions. Separate R12 cases exercise real lists and intervals. Five extra target/timezone runs all pass. [BQL results](r12-bql.json), [type audit](r12-type-matrix.json), [clock checks](r12-clock-targets.json).

Evidence is normalized after comparison. Source-dependent fingerprints retain values from the original inputs. Raw evidence and earlier provisional attempts remain in `.oracle-cache/r12/`.

## Remaining boundaries and reasons

- Ambiguous findfirst, multi-member joinstr and multi-member set representation depend on the oracle process's private randomized hash iteration. The portable engine retains explicit rejection for exact textual/order-dependent results.
- Python regex lookaround, pattern backreferences, Unicode classes and additional flags exceed the portable matcher contract. Its forward-progress iterator lacks Python's adjacent nonempty retry after an empty match. Lazy patterns with empty matches before remaining input are conservatively rejected because the iterator cannot request the nonempty retry. Locale-sensitive regex and complete Python regex equivalence remain unverified.
- Nonfinite Decimal values and documented exponent/rounding resource bounds exceed the finite accounting value model. Parsed source negative zero loses its sign before exact object/fingerprint projection, so those projections retain explicit rejection. Query-produced signed zero is supported.
- Date parsing implements the authored English/C-locale and dateutil-style corpus. Complete dateutil grammar, host locales and timezone-name combinations remain unverified. The wasm host has no local-timezone calendar service.
- Partial set sorting, exhaustive object/operator combinations and all malformed-loader recovery shapes remain bounded by authored evidence. General table/JOURNAL/BALANCES text layout retains the existing renderer contract. PRINT has the separate byte-level contract above.
- Interactive `.explain` and `.run` need shell state and a host output protocol. Genuine non-BQL exclusions include external Python plugins, document stat/discovery callbacks, renamed account taxonomy, account_rounding and the option/report limits in [compatibility.md](../compatibility.md). LIKE/JOIN and the probed FLATTEN/EXPLAIN keywords are rejected by the oracle.

## Performance

The unchanged `scripts/bench-matrix.py` runs all 36 target/size/method cases for main `992eaa2` and frozen implementation `3a86c51`, alternating baseline/candidate order. Each invocation uses 15 measurements, two warmups, a 20 ms minimum batch and the existing 30% median/RSS gate. The runner and benchmark-driver hashes are retained with the pinned source-archive hashes.

The initial matrix has 35 complete cases per side. Both wasm-gc 1M FIFO processes exit -5 with `Fatal JavaScript out of memory: Ineffective mark-compacts near heap limit`. That case remains unmeasured. The driver exits 0 while recording an incomplete case, so acceptance also checks each case's status.

Three complete pairs were repeated after selecting every stage/RSS ratio above 1.10, plus the historical JS 1M FIFO case. This selection threshold controls investigation. The acceptance gate stays at 1.30. The repeated cases are JS 100k FIFO, JS 1M FIFO and native 1M FIFO. Pre-run CPU idle is 89.49%–92.48% across the six invocations. Every repeat uses the same artifact hash as its initial run. Entire latest case pairs replace the originals for assessment, with every original sample retained. No best-stage selection is used.

```text
python3 scripts/bench-compare.py .oracle-cache/r12/performance-3a86c51-assessment/candidate --baseline .oracle-cache/r12/performance-3a86c51-assessment/baseline
NOT GATED (incomplete baseline): wasm-gc-1000000-FIFO.json
PASS: all baseline stage medians and RSS within tolerance
```

All 35 comparable pairs pass after low-load repeats. The largest final stage ratio is 1.074074 for wasm-gc 100k FIFO aggregate. This evidence retains the shared wasm heap gap and the driver's historical large-ORDER BY timing skips. The existing native 100k ORDER BY functional differential passes.

Snapshot directories live inside the working repo. The runner's `environment.commit` records the enclosing documentation/worktree HEAD. Actual measured source commits are pinned separately in `sources`, with archive hashes. The archived main checkout was never modified. Earlier cancelled matrices remain provisional evidence. [Complete samples and execution metadata](r12-performance.json), [final gate output](r12-bench-compare.log).

## Closeout

No files were moved to Trash and no permanent deletion was performed. Moved bytes are 0. Current source, fixtures, original inputs, all evidence and provisional runs, frozen references, build outputs, shared toolchain/oracle environments and unknown files are retained. No disposable candidate was selected. Task-owned benchmark and test processes completed, and no browser or service was started.

The retention manifest and empty restore map are recorded in the closeout summary. Complete branch/history, current tracked-tree, native CLI and task-evidence backups are verified under `.oracle-cache/r12-closeout/` after the final documentation commit. Its `receipt.json` records the delivery commit, clean Git status, backup hashes, verification and df snapshots. Observed disk changes are recorded separately from moved bytes, with no freed-space claim. [Closeout summary](r12-closeout.json).
