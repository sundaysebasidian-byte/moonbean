# Conformance Report

MoonBean is checked against Beancount v3 as an external black-box oracle. Beancount
is not linked, embedded or redistributed; it is installed into a throwaway Python
virtual environment only by the reproduction script. All ledgers under
`tests/ledgers/` were written for this project.

## Environment

| Item | Value |
| --- | --- |
| Date | 2026-10-31 |
| Platform | macOS (arm64) |
| MoonBit | 0.1.20261028 |
| Oracle | beancount 3.2.3 |
| Oracle query tool | beanquery 0.2.0 |
| MoonBean | main @ local commit |

## What is compared

For every ledger in `tests/ledgers/`:

1. **Diagnostics** — the set of `(file, category, line)` tuples produced by
   `bean-check` and by `moonbean check`, after mapping both to shared categories
   (balance, booking, close, currency, duplicate, open, pad, syntax, etc.).
   Messages, severity ordering and file paths are intentionally not compared.
2. **Final balances** — per-account totals from `BALANCES` (units plus lots,
   ignoring cost date and label).
3. **Fixed BQL queries** — `sum(position)` totals, `GROUP BY date`, `year()`
   filter, `root()` grouping, and `ORDER BY ... LIMIT`, compared row by row after
   normalising lot formatting.

BQL comparison is skipped when the ledger intentionally contains errors: the
oracle cannot reliably run queries over a broken ledger.

Ledgers 035 (`AVERAGE` booking) and 058 (`{*}` cost merging) are MoonBean
extensions. beancount 3.2.3 rejects both features, so they are validated against
MoonBean's own expectations and excluded from the oracle comparison count.

## Result

```
ledgers: 58, compared: 56, passed: 56, failed: 0, extensions: 2
```

Raw pass rate over compared ledgers: **56 / 56 = 100%**.
The 56 compared ledgers pass diagnostics; the two extensions are checked only against MoonBean expectations.

| Ledger | Diagnostics | BQL | Result | Notes |
| --- | --- | --- | --- | --- |
| `001-basic.beancount` | pass | pass | PASS |  |
| `002-multi-currency.beancount` | pass | pass | PASS |  |
| `003-commodity-prices.beancount` | pass | pass | PASS |  |
| `004-balance.beancount` | pass | pass | PASS |  |
| `005-balance-fail.beancount` | pass | skip | PASS |  |
| `006-pad.beancount` | pass | pass | PASS |  |
| `007-unused-pad.beancount` | pass | skip | PASS |  |
| `008-directives.beancount` | pass | pass | PASS |  |
| `009-open-constraints.beancount` | pass | pass | PASS |  |
| `010-close.beancount` | pass | pass | PASS |  |
| `011-close-unopened.beancount` | pass | skip | PASS |  |
| `012-inactive-account.beancount` | pass | skip | PASS |  |
| `013-duplicate-open.beancount` | pass | skip | PASS |  |
| `014-duplicate-close.beancount` | pass | skip | PASS |  |
| `015-tags-links.beancount` | pass | pass | PASS |  |
| `016-push-tags.beancount` | pass | pass | PASS |  |
| `017-pushmeta.beancount` | pass | pass | PASS |  |
| `018-entry-metadata.beancount` | pass | pass | PASS |  |
| `019-posting-metadata.beancount` | pass | pass | PASS |  |
| `020-posting-flags.beancount` | pass | pass | PASS |  |
| `021-arithmetic.beancount` | pass | pass | PASS |  |
| `022-interpolate-missing.beancount` | pass | pass | PASS |  |
| `023-multiple-missing.beancount` | pass | skip | PASS |  |
| `024-cost-per.beancount` | pass | pass | PASS |  |
| `025-cost-total.beancount` | pass | pass | PASS |  |
| `026-cost-date-label.beancount` | pass | pass | PASS |  |
| `027-price-per.beancount` | pass | pass | PASS |  |
| `028-price-total.beancount` | pass | pass | PASS |  |
| `029-booking-fifo.beancount` | pass | pass | PASS |  |
| `030-booking-lifo.beancount` | pass | pass | PASS |  |
| `031-booking-hifo.beancount` | pass | pass | PASS |  |
| `032-booking-strict.beancount` | pass | pass | PASS |  |
| `033-booking-strict-size.beancount` | pass | pass | PASS |  |
| `034-booking-none.beancount` | pass | pass | PASS |  |
| `035-booking-average.beancount` | pass | skip | PASS | beancount 3.2.3 reports 'AVERAGE method is not supported' |
| `036-booking-insufficient.beancount` | pass | skip | PASS |  |
| `037-booking-ambiguous.beancount` | pass | skip | PASS |  |
| `038-unbalanced.beancount` | pass | skip | PASS |  |
| `039-currency-constraint.beancount` | pass | skip | PASS |  |
| `040-unknown-account.beancount` | pass | skip | PASS |  |
| `041-include.beancount` | pass | pass | PASS |  |
| `042-plugin.beancount` | pass | pass | PASS |  |
| `043-options.beancount` | pass | pass | PASS |  |
| `044-tolerance-options.beancount` | pass | skip | PASS |  |
| `045-comments.beancount` | pass | pass | PASS |  |
| `046-string-escapes.beancount` | pass | pass | PASS |  |
| `047-syntax-error.beancount` | pass | skip | PASS |  |
| `048-duplicate-balance.beancount` | pass | skip | PASS |  |
| `049-invalid-booking-method.beancount` | pass | skip | PASS |  |
| `050-query-balances.beancount` | pass | pass | PASS |  |
| `051-query-journal.beancount` | pass | pass | PASS |  |
| `052-query-functions.beancount` | pass | pass | PASS |  |
| `053-query-group-limit.beancount` | pass | pass | PASS |  |
| `054-tolerance-inference.beancount` | pass | pass | PASS |  |
| `055-same-day-order.beancount` | pass | skip | PASS |  |
| `056-custom-values.beancount` | pass | pass | PASS |  |
| `057-bql-prices.beancount` | pass | pass | PASS |  |
| `058-cost-merge.beancount` | pass | skip | PASS | beancount 3.2.3 reports 'Cost merging is not supported yet' |

