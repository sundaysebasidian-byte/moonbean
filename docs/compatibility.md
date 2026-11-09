# Compatibility contract (0.2.3)

## Endpoint and evidence

The compatibility endpoint is **beancount 3.2.3 syntax and accounting semantics plus the complete beanquery 0.2.0 language**. This is a target, not a claim that the endpoint has been reached. MoonBean 0.2.3 does **not** implement the full endpoint. The explicit gaps below remain release limitations.

Oracle metadata was obtained through public runtime descriptors, independently authored parser inputs, and CLI `.tables`, `.describe`, `.help targets` and statement probes. No upstream source or fixtures were inspected or copied. Reproduce with the pinned oracle Python: `python scripts/compatibility_inventory.py`. [Machine-readable inventory](evidence/compatibility-inventory.json) retains signatures, defaults, repeated-assignment probes, columns and command results. A descriptor or successful parse is not semantic conformance evidence.

Evidence: `scripts/conformance.py` (ledger fixtures), `scripts/bql_differential.py` (109 checked queries/boundaries), `query/query_test.mbt`, `syntax/parser_test.mbt`, and [acceptance](evidence/r2-acceptance.md). Unsupported statements/functions return errors; recognized options retained as raw data may have no effect, as listed below.

## Options

Defaults and types are oracle values. Repeat means collection accumulation; scalar repetition replaces the value. The JSON includes actual repeated-example parser errors/results, including internal output options that the oracle accepts through `option` but applications should not normally set. Each unsupported item below can affect results; use the pinned oracle when that behavior is needed.

| Name | Oracle type | Default | Repeat | MoonBean boundary |
| --- | --- | --- | --- | --- |
| `include` | list | `[]` | yes | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `input_hash` | str | `` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `dcontext` | DisplayContext | `__default__     : sign=1   integer_max=1   fractional_common=_   fractional_max=_   "-0.*" "-0.*" ` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `commodities` | set | `set()` | yes | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `title` | str | `Beancount` | no | Supported storage; presentation title is host-owned (parser tests). |
| `name_assets` | str | `Assets` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `name_liabilities` | str | `Liabilities` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `name_equity` | str | `Equity` | no | Used for summary/report equity account labels; full renamed account taxonomy unsupported (realization option regression). |
| `name_income` | str | `Income` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `name_expenses` | str | `Expenses` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `account_previous_balances` | str | `Opening-Balances` | no | Used by FROM OPEN summary and report prior-earnings labels (period differential / realization option tests); other oracle contexts unverified. |
| `account_previous_earnings` | str | `Earnings:Previous` | no | Used by FROM OPEN summary and report prior-earnings labels (period differential / realization option tests); other oracle contexts unverified. |
| `account_previous_conversions` | str | `Conversions:Previous` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `account_current_earnings` | str | `Earnings:Current` | no | Implemented report current-earnings label (realization option regression); other oracle contexts unverified. |
| `account_current_conversions` | str | `Conversions:Current` | no | Implemented report conversion/residual label (realization report tests); other oracle contexts unverified. |
| `account_unrealized_gains` | str | `Earnings:Unrealized` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `account_rounding` | NoneType | `None` | no | Unsupported rounding-account postings; parsed/stored only. Balances/entries may differ; use oracle. |
| `conversion_currency` | str | `NOTHING` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `display_precision` | dict | `{}` | yes | Implemented for MoonBean report text and report metadata (realization precision test); full oracle precision/rendering policy not proven. |
| `inferred_tolerance_default` | dict | `{}` | yes | Supported per-currency and wildcard fallback defaults (044, 115–116); inferred currency tolerance overrides wildcard. Other combinations not exhaustively verified. |
| `tolerance_multiplier` | Decimal | `0.5` | no | Supported decimal inference (044, 054); not an exhaustive tolerance proof. |
| `inferred_tolerance_multiplier` | Decimal | `0.5` | no | Supported deprecated alias, emits warning (044). |
| `infer_tolerance_from_cost` | bool | `False` | no | Supported inference; TRUE/True/true/1 enabled, other values false (054, 115 and parser tests). |
| `documents` | list | `[]` | yes | Unsupported folder discovery and file existence validation; paths stored only. Host must verify receipts. |
| `operating_currency` | list | `[]` | yes | Stored repeatably; a single value selects report conversion in CLI/playground. Multi-currency oracle report layout unsupported. |
| `render_commas` | bool | `False` | no | Unsupported comma rendering; boolean parsed/stored only. Amount text differs; host can format numbers. |
| `plugin_processing_mode` | str | `default` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `long_string_maxlines` | int | `64` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `booking_method` | Booking | `Booking.STRICT` | no | Supported for STRICT, STRICT_WITH_SIZE, FIFO, LIFO, HIFO, NONE (029–034); AVERAGE is an extension. |
| `allow_pipe_separator` | bool | `False` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `allow_deprecated_none_for_tags_and_links` | bool | `False` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `use_precise_interpolation` | bool | `False` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `insert_pythonpath` | bool | `False` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |

