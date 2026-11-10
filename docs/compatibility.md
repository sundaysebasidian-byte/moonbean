# Compatibility contract (0.2.3)

## Endpoint and evidence

The compatibility endpoint is **beancount 3.2.3 syntax and accounting semantics plus the complete beanquery 0.2.0 language**. This is a target, not a claim that the endpoint has been reached. MoonBean 0.2.3 does **not** implement the full endpoint. The explicit gaps below remain release limitations.

Oracle metadata was obtained through public runtime descriptors, independently authored parser inputs, and CLI `.tables`, `.describe`, `.help targets` and statement probes. No upstream source or fixtures were inspected or copied. Reproduce with the pinned oracle Python: `python scripts/compatibility_inventory.py`. [Machine-readable inventory](evidence/compatibility-inventory.json) retains signatures, defaults, repeated-assignment probes, columns and command results. A descriptor or successful parse is not semantic conformance evidence.

Evidence: `scripts/conformance.py` (ledger fixtures), `scripts/bql_differential.py` (current results linked below), `query/query_test.mbt`, `syntax/parser_test.mbt`, and [current acceptance](evidence/r2-final-acceptance.md). QueryError now distinguishes Syntax, Compilation, Evaluation and Unsupported. Shared invalid-input cases compare normalized oracle error categories. Unsupported statements/functions return errors; recognized options retained as raw data may have no effect, as listed below.

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
| `balance` (meta, date, account, amount, tolerance, diff_amount) | Assertions supported (004, 005, 048); tolerance combinations remain bounded by fixtures. |
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

## BQL tables and every oracle column

