# R14 acceptance for MoonBean 0.2.8

The initial packet below records candidate 5a5f264 (runtime input 194caf2). It predates the independent R14 rejection; current rework results are recorded in the review-rework section. Historical memory measurements are not reruns of the reworked parser.

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
| S6 unterminated literals | An unmatched EOF string reports its physical opening line. Later quotes can form multiline literals and consume intervening directive-looking text. Unknown attached `word"` runs are rejected as whole tokens at their own physical line, permitting the reviewed subsequent-directive recovery. The earlier unconditional recovery claim was incorrect; the R14 rework regressions include cases 37/72 and the reviewer's option/full-year examples. Backslash-newline remains a lexical error. |
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

## Independent R14 review rework

This section supersedes the initial correctness/performance acceptance above. Runtime source is `1dfb5e5`; `1540b17` implements the main fixes, and `0fef3d6` finishes the recovery regression data. Later changes only add documentation/evidence. The main interface files remain consistent after moon info. The oracle is still Beancount 3.2.3 / beanquery 0.2.0 on Python 3.14.7 and dateutil 4.0.0. It was used only through public lexer/loader/printer/cursor APIs and CLI; no oracle source was read.

| Review finding | Reproduction and resulting behavior |
| --- | --- |
| Important 1: flag regression | The original e33a3fc CLI rejects the truncated lowercase flag. The reviewed 5a5f264 executable accepts it; the oracle rejects it. Flags now accept ASCII A–Z and ! # % & * ?, plus txn syntax. Lowercase letters and apostrophes are lexical errors. Authored scans cover valid/invalid header flags, narration/no narration, EOF and posting flags. |
| Important 2: attached word/quote | The option example now reports render_commas" on line 2 and retains both opens and the note. Whole unknown non-whitespace runs include attached quotes. Cases 37/72, the full-year mutation and all nine changed rejected PRINT examples are tracked with PRINT/count/error-line regressions. Recovery is lexical; a later quote may legally close a multiline string and consume intervening directive-like text. The original S6 wording promised too much and is corrected. |
| Leading dot and duplicate metadata | .5 is rejected in ledger syntax. Conflicting/repeated number, date, amount and currency metadata on transactions/postings reports a duplicate and preserves the first value. Ordinary directive metadata still permits last-value overwrite. Probes retain the oracle's equal-account, empty/one-character Latin-1 string and boolean/null singleton exceptions; longer/non-Latin-1 repeated strings remain errors. Full duplicate diagnostic prose keeps the existing MoonBean format. |
| Compact expressions and missing currency | 2*3 and other tested compact arithmetic are evaluated in metadata/postings. The reviewed Income:Gains -100. posting infers USD from the stock transaction's cost/price weight; the transaction remains in PRINT and count results. |
| Document trailing slash | The relative docs/ example is fixed: PRINT normalizes its resolved path without the final slash. The report's absolute-path spelling is a distinct oracle behavior: absolute /tmp/ and other absolute trailing slashes remain unchanged. Both forms have regression checks. |

The tracked original reviewer scripts are under scripts/review_r14. All 733 raw ledger fingerprints and their original oracle classifications are retained. Portable materialization reproduces the include/document context, with all 733 oracle exits unchanged. **710 classifications agree**; **23 named boundaries** retain 11 repetitions of the existing AVERAGE/cost-merge extensions and 12 unknown-option mutations accepted by the existing raw-option passthrough. These are explicit differences, not conformance passes. Unknown-option validation remains a separate gap; this rework preserves the existing host-facing raw-option contract.

The main differential adds **1554 checks**: 733 classifications, 244 authored check/PRINT/count triples, and 89 physical lexical diagnostic checks. Recovery cases also compare the actual lexer messages. The reviewed executable fails **385** checks in this same new corpus; the repaired executable passes all of them. The original 20790 checks remain in the runner. [Before failures](r14-rework-before.json), [new regression records](r14-rework-regressions.json), [summary and hashes](r14-rework-summary.json).

