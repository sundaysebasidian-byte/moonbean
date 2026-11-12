# R12 acceptance: independent-review rework of 0.2.6

## Version and method

This supersedes the acceptance claims for `f1cb94a`. Implementation is frozen at `ed31935cbccdb1334133e61fb57339d996c71379`; tracked review corpora are in `91b746c`. Main remains `992eaa2c46c2398a0cb0c456dd6b51e7d142b844`. Work stayed on `compat-0.2.6` in the existing `moonbean-r2` worktree. Version remains 0.2.6. Nothing was pushed, tagged or published.

Both independent reports were read before modifications. Every reported behavior was reproduced against `/tmp/moonbean-r4-oracle/bin` (Beancount 3.2.3 / beanquery 0.2.0). Only CLI, public cursor/printer/account APIs and runtime descriptors were used; oracle source was never read. Commands use `MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH`. Final cross-target tests and differential run with `TZ=UTC`; the unit-test date expectation comes from the oracle on the same day.

[Before-fix reproductions and oracle observations](r12-review-reproductions.json) retain A's 304-case run with 21 failures, the B finding repros, and all 168 successful-output byte differences on repository ledgers after excluding extension ledgers 035/058. The expanded baseline PRINT run had 11340 comparisons and 1404 total differences, including additional reviewer fixtures and error-category differences. All provisional attempts remain in `.oracle-cache/r12-rework/`; none is presented as a final pass.

## Findings and fixes

| Review finding | Resolution and regression |
| --- | --- |
| A date arithmetic; B 6/9 interval operations | Date±int, int+date, date−date, date±interval, interval+date and interval±interval now execute with typed values, month-end clipping and overflow errors. The 144-case operand/operator matrix includes invalid signatures and NULLs. interval−date raises Evaluation TypeError in both engines. |
| A two-digit years | Leading numeric years above 31 are expanded using the existing dateutil-style year window: `99-12-31` and `99/12/31` become 1999-12-31; `50-06-15` becomes 2050-06-15. |
| A round overflow | A quantized Decimal coefficient beyond the oracle's 28-digit precision raises Evaluation InvalidOperation, including the reported carry from 9999999999999999999999999999.5. Accounting Decimal storage is unchanged. |
| A unknown source | `FROM #nope` raises Compilation, including on empty inputs. Existing unknown/shadowed-column regressions remain active. |
| B 1 OPEN order | Ordinary same-day directives retain original source order; SELECT, JOURNAL and PRINT regressions include the reported Transit pass / First lot ordering. |
| B 2 CLEAR date | Transfer entries use the last transformed ledger entry's date, including after CLOSE. PRINT predicates apply after transformations, preventing filters from changing the transfer date or summary input. |
| B 3 cost summary | Prior Income/Expenses lots reduce to cost amounts before earnings summaries; ordinary asset lots retain their identity. |
| B 4 balance duplicates | Assertion identity includes account, date and currency; distinct same-day currencies no longer conflict. bean-check exit parity is retained. |
| B 5 Unicode accounts | Lexer recognition and semantic validation are separate. Valid Unicode letter/digit categories, digit-prefixed child accounts and supplementary-plane letters survive parsing and querying. Invalid names remain available for validation where the oracle lexer retains them. Character masks are generated directly from the pinned public account predicate, whose accepted domain exceeds its Unicode 16 category database; the generator and unit fixtures are tracked. |
| B 7 PRINT grouping | Repeated pad/document/query/custom groups no longer gain spurious blank lines. Transaction/commodity separation and changes of directive kind follow the oracle corpus. |
| B 8 tag/link order | PRINT sorts by Unicode code point rather than MoonBit's length-first string order; supplementary characters have regression coverage. |
| B 9 empty narration | Nonempty payee with empty narration prints the required `""`. |
| B 10 deep recursion | Excessive nesting/operator chains return `syntax query.depth_limit`, exit 1, instead of crashing. The portable limit is 256 nested parentheses or 256 recursive operators. Unit tests cover the boundary and oversized input on all three targets. |
| B 11 quoted nontransaction fields | note/event/query/custom/document raw strings mirror the oracle's observed printing, even when embedded quotes produce text that cannot round-trip. Transaction and metadata strings keep their distinct escaping rules. |
| B 12 metadata values | Currency/account/tag metadata print as quoted strings, matching their loaded oracle values. |
| B 13 coalesce | The special form accepts uniform argument types, evaluates arguments eagerly and preserves the reported constant-error precedence. Zero arguments raise Evaluation IndexError; incompatible declared types raise Compilation. No exhaustive multiple-error precedence claim is made. |
| B 14 one-character metadata key | The invalid token discards the owning directive, including transaction/posting cases, matching the reviewed loader recovery. |
| B 15 entry metadata scope | PRINT entry_meta/any_meta require an entry-bearing source and raise Compilation on the reported directive source. |
| B 16 evidence claim | PRINT claims are restricted to the exact widened corpus below. Arithmetic status and resource boundaries are stated explicitly. |