All ten advertised sources are now registered, with the per-column limits below. Use `#accounts`: bare `accounts` is a transaction filter in the oracle and is explicitly rejected until FROM filters are implemented. Bare `balances` is a MoonBean inventory extension. It is **not** oracle `#balances` (assertion rows). Table names are case-sensitive after `#`; unsupported sources are rejected. All advertised columns, including typed metadata/directives, fingerprints and assertion discrepancies, are enabled. Evidence is bounded by the authored corpus, not every possible input. The signed-zero representation boundary below limits admissible exact projections.

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
| `convert(amount, str)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `convert(amount, str, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `convert(position, str)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `convert(position, str, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `convert(inventory, str)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `convert(inventory, str, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
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
| `date_bin(str, date, date)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `date_bin(relativedelta, date, date)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `date_diff(date, date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `date_part(str, date)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `date_trunc(str, date)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `day(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `decimal(bool)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. String/object nonfinite and signed-zero conversions are explicitly rejected by the finite Decimal model; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. String/object nonfinite and signed-zero conversions are explicitly rejected by the finite Decimal model; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. String/object nonfinite and signed-zero conversions are explicitly rejected by the finite Decimal model; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(object)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. String/object nonfinite and signed-zero conversions are explicitly rejected by the finite Decimal model; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `decimal(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. String/object nonfinite and signed-zero conversions are explicitly rejected by the finite Decimal model; exponent/rounding resource bounds are explicit (conversion exponent +/-1,000,000; round digits -999,999 through +1,000,000). No guessed value is returned. |
| `empty(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `entry_meta(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `filter_currency(inventory, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `filter_currency(position, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `findfirst(str, set)` | Unsupported. Python regex matching/capture/replacement semantics are not implemented by this function layer; the core Regex subset is not a drop-in equivalent. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `getitem(dict, str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `getitem(dict, str, any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `getprice(str, str)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `getprice(str, str, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `grep(str, str)` | Unsupported. Python regex matching/capture/replacement semantics are not implemented by this function layer; the core Regex subset is not a drop-in equivalent. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `grepn(str, str, int)` | Unsupported. Python regex matching/capture/replacement semantics are not implemented by this function layer; the core Regex subset is not a drop-in equivalent. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `has_account(str)` | Unsupported. Python regex matching/capture/replacement semantics are not implemented by this function layer; the core Regex subset is not a drop-in equivalent. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `int(bool)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(object)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `int(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `interval(str)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `joinstr(set)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `leaf(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `length(list)` | Evaluator and type signature implemented; no positive list-typed expression is available in the currently supported oracle sources. Not counted as positive oracle evidence; getitem() returns object, not list. |
| `length(set)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `length(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `lower(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `maxwidth(str, int)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
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
| `parse_date(str)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `parse_date(str, str)` | Unsupported. No relativedelta/strptime/date-field query implementation; calendar truncation, bins and format errors need their own typed rules. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `possign(amount, str)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `possign(decimal, str)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `possign(inventory, str)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `possign(position, str)` | Unsupported. Not implemented in this batch; string/set ordering or sign/display rules require dedicated oracle cases before enabling this signature. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `quarter(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `repr(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Multi-member set representations (including nested sets) are explicitly rejected: CPython iteration depends on its hash seed; use typed JSON members or oracle for exact repr text. |
| `root(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `root(str, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `round(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure; signed-zero results and exponent resource limits are explicit rejections. |
| `round(decimal, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Negative digits can succeed (round(125.0,-1)); any signed-zero-producing row rejects the whole query, including ordinary ledgers. Negative digits are not universally rejected. Precision overflow is an Evaluation failure; signed-zero results and exponent resource limits are explicit rejections. |
| `round(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure; signed-zero results and exponent resource limits are explicit rejections. |
| `round(int, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Precision overflow is an Evaluation failure; signed-zero results and exponent resource limits are explicit rejections. |
| `safediv(decimal, decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `safediv(decimal, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `splitcomp(str, str, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `str(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Multi-member set representations (including nested sets) are explicitly rejected: CPython iteration depends on its hash seed; use typed JSON members or oracle for exact repr text. |
| `subst(str, str, str)` | Unsupported. Python regex matching/capture/replacement semantics are not implemented by this function layer; the core Regex subset is not a drop-in equivalent. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `substr(str, int, int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `today()` | Unsupported. Pure query context has no host clock/date callback. Reading a platform clock would give target/timezone-dependent results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `units(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `units(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `upper(str)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `value(inventory)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `value(inventory, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `value(position)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `value(position, date)` | Unsupported. Query price lookup/conversion is not implemented. The report PriceDb uses multi-edge conversion and is not an equivalent oracle query implementation; reusing it would change results. Impact: this query fails explicitly. Alternative: pinned beanquery 0.2.0; typed result post-processing is host-owned. |
| `weekday(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `year(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `yearmonth(date)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `count(*)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `count(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `first(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `last(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. |
| `max(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Set subset ordering and oracle Amount/Position ordering covered; min/max(Position) with differing cost date/label and other unimplemented record orderings are rejected explicitly. Not full any-object ordering. |
| `min(any)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Set subset ordering and oracle Amount/Position ordering covered; min/max(Position) with differing cost date/label and other unimplemented record orderings are rejected explicitly. Not full any-object ordering. |
| `sum(amount)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(inventory)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(decimal)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(int)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |
| `sum(position)` | Implemented typed signature; bql_function_differential.py compares values/repr and shared error categories. Oracle amount/position/inventory forms return inventory; legacy sum(units/weight/cost/value) columns retain documented local amount semantics. |

## Statements, clauses and operators

| Feature | Status / evidence or limitation |
| --- | --- |
| SELECT projections, SELECT * | Oracle source stars, including object/discrepancy columns, have typed differential cases. Mixed star projections, aliases and positional references remain unsupported. |
| DISTINCT | Scalar/set/amount/position DISTINCT supported before LIMIT. Position/amount keys preserve exact oracle representation (1.00 and 1.0 remain distinct); hash lookup replaces quadratic duplicate scans. Inventory/sum/object DISTINCT remains explicitly rejected. |
| FROM postings / transactions | Supported, including adjacent lowercase # names; BQL source differential. |
| WHERE, GROUP BY, HAVING, ORDER BY, LIMIT | Supported for accepted expressions; conformance and BQL differential. Aliases and positional references not implemented. Sorting caches expression keys, reuses projected column keys, preserves ties and NULL direction, and follows Unicode scalar ordering; bql_sort_differential.py covers seeded rows and a 100k-posting native corpus. |
| FROM OPEN ON / CLOSE ON | Supported standalone period sources (period differential); accounts projections/filters on OPEN summaries are explicitly rejected; arbitrary directive filters and combined named-table transforms unsupported. |
| FROM CLEAR, CLOSE without ON | Unsupported; use oracle. |
| FLATTEN keyword | Tested forms are syntax errors in beanquery 0.2.0 too (94 grammar probes); absent from its SELECT help. No flatten implementation is claimed. Host can expand typed inventory results. |
| PIVOT BY | Unsupported; host pivot or oracle. |
| FROM (SELECT …) / subqueries | Unsupported; use oracle or explicitly stage results in host. |
| BALANCES | Inventory report supported; oracle formatting and all clause combinations not promised. |
| JOURNAL | Account report supported; full oracle statement syntax not implemented. |
| PRINT / shell .explain / shell .run | Oracle-supported commands remain unimplemented. QueryResult has no ledger-printer/plan result kind; export is a host alternative, not equivalent output. `EXPLAIN SELECT` is a syntax error in the oracle; `.explain SELECT` is the supported shell command. |
| + - * /, comparisons = == != <> < <= > >=, AND OR NOT, IS [NOT] NULL, ~ regex | Supported for accepted expression types; arithmetic/NULL/regex differential. IS [NOT] NULL and ~ are supported as WHERE predicates; SELECT projections are rejected. Python-specific regex syntax not promised. |
| IN / NOT IN, BETWEEN, Boolean/comparison projections, %, aliases, positional references | Oracle accepts the probed forms; MoonBean does not implement them. [94 independent grammar/operator probes](evidence/r2-final-grammar.json), generated by scripts/bql_grammar_probe.py, record accepted/rejected forms. This is still not a proof of exhaustive grammar coverage. |
| LIKE / JOIN | Rejected by both pinned oracle and MoonBean; outside compatibility endpoint. |
| Unicode upper/lower | Supported using pinned CPython Unicode 16.0.0 data, including expansions and final sigma; typed bad arguments produce compilation errors. |

## Extensions and remaining verification gaps

`AVERAGE`, `{*}` cost merging and bare inventory `FROM balances` are extensions, not oracle coverage. Extra amount/units/cost/value columns and report conversion also have local semantics. Local diagnostic severity, messages and some source provenance differ; conformance compares normalized error categories, not exact messages. No claim of complete error-category equivalence for document/note/event/query/custom.

Inventory capture covers public built-in help and all 10 advertised tables; it is not a proof that undocumented function overloads/operators/shell commands do not exist. Full statement grammar and semantic combinations remain unverified. The endpoint is therefore not reached even beyond the explicit implementation gaps. Double-quoted words matching known column names are explicitly rejected: the parser does not yet preserve the oracle quoted-identifier resolution; use an unquoted column or a single-quoted literal.

Performance evidence retains the prior wasm-gc 1M FIFO default-heap baseline gap. ORDER BY now caches keys and sorts stably in O(n log n); native 100k-posting ordering has a separate oracle differential, while the unchanged baseline driver retains its historical large-order skips. See [performance.md](performance.md). No push, tag, deployment or publication is implied by this local candidate.

## Incremental implementation and unresolved scope

[Round 1 evidence](evidence/r2-return-acceptance.md) is historical. Round 2 adds typed dict/list/directive/enum/integer values, all advertised columns, booking annotations, assertion snapshots, exact field fingerprints on covered inputs, and note tags/links. [Round 2 acceptance](evidence/r2-final-acceptance.md) records actual reruns. Public runtime data and independently authored tests were used; no upstream implementation source or fixtures were read/copied.

The compiler now resolves source column types before function signatures, distinguishing int/decimal and set/frozenset. All 105 advertised scalar signatures and 11 aggregate signatures are registered for argument checking; registering a signature does not implement it. The table above marks each evaluator boundary. Integer arithmetic and integer sums use arbitrary-precision BigInt, with seeded 29–60-digit oracle cases. Numeric neg/abs use the oracle 28-digit context, including seeded large-decimal comparisons. Comparison operators, dynamic object conversions and arbitrary record ordering are not a complete Python type system. Function projection labels retain the existing MoonBean API spelling (for example sum_units), rather than oracle expression spelling.

Typed JSON carries nested decimal/date/record tags so objects are not flattened into strings. Set members are compared without an iteration-order contract. Python decimal scientific formatting is supported for finite values. The accounting Decimal core still loses the sign of a parsed negative zero: the parser marks negative-zero-bearing sources and DISTINCT and exact metadata/fingerprint/str/repr queries reject them explicitly. Legacy numeric/report outputs still lack signed-zero fidelity. This pre-existing core limitation was not solved by adding object variants; use the oracle when sign-preserving representation matters. Library hosts constructing AST values directly must preserve this representation flag. Signed-zero-producing query arithmetic/round/safediv also reject explicitly. For malformed ledgers (for example invalid list metadata), the oracle may return an empty set while MoonBean retains recoverable rows. Use bean-check before querying; this is an explicit result-set difference. Object queries over every malformed/unbooked error-ledger shape were not audited; selected assertion-error cases are the available evidence. Query decimal(str/object) detects signed zero and rejects it instead of fabricating a positive value. No complete table/value-domain equivalence is claimed.

The following work was **not completed in this round**; these are implementation gaps, not claims that the features are impossible:

| Remaining work | Concrete cause, impact and alternative |
| --- | --- |
| Scalar signatures still marked unsupported | Query-local price semantics, Python regex/strptime/relativedelta, clock injection and remaining string/set/sign rules lack implementations. Valid calls fail; execute them with pinned beanquery. |
| Full any-object aggregates and type/operator rules | Recursive values now exist, but arbitrary record comparison/hash coercion and Boolean operator/comparison projection plans do not; bool() function projections are supported except Inventory, which raises Evaluation. Declared non-hashable group types are Compilation failures; the oracle generic frozenset/accounts group failure is mirrored as Evaluation. Position grouping uses numeric equality, while DISTINCT uses exact representation. Arbitrary structural ordering/equality remains unsupported; legacy inventory comparison behavior is retained. Unsupported combinations fail; use scalar projections/typed host processing or oracle. |
| Subqueries, PIVOT, aliases, positional references | AST is one SelectQuery over ledger BqlRows; it has no relation schema/relation-node plan or pivot output schema. Adding values alone cannot execute these correctly. Stage typed results in a host or use oracle. |
| FROM directive filters, OPEN/CLOSE/CLEAR and accounts combinations | Period source construction retains balance summaries but not full synthetic transaction identities/account sets or final clearing/conversion entries. Combinations are rejected; use supported standalone periods or oracle. |
| PRINT, shell .explain/.run | No statement result kind for ledger printing, explain plans or stored-query dispatch. Export/run_query are host alternatives with different output contracts. |
| account_rounding | No residual-to-rounding-account pass on booked transactions; enabling only a label would change balances without correct tolerance/residual rules. Option remains stored without posting semantics; use oracle. |
| documents callback/discovery | Current pure loader has include resolution but no document stat/enumeration callback. Missing/existing receipt diagnostics and documents-folder generated entries are not equivalent. Native/host callers must stat/discover explicitly or use oracle; warning states files were not checked. |
| render_commas / operating_currency / display context | QueryResult lacks oracle display-context and multi-currency renderer. These options do not reproduce oracle JOURNAL/BALANCES/PRINT layouts. Host formatting is an alternative, not equivalent text. |
| Every directive/option diagnostic | Normalized authored cases pass; read-only options, converters, renamed root taxonomy, exact messages and every document/note/event/query/custom error combination are unproven. Use bean-check for final oracle validation. |

LIKE/JOIN and the probed FLATTEN/EXPLAIN keyword forms are rejected by the endpoint too. The remaining oracle-supported gaps above prevent a full-compatibility claim. The wasm-gc heap baseline gap and historical large-order timing skips remain documented in [performance.md](performance.md); the new large-order functional evidence is native-only.

## R9 defect repair and type audit

Mixed aggregate/nonaggregate SELECT projections now infer grouping from nonaggregate projections, preserving first-key encounter order and NULL keys, including supported OPEN/CLOSE ON sources. Pure aggregates retain one row on nonempty input and no rows on empty input. HAVING requires explicit GROUP BY; WHERE aggregates and mixed aggregate/nonaggregate expressions raise Compilation. Aggregates in ORDER BY alone do not group the SELECT. R9 tests compare these cases with the oracle.

The reproducible per-argument type matrix (`scripts/bql_type_matrix.py`) probes every advertised scalar signature with scalar, NULL, metadata, record, set, inventory, position, amount and interval expressions. It varies one argument at a time, not the Cartesian product. The list expression is a missing-metadata proxy (NULL), not a real list; unreachable list/relativedelta domains are not proven. No oracle-error/MoonBean-success cases remained in this matrix. Matching failures and deliberate capability rejections are distinct from conformance successes; full classifications are retained in the R9 evidence. Additional restrictive differences remain: date/decimal/int(NULL), getitem(Inventory,...) succeed in the oracle but fail compilation here; unimplemented-function validation can yield Unsupported instead of the oracle Compilation/Evaluation category. These are explicit remaining type/error gaps.

Published evidence is normalized after comparison by `scripts/normalize_evidence.py`: source paths use <repo> or <external> tokens. Original inputs/raw outputs stay in the ignored run directory; fingerprints remain those of the original compared input, not recomputed fingerprints of normalized filename strings.

R9 correctness acceptance and the outstanding loaded-host performance gate are recorded in [r9-acceptance.md](evidence/r9-acceptance.md). The final performance comparison failed four JS 1M FIFO stage limits after the fixed three-repeat policy; no performance PASS is claimed.
