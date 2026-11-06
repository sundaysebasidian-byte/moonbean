# Conformance Report

MoonBean is checked against Beancount v3 as an external black-box oracle. Beancount
is not linked, embedded or redistributed; it is installed into a throwaway Python
virtual environment only by the reproduction script. All ledgers under
`tests/ledgers/` were written for this project.

## Environment

| Item | Value |
| --- | --- |
| Date | 2026-11-06 |
| Platform | macOS (arm64) |
| MoonBit | 0.1.20261028 |
| Oracle | beancount 3.2.3 |
| Oracle query tool | beanquery 0.2.0 |
| MoonBean | local 0.2.0; not published |

## What is compared

For every ledger in `tests/ledgers/`:

1. **Diagnostics** — the set of `(file, category, line)` tuples produced by
   `bean-check` and by `moonbean check`, after mapping both to shared categories
   (balance, booking, close, currency, duplicate, open, pad, syntax, etc.).
   Messages, severity ordering and directory paths are intentionally not compared.
   Commodity and leaf diagnostics normalize synthetic oracle locations as described below.
2. **Final balances** — per-account totals from `BALANCES` (units plus lots,
   ignoring cost date and label).
3. **Raw price entries** — date, base, number and quote, preserving duplicates,
   including error ledgers.
4. **Fixed BQL queries** — `sum(position)` totals, `GROUP BY date`, `year()`
   filter, `root()` grouping, and `ORDER BY ... LIMIT`, compared row by row after
   normalising lot formatting.

BQL comparison is skipped when the ledger intentionally contains errors: the
oracle cannot reliably run queries over a broken ledger.

Ledgers 035 (`AVERAGE` booking) and 058 (`{*}` cost merging) are MoonBean
extensions. beancount 3.2.3 rejects both features, so they are validated against
MoonBean's own expectations and excluded from the oracle comparison count.

## Result

```
ledgers: 113, compared: 111, passed: 111, failed: 0, extensions: 2
```

Raw pass rate over compared ledgers: **111 / 111 = 100%**.
The 111 compared ledgers pass diagnostics; the two extensions are checked only against MoonBean expectations.