No finding was dismissed as a false positive. Two surprising oracle behaviors were confirmed and mirrored:

```text
SELECT interval('1 month')-interval('2 days') LIMIT 1
public cursor description: beanquery.Column(..., date)
public cursor row: (relativedelta(months=+1, days=-2),)
```

Downstream year/month/day, quarter/weekday/yearmonth, date conversion, comparison, arithmetic and calendar consumers have regressions for that declared-type/value mismatch. `OPEN ON ... CLOSE CLEAR` without a CLOSE ON date raises Evaluation TypeError in the oracle and MoonBean. Raw quote behavior above is also oracle behavior, not a round-trip guarantee. Exact observed output is in the reproduction packet.

## Required validation

All eight commands exited 0. Real output (complete notices/logs are linked below):

```text
$ moon info
Finished. moon: ran 12 tasks, now up to date
$ moon check --deny-warn
Finished. moon: ran 14 tasks, now up to date
$ moon fmt --check
Finished. moon: ran 75 tasks, now up to date
$ moon test --target native
Total tests: 191, passed: 191, failed: 0.
$ moon test --target wasm-gc
Total tests: 191, passed: 191, failed: 0.
$ moon test --target js
Total tests: 191, passed: 191, failed: 0.
$ python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin
BQL differential: 20549/20549 checks passed
```

The 20549 passing checks comprise 19928 oracle value/error/validation comparisons, 14 existing explicit capability-rejection checks, and 607 parser robustness/resource checks. The widened PRINT matrix contains 11502 successful byte comparisons and 426 shared failures. All 18 deep-construct inputs reached the engine and returned the clean limit error. Four mutation/special cases were rejected by the host argv layer and are not parser evidence. The separate 1822-case type audit has zero permissive successes and zero category differences. The public account-character audit has 3336192 checks and zero table differences.

The tracked main differential retains the previous 7502 checks, including the original 4030. Review A contributes all 317 cases, including 13 controls previously omitted by duplicate-query discovery. Review B contributes 84 PRINT statements (all 81 reviewer statements plus three transformation/filter controls) across exactly 142 ledgers, and 802 operator/source/validation/parser checks. Fixtures include every reviewer ledger plus quoting, metadata, transform-filter and supplementary-account controls.

PRINT compares exact successful stdout bytes and exact failure exit status/category. Its public cursor/printer worker was independently compared with bean-query CLI for all 11340 baseline calls: zero differences. Failure diagnostics are classified by shared category; exact diagnostic prose is not promised. Row and column order are preserved in the A/B scalar comparisons; set cells use the existing typed equivalence rule.

The parser corpus has 589 deterministic mutation/special cases and 18 deep-construct cases. These are resource/robustness checks, not oracle conformance. Host argv rejection (NUL/E2BIG) is recorded separately and does not prove parser handling of those inputs. Remaining explicit rejection checks retain their own classification. [Current differential](r12-review-bql.json) stores PRINT byte counts and SHA-256 after comparison; complete output and raw logs remain in the task cache. [Command statuses](r12-review-execution.json), [full command logs](r12-review-checks.log), [type audit](r12-review-type-matrix.json).

Regenerated interfaces are committed. `moon info` followed by `git diff --exit-code -- '*.mbti'` is clean. Experimental async dependency notices remain in command logs. The current native CLI is native-only; library tests pass on native, wasm-gc and JS.

## Performance after code settled

The frozen `ed31935` implementation and main `992eaa2` each ran all 36 target/size/method cases in 72 interleaved invocations. Each side has 35 complete cases. Both wasm-gc 1M FIFO processes exit -5 with `Fatal JavaScript out of memory: Ineffective mark-compacts near heap limit`; that pair remains unmeasured. The outer driver exits 0 for these incomplete cases, so individual case status was checked explicitly.