## Reproduce

The script creates a virtual environment, installs the pinned oracle versions,
builds MoonBean natively and runs the comparison:

```sh
./scripts/oracle.sh            # human readable output
./scripts/oracle.sh --markdown # regeneration of the table above
```

Set `MOONBEAN_ORACLE_VENV` to choose the virtual environment location and
`MOONBEAN_ORACLE_REINSTALL=1` (or pass `--reinstall`) to recreate it. The oracle
install is the only network dependency; MoonBean itself needs no third-party
runtime.

## Known oracle differences

- `AVERAGE` booking and `{*}` cost merging are implemented by MoonBean but
  rejected by beancount 3.2.3.
- Duplicate transaction detection is a MoonBean query/report feature; the oracle
  does not flag duplicate transactions either, so no diagnostic mismatch exists.
- The `document` directive is parsed and its account is validated. MoonBean does
  not stat the referenced file, so a missing receipt produces no diagnostic,
  unlike the oracle. Linking a document is treated as metadata-only.
- The original aggregate BALANCES check ignores cost date/label. R1 adds an independent posting-level check using `str(position)` that compares both fields and duplicate row counts.

## Historical aggregate-only differential (pre-R1, 2026-10-31)

`python3 scripts/random_differential.py --seed 20261031 --count 1000`
uses only Python stdlib and independently authored templates with randomized
currencies, amounts, dates, lot sizes/costs and descriptions. Eleven scenario
families include two purchase lots and reductions, seven booking methods,
pad/balance, price directives, multiple currencies, tolerance residuals
0.004/0.005/0.006, unknown/closed accounts and invalid currencies. This is
bounded template-based random testing, not exhaustive grammar fuzzing.

| Check | Actual count |
| --- | ---: |
| Generated / diagnostic comparisons attempted | 1000 |
| Fully matching ledgers | 858 |
| Nonmatching diagnostic sets | 142 |
| Matching error ledgers (queries skipped) | 390 |
| Clean ledgers with six balance/BQL comparisons each | 468 |
| Clean-ledger balance/BQL mismatches | 0 |