| Ledger | Diagnostics | BQL | Result | Notes |
| --- | --- | --- | --- | --- |
| `001-basic.beancount` | pass | pass | PASS |  |
| `002-multi-currency.beancount` | pass | pass | PASS |  |
| `003-commodity-prices.beancount` | pass | pass | PASS |  |
| `004-balance.beancount` | pass | pass | PASS |  |
| `005-balance-fail.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `006-pad.beancount` | pass | pass | PASS |  |
| `007-unused-pad.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `008-directives.beancount` | pass | pass | PASS |  |
| `009-open-constraints.beancount` | pass | pass | PASS |  |
| `010-close.beancount` | pass | pass | PASS |  |
| `011-close-unopened.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `012-inactive-account.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `013-duplicate-open.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `014-duplicate-close.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `015-tags-links.beancount` | pass | pass | PASS |  |
| `016-push-tags.beancount` | pass | pass | PASS |  |
| `017-pushmeta.beancount` | pass | pass | PASS |  |
| `018-entry-metadata.beancount` | pass | pass | PASS |  |
| `019-posting-metadata.beancount` | pass | pass | PASS |  |
| `020-posting-flags.beancount` | pass | pass | PASS |  |
| `021-arithmetic.beancount` | pass | pass | PASS |  |
| `022-interpolate-missing.beancount` | pass | pass | PASS |  |
| `023-multiple-missing.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
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
| `036-booking-insufficient.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `037-booking-ambiguous.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `038-unbalanced.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `039-currency-constraint.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `040-unknown-account.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `041-include.beancount` | pass | pass | PASS |  |
| `042-plugin.beancount` | pass | pass | PASS |  |
| `043-options.beancount` | pass | pass | PASS |  |
| `044-tolerance-options.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `045-comments.beancount` | pass | pass | PASS |  |
| `046-string-escapes.beancount` | pass | pass | PASS |  |
| `047-syntax-error.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `048-duplicate-balance.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `049-invalid-booking-method.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `050-query-balances.beancount` | pass | pass | PASS |  |
| `051-query-journal.beancount` | pass | pass | PASS |  |
| `052-query-functions.beancount` | pass | pass | PASS |  |
| `053-query-group-limit.beancount` | pass | pass | PASS |  |
| `054-tolerance-inference.beancount` | pass | pass | PASS |  |
| `055-same-day-order.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `056-custom-values.beancount` | pass | pass | PASS |  |
| `057-bql-prices.beancount` | pass | pass | PASS |  |
| `058-cost-merge.beancount` | pass | skip | PASS | beancount 3.2.3 reports 'Cost merging is not supported yet' |
| `059-plugin-auto-basic.beancount` | pass | pass | PASS |  |
| `060-plugin-auto-existing.beancount` | pass | pass | PASS |  |
| `061-plugin-auto-late-open.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `062-plugin-auto-directives.beancount` | pass | pass | PASS |  |
| `063-plugin-implicit-cost.beancount` | pass | pass | PASS |  |
| `064-plugin-implicit-total.beancount` | pass | pass | PASS |  |
| `065-plugin-implicit-priority.beancount` | pass | pass | PASS |  |
| `066-plugin-implicit-duplicates.beancount` | pass | pass | PASS |  |
| `067-plugin-commodity-valid.beancount` | pass | pass | PASS |  |
| `068-plugin-commodity-missing.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `069-plugin-commodity-price.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `070-plugin-unique-valid.beancount` | pass | pass | PASS |  |
| `071-plugin-unique-conflict.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `072-plugin-leaf-valid.beancount` | pass | pass | PASS |  |
| `073-plugin-leaf-invalid.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `074-plugin-order-prices-first.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `075-plugin-order-unique-first.beancount` | pass | pass | PASS |  |
| `076-plugin-combined-all.beancount` | pass | pass | PASS |  |
| `077-plugin-order-leaf-first.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `078-plugin-order-auto-first.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `079-plugin-commodity-exemptions.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `080-plugin-implicit-short.beancount` | pass | pass | PASS |  |
| `081-pad-interpolated.beancount` | pass | pass | PASS |  |
| `082-balance-interpolated.beancount` | pass | pass | PASS |  |
| `083-auto-pad-interpolated.beancount` | pass | pass | PASS |  |
| `084-exempt-before-price.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `085-exempt-after-price.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `086-exempt-other-account.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `087-leaf-note.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `088-leaf-document.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `089-leaf-close.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `090-leaf-pad.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `091-leaf-pad-source.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `092-leaf-custom.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `093-short-strict.beancount` | pass | pass | PASS |  |
| `094-short-fifo.beancount` | pass | pass | PASS |  |
| `095-short-lifo.beancount` | pass | pass | PASS |  |
| `096-short-hifo.beancount` | pass | pass | PASS |  |
| `097-short-strict_with_size.beancount` | pass | pass | PASS |  |
| `098-short-average.beancount` | pass | pass | PASS |  |
| `099-implicit-zero.beancount` | pass | pass | PASS |  |
| `100-pad-costed-sale.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `101-pad-costed-buy.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `102-pad-uncosted.beancount` | pass | pass | PASS |  |
| `103-pad-costed-unused.beancount` | pass | prices only | PASS | Error ledger; BQL skipped |
| `104-short-inferred-strict-0.beancount` | pass | pass | PASS |  |
| `105-short-inferred-strict-1.beancount` | pass | pass | PASS |  |
| `106-short-inferred-fifo-0.beancount` | pass | pass | PASS |  |
| `107-short-inferred-fifo-1.beancount` | pass | pass | PASS |  |
| `108-short-inferred-average-0.beancount` | pass | pass | PASS |  |
| `109-short-inferred-average-1.beancount` | pass | pass | PASS |  |
| `110-short-inferred-none-0.beancount` | pass | pass | PASS |  |
| `111-short-inferred-none-1.beancount` | pass | pass | PASS |  |
| `112-round-zero.beancount` | pass | pass | PASS |  |
| `113-round-zero.beancount` | pass | pass | PASS |  |


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
  unlike the oracle. Linking a document is treated as metadata-only and now emits a
  `validation.document_unchecked` warning at the directive location.
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

Still outside the engine: subqueries, JOIN, PIVOT, arbitrary Python plugins, and BQL `CLOSE ON`
conversion entries (the report layer closes and carries earnings instead).

Backend checks run on native, js, wasm-gc and wasm (125 tests each); the
browser bundle has 29 node checks and 8 headless-Chrome checks (`web/smoke.mjs`,
`web/dom-smoke.mjs`). Oracle comparison covers 113 ledgers: 111 of 111 compared pass, with two extensions (the original 80 retain 78/78).

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

## 0.1.1 local reproduction evidence

The original 58-ledger oracle was rerun: 56/56 compared passed, 0 failed,
2 extensions. Both 1000-ledger seeds were rerun with the pinned external oracle;
see [seed 7](evidence/random-7.log) and [seed 20261101](evidence/random-20261101.log).
These remain black-box comparisons; no upstream source or fixtures were copied.

[Migration fixtures](../examples/migration/) exercise native automatic account creation,
metadata-only documents, successful relative includes followed by a missing
include, normalized include cycles, and explicit execution of stored subquery,
JOIN and PIVOT query texts. The BQL boundary errors have codes
`query.unsupported.subquery`, `query.unsupported.join`, `query.unsupported.pivot`
and a query-relative `BQL:line:column` location in the existing error text;
`failure()` classifies them as `Unsupported`. Ledger `query` directives are
stored, not executed by check. [Raw migration output](evidence/migration.json)
is checked by `scripts/migration_smoke.py`, alongside four-backend unit tests.
See the README migration section for exact lines, exit statuses and host duties.
Include failures preserve the including directive location; ordinary validation
after expansion currently uses the root filename and expanded-text line, not a
child-file source map. The migration include fixture makes this limit explicit.
Document warnings do not imply file verification; plugin warnings do not imply
execution. Here, non-execution refers only to unimplemented plugins; the five native plugins execute in 0.2.0. The conformance harness compares errors, not advisory warnings.

Updated 100k performance measurements, historical arrays, query profiles and
limitations are in [performance.md](performance.md). Local acceptance command
logs are retained in [evidence/](evidence/); this is not a new CI/deployment or
mooncakes publication claim.


## Native plugins (0.2.0)

| Plugin (`beancount.plugins.` prefix) | Supported behavior |
| --- | --- |
| `auto_accounts` | Create missing opens at the first account reference; an existing later open is not moved. |
| `implicit_prices` | Generate deduplicated daily prices from explicit posting prices (including total prices) or costs on lot augmentations; price overrides cost, reductions alone do not quote costs. Explicit price entries are retained. |
| `check_commodity` | Require declarations for open currencies, balances, posting units/costs/prices and price pairs; one error per missing currency. Account/currency regex exemptions also suppress price-only uses of the exempted currency, regardless of directive order; other non-exempt accounts still report it. Price-context regex keys do not exempt prices. |
| `unique_prices` | One error per date/base/quote group with unequal numbers; equivalent decimal scales do not conflict. |
| `leafonly` | One error per account with descendants referenced by postings, note, document, close, pad (both accounts), or custom account values. Open and balance alone are exempt. |

Enabled plugins run in declaration order after booking/default padding and before
final account validation. Unknown names, including third-party Python plugins,
are retained with `validation.plugin` warnings naming the unimplemented plugin;
their transformations and checks do not run, so dependent balances or errors may
differ. No Python interpreter is embedded. Native, wasm-gc and JS share the same
implementation. Library diagnostics, CLI text and exported JSON retain sources;
`export --json` also emits diagnostics and entries on invalid input (exit 1).

The specification basis is the official [Scripting & Plugins: Load Pipeline and
Plugin Configuration](https://beancount.github.io/docs/beancount_scripting_plugins/)
and [V3: Built-in Plugins](https://beancount.github.io/docs/beancount_v3/).
The latter lists these five native candidates; detailed edge behavior was
established with independently authored black-box inputs against Beancount 3.2.3,
without reading upstream plugin source, comments or fixtures.

Configuration boundary: `check_commodity` accepts a dictionary of quoted regex
strings using MoonBit's regex engine. Python-specific regex constructs or Python
literal forms outside that grammar are not implemented and are excluded from
supported configuration modes; they produce a named `validation.plugin` warning
and skip that plugin. The other four native plugins accept no configuration:
any configuration string (including an empty string) emits a named
`validation.plugin` warning and skips the plugin. Beancount 3.2.3 instead reports
a plugin call failure (exit 1); MoonBean warnings are advisory (exit 0 unless
other validation errors occur). No-configuration declarations remain supported.

Source-position differences are intentional: Beancount uses synthetic
`<auto_accounts>` locations for generated opens, `<check_commodity>:0` for missing
commodities and sometimes `<leafonly>:0`. MoonBean uses original ledger locations.
The harness normalizes commodity errors by currency and leaf errors by account;
other error locations are compared directly. Include-origin tests verify the
original file and line independently. Generated price locations match the
originating transaction. These are diagnostic provenance differences, not omitted
validation or transformation behavior.

Independently authored ledgers 059–113 cover plugin cases plus interpolated
inventories with/without pad, commodity exemption propagation, leaf directive
references, zero total prices and costed short opening. Empty-inventory costed
short openings now pass STRICT, FIFO, LIFO, HIFO, STRICT_WITH_SIZE, AVERAGE and
NONE; implicit_prices quotes their cost. This does not remove the existing
AVERAGE reduction extension or claim complete short-position lifecycle coverage.
The 33 new fixtures retain all original 80 results (78 compared, two extensions).
Raw price entries (including duplicates) are compared even on invalid ledgers;
clean ledgers also compare balances, lots and fixed queries. The existing random
generator does not declare plugins; its two 1000-ledger runs cover regressions in
booking, diagnostics, balances and reporting, not randomized plugin behavior.


Both seeds `7` and `20261101` completed 1000 inputs each: 858 matched,
142 AVERAGE differences, 0 non-AVERAGE differences; each included 468 clean
ledgers with balance/query/report checks. Results are retained in
[evidence/plugins-random-summary.json](evidence/plugins-random-summary.json).
`moon check --deny-warn --target all`, `moon test --target all` (125 tests per
target), `moon fmt --check` and `moon info` pass; `.mbti` files are unchanged.
The web build, 29 Node smoke checks and 8 DOM checks pass.

The complete 113-ledger run passed 111/111 comparisons with 2 existing extensions;
the original 80 fixtures retained their results. See [raw output](evidence/r6-oracle.log).

## Pad and short-opening boundaries (R6)

When a balance needs padding, a cost-bearing position in the asserted currency
(including subaccounts) produces `Attempt to pad an entry with cost for balance: (...)`
at the balance line, and `check` exits 1. The padding transaction is still inserted,
matching oracle balances. With no difference outside tolerance, no padding is
inserted and an unused pad still reports `Unused Pad entry`. Uncosted postings
between pad and balance remain supported. Ledgers 100–103 cover these cases.

Empty-cost `{}` and `{USD}` negative postings without positive inventory use
transaction residuals to infer opening cost. Ledgers 104–111 compare STRICT,
FIFO, AVERAGE and NONE; this does not claim a complete short-position lifecycle.
Ledgers 112–113 compare both orders of a same-transaction round trip: a zero
automatic cash posting is omitted; explicit zero postings remain intact.

The review baseline fails 12 of the 14 new ledgers (two pad errors, eight
inferred-cost openings, two round-trip query row sets); the two pad controls
already pass. See [baseline output](evidence/r6-baseline.log),
[exact pad messages and exit codes](evidence/r6-pad.json) and
[posting-level comparisons](evidence/r6-postings.json).

R6 re-runs retain the same two seeded results: see [random summary](evidence/r6-random-summary.json) and [validation summary](evidence/r6-validation.json).
