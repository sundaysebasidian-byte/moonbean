# MoonBean BQL extensions

These are MoonBean additions, not a promise of beanquery 0.2.0 syntax coverage. They work through the same query API and CLI as ordinary BQL.

| Query | Result |
| --- | --- |
| `SELECT nullif(payee, '') FROM transactions` | Returns NULL for equal values; otherwise keeps the first argument. |
| `SELECT avg(number(units)) WHERE account = 'Expenses:Food'` | Exact accumulation followed by one final division, rounded to 28 significant decimal digits. |
| `SELECT count_distinct(account)` | Number of distinct non-NULL scalars. It uses the existing DISTINCT identity, including equal decimal scales and the existing numeric equivalence for booleans. |
| `SELECT median(number(units))` | Numeric middle value, or exact mean of the central pair. |
| `SELECT collect(payee) FROM transactions` | Typed list in source order, including NULLs. |
| `SELECT first_non_null(payee), last_non_null(payee) FROM transactions` | Non-NULL endpoints in source order. Existing FIRST already skips NULL; FIRST_NON_NULL is its explicit-name alias, while LAST_NON_NULL is new behavior. |
| `SELECT DISTINCT account ORDER BY account LIMIT 20 OFFSET 40` | Skip 40 rows after sorting and deduplication, then return up to 20. |
| `SELECT payee FROM transactions ORDER BY payee DESC NULLS FIRST` | Explicit NULL ordering is independent of sort direction. |
| `SELECT split_text('food::tax::', '::') LIMIT 1` | Splits on a literal delimiter, preserving empty fields. Empty delimiter is an error. |
| `SELECT join_text(collect(payee), ', ') FROM transactions` | Joins strings in a typed list; skips NULL members and rejects non-text members. |
| `SELECT trim(payee) FROM transactions` | Removes boundary whitespace; `ltrim` and `rtrim` trim a single edge. |
| `SELECT replace_text(narration, ' - ', ' / ') FROM transactions` | Literal replacement, not regex. Empty search text leaves input unchanged. |
| `SELECT count(*) WHERE starts_with(account, 'Expenses:')` | Literal, case-sensitive prefix test. `ends_with` is the corresponding suffix test. |
| `SELECT date_format(date, '%Y-%m') FROM transactions` | Locale-neutral formats: `%Y %m %d %j %F %%`. Other directives error. |
| `SELECT month_end(date), days_in_month(date) FROM transactions` | Month end and day count with leap-year rules. |
| `SELECT clamp(number(units), 0, 1000)` | Clips to numeric bounds; reversed bounds error. |
| `RUN SAVED 'monthly'` | Runs an exact-case named, unique `query` directive without entering a shell. Nested saved queries are rejected. |

Existing BQL empty filtered inputs still produce no aggregate row. For an existing group whose numeric values are all NULL, `avg` and `median` return NULL. `collect` retains NULLs, and `join_text` omits them. Use `ORDER BY` for deterministic pagination when order matters.

## Query conditions and weighted averages

`a IS DISTINCT FROM b` and `a IS NOT DISTINCT FROM b` always return a Boolean for scalar values. Two NULLs compare alike; NULL and a value are distinct. Numeric equality follows existing BQL scalar identity (for example, `1`, `1.0`, and `TRUE` compare alike). Text is case-sensitive. These forms do not compare structural values such as sets or lists.

A searched `CASE WHEN predicate THEN value ... ELSE value END` selects the first true branch and evaluates only that branch. A NULL condition does not match. If no branch matches and `ELSE` is absent, the result is NULL. Non-null branch types must agree. Use an alias for a short result heading.

```sql
SELECT CASE WHEN payee IS NULL THEN 'Unassigned' ELSE payee END AS payee_label,
       currency,
       weighted_avg(number(units), 1) AS average_amount
GROUP BY payee_label, currency
```

`weighted_avg(value, weight)` skips rows with a NULL in either argument, accepts signed numeric weights, and returns NULL when their total is zero. Products and sums are exact; the final Decimal division rounds to the existing 28-significant-digit context. Group by currency for financial values; the function does not perform currency conversion.

A single semicolon may terminate a complete top-level query. Additional statements and interior semicolons are rejected; a semicolon inside quotes is text. An unterminated query literal is reported at the opening quote, using the existing line and UTF-16 column convention.

## More ways to query and export the ledger

Aggregate expressions accept a local FILTER. For example, SELECT count(*) FILTER (WHERE number > 0) AS credits, count(*) FILTER (WHERE number < 0) AS debits FROM #postings returns both measures without filtering away either side for the other aggregate. An empty per-group filter keeps the group; COUNT is zero and AVG is NULL. HAVING without GROUP BY is available for a global aggregate projection without row-level expressions. Whole-input empty groups retain MoonBean's existing no-row behavior.

bool_or / bool_and ignore NULL and return NULL when no Boolean value is known. arg_min / arg_max choose the first observed row on ties and skip NULL keys; the returned value itself may be NULL. percentile_disc(value, fraction) takes a numeric literal in [0, 1], ignores NULL values and returns an observed value at nearest rank (zero means the first value).

list_at(items,index) uses zero-based numbering and returns NULL outside the list; negative coordinates count from the end. list_slice(items,start,end) is half-open, clamps bounds and retains element types. Either operation propagates explicit NULL arguments.

account_in_subtree(account, root) includes the root itself and colon-separated descendants; it is case-sensitive. fiscal_year(date,start_month) labels by the year in which the period starts, and fiscal_quarter uses the same month in 1–12. The business calendar counts Monday–Friday only and does not account for holidays. business_days_between uses [start,end), and reverses the sign for reverse intervals. add_business_days excludes the initial day when moving and returns the same date for a zero offset. round_increment(value, positive_step) uses exact nearest multiples, ties to even, and the step's scale.

SELECT date,name,query_string FROM #queries lists exact saved text without running it. SELECT date,type,values FROM #custom exposes typed custom records; meta is also available on both tables. UNION ALL combines top-level SELECT branches in order, keeps duplicates, and uses the first branch's column names; the branches must have the same arity and compatible same-kind result types, excluding NULL-only columns. Each branch's ORDER BY, LIMIT and OFFSET apply to that branch. There is no global set sort, nested UNION ALL or PIVOT branch support.

Regex operators ~ and !~ accept literal or computed textual patterns within the portable engine's covered dialect. With a nullable typed operand they propagate NULL; prefix NOT is a different conditional operation. Python-specific assertions and backreferences remain out of scope.

Use moonbean query ledger.beancount 'SELECT date,account,number LIMIT 20' --csv for a CSV table with headings and CRLF records. NULL and empty text both produce an empty field; use --json for typed values or PRINT. CSV exports literal text, not spreadsheet formulas generated by MoonBean. Import text from untrusted ledger inputs as text rather than permitting the spreadsheet to interpret it as a formula.
