# R14 acceptance for MoonBean 0.2.8

The pinned environments were restored on 2026-11-15 (local time). Correctness acceptance passed against the restored oracle; paired performance measurements are in progress; the earlier interrupted attempt is retained as historical evidence in [the environment blocker record](r14-environment-blocker.json).

## Source and method

Work uses compat-0.2.8 in the existing moonbean-r2 worktree. The comparison baseline is `e33a3fc6b72470193ef25b98aff322579c266bf0`, the reviewed 0.2.7 source. Runtime implementation is frozen at `344ad10a26c69191c40857d10a76922253828c19`. The preserved partial benchmark archived e33a3fc and e38ff33. Runtime files in e38ff33 and 344ad10 are identical. The latter commit strengthens the Python diagnostic comparison. Source archives, build logs and artifact hashes retain these identities.

Commands use `MOON_HOME=/tmp/moon-new PATH=/tmp/moon-new/bin:$PATH`. The black-box oracle is Beancount 3.2.3 / beanquery 0.2.0 in `/tmp/moonbean-r4-oracle/bin`. Public loader, cursor, printer, datetime and dateutil APIs supplied observations. Oracle source was never inspected. Correctness tests use TZ=UTC and the current oracle date (2026-11-16 for this rerun). The restored oracle uses Python 3.14.7, replacing the earlier 3.14.6, with python-dateutil 4.0.0; Beancount 3.2.3 and beanquery 0.2.0 are unchanged. The system Python driving the differential remains 3.14.6. [Restored environment](r14-environment.json).

## S1–S7

| Finding | Implementation and verification |
| --- | --- |
| S1 host-clock import contract | Linking host_clock requires moonbean:clock.local_date at instantiation. An absent import raises TypeError before guest execution, even when install is unused. After import resolution, zero/invalid results or unused installation select the target UTC default. Unlinked Wasm programs use UTC. CHANGELOG and compatibility wording state these preconditions. |
| S2 DST and short years | Added Los Angeles 2024-03-10T07:30Z and 2024-11-03T06:30Z, whose local dates are the preceding calendar day. Added years 2079/2080 and parse_date('06-15-29'), checked against fresh public dateutil parserinfo objects under the fixture year. The result changes from 2029-06-15 to 2129-06-15. |
| S3 host scope | Imported-module integration tests execute wasm-gc on Node 24.18.0 / V8. The wasm target also declares the import. Browser, wasmtime and non-GC wasm adapter integration remain unverified. Native/JS library tests exercise their respective default clocks. |
| S4 lexer provenance | Retained lexer 27195325… is an uncommitted pre-format snapshot. Pinned moonfmt produces the exact published e33a3fc lexer 4e5b72e7…. The difference is layout of the word-cache match arm. Corrected r13-acceptance.md and the profile_source_note preserve the actual historical source hash and identify this difference. |
| S5 repeatability and memory | Pending. One baseline process completed before interruption. Three complete pairs and heap-headroom measurements await restoration of the pinned environments. |
| S6 unterminated literals | Incomplete strings raise Invalid token diagnostics at the physical opening line, discard the affected directive and recover following directives. A closing quote on a later line forms a multiline literal. Backslash-newline is a lexical error in the oracle. |
| S7 ordinary syntax | Multiline text preserves indentation, blank lines, CRLF and source locations. Amount, expression and empty metadata retain typed values through BQL, PRINT and export. Pushed metadata follows transaction scope. Include expansion handles logical lines and escaped paths. fmt preserves a multiline ledger's original layout. |

[Lexer byte provenance](r14-lexer-provenance.json) retains full hashes. The historical R13 sampled-RSS values retain their original provenance. The new performance packet uses pristine committed sources.

## Review classifications and parser evidence

All 73 original classification mismatches were reproduced before editing, using the original reviewer paths. Exact fixture bytes and hashes are tracked under tests/r14/review. The copied corpus has a private directory context that preserves the original document-file classification, asserted by every replay.

64 supported cases now match the oracle classification. The remaining nine cases exercise AVERAGE (five cases) or cost merging (four cases), which MoonBean intentionally implements as extensions and the oracle rejects. Their explicit boundary checks retain both outcomes and the reason. These cases preserve caller-visible extension behavior.

Authored probes check exit status, typed metadata/directive values and fingerprints, PRINT bytes, physical lexical-error lines and formatter round trips. Error-family comparisons cover the reviewed lexical, syntax, categorization and document failures. Semantic-error positions and exact prose retain the existing parser/validator conventions where recorded. The corpus retains each observed diagnostic for review.

The standalone tracked corpus passes 241/241 checks. Its 73 review cases comprise 64 matching classifications and nine explicit extension checks. The authored cases add 168 checks of parsing, diagnostics, typed values, PRINT and formatting. All 73 stored byte fingerprints match the committed fixtures. [Parser results](r14-parser.json), [before-fix reproductions](r14-review-before.json).

