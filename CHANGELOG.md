# Changelog

## 0.2.3 (local candidate)

- R9 performance remains unverified: the authorized loaded-host third-repeat comparison exceeds four JS 1M FIFO stage limits; retain all measurements for independent idle-host review.
- R9: fix implicit aggregate grouping and Inventory bool errors; add period/NULL/error regressions and per-signature type probes. Correct star/operator/round/malformed-ledger boundaries and normalize exported evidence paths.

- Preserve arbitrary precision for integer add/subtract/multiply and integer sums; compare seeded 29–60-digit queries with the oracle.

- Cache stable O(n log n) sort keys, distinguish text/date group keys and Unicode scalar ordering; add seeded sort and 100k native posting differentials. Keep row provenance lazy and avoid parser/tolerance hot-path allocations.
- Return round 2: add typed recursive metadata/directive values and every advertised table column, including generated metadata, identities and assertion discrepancies; preserve note tags/links and correct same-day directive order.
- Resolve function signatures after source types, distinguish int/decimal and set/frozenset; add common metadata, calendar, amount/inventory, numeric conversion, rounding and component functions. 74 scalar signatures have evaluators; 31 remain unimplemented, with explicit value-domain/type gaps.
- Implement exact-representation position DISTINCT with hash lookup, finite Python decimal rendering and explicit rejection of signed-zero object queries/nonfinite conversions/nonportable set repr. Correct cost-based tolerance inference and add structured/random oracle cases. See compatibility.md for remaining query-plan, option and diagnostic work.

- Return round 1: add scalar/amount/set adapters for eight directive sources, source column validation and canonical native query filenames; the first batch retained typed object/id/discrepancy gaps (resolved with the round 2 boundaries above).
- Add full Unicode 16 upper/lower mappings with contextual final sigma, reproducible data generation and a 7196-row oracle corpus; align CI Python to 3.14 (remote CI unverified).
- Add first/last and scalar min/max, amount-column sums, empty-source and all-NULL sum behavior, boolean/frozenset values and matchable Compilation/Evaluation errors. Guard unsupported quoted identifiers and bare accounts FROM filtering rather than silently approximating them.

- Record pinned oracle option, directive, table/column and function inventories and an explicit compatibility contract; full beanquery compatibility remains unimplemented.
- Support SELECT *, scalar/set DISTINCT, transaction accounts and meta(), entry_meta(), and NULL-aware count(expr).
- Accept oracle boolean spellings and wildcard inferred tolerance defaults; retain explicit rounding, document host and rendering limitations.


## 0.2.2

- Add offline seeded, multi-scale library-stage performance measurements for native, JS and wasm-gc, including cost booking and representative BQL queries.
- Retain warmup/sample arrays, percentiles, throughput, process peak RSS and stage profiles; preserve partial samples/full diagnostics on backend failure and add a local baseline regression checker.

## 0.2.1

- Add Unicode code-point `length` and zero-origin, end-exclusive `substr` with negative/clipped integer literal indices and typed NULL propagation.
- Add one-row-per-transaction `FROM transactions` / `#transactions` with explicit column boundaries; preserve empty versus absent payees.
- Keep NULL and empty string groups distinct and sort NULL first in ascending order.
- Preserve oracle BQL backslashes/doubled quotes and ledger text following non-BMP characters; retain query locations for invalid regex and unsupported capabilities.
- Verify 114 ledgers (112 comparable, two extensions), 41 extended BQL outputs plus 51 capability boundaries, 132 tests per backend and both 1000-input differential seeds.
- Document oracle support for Unicode upper/lower, subqueries and PIVOT BY as unimplemented; LIKE/JOIN and startswith/findfirst signatures are rejected by the pinned oracle.
- Reject unsupported hash tables, star projections and non-count star arguments with BQL positions; keep bare balances as inventory.
- Sort tags/links in text output; retain source-order JSON arrays.

## 0.2.0

- Match cost-bearing pad errors while preserving padding balances; a zero difference leaves the pad unused.
- Infer empty-cost short openings without positive inventory; omit zero automatic residual postings in same-transaction round trips.

- Record interpolated posting amounts in booking inventories before balance assertions and padding.
- Propagate account commodity exemptions to price-only uses; extend leafonly to note, document, close, pad and custom account references.
- Warn by plugin name and skip unsupported configuration strings on the four no-configuration native plugins.
- Accept costed short openings without positive inventory under all seven booking methods; generate implicit zero prices for zero total prices on zero units.
- Add 33 regression ledgers (113 total, 111 comparable) and nine tests (125 per backend).

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
