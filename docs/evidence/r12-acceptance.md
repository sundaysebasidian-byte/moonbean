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

All listed commands exited 0. Full logs are retained in [r12-checks.log](r12-checks.log), with command statuses in [r12-execution.json](r12-execution.json).

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

The interleaved matrix for frozen code `3a86c51` and main `992eaa2` is running. Earlier matrices are provisional. Final comparison and low-load rerun results will be recorded here before delivery.

## Closeout

Project closeout and the complete branch/evidence backup will be recorded after the performance run and final documentation commit. Source, fixtures, test evidence, frozen references and shared toolchain/oracle environments are retained throughout.
