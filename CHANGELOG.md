# Changelog

## 0.1.0

Initial release.

### Parser

- All Beancount directives: `option`, `plugin`, `include`, `pushtag`/`poptag`,
  `pushmeta`/`popmeta`, `open`, `close`, `commodity`, `balance`, `pad`,
  `price`, `note`, `document`, `event`, `query`, `custom`, transactions.
- Transaction flags, payee/narration, tags, links, entry/posting metadata and
  posting flags.
- Arithmetic expressions in posting amounts and costs, `{}` / `{{}}` costs
  (unit, total, date, label), `@` / `@@` prices and omitted amounts.
- Line-accurate diagnostics for malformed input.

### Booking

- Exact decimal arithmetic with Beancount-compatible tolerance inference.
- STRICT, STRICT_WITH_SIZE, FIFO, LIFO, HIFO, AVERAGE and NONE methods,
  including `{*}` cost merging (MoonBean extensions for AVERAGE and `{*}`).
- Lot matching with ambiguity and insufficiency errors.

### Validation

- Account lifecycle, open currency constraints, balancing, balance assertions,
  pads and duplicate open/close/balance detection.
- Beancount-compatible error precedence and balance tolerance inference.
- On-demand duplicate transaction detection through the library API.
- Unsupported plugins are recorded and reported as warnings with their source
  line.

### Realization and reports

- Per-account inventories, price database, currency conversion.
- Trial balance, balance sheet, income statement, inventory and register
  reports in text and JSON.
- JSON ledger export with options, accounts, entries, errors and warnings.

### Query

- BQL subset: SELECT/FROM/WHERE/GROUP BY/ORDER BY/LIMIT, BALANCES, JOURNAL.
- Columns and functions used by common balance and journal queries.
- Text and JSON result rendering.

### Tooling

- `moonbean check`, `bal [--at DATE] [--convert CCY]`, `query`, `fmt`,
  `export --json`.
- Pure library facade usable from native, wasm-gc and JavaScript.
- Full-year example ledger and an embeddable library demo.
- Oracle conformance harness with 58 self-written ledgers (56 compared,
  56 passing) and a 100k-transaction benchmark.
- CI for ubuntu/macOS/Windows plus an upstream oracle job.

## Unreleased

- Reproducible 1000-ledger differential; exact oracle inventories before CSV rendering.
- HAVING, Decimal arithmetic, regex, tags/links/posting metadata and partial period balance queries.
- CLI bs/is/register/dups, single operating currency and report display precision.
- Single-buffer decimal parsing; host API docs and typed query failure categories.
- Windows CI path/shell correction, pinned oracle bootstrap and differential jobs.
- 94 tests on native/js/wasm-gc; remaining boundaries in conformance/performance reports.
- Browser playground (`playground/` JS exports, static page in `web/`) with a Pages workflow and a node smoke test.

## Review R1 backend (2026-10-31)

- Preserve split booked lot details across BQL, journals, register and export; reject FROM transactions.
- Close prior/current earnings, balance cost/market reports, expose incomplete conversion and per-currency totals.
- Add deterministic dated multihop price paths and inferred text display precision; keep JSON exact.
- Share cycle-safe include traversal across library and CLI, including Windows/UNC normalization.
- Expand independent review and two-seed random oracle comparisons to row-level costs, reports and price paths.