A separate 16-case before/after audit of changed rejected PRINT output now has 15 exact matches. Its only remaining difference is the review's already-existing literal NULL metadata rendering (meta19-open); this is outside the new findings and is retained explicitly. Empty metadata and source NULL are not an equivalence claim. The nine flag/quote-recovery cases all match. The reviewer's entire 900 typed-query matrix was retained as a script, not claimed as a rerun. [Separate audit](r14-rework-recovery-audit.json).

### Rework acceptance commands

All ten commands exited 0. These are actual final-run output excerpts.

```text
$ moon info
Finished. moon: ran 14 tasks, now up to date
$ moon check --deny-warn
Finished. moon: ran 15 tasks, now up to date
$ moon fmt --check
Finished. moon: ran 82 tasks, now up to date
$ moon test --target native
Total tests: 207, passed: 207, failed: 0.
$ moon test --target wasm-gc
Total tests: 207, passed: 207, failed: 0.
$ moon test --target js
Total tests: 207, passed: 207, failed: 0.
$ moon build --release --target native cmd/main
  sundaysebasidian-byte/moonbean/cmd/main  native  <repo>/_build/native/release/build/cmd/main/main.exe
$ moon build --release --target wasm-gc tests/clock_host
  sundaysebasidian-byte/moonbean/tests/clock_host  wasm-gc  <repo>/_build/wasm-gc/release/build/tests/clock_host/clock_host.wasm
$ node scripts/wasm-clock-test.mjs
Wasm host clock: 215/215 checks passed
$ python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin --ours _build/native/release/build/cmd/main/main.exe
BQL differential: 22344/22344 checks passed
```

The result is **22344/22344**, including all original 20790 checks and all 1554 new checks. Passing totals include explicit boundaries and parser resource checks; they are finite evidence rather than full language equivalence. Native, wasm-gc and JS each pass **207/207** unit tests; imported clock checks remain **215/215**, specifically Node-hosted wasm-gc. [Statuses](r14-rework-commands.json), [complete logs](r14-rework-checks.log).

### Rework short interleaved A/B

Only the requested short native/JS comparison was rerun after the final runtime fix. The earlier three-pair Wasm memory packet remains evidence for its earlier source, not for this reworked parser. All **24/24** final process invocations completed all eleven expected stages, with no timeouts or OOM. Baseline e33a3fc and candidate 1dfb5e5 are pristine archived sources. No source/benchmark code changes followed the freeze; the later recovery commit only expands fixture data. Each process uses two warmups and one measured sample per stage. Whole-case order alternates over three pairs; no idle wait or heap flags were used.

```text
$ python3 scripts/bench-r14.py --baseline e33a3fc --candidate HEAD --short-only --out .oracle-cache/r14-rework/performance-final
native 1000000 baseline round 3 complete RSS 1255636992
native 1000000 candidate round 3 complete RSS 1255735296
js 1000000 candidate round 3 complete RSS 2924625920
js 1000000 baseline round 3 complete RSS 2944712704
```

The shared-host one-minute load samples span 4.319–6.560; correctness/differential execution overlapped the early pairs. Each cell below is the median of three within-round candidate/base stage-time ratios; smaller is faster. ORDER BY retains the existing >=100k FIFO benchmark skip.

| Stage | native 100k | JS 100k | native 1M | JS 1M |
| --- | ---: | ---: | ---: | ---: |
| parse | 0.921 | 1.082 | 0.915 | 1.052 |
| booking_FIFO | 0.952 | 1.040 | 1.013 | 0.986 |
| validate_pad_FIFO | 1.000 | 0.966 | 1.003 | 1.019 |
| realize | 1.000 | 0.962 | 0.973 | 1.107 |
| format | 1.049 | 1.033 | 1.057 | 1.020 |
| aggregate | 1.000 | 1.000 | 1.028 | 1.027 |
| group | 1.000 | 1.000 | 1.016 | 1.106 |
| regex | 1.051 | 1.132 | 1.034 | 1.036 |
| transactions | 1.000 | 0.973 | 1.046 | 1.097 |
| length | 1.100 | 1.000 | 1.095 | 1.021 |
| substr | 1.018 | 1.000 | 1.012 | 1.007 |

