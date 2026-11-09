# Compatibility contract (0.2.3)

## Endpoint and evidence

The compatibility endpoint is **beancount 3.2.3 syntax and accounting semantics plus the complete beanquery 0.2.0 language**. This is a target, not a claim that the endpoint has been reached. MoonBean 0.2.3 does **not** implement the full endpoint. The explicit gaps below remain release limitations.

Oracle metadata was obtained through public runtime descriptors, independently authored parser inputs, and CLI `.tables`, `.describe`, `.help targets` and statement probes. No upstream source or fixtures were inspected or copied. Reproduce with the pinned oracle Python: `python scripts/compatibility_inventory.py`. [Machine-readable inventory](evidence/compatibility-inventory.json) retains signatures, defaults, repeated-assignment probes, columns and command results. A descriptor or successful parse is not semantic conformance evidence.

Evidence: `scripts/conformance.py` (ledger fixtures), `scripts/bql_differential.py` (current results linked below), `query/query_test.mbt`, `syntax/parser_test.mbt`, and [current acceptance](evidence/r2-return-acceptance.md). QueryError now distinguishes Syntax, Compilation, Evaluation and Unsupported. Shared invalid-input cases compare normalized oracle error categories. Unsupported statements/functions return errors; recognized options retained as raw data may have no effect, as listed below.

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

All ten advertised sources are now registered, with the per-column limits below. Use `#accounts`: bare `accounts` is a transaction filter in the oracle and is explicitly rejected until FROM filters are implemented. Bare `balances` is a MoonBean inventory extension. It is **not** oracle `#balances` (assertion rows). Table names are case-sensitive after `#`; unsupported sources are rejected. `transactions.meta` as a dict column is unsupported; `meta(key)` is supported on transactions.

