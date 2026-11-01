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
- The aggregate BALANCES check ignores cost date and label. A separate posting-level check compares them through `str(position)`, together with duplicate row counts.

## Seeded differential

`scripts/random_differential.py` writes template-based random ledgers (random
currencies, amounts, dates, lot sizes and costs) and compares each one with
beancount 3.2.3. Scenario families include reductions that reach into a third
lot, several postings on one day, quote bridges between currencies, the seven
booking methods, pad/balance, tolerance residuals and deliberately invalid
ledgers (unknown or closed accounts, bad currencies). This is bounded template
testing, not exhaustive grammar fuzzing.

For each clean ledger the run compares aggregate balances and scalar queries,
posting-level rows (row count, cost amount, currency, date and label, duplicate
multiplicity), balance sheet and income statement, the balance-sheet identity
and a price-path conversion. Ordering among postings with identical date and
account is not compared. Invalid ledgers compare diagnostics only.

| Seed | Ledgers | Matching | AVERAGE differences | Other differences | Clean-ledger checks |
| --- | ---: | ---: | ---: | ---: | ---: |
| 7 | 1000 | 858 | 142 | 0 | 5148 |
| 20261101 | 1000 | 858 | 142 | 0 | 5148 |

Each seed has 468 clean ledgers and 390 invalid ledgers whose diagnostics match;
234 of the clean ledgers contain a reduction crossing three lots. All 142
differences per seed are the AVERAGE extension: beancount 3.2.3 reports
`average_unsupported`, MoonBean implements AVERAGE. With the oracle's
`average_unsupported` diagnostics removed the diagnostic sets are identical.
The default runner exits 1 for these differences; `--allow-known-extensions`
accepts only that exact delta, and any other difference still fails. Per-seed
counts and the AVERAGE ledger ids are in `docs/random-differential.json`.

```sh
./scripts/oracle.sh
python3 scripts/random_differential.py --seed 7 --count 1000 --out .oracle-cache/differential/seed-7 --allow-known-extensions
python3 scripts/random_differential.py --seed 20261101 --count 1000 --out .oracle-cache/differential/seed-20261101 --allow-known-extensions
python3 scripts/report_differential.py
python3 scripts/include_smoke.py
python3 scripts/bql_differential.py
```

## Reports, lots, prices and includes

`tests/regression/` holds 22 independently written ledgers (three-lot
reductions, cost dates and labels, tolerance edges, income-only, expense-only,
loss and multi-year reports). `scripts/report_differential.py` runs them plus
three price-path scenarios: 25 scenario records and 144 checks, all passing.

| Area | Behaviour and how it is checked |
| --- | --- |
| Balance sheet | Cost-basis report matches beanquery `FROM OPEN ON ... CLOSE ON ... CLEAR`; the income statement matches the same period before `CLEAR`. Prior and current earnings go to the accounts named by the earnings options. Market-value changes appear as an `Equity:Earnings:Unrealized` reserve and exact FX rounding as a separate adjustment, so Assets + Liabilities + Equity is exactly zero per currency. |
| Currency conversion | Date-filtered BFS over direct and inverse quotes, lexical tie-break, cycle detection. When a path is missing the report sets `complete: false`, lists `report.conversion_incomplete` diagnostics and splits totals by currency. |
| Lots | A reduction that spans lots is stored as several booked postings; BQL, `JOURNAL`, register and JSON export show the same rows. |
| `FROM transactions` | Rejected at parse time as unsupported; there is no transaction row source. |
| Includes | One iterative stack shared by the library and the CLI. Self, mutual, absolute and normalized cycles report `include.cycle`; missing files report `include.missing`; maximum depth 1024. Cycles are covered by `scripts/include_smoke.py` instead of the oracle, because beancount reports a duplicate-filename error at `<load>:0` while MoonBean reports the including file and line. |
| Display precision | Text reports use one scale per currency (the most common booked scale, ties to the larger; an explicit `display_precision` wins). JSON keeps exact amounts and adds `display_precision`. |

Still outside the engine: subqueries, JOIN, PIVOT, plugins, and BQL `CLOSE ON`
conversion entries (the report layer closes and carries earnings instead).

Backend checks run on native, js and wasm-gc (108 tests each, plus wasm); the
browser bundle has 29 node checks and 8 headless-Chrome checks (`web/smoke.mjs`,
`web/dom-smoke.mjs`). Oracle comparison of the 58 original ledgers is unchanged
at 56 of 56, with two extensions.

## Extended query matrix

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

## API and CI

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
The [GitHub CI run](https://github.com/sundaysebasidian-byte/moonbean/actions/runs/41272096814) passed on Ubuntu, macOS and Windows, including the playground, pinned oracle and both 1000-ledger differential seeds. [Pages deployment](https://github.com/sundaysebasidian-byte/moonbean/actions/runs/41272096811) also passed. Online assets match the local build by SHA-256; the downloaded engine passed all 29 smoke checks. Verified 2026-11-01.