Observed medians span **0.915–1.132**; the largest is js 100000 regex. All per-round ratios, source/artifact hashes, RSS and load samples are retained. These short shared-host samples do not prove zero performance regression or complete the historical full matrix gate. [Raw measurements](r14-rework-performance.json), [paired ratios](r14-rework-performance-summary.json), [transcript](r14-rework-performance.log).

### Rework closeout

No push or publication occurred. Current source, exact test inputs, historical attempts and final evidence are retained. Superseded acceptance/performance processes were stopped before the final runtime freeze; only this task's processes were terminated. No temporary service or browser tab was opened. The local verified backup receipt, process inventory, df observations, manifest and empty restore map are under .oracle-cache/r14-rework-closeout/. No item was selected for Trash; shared and unknown resources remain untouched.

## CI-only include fixture follow-up (main 825c412)

The earlier acceptance omitted the workflow's include smoke and other CI-only commands. This follow-up reads both .github/workflows/ci.yml and pages.yml and inventories every step, including all OS matrix rows. Fixture repair commit is f08310e on compat-0.2.8; runtime MoonBit files and version 0.2.8 are unchanged from 825c412.

The original include smoke reproducibly exits 1 at its document_unchecked assertion. It now asserts document_missing at child.beancount:5 for an absent document, alongside the original balance/include errors. Each direct/nested include case resets its source. The positive branch creates present-receipt.pdf, checks clean native CLI success without warnings, then checks export's existing pure-library contract: no errors and exactly one document_unchecked warning at child.beancount:5. Neither the document-existence check nor validation behavior was weakened. Independent bean-check probes return 1/1 when the document is absent and 0/0 when it exists. [Before failure](r14-ci-include-before.log), [document probes](r14-ci-document-probe.json).

### Environment and scope

Executed on macOS 27.2 arm64 with the provided Moon 0.1.20261104 / moonc v0.10.20+65efd5b93, a task-local Node 22.23.5, Chrome 157.0.8103.52 and the restored oracle Python 3.14.7 / Beancount 3.2.3 / beanquery 0.2.0 / dateutil 4.0.0. Python commands in the workflow replay resolve to Python 3.14.7; orchestration uses system Python 3.14.6. The supplied MoonBit and oracle installations were reused rather than overwritten by the unpinned setup installers. Node 22 was installed in an isolated local npm cache. Browser tests really launched isolated headless Chrome; no interactive user profile was used.

This is local command execution, not a hosted CI run. Ubuntu/Windows and the hosted macos-latest image are unverified; this host has neither those runners nor Docker. GitHub checkout/setup actions themselves were not invoked. Local artifact archives were constructed and their bytes verified, but remote uploads, configure-pages and deploy-pages actions were not run. Deployment is excluded by the explicit no-publish instruction. The unpinned MoonBit installer/latest hosted toolchain is not claimed as tested.

### Every workflow step

PASS means the indicated commands actually exited 0 locally. The OS column names the workflow matrix/runner; notes distinguish local macOS execution from hosted execution. Conditional, provisioning and hosted-only steps have explicit statuses rather than fabricated passes.