`filename` and `plugin` are oracle read-only option names. MoonBean does not yet mirror all unknown/read-only option errors, value converters or deprecated-option diagnostics. These are explicit diagnostic gaps. Include and plugin directives are distinct from internal option values.

## Directives

| Directive / controls | Status and evidence / limitation |
| --- | --- |
| `open` (meta, date, account, currencies, booking) | Syntax, currencies and booking supported (009, 013, 029–034); renamed root options are a gap. |
| `close` (meta, date, account) | Account lifecycle validation supported (010–014). |
| `commodity` (meta, date, currency) | Syntax/metadata retained (003); full BQL table unsupported. |
| `pad` (meta, date, account, source_account) | Padding and cost-inventory rejection supported (006, 007, 100–103). |
| `balance` (meta, date, account, amount, tolerance, diff_amount) | Assertions supported (004, 005, 048); tolerance combinations remain bounded by fixtures. |
| `transaction` (meta, date, flag, payee, narration, tags, links, postings) | Booking, metadata and postings supported by conformance fixtures; complete short-position lifecycle not claimed. |
| `note` (meta, date, account, comment, tags, links) | Account validation and text parsing supported (008, 087); tag/link round-trip and every oracle error category not exhaustively verified. |
| `event` (meta, date, type, description) | Date/type/description parsing and retention supported (008); BQL events source unsupported. |
| `query` (meta, date, name, query_string) | Date/name/query text retained (008). Check does not execute stored queries, as with bean-check; oracle `.run name` execution unsupported. Call `run_query` explicitly for supported query texts. |
| `price` (meta, date, currency, amount) | Raw prices and duplicate preservation supported (003, 057, 063–070). |
| `document` (meta, date, account, filename, tags, links) | Account validation and metadata parsing supported (008, 088); file stat and documents-folder discovery unsupported: the pure library has no document resolver callback. A warning explicitly states the file was not checked; host must check it. |
| `custom` (meta, date, type, values) | Typed values/account references supported (056, 092); no custom plugin semantics. All oracle error categories not exhaustively verified. |
| `include` | Supported via native filesystem / host resolver (041 and include smoke); host filesystem policy applies. |
| `plugin` | Five built-ins supported; other Python plugins only warn and do not execute. See conformance.md. |
| `pushtag` / `poptag`, `pushmeta` / `popmeta` | Supported stacks (016–017). |

## BQL tables and every oracle column

Bare `balances` is a MoonBean inventory extension. It is **not** oracle `#balances` (assertion rows). Table names are case-sensitive after `#`; unsupported sources are rejected. `transactions.meta` as a dict column is unsupported; `meta(key)` is supported on transactions.