All 142 differences are the AVERAGE extension: ledger IDs `6 + 7*k` for
`k=0..141`. The pinned oracle emits `average_unsupported`, while MoonBean
implements AVERAGE. Each ledger ID, full expected/actual diagnostic set and
reason is recorded in `docs/random-differential.json`; the runner writes raw
results and the generated ledgers to its `--out` directory. No diagnostic
differences are removed from the reported count. The default
runner exits 1 for these differences. `--allow-known-extensions` permits CI
success only when deleting the oracle's AVERAGE-unsupported diagnostics makes
the complete diagnostic sets identical; unexpected differences still fail.

The original CSV runner rounded inventory quantities using beanquery's display
precision. This produced 166 false balance differences on the initial random
run. Oracle queries now stringify inventory values **before** CSV rendering,
then compare exact Decimals. The baseline 56 comparable ledgers still pass.

Reproduction (build via `./scripts/oracle.sh` first):

```sh
python3 scripts/random_differential.py --allow-known-extensions
python3 scripts/bql_differential.py
python3 scripts/cli_smoke.py
```

### Extended query matrix

12/12 additional external beanquery comparisons pass on independently written
ledger fixtures: aggregate HAVING, numeric precedence/parentheses/unary/division,
regex account filtering, populated tags/links and posting metadata, and four
unit/cost balance views combining OPEN/CLOSE periods.

| Capability | Status and precise boundary |
| --- | --- |
| HAVING | Aggregate comparisons, boolean combinations and null tests |
| Arithmetic | Decimal `+ - * /`, precedence and parentheses; no Amount/Inventory arithmetic; zero division produces null |
| `~` | Case-insensitive literal regex via MoonBit core; invalid/unsupported patterns return an error; regex dialect is not Python's entire dialect |
| SQL LIKE | Unsupported; beanquery 0.2.0 also rejects this syntax; use `~` |
| tags / links | Structured arrays in JSON, comma-separated text |
| `meta('key')` | Posting metadata; no entry_meta or arbitrary dynamic metadata expression |
| BALANCES AT / FROM | AT units/cost; FROM postings/balances or OPEN/CLOSE ON dates, optional WHERE |
| OPEN ON | Summarizes earlier lots, transfers Income/Expenses to Equity:Earnings:Previous; honors account_previous_earnings / account_previous_balances options |
| CLOSE ON | Exclusive date cutoff; currency-conversion normalization entries are not synthesized; partial compatibility |
| FROM transaction predicates | Unsupported; this implementation's FROM accepts the sources/period forms above |
| Subqueries / JOIN / PIVOT | Unsupported; rejected by parser, reserved for later work |

These comparisons cover ordinary default-name period balances. They do not
prove exact synthetic metadata/ordering, custom summarization account options,
or conversion normalization. Period support is deliberately marked partial.

### API and CI audit

All pure library packages typecheck/test on native, js and wasm-gc (also wasm).
The native-only CLI owns filesystem/process access; hosts call the pure library.
`QueryResult.failure()` exposes matchable Syntax/Unsupported variants while
retaining the existing `error` text. Unknown columns now return an explicit
error. `Diagnostic.code` and `loc` remain available for validation matching.
The internal decimal precision constant is no longer public. Host-facing root
functions and new APIs have documentation; legacy lower-level API documentation
is not yet complete, and `.mbti` data records remain public for host integration.

CI installs MoonBit using the official unix/PowerShell URLs documented at
https://www.moonbitlang.com/download . Windows explicitly uses pwsh and
USERPROFILE instead of a hard-coded runner username. Oracle bootstrap pins
pip 25.2, Beancount 3.2.3 and beanquery 0.2.0 with Python 3.12 in CI. The
workflow runs random differential and extended BQL checks and uploads evidence.
The workflows have not been executed on GitHub yet.

## R1 backend review fixes

The historical run above only establishes aggregate compatibility for its old
bounded templates. The generator has since changed: it is not a reproduction of
those old inputs. R1 evidence and reproduction commands below supersede that
coverage claim; this remains bounded template testing, not grammar fuzzing.

