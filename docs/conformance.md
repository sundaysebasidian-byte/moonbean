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
All 58 ledgers pass the diagnostics comparison.

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
- Cost date and label are ignored when comparing lots; they are preserved in the
  MoonBean inventory but the oracle's CSV output for `BALANCES` does not expose
  them in a stable way.