The new source syntax also covers empty narration, empty metadata and removal of zero-residual automatic postings. Standalone indented comments produce the oracle's indentation error. Native CLI check verifies explicit document paths through the host filesystem. The pure library retains its document-verification warning for callers to handle. Automatic document discovery remains a host endpoint exclusion.

The restored oracle also segfaults on metadata `amount: 1/0 USD`: bean-check returns signal 11 (subprocess return code -11), with no diagnostic text. MoonBean returns exit 1 and `parse.number: division by zero`. This robustness difference is retained explicitly, outside the passing conformance count. [Exact source and process results](r14-oracle-crash.json).

## Correctness commands

All ten commands completed against the restored environment and exited 0. Actual output excerpts follow.

```text
$ moon info
Finished. moon: ran 14 tasks, now up to date
$ moon check --deny-warn
Finished. moon: ran 28 tasks, now up to date
$ moon fmt --check
Finished. moon: no work to do
$ moon test --target native
Total tests: 200, passed: 200, failed: 0.
$ moon test --target wasm-gc
Total tests: 200, passed: 200, failed: 0.
$ moon test --target js
Total tests: 200, passed: 200, failed: 0.
$ moon build --release --target native cmd/main
  sundaysebasidian-byte/moonbean/cmd/main  native  /Users/sebasidian/.t3/projects/moonbit-nov/.wt/moonbean-r2/_build/native/release/build/cmd/main/main.exe
$ moon build --release --target wasm-gc tests/clock_host
  sundaysebasidian-byte/moonbean/tests/clock_host  wasm-gc  /Users/sebasidian/.t3/projects/moonbit-nov/.wt/moonbean-r2/_build/wasm-gc/release/build/tests/clock_host/clock_host.wasm
$ node scripts/wasm-clock-test.mjs
Wasm host clock: 215/215 checks passed
$ python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin --ours _build/native/release/build/cmd/main/main.exe
BQL differential: 20790/20790 checks passed
```

The combined differential passes **20790/20790** checks: the unchanged original 20549 checks plus 241 new parser checks. Passing checks include explicit rejection/extension and resource-robustness probes; this total does not claim full language equivalence. The nine new extension checks retain AVERAGE/cost-merge behavior as described above. [Command statuses](r14-correctness-commands.json), [full logs](r14-correctness.log), [differential records](r14-bql.json). PRINT output byte counts and SHA-256 are stored after exact comparison; full original output is retained in the local task cache.
The main runner retains the original 20549 checks and the additional tracked parser corpus. The required targets share the parser implementation. Generated interfaces are committed and checked for consistency.

## Clock checks

215 logical checks pass in Node-hosted wasm-gc. Eleven fixtures run in four provider modes. The count includes 176 result-cell checks, eleven independent local-calendar checks, eleven per-read advancement checks, one missing-import failure, eight local/UTC fixture distinctions and eight explicit rolling-year-boundary checks. The 50-06-15 column remains 2050 within this fixture range. The 06-15-29 column supplies the tested century transition. [Clock output](r14-clock.log).

## Shared-host performance and memory

One e33a3fc baseline moonrun 1M FIFO process completed all fifteen measurements per stage with peak RSS 1,715,732,480 bytes. This is one process sample and supplies zero completed pairs. Candidate pairing, three-pair repeatability, Node/V8 heap headroom and short native/JS ratios remain pending. The interrupted raw record is retained in .oracle-cache/r14/performance/. The later restart failed during baseline compilation because /tmp/moon-new was absent. The tracked scripts/bench-r14.py retains the requested alternating shared-host measurement plan.

Loads are recorded throughout each process. Measurement starts without waiting for idle, as requested. Every whole-case A/B order alternates across rounds. The short native/JS runs use two warmups and one measured sample per stage in each of three separate processes. The historical >=100k FIFO ORDER BY timing skip is retained.

The planned moonrun default-heap pairs use two warmups and all fifteen measurements per stage. Planned Node/V8 heap-statistic pairs use the same guest artifacts, two warmups and one measurement per stage. The Node adapter samples public V8 heap statistics at guest clock reads and completed output records. Reported headroom is sampled available heap and limit minus peak sampled used heap. Transient intra-action peaks can exceed the samples. Peak process RSS comes from /usr/bin/time -l. Node and moonrun have their own heap configurations. Moonrun's public CLI exposes completion and process RSS, with no heap-limit/statistics query. Its heap headroom remains unquantified.

## Remaining scope and closeout

The nine retained review mismatches are the intentional AVERAGE/cost-merge extensions. Existing randomized-set, portable-regex, finite-Decimal/source-negative-zero, exhaustive dateutil/locale and host endpoint boundaries retain their documented scope. Required clock integration evidence is specific to Node-hosted wasm-gc. The parser diagnostic comparison has the family/physical-lexer-position scope above.

The blocked handoff retains current source, exact reviewer inputs, provisional/final partial logs and benchmark snapshots. Its manifest, verified backup receipt, zero-move restore map and process/df records are stored locally under .oracle-cache/r14-blocked-closeout/. The two missing environment directories are recorded as blockers. No cleanup candidate is selected.
