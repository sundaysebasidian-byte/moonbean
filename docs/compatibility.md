# Compatibility contract (0.2.6)

## Endpoint and evidence

The compatibility endpoint is **beancount 3.2.3 syntax and accounting semantics plus the complete beanquery 0.2.0 language**. This is a target, not a claim that the endpoint has been reached. MoonBean 0.2.6 does **not** implement the full endpoint. The explicit gaps below remain release limitations.

Oracle metadata was obtained through public runtime descriptors, independently authored parser inputs, and CLI `.tables`, `.describe`, `.help targets` and statement probes. No upstream source or fixtures were inspected or copied. Reproduce with the pinned oracle Python: `python scripts/compatibility_inventory.py`. [Machine-readable inventory](evidence/compatibility-inventory.json) retains signatures, defaults, repeated-assignment probes, columns and command results. A descriptor or successful parse is not semantic conformance evidence.

Evidence: `scripts/conformance.py` (ledger fixtures), `scripts/bql_differential.py` (current results linked below), `query/query_test.mbt`, `syntax/parser_test.mbt`, and [current acceptance](evidence/r12-acceptance.md). QueryError now distinguishes Syntax, Compilation, Evaluation and Unsupported. Shared invalid-input cases compare normalized oracle error categories. Unsupported statements/functions return errors; recognized options retained as raw data may have no effect, as listed below.

## Options

Defaults and types are oracle values. Repeat means collection accumulation; scalar repetition replaces the value. The JSON includes actual repeated-example parser errors/results, including internal output options that the oracle accepts through `option` but applications should not normally set. Each unsupported item below can affect results; use the pinned oracle when that behavior is needed.

| Name | Oracle type | Default | Repeat | MoonBean boundary |
| --- | --- | --- | --- | --- |
| `include` | list | `[]` | yes | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `input_hash` | str | `` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `dcontext` | DisplayContext | `__default__     : sign=1   integer_max=1   fractional_common=_   fractional_max=_   "-0.*" "-0.*" ` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `commodities` | set | `set()` | yes | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `title` | str | `Beancount` | no | Supported storage; presentation title is host-owned (parser tests). |
| `name_assets` | str | `Assets` | no | Used by account_sortkey; renamed root account syntax/lifecycle taxonomy remains unsupported. Use oracle for those semantics. |
| `name_liabilities` | str | `Liabilities` | no | Used by account_sortkey; renamed root account syntax/lifecycle taxonomy remains unsupported. Use oracle for those semantics. |
| `name_equity` | str | `Equity` | no | Used for summary/report equity account labels; full renamed account taxonomy unsupported (realization option regression). |
| `name_income` | str | `Income` | no | Used by account_sortkey; renamed root account syntax/lifecycle taxonomy remains unsupported. Use oracle for those semantics. |
| `name_expenses` | str | `Expenses` | no | Used by account_sortkey; renamed root account syntax/lifecycle taxonomy remains unsupported. Use oracle for those semantics. |
| `account_previous_balances` | str | `Opening-Balances` | no | Used by FROM OPEN summary and report prior-earnings labels (period differential / realization option tests); other oracle contexts unverified. |
| `account_previous_earnings` | str | `Earnings:Previous` | no | Used by FROM OPEN summary and report prior-earnings labels (period differential / realization option tests); other oracle contexts unverified. |
| `account_previous_conversions` | str | `Conversions:Previous` | no | Used by OPEN prior-period conversion labels. Default-label R12 transformations are verified; arbitrary option combinations remain unverified. |
| `account_current_earnings` | str | `Earnings:Current` | no | Implemented report current-earnings label (realization option regression); other oracle contexts unverified. |
| `account_current_conversions` | str | `Conversions:Current` | no | Implemented report conversion/residual label (realization report tests); other oracle contexts unverified. |
| `account_unrealized_gains` | str | `Earnings:Unrealized` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `account_rounding` | NoneType | `None` | no | Unsupported rounding-account postings; parsed/stored only. Balances/entries may differ; use oracle. |
| `conversion_currency` | str | `NOTHING` | no | Unsupported semantics; retained as raw option only. Use oracle for dependent loading, validation or reporting. |
| `display_precision` | dict | `{}` | yes | Implemented for MoonBean report text and report metadata (realization precision test); full oracle precision/rendering policy not proven. |
| `inferred_tolerance_default` | dict | `{}` | yes | Supported per-currency and wildcard fallback defaults (044, 115–116); inferred currency tolerance overrides wildcard. Other combinations not exhaustively verified. |
| `tolerance_multiplier` | Decimal | `0.5` | no | Supported decimal inference (044, 054); not an exhaustive tolerance proof. |
| `inferred_tolerance_multiplier` | Decimal | `0.5` | no | Supported deprecated alias, emits warning (044). |
| `infer_tolerance_from_cost` | bool | `False` | no | Supported quantity-precision times cost/price inference, with per-posting 0.5 cap and accumulated currency tolerances (119, object metadata differential); TRUE/True/true/1 enabled. |
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
| `commodity` (meta, date, currency) | Syntax/metadata retained (003); typed commodity table supported (every-column differential). |
| `pad` (meta, date, account, source_account) | Padding and cost-inventory rejection supported (006, 007, 100–103). |
| `balance` (meta, date, account, amount, tolerance, diff_amount) | Assertions supported (004, 005, 048); same-day duplicate identity includes currency. The independent review fixture verifies distinct USD/EUR assertions; tolerance combinations remain bounded by fixtures. |
| `transaction` (meta, date, flag, payee, narration, tags, links, postings) | Booking, metadata and postings supported by conformance fixtures; complete short-position lifecycle not claimed. |
| `note` (meta, date, account, comment, tags, links) | Account validation and text parsing supported (008, 087); tags/links and stacks retained and queried (118); every oracle error category is not exhaustively verified. |
| `event` (meta, date, type, description) | Date/type/description parsing and retention supported (008); typed events source supported (every-column differential). |
| `query` (meta, date, name, query_string) | Date/name/query text retained (008). Check does not execute stored queries, as with bean-check; oracle `.run name` execution unsupported. Call `run_query` explicitly for supported query texts. |
| `price` (meta, date, currency, amount) | Raw prices and duplicate preservation supported (003, 057, 063–070). |
| `document` (meta, date, account, filename, tags, links) | Account validation and metadata parsing supported (008, 088); file stat and documents-folder discovery unsupported: the pure library has no document resolver callback. A warning explicitly states the file was not checked; host must check it. |
| `custom` (meta, date, type, values) | Typed values/account references supported (056, 092); no custom plugin semantics. All oracle error categories not exhaustively verified. |
| `include` | Supported via native filesystem / host resolver (041 and include smoke); host filesystem policy applies. |
| `plugin` | Five built-ins supported; other Python plugins only warn and do not execute. See conformance.md. |
| `pushtag` / `poptag`, `pushmeta` / `popmeta` | Supported stacks (016–017). |

