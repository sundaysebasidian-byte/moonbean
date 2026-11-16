# R14 acceptance for MoonBean 0.2.8

The pinned environments were restored on 2026-11-15 (local time). Correctness and the requested paired shared-host measurements completed against the restored environment; the earlier interrupted attempt is retained as historical evidence in [the environment blocker record](r14-environment-blocker.json).

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
| S5 repeatability and memory | Three complete default-heap moonrun pairs and three Node/V8 heap-statistic pairs pass. Per-process RSS, actual Node heap limit and sampled headroom are recorded below. |
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
  sundaysebasidian-byte/moonbean/cmd/main  native  <repo>/_build/native/release/build/cmd/main/main.exe
$ moon build --release --target wasm-gc tests/clock_host
  sundaysebasidian-byte/moonbean/tests/clock_host  wasm-gc  <repo>/_build/wasm-gc/release/build/tests/clock_host/clock_host.wasm
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

All **36/36 process invocations** completed with exit 0 and all eleven expected stages. Both source trees were exported from Git before any build: baseline `e33a3fc` and candidate `194caf2`. Later commits only add acceptance evidence/docs. Both use the same benchmark-driver bytes; all build/artifact/runner hashes are recorded. The original interrupted sample remains historical and is excluded from these pairs.

```text
$ python3 scripts/bench-r14.py --baseline e33a3fc --candidate 194caf2 --out .oracle-cache/r14/performance-restored
native 1000000 baseline round 3 complete RSS 1255620608
native 1000000 candidate round 3 complete RSS 1255718912
js 1000000 candidate round 3 complete RSS 3181854720
js 1000000 baseline round 3 complete RSS 2887385088
```

The host has 16 GiB RAM and 10 logical CPUs. Observed one-minute load samples span 3.183–8.630. No idle wait was used. Correctness/differential execution overlapped the beginning of this run; later pairs and short A/B runs continued after it completed. Whole-case A/B order alternates across rounds. [Every process and load sample](r14-performance.json), [paired summaries](r14-performance-summary.json), [runner transcript](r14-performance.log).

### wasm-gc 1M FIFO completion and memory

Moonrun uses two warmups and fifteen measured iterations per stage, with the default heap and no heap flags. Each row below is an independent process. RSS is the process maximum from `/usr/bin/time -l`; MiB uses 1048576 bytes.

| Pair | main RSS (MiB) | 0.2.8 RSS (MiB) | Completion |
| --- | ---: | ---: | --- |
| 1 | 1577.5 | 1462.6 | both 11 stages × 15 measurements |
| 2 | 1616.0 | 1663.8 | both 11 stages × 15 measurements |
| 3 | 1403.6 | 1562.6 | both 11 stages × 15 measurements |

The same wasm-gc guest artifacts also ran on Node 24.18.0 / V8 13.6.233.17-node.50, using two warmups and one measured iteration per stage in each of three paired processes. `NODE_OPTIONS` was cleared for these child processes. V8 reports its default heap limit as **4,496,293,888 bytes (4288 MiB)** in all six processes. Public heap statistics were sampled at guest clock reads and completed output records.

| Pair | Side | Peak RSS (MiB) | Peak sampled used heap (MiB) | Limit minus peak used (MiB) | Minimum sampled available heap (MiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | main | 2363.5 | 2447.1 | 1840.9 | 1879.1 |
| 1 | 0.2.8 | 2474.5 | 2404.9 | 1883.1 | 1916.0 |
| 2 | main | 2618.6 | 2409.2 | 1878.8 | 1911.7 |
| 2 | 0.2.8 | 2638.3 | 2405.0 | 1883.0 | 1915.8 |
| 3 | main | 2749.3 | 2409.2 | 1878.8 | 1911.6 |
| 3 | 0.2.8 | 2600.4 | 2404.6 | 1883.4 | 1916.2 |

All six Node/V8 processes completed without OOM. These are sampled heap observations, not a bound on transient intra-action peaks. RSS and V8 heap usage measure different quantities and are not subtracted from one another. Moonrun has its own V8 configuration; its public CLI provides no heap-limit/statistics query, so its heap headroom remains unquantified. The Node measurements establish headroom specifically for this Node host.

### Short native/JS A/B

Three within-round pairs per target/count use two warmups and one measured sample per stage per process. Each cell is the **median of the three within-round candidate/main time ratios**, rather than a ratio of unrelated extrema. Smaller is faster; 1.000 is equal. Full per-round ratios and stage seconds are retained in the summary. The existing >=100k FIFO ORDER BY timing skip is unchanged.

| Stage | native 100k | JS 100k | native 1M | JS 1M |
| --- | ---: | ---: | ---: | ---: |
| parse | 0.907 | 1.017 | 0.897 | 1.011 |
| booking_FIFO | 0.964 | 0.978 | 0.996 | 0.991 |
| validate_pad_FIFO | 1.000 | 1.025 | 0.994 | 1.049 |
| realize | 0.969 | 1.000 | 1.006 | 1.008 |
| format | 1.032 | 1.049 | 1.008 | 1.118 |
| aggregate | 0.938 | 0.957 | 0.987 | 0.991 |
| group | 0.966 | 0.984 | 0.993 | 1.029 |
| regex | 1.059 | 0.938 | 0.978 | 1.070 |
| transactions | 1.048 | 0.941 | 1.023 | 0.954 |
| length | 1.033 | 0.967 | 0.986 | 0.935 |
| substr | 1.000 | 1.043 | 0.962 | 0.979 |

Observed medians range from 0.897 to 1.118. The largest increase is JS 1M format: +11.823% by the paired median, with individual ratios 1.179142, 1.118231 and 0.906326. No sampled stage median exceeds the historical 1.30 reference line; this is not a claim of zero regression. These three short shared-host pairs do not establish an idle-host performance bound or replace the historical full 30% matrix gate.

## Remaining scope and closeout

The nine retained review mismatches are the intentional AVERAGE/cost-merge extensions. Existing randomized-set, portable-regex, finite-Decimal/source-negative-zero, exhaustive dateutil/locale and host endpoint boundaries retain their documented scope. Required clock integration evidence is specific to Node-hosted wasm-gc. The parser diagnostic comparison has the family/physical-lexer-position scope above.

Final source, reviewer inputs, complete differential output, frozen benchmark trees/artifacts and all historical attempts are retained. No temporary service or browser was started. The completed local closeout manifest, verified Git/raw-evidence backups, process inventory, zero-move restore map and observed df values are stored under `.oracle-cache/r14-final-closeout/`. Nothing is selected for Trash; current/shared/unknown inputs and prior backups are retained. No push or publication occurred.