| Table | Column | Oracle type | Status / evidence or alternative |
| --- | --- | --- | --- |
| `accounts` | `account` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `accounts` | `open` | `open` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `accounts` | `close` | `close` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `account` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `amount` | `amount` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `tolerance` | `decimal` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `balances` | `discrepancy` | `amount` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `commodities` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `commodities` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `commodities` | `name` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `account` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `filename` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `tags` | `frozenset` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `documents` | `links` | `frozenset` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `id` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `type` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `filename` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `lineno` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `year` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `month` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `day` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `flag` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `payee` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `narration` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `description` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `tags` | `set` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `links` | `set` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `meta` | `dict` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `entries` | `accounts` | `set[str]` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `events` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `events` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `events` | `type` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `events` | `description` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `account` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `comment` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `tags` | `frozenset` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `notes` | `links` | `frozenset` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `type` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `id` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `date` | `date` | Supported (BQL differential / query tests). |
| `postings` | `year` | `int` | Unsupported direct column; use year(date) / month(date). |
| `postings` | `month` | `int` | Unsupported direct column; use year(date) / month(date). |
| `postings` | `day` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `filename` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `lineno` | `int` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `location` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `flag` | `str` | Supported (BQL differential / query tests). |
| `postings` | `payee` | `str` | Supported (BQL differential / query tests). |
| `postings` | `narration` | `str` | Supported (BQL differential / query tests). |
| `postings` | `description` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `tags` | `set` | Supported (BQL differential / query tests). |
| `postings` | `links` | `set` | Supported (BQL differential / query tests). |
| `postings` | `posting_flag` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `account` | `str` | Supported (BQL differential / query tests). |
| `postings` | `other_accounts` | `set` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `number` | `decimal` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `currency` | `str` | Supported (BQL differential / query tests). |
| `postings` | `cost_number` | `decimal` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `cost_currency` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `cost_date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `cost_label` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `position` | `position` | Supported (BQL differential / query tests). |
| `postings` | `price` | `amount` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `weight` | `amount` | Supported (BQL differential / query tests). |
| `postings` | `balance` | `inventory` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `meta` | `dict` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `entry` | `transaction` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `postings` | `accounts` | `set[str]` | Supported (BQL differential / query tests). |
| `prices` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `prices` | `date` | `date` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `prices` | `currency` | `str` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `prices` | `amount` | `amount` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `transactions` | `meta` | `metadata` | Not implemented by the source adapter/evaluator; use oracle source/column. No equivalent promised. |
| `transactions` | `date` | `date` | Supported (BQL differential / query tests). |
| `transactions` | `flag` | `str` | Supported (BQL differential / query tests). |
| `transactions` | `payee` | `str` | Supported (BQL differential / query tests). |
| `transactions` | `narration` | `str` | Supported (BQL differential / query tests). |
| `transactions` | `tags` | `set` | Supported (BQL differential / query tests). |
| `transactions` | `links` | `set` | Supported (BQL differential / query tests). |
| `transactions` | `accounts` | `set[str]` | Supported (BQL differential / query tests). |

## BQL functions and aggregates

Support is limited to accepted argument expressions/types. Functions on unsupported dict/object columns remain unavailable even if the name is accepted for other types.

| Oracle signature | Status / evidence or alternative |
| --- | --- |
| `abs(decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `abs(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `abs(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `account_sortkey(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `any_meta(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `bool(any)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `close_date(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `commodity(amount)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `commodity_meta(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `commodity_meta(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(amount, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(amount, str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(position, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(position, str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(inventory, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `convert(inventory, str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `cost(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `cost(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `currency(amount)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `currency_meta(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `currency_meta(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date(object)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date(int, int, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_add(date, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_bin(str, date, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_bin(relativedelta, date, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_diff(date, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_part(str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `date_trunc(str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `day(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `decimal(bool)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `decimal(decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `decimal(int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `decimal(object)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `decimal(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `empty(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `entry_meta(str)` | Supported (BQL differential / query tests). |
| `filter_currency(inventory, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `filter_currency(position, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `findfirst(str, set)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `getitem(dict, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `getitem(dict, str, any)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `getprice(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `getprice(str, str, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `grep(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `grepn(str, str, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `has_account(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `int(bool)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `int(decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `int(int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `int(object)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `int(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `interval(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `joinstr(set)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `leaf(str)` | Supported (BQL differential / query tests). |
| `length(list)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `length(set)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `length(str)` | Supported (BQL differential / query tests). |
| `lower(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `maxwidth(str, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `meta(str)` | Supported (BQL differential / query tests). |
| `month(date)` | Supported (BQL differential / query tests). |
| `neg(amount)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `neg(decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `neg(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `neg(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `number(amount)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `only(str, inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `open_date(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `open_meta(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `open_meta(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `parent(str)` | Supported (BQL differential / query tests). |
| `parse_date(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `parse_date(str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `possign(amount, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `possign(decimal, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `possign(inventory, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `possign(position, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `quarter(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `repr(any)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `root(str)` | Supported (BQL differential / query tests). |
| `root(str, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `round(decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `round(decimal, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `round(int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `round(int, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `safediv(decimal, decimal)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `safediv(decimal, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `splitcomp(str, str, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `str(any)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `subst(str, str, str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `substr(str, int, int)` | Supported (BQL differential / query tests). |
| `today()` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `units(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `units(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `upper(str)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(inventory, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(position, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `weekday(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `year(date)` | Supported (BQL differential / query tests). |
| `yearmonth(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `count(*)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `count(any)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `first(any)` | Unsupported signature; use beanquery 0.2.0. |
| `last(any)` | Unsupported signature; use beanquery 0.2.0. |
| `max(any)` | Unsupported signature; use beanquery 0.2.0. |
| `min(any)` | Unsupported signature; use beanquery 0.2.0. |
| `sum(amount)` | Unsupported signature; use beanquery 0.2.0. |
| `sum(inventory)` | Unsupported signature; use beanquery 0.2.0. |
| `sum(decimal)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `sum(int)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `sum(position)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |

## Statements, clauses and operators

| Feature | Status / evidence or limitation |
| --- | --- |
| SELECT projections, SELECT * | Supported on postings/transactions; oracle default columns, BQL source differential. Mixed star projections rejected. |
| DISTINCT | Supported before LIMIT for scalar/set expressions; BQL differential and query tests. DISTINCT amount/position/inventory/sum projections are explicitly rejected: oracle position deduplication does not follow ordinary numeric equality. Currently quadratic in output count. |
| FROM postings / transactions | Supported, including adjacent lowercase # names; BQL source differential. |
| WHERE, GROUP BY, HAVING, ORDER BY, LIMIT | Supported for accepted expressions; conformance and BQL differential. Aliases and positional references not implemented. |
| FROM OPEN ON / CLOSE ON | Supported standalone period sources (period differential); accounts projections/filters on OPEN summaries are explicitly rejected; arbitrary directive filters and combined named-table transforms unsupported. |
| FROM CLEAR, CLOSE without ON | Unsupported; use oracle. |
| FLATTEN | Unsupported; host can expand supported inventory output, or use oracle. |
| PIVOT BY | Unsupported; host pivot or oracle. |
| FROM (SELECT …) / subqueries | Unsupported; use oracle or explicitly stage results in host. |
| BALANCES | Inventory report supported; oracle formatting and all clause combinations not promised. |
| JOURNAL | Account report supported; full oracle statement syntax not implemented. |
| PRINT / EXPLAIN / shell .run | Unsupported; ledger export/API query result is an alternative, not equivalent output. |
| + - * /, comparisons = == != <> < <= > >=, AND OR NOT, IS [NOT] NULL, ~ regex | Supported for accepted expression types; arithmetic/NULL/regex differential. Python-specific regex syntax not promised. |
| IN / NOT IN, quantified comparisons, other operators | Unsupported / not exhaustively enumerated. Operator inventory remains incomplete; no full-language claim. |
| LIKE / JOIN | Rejected by both pinned oracle and MoonBean; outside compatibility endpoint. |
| Unicode upper/lower | Unsupported; no ASCII-only approximation. |

## Extensions and remaining verification gaps

`AVERAGE`, `{*}` cost merging and bare inventory `FROM balances` are extensions, not oracle coverage. Extra amount/units/cost/value columns and report conversion also have local semantics. Local diagnostic severity, messages and some source provenance differ; conformance compares normalized error categories, not exact messages. No claim of complete error-category equivalence for document/note/event/query/custom.

Inventory capture covers public built-in help and all 10 advertised tables; it is not a proof that undocumented function overloads/operators/shell commands do not exist. Full statement grammar and semantic combinations remain unverified. The endpoint is therefore not reached even beyond the explicit implementation gaps.

Performance evidence retains prior wasm-gc 1M FIFO default-heap limitation and uncompleted large ungrouped ORDER BY. See [performance.md](performance.md). No push, tag, deployment or publication is implied by this local candidate.

## Remaining work in priority order

1. Add the other eight advertised tables and all missing columns, including typed transaction metadata dictionaries. Current transaction `meta(key)` does not expose the dict column.
2. Implement and differential-test the unsupported function/aggregate signatures above, Unicode casing, full argument type checking and empty-input aggregate behavior. Existing output tests are a bounded set.
3. Implement FROM directive filters/CLEAR, FLATTEN, PIVOT BY, subqueries, PRINT and EXPLAIN, aliases and positional references. Resolve oracle DISTINCT position identity behavior before enabling non-scalar DISTINCT.
4. Implement rounding-account postings, document host verification/discovery, comma/precision presentation, renamed account taxonomy, processing modes and the remaining option converters/diagnostics.
5. Exhaustively enumerate grammar/operator combinations beyond the CLI help/probes and compare every directive error category. This release's inventory is not an exhaustive language-conformance proof.
