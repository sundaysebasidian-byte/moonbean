# Changelog

## 0.2.0

- Record interpolated posting amounts in booking inventories before balance assertions and padding.
- Propagate account commodity exemptions to price-only uses; extend leafonly to note, document, close, pad and custom account references.
- Warn by plugin name and skip unsupported configuration strings on the four no-configuration native plugins.
- Accept costed short openings without positive inventory under all seven booking methods; generate implicit zero prices for zero total prices on zero units.
- Add 19 regression ledgers (99 total, 97 comparable) and six tests (122 per backend).

- Execute five built-in plugins natively in declaration order: auto_accounts, implicit_prices, check_commodity, unique_prices and leafonly. Preserve original source locations and explicitly warn for unimplemented plugins/configuration modes.
- Validate account references after plugin transformations; keep booking and default padding before user plugins.
- Export entries and diagnostics as JSON even when validation fails (exit status remains 1).
- Add 22 independently authored plugin ledgers, raw price comparisons and portable plugin tests; update migration behavior and compatibility boundaries.
- No public API signature changes are expected from `moon info`; generated `.mbti` files remain unchanged.
- Prepare version 0.2.0 locally; no push, package publication or tag.

## 0.1.1

- Preserve per-line include origins in `ExpandedSource.source_map`; `check_source` and `syntax.parse_source` accept an optional source map. Library diagnostics, CLI text and JSON retain original file/line locations.
- Preserve non-BMP BQL string characters and reject non-BMP characters outside strings with positioned lexical errors; trailing unsupported clauses cannot be silently discarded.
- Make the plugin migration example require automatic account creation and fail explicitly without plugin execution.
- Resolve performance output paths from the repository root and retain relative command paths in evidence.

- Retain seeded 100k timings, environment/input fingerprints, historical arrays and query CPU profiles; compare the historical decimal parser in an isolated source snapshot.
- Add independently authored migration examples and CLI checks for plugins, documents, includes and unsupported BQL.
- Report subquery/JOIN/PIVOT failures with stable codes and query-relative locations; warn explicitly that document files are unchecked.
- Version 0.1.1 is prepared locally; no publication is implied.
- Reproducible 1000-ledger differential; exact oracle inventories before CSV rendering.
- HAVING, Decimal arithmetic, regex, tags/links/posting metadata and partial period balance queries.
- CLI bs/is/register/dups, single operating currency and report display precision.
- Single-buffer decimal parsing; host API docs and typed query failure categories.
- Windows CI path/shell correction, pinned oracle bootstrap and differential jobs.
- 112 tests on native, js, wasm-gc and wasm; remaining boundaries in conformance/performance reports.
- Browser playground (`playground/` JS exports, static page in `web/`) with a Pages workflow, a node smoke test and a headless-Chrome check that ledger text never becomes markup.
- Playground shows the engine's own totals, marks incomplete currency conversion and reports whether the balance sheet balances.
- Booked lot postings are kept whole across BQL, `JOURNAL`, register and JSON export; a reduction spanning lots is several rows.
- Balance sheet carries prior and current earnings into `Equity:Earnings:*`, lists market-value changes as an `Unrealized` reserve and balances exactly per currency.
- Deterministic dated multi-hop price paths with cycle detection; a missing path returns `report.conversion_incomplete` and totals split by currency.
- Text reports use one display scale per currency; JSON keeps exact amounts and adds `display_precision`.
- `FROM transactions` is rejected as unsupported instead of aliasing `postings`.
- `include` expansion shares one cycle-safe iterative stack between the library and the CLI (`include.cycle`, `include.missing`, depth 1024).
- Oracle differential extended to posting-level rows, reports and price paths; two seeds of 1000 ledgers show no difference other than the AVERAGE extension.

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
