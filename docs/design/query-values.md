# Query value and column implementation design

The existing flat BqlRow is a posting projection. Its extra directive pointer
cannot express dictionaries, nested directives or assertion-time results. Adding
more nullable scalar fields would silently discard types.

This increment adds recursive dictionary, list and named-record QueryValue
variants, plus a distinct arbitrary-precision integer value. Records retain a
name and ordered typed fields; they are not pre-rendered strings. JSON exports
structured values and text rendering uses a separate Python-compatible repr.
Source metadata contains filename/lineno and user values; generated booking
metadata must be computed from the booked entry/options before enabling it.

Directive objects are built only when projected. Account open/close references
are resolved from the realized entry stream, including missing close = NULL.
Balance discrepancy is computed at the assertion boundary, using prior entries,
subaccounts and tolerance, not final inventory. Identity hashes are enabled only
when the oracle's field encoding has been established independently.

The implemented source-resolved pass separates expression types from evaluation: nullable source-column
schemas and function signatures are checked after source resolution. Evaluation
gets a read-only query context for prices, options and entry/account metadata.
Integer and decimal types must remain distinct even when values compare equal.
Unsupported signatures raise compilation/unsupported errors rather than returning
NULL as a fallback.

Each column family gets black-box typed JSON comparisons, plus text checks where
the oracle has a deterministic representation. New-source construction remains
linear; existing posting paths must retain the performance gate. Declared non-hashable GROUP BY types fail like the oracle; position grouping uses numeric equality while DISTINCT preserves representation. Arbitrary structural comparisons remain an explicit boundary. Subqueries and other relation-plan changes remain separate work.

The first full performance matrix found regressions in scalar sorting and some
JS/wasm-gc paths. Preserve that matrix. The follow-up keeps optional entry/table/
posting/running provenance in one lazily allocated RowExtra, restoring the small
posting-row shape for existing scalar queries. Text-to-text comparisons bypass
structural-value checks. Tolerance inference uses explicit cache lookup (no
per-posting closure) and allocates cost collections only when that option is on.
These are private representation changes; typed values and rejection boundaries
must remain unchanged. Check affected cases first, then repeat the complete gate.

Signed-zero detection moves into the existing lexer pass with a private optional
flag; the public tokenize API is unchanged. This avoids scanning each token array
a second time, particularly costly on wasm-gc.

The small-matrix follow-up isolated the remaining regression to ORDER BY.
Evaluate non-projected order expressions once per output row, reuse projected
column keys, and sort row indices in O(n log n), breaking equal keys by original
index. This keeps NULL/direction/tie behavior stable and avoids repeated grouped
expression evaluation. Amount/position order uses independently observed oracle
keys; unsupported structural order remains an error. String grouping keys use a
type/length prefix instead of JSON escaping; date and text keys must stay distinct.
The unchanged baseline driver still skips its historical large-order cases.