| Table | Column | Oracle type | Status / evidence or alternative |
| --- | --- | --- | --- |
| `accounts` | `account` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `accounts` | `open` | `open` | Pending typed directive-object values. QueryValue cannot carry Open/Close objects; join the source data in the host or use oracle. |
| `accounts` | `close` | `close` | Pending typed directive-object values. QueryValue cannot carry Open/Close objects; join the source data in the host or use oracle. |
| `balances` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `balances` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `balances` | `account` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `balances` | `amount` | `amount` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `balances` | `tolerance` | `decimal` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `balances` | `discrepancy` | `amount` | Pending assertion-time differences. AST.Balance retains the assertion but not the validated discrepancy; use check diagnostics or oracle. |
| `commodities` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `commodities` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `commodities` | `name` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `documents` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `documents` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `documents` | `account` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `documents` | `filename` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. Native query filenames are absolute; library hosts supply canonical source names. Document paths are lexically resolved, not stat-verified. |
| `documents` | `tags` | `frozenset` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `documents` | `links` | `frozenset` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `id` | `str` | Pending exact oracle directive fingerprinting; its canonical field encoding has not been reproduced. No guessed hash is emitted; use oracle. |
| `entries` | `type` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `filename` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. Native query filenames are absolute; library hosts supply canonical source names. Document paths are lexically resolved, not stat-verified. |
| `entries` | `lineno` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `year` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `month` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `day` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `flag` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `payee` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `narration` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `description` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `tags` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `links` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `entries` | `meta` | `dict` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `entries` | `accounts` | `set[str]` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `events` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `events` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `events` | `type` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `events` | `description` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `notes` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `notes` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `notes` | `account` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `notes` | `comment` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `notes` | `tags` | `frozenset` | Empty frozensets supported. Tagged/linked note syntax remains unimplemented: AST.Note has no fields for them; use oracle for such notes. |
| `notes` | `links` | `frozenset` | Empty frozensets supported. Tagged/linked note syntax remains unimplemented: AST.Note has no fields for them; use oracle for such notes. |
| `postings` | `type` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `id` | `str` | Pending exact oracle directive fingerprinting; its canonical field encoding has not been reproduced. No guessed hash is emitted; use oracle. |
| `postings` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `year` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `month` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `day` | `int` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `filename` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `lineno` | `int` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `location` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `flag` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `payee` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `narration` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `description` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `tags` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `links` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `posting_flag` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `account` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `other_accounts` | `set` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `number` | `decimal` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `currency` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `cost_number` | `decimal` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `cost_currency` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `cost_date` | `date` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `cost_label` | `str` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `position` | `position` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `price` | `amount` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `weight` | `amount` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `postings` | `balance` | `inventory` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `meta` | `dict` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `postings` | `entry` | `transaction` | Pending source adapter/typed evaluation; use the oracle. No equivalent value is promised. |
| `postings` | `accounts` | `set[str]` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `prices` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `prices` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `prices` | `currency` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `prices` | `amount` | `amount` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `meta` | `metadata` | Pending typed dictionary values and generated booking annotations. QueryValue has no dict variant; returning text or fabricated NULL would lose types. User-key meta() is available; use oracle for the whole dict. |
| `transactions` | `date` | `date` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `flag` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `payee` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `narration` | `str` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `tags` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `links` | `set` | Supported for accepted ledger inputs; table differential and four-backend tests. |
| `transactions` | `accounts` | `set[str]` | Supported for accepted ledger inputs; table differential and four-backend tests. |

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
| `entry_meta(str)` | User-key lookup supported. Directive sources additionally expose filename/lineno through meta(); posting reserved/generated metadata is not complete. Computed-key signatures and object conversion remain pending. |
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
| `lower(str)` | Supported for Unicode 16.0.0, matching the pinned CPython oracle. Multi-codepoint mappings and contextual final sigma; 7196-row differential corpus, including all 2981 changed scalars and 7060 contextual property scalars. |
| `maxwidth(str, int)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `meta(str)` | User-key lookup supported. Directive sources additionally expose filename/lineno through meta(); posting reserved/generated metadata is not complete. Computed-key signatures and object conversion remain pending. |
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
| `upper(str)` | Supported for Unicode 16.0.0, matching the pinned CPython oracle. Multi-codepoint mappings and contextual final sigma; 7196-row differential corpus, including all 2981 changed scalars and 7060 contextual property scalars. |
| `value(inventory)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(inventory, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(position)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `value(position, date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `weekday(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `year(date)` | Supported (BQL differential / query tests). |
| `yearmonth(date)` | Not implemented by the query parser/evaluator; use beanquery 0.2.0. |
| `count(*)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `count(any)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `first(any)` | Supported for represented QueryValue types; first skips NULL, last preserves final NULL. Object/dict inputs depend on pending value types; generic accounts function calls also fail in the oracle. |
| `last(any)` | Supported for represented QueryValue types; first skips NULL, last preserves final NULL. Object/dict inputs depend on pending value types; generic accounts function calls also fail in the oracle. |
| `max(any)` | Scalar numbers, bools, dates and strings supported; NULL ignored. Set/position/inventory comparison rules are not implemented and explicitly rejected, not approximated as scalar ordering. |
| `min(any)` | Scalar numbers, bools, dates and strings supported; NULL ignored. Set/position/inventory comparison rules are not implemented and explicitly rejected, not approximated as scalar ordering. |
| `sum(amount)` | Supported for available amount columns; result is Inventory. Price-table differential covers the amount/currency total. |
| `sum(inventory)` | Unsupported signature; use beanquery 0.2.0. |
| `sum(decimal)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `sum(int)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |
| `sum(position)` | Supported for accepted expressions; count(expr) excludes NULL (BQL differential). |

## Statements, clauses and operators

| Feature | Status / evidence or limitation |
| --- | --- |
| SELECT projections, SELECT * | Default stars supported on postings/transactions/events/prices/notes/documents; stars containing unsupported object/id/discrepancy columns remain rejected. Mixed star projections rejected. |
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
| Unicode upper/lower | Supported using pinned CPython Unicode 16.0.0 data, including expansions and final sigma; typed bad arguments produce compilation errors. |

## Extensions and remaining verification gaps

`AVERAGE`, `{*}` cost merging and bare inventory `FROM balances` are extensions, not oracle coverage. Extra amount/units/cost/value columns and report conversion also have local semantics. Local diagnostic severity, messages and some source provenance differ; conformance compares normalized error categories, not exact messages. No claim of complete error-category equivalence for document/note/event/query/custom.

Inventory capture covers public built-in help and all 10 advertised tables; it is not a proof that undocumented function overloads/operators/shell commands do not exist. Full statement grammar and semantic combinations remain unverified. The endpoint is therefore not reached even beyond the explicit implementation gaps. Double-quoted words matching known column names are explicitly rejected: the parser does not yet preserve the oracle quoted-identifier resolution; use an unquoted column or a single-quoted literal.

Performance evidence retains prior wasm-gc 1M FIFO default-heap limitation and uncompleted large ungrouped ORDER BY. See [performance.md](performance.md). No push, tag, deployment or publication is implied by this local candidate.

## Return round 1: first implementation batch

Current local evidence is in [r2-return-acceptance.md](evidence/r2-return-acceptance.md); earlier acceptance describes the preceding candidate. CI now selects Python 3.14 to match the oracle's Unicode 16.0.0 runtime; this change has not been pushed or run remotely. Unicode data is reproducibly generated using CPython's public string API, without importing or reading Beancount implementation code.

The eight additional source adapters are implemented for the scalar/amount/set columns marked above. Raw dict/directive/id/discrepancy values remain intentionally rejected. Document filename resolution does not prove file existence. Empty-source aggregates produce no rows, matching the oracle; numeric sum over nonempty all-NULL input produces zero. Booleans and frozensets retain explicit QueryValue variants.

The oracle itself raises an internal AttributeError when functions consume its generic `accounts` column type (observed for count, first and upper). MoonBean explicitly reports an Evaluation failure rather than returning a successful approximate result. The corpus records both failures and compares their error category. This is an oracle limitation, not evidence of successful aggregate execution.

## Remaining work in priority order

1. Implement typed metadata dictionaries/directive objects, booking-generated annotations, exact directive fingerprints and assertion discrepancies; then enable the rejected columns and applicable SELECT * forms. Add tagged/linked note storage. The adapters are not complete tables until these columns work.
2. Implement the remaining function signatures, full scalar type inference/conversions, non-scalar min/max and inventory sum expressions. Preserve Python's integer/decimal distinction and signed/representational details. Current numeric value representation and static argument validation do not constitute a complete type system. Function result column labels also retain the legacy underscore convention instead of the oracle expression labels; direct source-column labels are checked separately.
3. Implement FROM directive filters/OPEN/CLOSE/CLEAR combinations, subqueries, PIVOT BY, FLATTEN, position DISTINCT, PRINT/EXPLAIN, aliases, quoted identifiers and positional references. The source adapters do not solve this grammar work. Exhaustive grammar/operator enumeration also remains unfinished.
4. Implement document host callbacks/discovery, rounding-account postings, comma/operating-currency presentation, remaining option converters and all directive diagnostic categories. No option or host-callback implementation was added in this batch.
5. Add differential queries for every remaining item and error class, rather than treating the existing finite suite as full-language conformance.

These are pending implementation tasks, not claims that the features are impossible. This first batch does not satisfy the full endpoint or clear the review rejection by itself.