| Workflow/job | OS | Step | Result | Notes |
| --- | --- | --- | --- | --- |
| ci.yml/build | macos-latest | Checkout | LOCAL IDENTITY VERIFIED | Existing authorized worktree at f08310e; checkout action itself not invoked. |
| ci.yml/build | macos-latest | Install MoonBit (unix) | PROVISIONED, INSTALLER NOT RUN | Reused the explicitly provided /tmp/moon-new; did not run an unpinned installer into the shared user environment. |
| ci.yml/build | macos-latest | Install MoonBit (windows) | SKIP: workflow condition | The workflow excludes this installer on this OS. |
| ci.yml/build | macos-latest | Toolchain version | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | Check | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | Build | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | Test | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | Formatting | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | Generated interfaces are committed | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | macos-latest | README quick start | PASS locally | Executed on local macOS 27.2 arm64, not a hosted macos-latest image. |
| ci.yml/build | ubuntu-latest | Checkout | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Install MoonBit (unix) | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Install MoonBit (windows) | SKIP: workflow condition | The workflow excludes this installer on this OS. |
| ci.yml/build | ubuntu-latest | Toolchain version | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Check | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Build | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Test | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Formatting | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | Generated interfaces are committed | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | ubuntu-latest | README quick start | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Checkout | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Install MoonBit (unix) | SKIP: workflow condition | The workflow excludes this installer on this OS. |
| ci.yml/build | windows-latest | Install MoonBit (windows) | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Toolchain version | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Check | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Build | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Test | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Formatting | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | Generated interfaces are committed | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/build | windows-latest | README quick start | NOT RUN on this OS | Only a macOS arm64 host is available; no Linux/Windows runner or Docker installed. |
| ci.yml/playground | ubuntu-latest | Checkout | LOCAL IDENTITY VERIFIED | Existing worktree; hosted checkout action not invoked. |
| ci.yml/playground | ubuntu-latest | Install MoonBit | PROVISIONED, INSTALLER NOT RUN | Provided pinned toolchain reused. |
| ci.yml/playground | ubuntu-latest | Set up Node 22 | PASS locally | Local task-isolated Node 22.23.5; setup-node action itself not invoked. |
| ci.yml/playground | ubuntu-latest | Build bundle | PASS locally | Workflow commands executed locally on macOS; Ubuntu image unverified. |
| ci.yml/playground | ubuntu-latest | Smoke test | PASS locally | 29 checks; Node 22.23.5. |
| ci.yml/playground | ubuntu-latest | Browser smoke test | PASS locally | 8 tests; isolated headless Chrome 157.0.8103.52, desktop and 390px viewport; local macOS. |
| pages.yml/deploy | ubuntu-latest | Checkout | LOCAL IDENTITY VERIFIED | Existing worktree; hosted checkout action not invoked. |
| pages.yml/deploy | ubuntu-latest | Install MoonBit | PROVISIONED, INSTALLER NOT RUN | Provided pinned toolchain reused. |
| pages.yml/deploy | ubuntu-latest | Set up Node 22 | PASS locally | Local task-isolated Node 22.23.5; setup-node action itself not invoked. |
| pages.yml/deploy | ubuntu-latest | Build playground | PASS locally | Workflow commands executed locally on macOS; Ubuntu image unverified. |
| pages.yml/deploy | ubuntu-latest | Smoke test | PASS locally | 29 checks; Node 22.23.5. |
| pages.yml/deploy | ubuntu-latest | Browser smoke test | PASS locally | 8 tests; isolated headless Chrome 157.0.8103.52, desktop and 390px viewport; local macOS. |
| pages.yml/deploy | ubuntu-latest | Configure Pages | NOT RUN: hosted GitHub action | Remote Pages configuration was not changed. |
| pages.yml/deploy | ubuntu-latest | Upload Pages artifact | LOCAL PACKAGING VERIFIED; REMOTE UPLOAD NOT RUN | pages-artifact.json verifies all seven files and archive bytes. |
| pages.yml/deploy | ubuntu-latest | Deploy Pages | NOT RUN: user prohibits publishing | No deployment, push, or publication. |
| ci.yml/oracle | ubuntu-latest | Checkout | LOCAL IDENTITY VERIFIED | Existing worktree; hosted checkout not invoked. |
| ci.yml/oracle | ubuntu-latest | Install MoonBit | PROVISIONED, INSTALLER NOT RUN | Provided toolchain reused. |
| ci.yml/oracle | ubuntu-latest | Toolchain version | PASS locally |  |
| ci.yml/oracle | ubuntu-latest | Set up Python 3.14 | PROVISIONED 3.14.7; HOSTED ACTION NOT RUN | Workflow Python commands resolve to the restored oracle Python 3.14.7; wrapper uses system 3.14.6. |
| ci.yml/oracle | ubuntu-latest | Run oracle conformance | PASS locally | Pinned restored oracle reused; tee report mapped to .oracle-cache/r14-ci/conformance.md. |
| ci.yml/oracle | ubuntu-latest | Seeded differential and extended BQL | PASS locally | All five commands executed with their default case counts and original flags. |
| ci.yml/oracle | ubuntu-latest | Upload conformance report | LOCAL PACKAGING VERIFIED; REMOTE UPLOAD NOT RUN | Artifact byte hashes verified; report filename mapped locally. No GitHub upload action invoked. |