| Issue | Implemented behavior and evidence |
| --- | --- |
| B-02 | Cost-basis bs matches beanquery `FROM OPEN ON ... CLOSE ON ... CLEAR`; is matches the same period before CLEAR. Earnings account options, prior/current periods, profit/loss, foreign currency and inclusive snapshots tested. Market valuation changes and exact FX rounding are separate equity report adjustments. |
| I-01 | Date-filtered BFS, inverse edges, lexical tie breaking and cycle detection. The independent chain matches beanquery conversion. Missing paths produce structured diagnostics and grouped currency totals; a single unqualified total requires complete conversion. |
| I-02 | Save split booked postings once; compare posting counts, cost amount/currency/date/label. JOURNAL, register and JSON export are checked independently against the same oracle posting multiset. |
| I-03 | FROM transactions returns Unsupported at parse time; independent transaction source remains unimplemented. |
| I-04 | One iterative include stack for pure callback API and async native CLI. Self/mutual/absolute/normalized cycles, missing files and deep valid loads tested. CLI cycle timeout guard is 5s; errors retain the including path and line. |
| S-01 backend | Infer one display scale per currency; explicit quantum overrides it. Raw JSON values remain exact and expose display metadata separately. |
| S-02 | Three purchase lots, reductions reaching partially into a third lot, multiple same-day postings/transactions, explicit quote bridges and accounting invariants added. |

The 18 independently authored review ledgers are retained in `tests/review/`,
plus four new income/expense/loss/multi-year ledgers. The review runner includes
additional chain and historical report checks; current totals are recorded in
`docs/r1-differential.json`. Cyclic includes are separate host regression tests:
the oracle reports Duplicate filename parsed at `<load>:0`; MoonBean returns the
requested include.cycle with the actual including filename/line. This intentional
location/category distinction is not hidden in the random ledger counts.

For each clean random ledger the suite runs six original aggregate/scalar/lot
queries plus posting details, bs, is, the bs identity and a quote-bridge conversion
comparison. Posting comparison preserves duplicate multiplicities; ordering among
identical date/account keys is not compared. Error ledgers compare diagnostics
only. AVERAGE is still an explicitly counted oracle extension.

```sh
export PATH="$HOME/.moon/bin:$PATH"
./scripts/oracle.sh
python3 scripts/review_differential.py
python3 scripts/include_smoke.py
python3 scripts/random_differential.py --seed 7 --count 1000 --out .oracle-cache/r1/seed-7 --allow-known-extensions
python3 scripts/random_differential.py --seed 20261101 --count 1000 --out .oracle-cache/r1/seed-20261101 --allow-known-extensions
```

The accepted native executable is fingerprinted with the source checkpoint in
`.oracle-cache/r1/release-build.json`; the final two datasets and complete raw
results are retained in `.oracle-cache/r1/release-seed-*`. Structured committed
summary evidence is in `docs/r1-differential.json`. Default random-run exit status
remains nonzero for counted AVERAGE differences; the opt-in flag permits only the
exact known diagnostic delta. No non-AVERAGE difference may be waived.

Remaining scope: FROM transactions, subqueries/JOIN/PIVOT, BQL CLOSE conversion
normalization, plugins, the front-end XSS/diagnostic display and publishing are
outside this fix. No UI source changed; only affected web smoke assertions were
updated. GitHub CI has not executed and nothing was pushed or published.

### Final R1 measured counts

| Seed | Ledgers | Matching | AVERAGE diagnostic differences | Non-AVERAGE differences | Clean-ledger detailed checks |
| --- | ---: | ---: | ---: | ---: | ---: |
| 7 | 1000 | 858 | 142 | 0 | 5148 |
| 20261101 | 1000 | 858 | 142 | 0 | 5148 |

Each seed includes 468 clean ledgers and 390 matching deliberately invalid ledgers. Each has 234 clean FIFO/LIFO/HIFO reductions crossing three lots.

Original oracle: 56/56 comparable (58 total, two extensions). Review: 22 retained ledger files, 25 scenario records, 144/144 checks. Extended BQL 12/12; three required backends 108/108 each; extra wasm 108/108; web smoke 21/21 and CLI include smoke 5/5.
