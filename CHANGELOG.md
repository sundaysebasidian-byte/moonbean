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
- 108 tests on native, js, wasm-gc and wasm; remaining boundaries in conformance/performance reports.
- Browser playground (`playground/` JS exports, static page in `web/`) with a Pages workflow, a node smoke test and a headless-Chrome check that ledger text never becomes markup.
- Playground shows the engine's own totals, marks incomplete currency conversion and reports whether the balance sheet balances.
- Booked lot postings are kept whole across BQL, `JOURNAL`, register and JSON export; a reduction spanning lots is several rows.
- Balance sheet carries prior and current earnings into `Equity:Earnings:*`, lists market-value changes as an `Unrealized` reserve and balances exactly per currency.
- Deterministic dated multi-hop price paths with cycle detection; a missing path returns `report.conversion_incomplete` and totals split by currency.
- Text reports use one display scale per currency; JSON keeps exact amounts and adds `display_precision`.
- `FROM transactions` is rejected as unsupported instead of aliasing `postings`.
- `include` expansion shares one cycle-safe iterative stack between the library and the CLI (`include.cycle`, `include.missing`, depth 1024).
- Oracle differential extended to posting-level rows, reports and price paths; two seeds of 1000 ledgers show no difference other than the AVERAGE extension.