### Command results

- Check/build/test all targets, formatting, generated interfaces and git diff: exit 0. Tests: **207/207 on each of wasm, wasm-gc, JS and native** (828 total).
- README quick start: all five actual commands exit 0 (check, converted balance, grouped query, format, JSON export).
- Playground and Pages: each job's build exits 0, Node smoke **29/29**, browser smoke **8/8** (desktop plus 390px coverage). Both jobs were executed separately.
- Oracle conformance: **120 ledgers; 118 compared/passed, 0 failed, 2 declared extensions**.
- Seed 7 and seed 20261101: **1000 each**, **0 non-AVERAGE mismatches**, **142 known AVERAGE-extension differences each**, both exit 0 under the unchanged allow-known-extensions rule; 468 clean-query cases each. These are not 1000 strict equivalence passes.
- Report differential: **25 groups, 144 checks, 0 failures**.
- Include smoke: cycles/missing/depth **5/5**, then both direct/nested absent/present document/source-location/JSON contracts pass.
- Full BQL differential: **22344/22344**, exit 0, with its existing explicit boundary/resource-check distinctions.
- Local conformance artifact: four required files verified, including hidden .oracle-cache paths. Pages artifact: seven files verified, including .nojekyll. No artifact was uploaded.

Actual output excerpts:

```text
$ moon test --target all
Total tests: 207, passed: 207, failed: 0. [wasm]
Total tests: 207, passed: 207, failed: 0. [wasm-gc]
Total tests: 207, passed: 207, failed: 0. [js]
Total tests: 207, passed: 207, failed: 0. [native]
$ node web/smoke.mjs
29 checks passed
$ node web/dom-smoke.mjs
ok   the page raised no exceptions
$ node web/smoke.mjs
29 checks passed
$ node web/dom-smoke.mjs
ok   the page raised no exceptions
$ bash -o pipefail -c ./scripts/oracle.sh --markdown | tee .oracle-cache/r14-ci/conformance.md
ledgers: 120, compared: 118, passed: 118, failed: 0, extensions: 2
$ python3 scripts/random_differential.py --seed 7 --out .oracle-cache/differential/seed-7 --oracle /tmp/moonbean-r4-oracle/bin --allow-known-extensions
compared 1000; mismatches 142
{"seed": 7, "count": 1000, "mismatches": 142, "clean_queries": 468, "non_average_mismatches": 0}
$ python3 scripts/random_differential.py --seed 20261101 --out .oracle-cache/differential/seed-20261101 --oracle /tmp/moonbean-r4-oracle/bin --allow-known-extensions
compared 1000; mismatches 142
{"seed": 20261101, "count": 1000, "mismatches": 142, "clean_queries": 468, "non_average_mismatches": 0}
$ python3 scripts/report_differential.py --oracle /tmp/moonbean-r4-oracle/bin
  "ledgers": 25,
  "checks": 144,
  "failures": 0,
$ python3 scripts/include_smoke.py
CLI include self/mutual/absolute cycles, missing file and depth 100: 5/5 PASS
CLI nested include source locations, absent/present documents and JSON warning contract: PASS
$ python3 scripts/bql_differential.py --oracle /tmp/moonbean-r4-oracle/bin
BQL differential: 22344/22344 checks passed
```

[Per-step statuses, versions, workflow/source/artifact/log hashes and summaries](r14-ci-execution.json), [complete command logs](r14-ci-checks.log), [conformance table](r14-ci-conformance.md). The conformance tee target is mapped locally to .oracle-cache/r14-ci/conformance.md to avoid an untracked root file; the packaged artifact retains conformance.md as its logical name. Raw BQL and seeded inputs/results remain in the task cache.

The CI follow-up closeout retains the current source, generated oracle inputs/results, Node 22 tool cache and previous web/dist byte backup. Its verified backup receipt, process inventory, df observations, manifest and empty restore map are in .oracle-cache/r14-ci-closeout/. Only task-owned headless browsers/static servers were opened, and all finished. No shared/user process was stopped, no item was selected for Trash, and no push/publication occurred.