Three full pairs were repeated: JS 100k FIFO, JS 1M FIFO and native 1k FIFO. Selection used any initial stage/RSS ratio above 1.10, plus the historical JS 1M FIFO case; the acceptance gate stayed at 1.30. CPU idle before the six repeat invocations ranged from 90.74% to 93.90%. Initial JS 1M candidate completion coincided with a 1-minute host load of 9.19; its original samples remain recorded. Repeat artifact hashes match the initial ones. All 35 comparable final pairs pass the original median/RSS gate after replacing whole repeated pairs.

```text
$ python3 scripts/bench-compare.py .oracle-cache/r12-rework/performance-ed31935-assessment/candidate --baseline .oracle-cache/r12-rework/performance-ed31935-assessment/baseline
NOT GATED (incomplete baseline): wasm-gc-1000000-FIFO.json
PASS: all baseline stage medians and RSS within tolerance
```

[Measurements, source/artifact hashes, host snapshots and original/repeat samples](r12-review-performance.json), [gate output](r12-review-bench-compare.log). The historical large-ORDER BY timing skips remain; the separate native large-order functional differential passes. This is the existing tolerance gate, not proof of zero timing change or performance for the unmeasured heap case.

Both source archives and the unchanged bench-matrix.py hash are pinned. The main checkout was not built or modified: baseline runs use its verified frozen archive under the existing worktree. Every invocation uses 15 measurements, two warmups, 20 ms minimum batching and the original 30% stage-median/RSS gate. Baseline/candidate order alternates by complete case; every invocation records host load and CPU idle. Whole-case repeats replace original pairs for assessment; samples and failed attempts remain available, with no best-stage selection.

Snapshot directories are inside this repository. The benchmark's environment.commit records the enclosing worktree HEAD, while the source commit/archive hashes identify the actual implementation. The archive hashes, driver hashes and artifact hashes are the source identity evidence.

## Remaining boundaries

- CPython process-randomized set iteration prevents exact ambiguous findfirst, multi-member joinstr and order-dependent set representation. These remain explicit rejections; deterministic/single-member cases execute.
- Python regex lookaround, pattern backreferences, Unicode classes/extra flags and adjacent empty/nonempty lazy-retry semantics exceed the portable matcher. The five conservative lazy-substitution rejections remain documented; ordinary empty substitution and the reviewed hyphen wrapping are supported.
- Nonfinite Decimal values, source-parsed negative-zero exact object projections, and documented numeric/resource bounds remain excluded. Query-produced signed zero remains supported, including round and tested consumers.
- Date parsing is bounded by the authored dateutil/strptime corpus, including the new two-digit-year cases. Complete dateutil grammar, locales and timezone names are unverified. Native/JS use local calendar dates; wasm-gc uses UTC because its host API lacks a local calendar service. Historical cross-day clock evidence remains in r12-clock-targets.json; this rework's required tests use the current oracle UTC date.
- PRINT equality is established only for the specified matrices. Exhaustive malformed-loader recovery, combinations of transforms, arbitrary object/operator behavior and general table/JOURNAL/BALANCES text layout remain unproven. Exceeding the documented query recursion budget yields a deliberate Syntax resource error.
- Genuine non-BQL exclusions remain: external Python plugins, document stat/discovery callbacks, renamed-root accounting behavior, account_rounding and the option/report effects listed in compatibility.md. Interactive .explain/.run need shell state/output protocols. LIKE/JOIN and the probed FLATTEN/EXPLAIN keyword forms are rejected by the oracle.

This finite evidence closes the reported findings; it does not establish complete beanquery or Beancount equivalence. Earlier r12-*.json/log files retain the historical f1cb94a acceptance data; current rework files use r12-review-* names.

## Closeout

The local closeout packet is `.oracle-cache/r12-rework-closeout/`: `manifest.json`, `restore-map.json`, `execution.jsonl`, `receipt.json` and before/after df snapshots. The receipt records the delivered commit, unchanged main SHA, clean Git status, process checks, Git bundle verification, tracked-blob checks, raw-evidence hashes and native CLI backup hash. A copy of both frozen source inputs is retained with the evidence.

No cleanup candidate was selected: zero Trash moves, zero moved bytes and zero attributable space-release claim. Current source, main rollback, original/review inputs, provisional and final evidence, frozen build artifacts, shared toolchain/oracle and unknown files are retained. The restore map has no moved items. No browser or server was started; benchmark/test helper processes are checked at closeout. Observed df changes are reported separately in the receipt and are not attributed to cleanup. The earlier f1cb94a closeout packet remains protected.
