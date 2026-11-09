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

The next step separates expression types from evaluation: nullable source-column
schemas and function signatures are checked after source resolution. Evaluation
gets a read-only query context for prices, options and entry/account metadata.
Integer and decimal types must remain distinct even when values compare equal.
Unsupported signatures raise compilation/unsupported errors rather than returning
NULL as a fallback.

Each column family gets black-box typed JSON comparisons, plus text checks where
the oracle has a deterministic representation. New-source construction remains
linear; existing posting paths must retain the performance gate. Subqueries and
other query-plan changes follow only after the typed values and function layer
have sufficient coverage.