Account parsing preserves the reviewed non-ASCII names, supplementary-plane letters and digit-prefixed child components. Semantic character masks come from the pinned public account.is_valid predicate; its accepted domain differs from the runtime's Unicode 16 categories. A separate 3,336,192-call audit checks every Unicode scalar at root-first, child-first and body positions with zero table differences. Lexer rejection versus validation-error retention has authored fixtures, not an exhaustive malformed-loader proof.

## BQL tables and every oracle column

All ten advertised sources are now registered, with the per-column limits below. Use `#accounts` for account directives. Bare `accounts` is an oracle posting-source truth filter and now executes through the FROM plan. Bare `balances` is a MoonBean inventory extension. It is **not** oracle `#balances` (assertion rows). Table names are case-sensitive after `#`; unknown names raise Compilation, as do unknown/shadowed column references. All advertised columns, including typed metadata/directives, fingerprints and assertion discrepancies, are enabled. Evidence is bounded by the authored corpus, not every possible input. The signed-zero representation boundary below limits admissible exact projections.

| Table | Column | Oracle type | Status / evidence or alternative |
| --- | --- | --- | --- |
| `accounts` | `account` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `accounts` | `open` | `open` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `accounts` | `close` | `close` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `account` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `amount` | `amount` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `tolerance` | `decimal` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `balances` | `discrepancy` | `amount` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. Snapshot at the failed assertion, including tolerated/padded NULL cases. |
| `commodities` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `commodities` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `commodities` | `name` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `documents` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `documents` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `documents` | `account` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `documents` | `filename` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. Native paths are canonical; library hosts supply source names. Document paths are resolved lexically, without stat. |
| `documents` | `tags` | `frozenset` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `documents` | `links` | `frozenset` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `id` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. MD5 field encoding derived through public hash_entry outputs; source metadata and booking annotations included. Signed-zero limitation below remains. |
| `entries` | `type` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `filename` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. Native paths are canonical; library hosts supply source names. Document paths are resolved lexically, without stat. |
| `entries` | `lineno` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `year` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `month` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `day` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `flag` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `payee` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `narration` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `description` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `tags` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `links` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `meta` | `dict` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `entries` | `accounts` | `set[str]` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `events` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `events` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `events` | `type` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `events` | `description` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `account` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `comment` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `tags` | `frozenset` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `notes` | `links` | `frozenset` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `type` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `id` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. MD5 field encoding derived through public hash_entry outputs; source metadata and booking annotations included. Signed-zero limitation below remains. |
| `postings` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `year` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `month` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `day` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `filename` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. Native paths are canonical; library hosts supply source names. Document paths are resolved lexically, without stat. |
| `postings` | `lineno` | `int` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `location` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `flag` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `payee` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `narration` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `description` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `tags` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `links` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `posting_flag` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `account` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `other_accounts` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `number` | `decimal` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `currency` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `cost_number` | `decimal` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `cost_currency` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `cost_date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `cost_label` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `position` | `position` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `price` | `amount` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `weight` | `amount` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `balance` | `inventory` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `meta` | `dict` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `entry` | `transaction` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `postings` | `accounts` | `set[str]` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `prices` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `prices` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `prices` | `currency` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `prices` | `amount` | `amount` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `meta` | `metadata` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `date` | `date` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `flag` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `payee` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `narration` | `str` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `tags` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `links` | `set` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |
| `transactions` | `accounts` | `set[str]` | Supported typed value; every-column JSON oracle comparison in bql_object_differential.py; NULL and nested values compared. |


## BQL functions and aggregates

Support is limited to accepted argument expressions/types. Functions on unsupported dict/object columns remain unavailable even if the name is accepted for other types.

| Oracle signature | Status / evidence or alternative |
| --- | --- |
| `abs(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `abs(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `abs(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `account_sortkey(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `any_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `bool(any)` | Scalar truth conversion supported; Inventory raises Evaluation (oracle NotImplementedError), not an emptiness value. Use empty(inventory). R9 differential covers this boundary. |
| `close_date(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `commodity(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `commodity_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `commodity_meta(str, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `convert(amount, str)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `convert(amount, str, date)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `convert(position, str)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `convert(position, str, date)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `convert(inventory, str)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `convert(inventory, str, date)` | Implemented for amount/position/inventory, dated and latest direct/inverse quotes, cost-currency bridging for costed positions, and unchanged units on missing rates. R11 compares typed results and exact repr, including repeated dates and inverse Decimal precision; this is query-local pricing, not report multi-edge conversion. |
| `cost(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `cost(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `currency(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `currency_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `currency_meta(str, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date(object)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date(int, int, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date_add(date, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date_bin(str, date, date)` | Implemented day flooring and calendar year/month stepping, including clipped month ends and the oracle calendar boundary-day behavior. Invalid strings raise Evaluation and zero intervals raise Evaluation. Pure negative intervals return NULL; mixed signed month/day intervals follow their net calendar step in the reviewed corpus. R12 compares both overloads on seeded dates before/at/after origins. |
| `date_bin(relativedelta, date, date)` | Implemented with the same rules as the string overload; interval values retain their type through nested queries and JSON. R12 includes invalid, negative, zero and large interval cases. |
| `date_diff(date, date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date_part(str, date)` | Implemented case-sensitive oracle fields (year/month/quarter/week/dow/isodow/epoch/decade/century/millennium); unknown fields return NULL, including day. R11 includes ISO week boundaries, year 1/9999 and seeded dates. |
| `date_trunc(str, date)` | Implemented year/month/quarter/week/decade/century/millennium; unknown fields return NULL. Year-zero decade truncation raises Evaluation. R11 seeded calendar and boundary probes. |
| `day(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `decimal(bool)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Nonfinite string/object conversions remain explicitly rejected by the finite Decimal model; signed-zero strings use the query-only negative-zero value; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Nonfinite string/object conversions remain explicitly rejected by the finite Decimal model; signed-zero strings use the query-only negative-zero value; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Nonfinite string/object conversions remain explicitly rejected by the finite Decimal model; signed-zero strings use the query-only negative-zero value; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(object)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Nonfinite string/object conversions remain explicitly rejected by the finite Decimal model; signed-zero strings use the query-only negative-zero value; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Nonfinite string/object conversions remain explicitly rejected by the finite Decimal model; signed-zero strings use the query-only negative-zero value; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `empty(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `entry_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `filter_currency(inventory, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `filter_currency(position, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `findfirst(str, set)` | Implemented when zero or one set member matches the tested regex dialect. Multiple matching members depend on CPython hash seed and fail explicitly as Unsupported. These rejection checks are not compatibility successes. |
| `getitem(dict, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `getitem(dict, str, any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `getprice(str, str)` | Implemented dated/latest query-local quotes, identity rates, inverse direction normalization, repeated-date precedence and missing/zero rates. R11 compares exact Decimal repr. No arbitrary graph traversal. |
| `getprice(str, str, date)` | Implemented dated/latest query-local quotes, identity rates, inverse direction normalization, repeated-date precedence and missing/zero rates. R11 compares exact Decimal repr. No arbitrary graph traversal. |
| `grep(str, str)` | Implemented the tested portable regex dialect, case-sensitive search and NULL propagation. Escaped metacharacters, noncapturing groups, scoped case-insensitivity and bounded quantifiers are tested. Python Unicode classes, lookaround, backreferences and additional flags exceed the portable matcher contract and remain explicit boundaries. R11 compares values and shared pattern errors. |
| `grepn(str, str, int)` | Implemented the tested portable regex dialect and numbered captures, unmatched groups/strings and invalid group errors. Python-only patterns remain Unsupported, as for grep. R11 compares typed values and normalized errors. |
| `has_account(str)` | Implemented case-insensitive matching against transaction accounts, including postings/transactions/entries and relation accounts columns. Missing accounts columns raise Compilation. Regex dialect restrictions are the same as grep. |
| `int(bool)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(object)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `interval(str)` | Implemented signed integer year/years, month/months and day/days with whitespace separation. Months normalize into years and months. Invalid units, compound interval strings and fractional counts return NULL. Arithmetic can combine parsed intervals into mixed month/day values; date±interval, interval+date and interval±interval are implemented. interval−date raises Evaluation TypeError in the oracle and MoonBean. The pinned oracle declares interval subtraction as date while returning an interval; the reviewed downstream consumers mirror that quirk. The typed result has relativedelta str/repr/JSON rendering, including the tested large-count scientific notation. |
| `joinstr(set)` | Implemented for empty/singleton sets. Multi-element iteration depends on CPython hash seed and fails explicitly as Unsupported; no deterministic sorted approximation is returned. |
| `leaf(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `length(list)` | Implemented with positive R12 literal-list probes, including the oracle omission of NULL elements after the first list item. getitem() still declares object. |
| `length(set)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `length(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `lower(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `maxwidth(str, int)` | Implemented whitespace collapse, placeholder/width errors, word boundaries and tested single/multiple hyphen chunks. R12 compares widths 4-13 on authored hyphen grids and retains the R11 Unicode/whitespace cases. Exhaustive Python textwrap equivalence is unverified. |
| `meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `month(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `neg(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `neg(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `neg(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `neg(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `number(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `only(str, inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `open_date(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `open_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `open_meta(str, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `parent(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `parse_date(str)` | Implemented tested dateutil-style numeric and English month/weekday forms, compact dates, partial dates defaulting from the local current date, the rolling two-digit-year window, and validated time/timezone suffixes discarded on conversion to date. Invalid dates raise Evaluation. Exhaustive dateutil grammar and host locale behavior remain unverified. R12 retains authored positive and invalid examples. |
| `parse_date(str, str)` | Implemented tested numeric/month-name, ordinal-day, ISO/week-number and time/offset strptime directives, English C-locale expansions and percent literals. Defaults, invalid fields, duplicate directives and incomplete ISO-week formats have oracle comparisons. Host-specific locale and timezone-name equivalence remain unverified. |
| `possign(amount, str)` | Implemented decimal/amount/position/inventory account-root sign convention, preserving values for Assets/Expenses and using numeric negation otherwise. R11 covers typed values and repr across all five roots, unknown roots and case differences. |
| `possign(decimal, str)` | Implemented decimal/amount/position/inventory account-root sign convention, preserving values for Assets/Expenses and using numeric negation otherwise. R11 covers typed values and repr across all five roots, unknown roots and case differences. |
| `possign(inventory, str)` | Implemented decimal/amount/position/inventory account-root sign convention, preserving values for Assets/Expenses and using numeric negation otherwise. R11 covers typed values and repr across all five roots, unknown roots and case differences. |
| `possign(position, str)` | Implemented decimal/amount/position/inventory account-root sign convention, preserving values for Assets/Expenses and using numeric negation otherwise. R11 covers typed values and repr across all five roots, unknown roots and case differences. |
| `quarter(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `repr(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Multi-member set representations (including nested sets) are explicitly rejected: CPython iteration depends on its hash seed; use typed JSON members or oracle for exact repr text. |
| `root(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `root(str, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `round(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure. Round-produced signed zero preserves its sign and tested numeric consumers. Rounding resource bounds remain explicit. |
| `round(decimal, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Negative digits, including negative-zero-producing results, have R12 differential coverage. Precision overflow is an Evaluation failure. Round-produced signed zero preserves its sign and tested numeric consumers. Rounding resource bounds remain explicit. |
| `round(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure. Round-produced signed zero preserves its sign and tested numeric consumers. Rounding resource bounds remain explicit. |
| `round(int, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure. Round-produced signed zero preserves its sign and tested numeric consumers. Rounding resource bounds remain explicit. |
| `safediv(decimal, decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `safediv(decimal, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `splitcomp(str, str, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `str(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Multi-member set representations (including nested sets) are explicitly rejected: CPython iteration depends on its hash seed; use typed JSON members or oracle for exact repr text. |
| `subst(str, str, str)` | Implemented literal replacement in the tested portable regex dialect, including empty patterns and greedy empty matches. Numbered capture references, numeric group syntax, octal escapes and replacement control escapes are implemented. Python-only pattern constructs and lazy patterns with interior empty matches remain conservative explicit rejections. Nonempty lazy matches and end-only empty matches execute. The portable matcher exposes forward-progress replacement without that retry contract. |
| `substr(str, int, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `today()` | Native uses libc localtime and JS uses Date local calendar fields. WebAssembly supports a per-read host calendar callback through the optional host_clock import adapter, including timezone/DST and partial-date defaults. The default WebAssembly calendar and unavailable-provider fallback are UTC. See the host calendar integration below. |
| `units(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `units(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `upper(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `value(inventory)` | Implemented for position/inventory: cost currency is the valuation currency; uncosted or unpriced units remain unchanged. R11 compares typed values and exact repr with latest/dated quotes and missing prices. |
| `value(inventory, date)` | Implemented for position/inventory: cost currency is the valuation currency; uncosted or unpriced units remain unchanged. R11 compares typed values and exact repr with latest/dated quotes and missing prices. |
| `value(position)` | Implemented for position/inventory: cost currency is the valuation currency; uncosted or unpriced units remain unchanged. R11 compares typed values and exact repr with latest/dated quotes and missing prices. |
| `value(position, date)` | Implemented for position/inventory: cost currency is the valuation currency; uncosted or unpriced units remain unchanged. R11 compares typed values and exact repr with latest/dated quotes and missing prices. |
| `weekday(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `year(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `yearmonth(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `count(*)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `count(any)` | Implemented typed signature; NULL-aware counts have differential evidence. count(DISTINCT x) is rejected as Syntax in both engines (S5); it is not an aggregate overload. |
| `first(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `last(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `max(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Set subset ordering and oracle Amount/Position ordering covered; max(Position) compares cost dates and labels, including shared None/type errors. Generic structural ordering is bounded by the authored aggregate corpus and raises Evaluation for unsupported Python orderings. Not full any-object ordering. |
| `min(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Set subset ordering and oracle Amount/Position ordering covered; max(Position) compares cost dates and labels, including shared None/type errors. Generic structural ordering is bounded by the authored aggregate corpus and raises Evaluation for unsupported Python orderings. Not full any-object ordering. |
| `sum(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |

## Statements, clauses and operators

| Feature | Status / evidence or limitation |
| --- | --- |
| SELECT projections, SELECT * | Oracle source stars, including object/discrepancy columns, have typed differential cases. AS aliases (including quoted alias declarations) and one-based GROUP BY/ORDER BY references are supported. Double-quoted words resolve case-sensitively against their source schema, falling back to strings. Mixed star lists raise Syntax, matching the oracle. |
| DISTINCT | Scalar/set/amount/position DISTINCT and scalar sums over computed grouping keys are supported before LIMIT. Position/amount keys retain exact representation. Inventory and structural values, including aggregate inventories, use retained value keys and have R12 regressions. Exhaustive nested-value equivalence is unverified. |
| FROM postings / transactions | Supported, including adjacent lowercase # names; BQL source differential. |
| WHERE, GROUP BY, HAVING, ORDER BY, LIMIT | Bounded clause support: WHERE aggregates fail Compilation; HAVING needs explicit GROUP BY and an aggregate expression. Aggregate SELECT/ORDER BY nonaggregate targets must exactly match group expressions; derived expressions are not automatically covered. Mixed aggregate/row HAVING and ORDER BY expressions bind ordinary references to the final source row, including rows removed by filters, matching the probed oracle behavior. LIMIT accepts nonnegative integers; LIMIT -1 is Syntax in the public API (S7), despite historical CLI-only Evaluation labels. OFFSET remains unsupported. Bare aliases and one-based positions resolve to SELECT targets in GROUP BY/ORDER BY only; aliases inside expressions or WHERE/HAVING are source-column lookups, as in the oracle. R10 Cartesian probes compare clause interactions. Sorting caches expression keys, reuses projected column keys, preserves ties and NULL direction, and follows Unicode scalar ordering; bql_sort_differential.py covers seeded rows and a 100k-posting native corpus. |
| FROM predicates / OPEN ON / CLOSE ON | Shared directive transformations precede posting filters. Combined OPEN/CLOSE/CLEAR, synthetic account sets/metadata/fingerprints and original-ledger price lookup have R12 coverage. Named #table transforms are rejected by the oracle. |
| FROM CLEAR, CLOSE without ON | Implemented earnings transfers and residual conversions. Cost-bearing earnings transfer their cost value into equity. |
| FLATTEN keyword | Tested forms are syntax errors in beanquery 0.2.0 too (94 grammar probes); absent from its SELECT help. No flatten implementation is claimed. Host can expand typed inventory results. |
| PIVOT BY | Supported two-target pivot after SELECT/group/order/distinct/limit. Dynamic headers, multiple measures, NULL fill, sorted keys and last duplicate cell match R11 probes. Ungrouped pivot and incomparable NULL keys raise Evaluation. Pivot used as a subquery raises Evaluation in the oracle too; no nested pivot relation is claimed. |
| FROM (SELECT …) / subqueries | Recursive materialized relations carry names and declared types into projection, filtering, grouping and sorting. Nested SELECT, star, empty relations, aliases and aggregate outer queries have R11 evidence. Source aliases after the closing parenthesis are Syntax in the oracle too. |
| BALANCES | Canonical account/inventory SELECT plan supports AT valuation functions and FROM transforms, preserving zero inventories and account ordering. General oracle table formatting remains outside the typed-result contract. |
| JOURNAL | Canonical SELECT plan supports optional quoted account regex, AT valuation and FROM transforms, with oracle projection names and running balances. Existing unquoted/LIMIT extensions remain available. |
| PRINT | A distinct DirectiveText result carries ledger text and typed directive rows. The native CLI emits the text directly, including oracle blank lines, postings, metadata and raw Decimal precision. The widened R12 review differential runs exactly 84 PRINT statements across 142 ledgers (excluding extension ledgers 035/058), comparing successful output bytes and failure exit/category parity. It covers original same-day order, cost-valued earnings summaries, last-entry CLEAR dates, post-transform filters, code-point tag ordering, Unicode accounts, empty narration and metadata/raw-field quoting. This finite corpus does not establish arbitrary PRINT equivalence. The public root API forwards diagnostics to the optional query diagnostics parameter. PRINT WHERE, named tables and LIMIT are Syntax in the oracle too. |
| Shell .explain / .run | Unimplemented interactive-shell commands. The library/CLI has no interactive shell or plan renderer. `EXPLAIN SELECT` remains a Syntax error in the oracle. |
| + - * /, comparisons = == != <> < <= > >=, AND OR NOT, IS [NOT] NULL, ~ regex | Supported for accepted expression types; arithmetic/NULL/regex differential. Date±int, int+date, date−date, date±interval, interval+date and interval±interval have value/type/error regressions; unsupported signatures retain oracle Compilation errors. Boolean/comparison, IS [NOT] NULL and ~ projections now preserve oracle NULL propagation and short-circuit rules on accepted types; R11 covers implicit grouping and aggregate predicates. Structural/Python object operator rules remain incomplete. Python-specific regex syntax not promised. |
| IN / NOT IN, BETWEEN, % | Implemented literal lists, container membership, typed ranges and Python integer/Decimal remainder, including negative operands, NULLs, zero divisors and precision errors. Boolean/comparison projections, aliases and positional references from the historical S6 gap are implemented in R11. [94 independent grammar/operator probes](evidence/r2-final-grammar.json), generated by scripts/bql_grammar_probe.py, record accepted/rejected forms. This is still not a proof of exhaustive grammar coverage. |
| LIKE / JOIN | Rejected by both pinned oracle and MoonBean; outside compatibility endpoint. |
| Unicode upper/lower | Supported using pinned CPython Unicode 16.0.0 data, including expansions and final sigma; typed bad arguments produce compilation errors. |

## Extensions and remaining verification gaps

`AVERAGE`, `{*}` cost merging and bare inventory `FROM balances` are extensions, not oracle coverage. Extra amount/units/cost/value columns and report conversion also have local semantics. Local diagnostic severity, messages and some source provenance differ; conformance compares normalized error categories, not exact messages. No claim of complete error-category equivalence for document/note/event/query/custom.

Inventory capture covers public built-in help and all 10 advertised tables; it is not a proof that undocumented function overloads/operators/shell commands do not exist. Full statement grammar and semantic combinations remain unverified. The endpoint is therefore not reached even beyond the explicit implementation gaps. Quoted lookup and mixed-star rejection now have oracle regressions. The interactive shell protocol is a separate host exclusion.

The original R12 performance record compares `3a86c51` with main `992eaa2`; it predates the review fixes. The review rework freezes implementation `ed31935` and reruns the same interleaved matrix: all 35 complete pairs pass the original 30% median/RSS gate after three whole-pair low-load repeats. Both wasm-gc 1M FIFO cases remain incomplete due to default-heap exhaustion. Historical large-ORDER BY timing skips also remain unmeasured. Historical R11 gate failures are retained in their original evidence. No push, tag, deployment or publication is implied by this local candidate. [R12 acceptance](evidence/r12-acceptance.md), [current performance records](evidence/r12-review-performance.json).

## Incremental implementation and unresolved scope

[Round 1 evidence](evidence/r2-return-acceptance.md) is historical. Round 2 adds typed dict/list/directive/enum/integer values, all advertised columns, booking annotations, assertion snapshots, exact field fingerprints on covered inputs, and note tags/links. [Round 2 acceptance](evidence/r2-final-acceptance.md) records actual reruns. Public runtime data and independently authored tests were used; no upstream implementation source or fixtures were read/copied.

The compiler now resolves source column types before function signatures, distinguishing int/decimal and set/frozenset. All 105 advertised scalar signatures and 11 aggregate signatures are registered for argument checking; registering a signature does not implement it. The table above marks each evaluator boundary. Integer arithmetic and integer sums use arbitrary-precision BigInt, with seeded 29–60-digit oracle cases. Numeric neg/abs use the oracle 28-digit context, including seeded large-decimal comparisons. Comparison operators, dynamic object conversions and arbitrary record ordering are not a complete Python type system. Function projection labels retain the existing MoonBean API spelling (for example sum_units), rather than oracle expression spelling.

Typed JSON carries nested decimal/date/record tags so objects are not flattened into strings. Set members are compared without an iteration-order contract. Python decimal scientific formatting is supported for finite values. The accounting Decimal core still loses the sign of a parsed negative zero: the parser marks negative-zero-bearing sources and DISTINCT and exact metadata/fingerprint/str/repr queries reject them explicitly. Legacy numeric/report outputs still lack signed-zero fidelity. This pre-existing core limitation was not solved by adding object variants; use the oracle when sign-preserving representation matters. Library hosts constructing AST values directly must preserve this representation flag. Round-produced signed zero now has an isolated query value and retains str/repr/JSON, numeric comparison, grouping, nested rounding and tested arithmetic consumers. Query arithmetic, safediv and decimal string conversions also preserve tested negative-zero results. The accounting Decimal representation is unchanged. For malformed ledgers (for example invalid list metadata), the oracle may return an empty set while MoonBean retains recoverable rows. Use bean-check before querying; this is an explicit result-set difference. Object queries over every malformed/unbooked error-ledger shape were not audited; selected assertion-error cases are the available evidence. The query-only negative-zero variant preserves finite signed-zero conversions without modifying accounting Decimal storage. No complete table/value-domain equivalence is claimed.

The following work was **not completed in this round**; these are implementation gaps, not claims that the features are impossible:

| Remaining work | Concrete cause, impact and alternative |
| --- | --- |
| Scalar evaluator inventory | All 105 advertised scalar signatures have evaluators with the value-domain restrictions in their rows above. The six R11 missing signatures now execute. Full language and value-domain equivalence remains unverified. |
| Full any-object aggregates and type/operator rules | Recursive values now exist, but arbitrary record comparison/hash coercion remains incomplete; bool() function projections are supported except Inventory, which raises Evaluation. Explicit non-hashable GROUP BY types are Compilation failures; explicit generic frozenset/accounts group failure is mirrored as Evaluation. Implicit tags/links grouping on notes/transactions is supported, including empty sets, with membership equality and first-encounter group order. Position grouping uses numeric equality, while DISTINCT uses exact representation. Known unsupported comparison signatures now raise Compilation, including dict/record/inventory/list/amount/position/set comparisons. Dynamic object-to-scalar comparisons and generic aggregate ordering have bounded tests. Legacy inventory comparison behavior remains for extension columns. Unverified combinations require further oracle probes; use scalar projections/typed host processing or oracle. |
| Relation/statement combinations beyond R11 | Recursive relation schemas, AS, positional references and PIVOT are implemented for the probed combinations. Source-aware quoted lookup is implemented. Mixed star lists and PIVOT-as-subquery have oracle rejection parity. Full grammar combinations remain unproven; use the pinned oracle for unverified workflows. |
| FROM transform combinations beyond the R12 corpus | SELECT, JOURNAL, BALANCES and PRINT share OPEN/CLOSE/CLEAR transformations. Synthetic identities/account sets, costs and price context have authored regressions. Every malformed-loader recovery and transform combination remains unverified. |
| Shell .explain/.run | Interactive plan rendering and stored-query dispatch remain unimplemented. Their shell state and output protocol are absent from the current API. PRINT has a separate directive-text result and native CLI path. |
| account_rounding | No residual-to-rounding-account pass on booked transactions; enabling only a label would change balances without correct tolerance/residual rules. Option remains stored without posting semantics; use oracle. |
| documents callback/discovery | Current pure loader has include resolution but no document stat/enumeration callback. Missing/existing receipt diagnostics and documents-folder generated entries are not equivalent. Native/host callers must stat/discover explicitly or use oracle; warning states files were not checked. |
| render_commas / operating_currency / display context | The query table renderer lacks the oracle display-context/multi-currency layout contract. PRINT preserves directive precision; its byte-level evidence is limited to the exact 84-statement/142-ledger review matrix and the earlier nine-statement corpus. General table/JOURNAL/BALANCES layout parity remains unimplemented because the current renderer retains its public text/CSV/JSON contract and lacks the oracle display-context renderer. |
| Every directive/option diagnostic | Normalized authored cases pass; read-only options, converters, renamed root taxonomy, exact messages and every document/note/event/query/custom error combination are unproven. Use bean-check for final oracle validation. |

LIKE/JOIN and the probed FLATTEN/EXPLAIN keyword forms are rejected by the endpoint too. The remaining oracle-supported gaps above prevent a full-compatibility claim. The wasm-gc heap baseline gap and historical large-order timing skips remain documented in [performance.md](performance.md); the new large-order functional evidence is native-only.

## R9 defect repair and type audit

Mixed aggregate/nonaggregate SELECT projections now infer grouping from nonaggregate projections, preserving first-key encounter order and NULL keys, including supported OPEN/CLOSE ON sources. Pure aggregates retain one row on nonempty input and no rows on empty input. HAVING requires explicit GROUP BY and an aggregate expression; WHERE aggregates and mixed aggregate/nonaggregate SELECT expressions raise Compilation. Uncovered ORDER BY targets in aggregate queries also raise Compilation. Aggregates in ORDER BY alone do not group the SELECT. R9 tests compare these cases with the oracle.

The reproducible per-argument type matrix (`scripts/bql_type_matrix.py`) probes every advertised scalar signature with scalar, NULL, metadata, record, set, inventory, position, amount and interval expressions. It varies one argument at a time, not the Cartesian product. The historical matrix uses a missing-metadata proxy for lists. R12 separately adds real list literals and typed intervals. No oracle-error/MoonBean-success cases remained in this matrix. Matching failures and deliberate capability rejections are distinct from conformance successes; full classifications are retained in the R9 evidence. R12 accepts date/decimal/int(NULL), matching the oracle object-conversion overloads. R12 implements getitem(Inventory,...) NULL/default behavior and implicit object-to-scalar comparison casts. Broader dynamic Python coercions remain bounded by authored probes. No blanket type/error equivalence is claimed.

Published evidence is normalized after comparison by `scripts/normalize_evidence.py`: source paths use <repo> or <external> tokens. Original inputs/raw outputs stay in the ignored run directory; fingerprints remain those of the original compared input, not recomputed fingerprints of normalized filename strings.

R9 correctness acceptance and the outstanding loaded-host performance gate are recorded in [r9-acceptance.md](evidence/r9-acceptance.md). The final performance comparison failed four JS 1M FIFO stage limits after the fixed three-repeat policy; no performance PASS is claimed.

## R10 aggregate-clause boundaries

B2/B3: aggregate ORDER BY nonaggregate targets must exactly match a grouping expression; account_sortkey(account) is not covered by GROUP BY account. A pure aggregate cannot ORDER BY an ordinary column. A HAVING predicate without any aggregate raises Compilation, including grouped-column regex tests. R12 implements mixed aggregate/ordinary-row references inside HAVING and ORDER BY. Aggregate arguments use their group, while ordinary references bind to the final source row before filters, matching authored black-box probes.

I3: implicit grouping accepts tags and links frozensets on #notes and #transactions. Equal memberships share a group regardless of spelling order, empty sets group together, and output groups follow first encounter. Explicit GROUP BY tags/links retains the oracle rejection (Compilation for transaction set columns, Evaluation for generic note frozenset types). Set JSON members retain the existing local order convention; comparisons use membership, not Python iteration order.

S5: count(DISTINCT x) remains unsupported by both endpoints; R10 now rejects it as Syntax, matching oracle ParseError instead of the earlier Unsupported diagnostic. S6 is historical and was closed by R11 Boolean/comparison projections and implicit grouping. S7: LIMIT -1 is Syntax in both the public failure() API and the oracle; the old CLI-only classifier labeled the unprefixed integer diagnostic Evaluation. The differential classifier now follows failure()'s prefix contract; unit tests verify S5/S7 API variants. CLI text alone does not encode an error-category field.

The R10 2444-call clause audit includes a Cartesian grid plus targeted set/order/HAVING/OFFSET cases. It has no oracle-error/MoonBean-success cases. R12 closes the six computed-key scalar aggregate DISTINCT rejections; R11 had already closed the two Boolean/comparison projections. R12 also closes the two mixed HAVING calls and mixed ORDER BY call with final-source-row binding. These cases now compare values as conformance checks. Full classification/value checks and limitations are linked from [R10 acceptance](evidence/r10-acceptance.md). The earlier 1822-call zero-permissive statement concerns only the R9 scalar-function matrix, not arbitrary language clauses.

## R11 relation plans and scalar expansion (0.2.5)

R11 supersedes the earlier subquery/PIVOT/alias/positional-reference and S6 projection gaps. Recursive SELECT relations materialize typed rows without retaining ledger-column bindings. Projection aliases are resolved only in the top-level GROUP BY/ORDER BY reference positions. PIVOT reshapes the limited result into a dynamic schema with sorted axes, sparse NULL cells and oracle duplicate-cell precedence. Expression spelling is retained for relation/pivot names; existing public top-level function labels retain their documented MoonBean spelling.

All 31 previously missing scalar signatures now have evaluators, including the partial domains described above. R12 adds the independent R11 and R12 A/B review corpora, seeded interval/date-bin probes, dateutil/strptime and two-digit year cases, date/interval arithmetic, same-day clock comparisons, round precision/representation regressions, and the bounded PRINT matrix. The tracked review scripts retain the reviewers' cases; parser fuzz/resource checks are counted separately from oracle comparisons. Native, JS and wasm-gc reject queries exceeding 256 nested parentheses or 256 recursive operators with Syntax query.depth_limit; this is an explicit resource boundary, not oracle conformance. Unsupported input domains are counted separately from conformance comparisons. Exact diagnostic prose and exhaustive grammar/value-domain equivalence are unverified.

PRINT, signed-zero round, quoted lookup, IN/BETWEEN/modulo, generic source transforms, canonical JOURNAL/BALANCES, structural DISTINCT and mixed aggregate-row clauses are implemented in 0.2.6 with bounded differential coverage. Remaining BQL boundaries include CPython randomized set iteration, Python regex features outside the portable matcher, nonfinite/resource-bounded Decimal domains, source-parsed negative-zero exact representations and exhaustive dateutil/locale parsing. Shell commands and general oracle table formatting remain host exclusions. Genuine non-BQL exclusions include external Python plugins, document discovery/stat callbacks, renamed account taxonomy, account_rounding and the option/report boundaries listed above. See [R12 acceptance](evidence/r12-acceptance.md) for current results and performance evidence.

## WebAssembly host calendar (0.2.7)

`query.set_local_date_provider` installs an instance-local callback from Unix epoch
milliseconds (`Double`) to `YYYYMMDD` (`Int32`). It is consulted for every clock
read, including `today()`, partial `parse_date` defaults and the rolling
two-digit-year window. `None`, zero and invalid calendar dates select the target
default. Native/JS defaults use their local calendars. WebAssembly defaults to UTC.

For a JS-hosted wasm-gc application, import the optional
`sundaysebasidian-byte/moonbean/host_clock` package and call `@host_clock.install()`
before running queries. The linked application then imports
`moonbean:clock.local_date(f64) -> i32`. Supply the shipped JS adapter alongside
the application's existing imports.

```js
import { clockImports } from './host_clock/imports.mjs';
const imports = { ...applicationImports, ...clockImports() };
const { instance } = await WebAssembly.instantiate(bytes, imports, compileOptions);
```

`clockImports()` uses JS `Date` local calendar fields at the supplied timestamp,
including the host's timezone and DST rules. `clockImports(null)` supplies a zero
callback for hosts without a calendar service, selecting UTC. A custom provider
can be passed to `clockImports(provider)`. It must return an integer calendar date
or zero. Invalid returned dates also select UTC. Applications can supply a direct
MoonBit callback through `@query.set_local_date_provider(Some(provider))`, and
reset it with `None`.

Moon 0.1.20261104 core `env.now()` imports
`__moonbit_time_unstable.now` and exposes epoch milliseconds. Its clock API has no
local calendar or timezone service. `extern "wasm"` supplies inline Wasm code, and
named foreign declarations create host imports. WebAssembly resolves imports
before guest execution, so an absent function cannot be detected by guest code.
The optional adapter keeps the default library and `moon test --target wasm-gc`
usable with existing moonrun hosts. An application opting into the import must
supply either the local callback or the zero callback at instantiation. Bare
moonrun continues to use UTC. [MoonBit FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html).

Run the actual imported-module checks with the pinned toolchain.

```sh
moon build --release --target wasm-gc tests/clock_host
node scripts/wasm-clock-test.mjs
```

The fixture checks UTC, Los Angeles and Kiritimati cross-day dates, both Los
Angeles DST transitions, clock advancement after installation, partial dates and
invalid/unavailable/uninstalled-provider fallbacks. Python's public datetime API
from the pinned oracle environment independently checks each local date.
