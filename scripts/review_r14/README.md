These are the original independent R14 reviewer scripts, preserved unchanged.
Their original `/tmp/r14*` paths describe the review workspace. The portable,
tracked acceptance runner is `scripts/bql_r14_review_differential.py`, imported by
`scripts/bql_differential.py`. It verifies all 733 immutable input fingerprints
and classifications, materializes include/document fixtures, and compares
additional authored error lines, PRINT bytes and counts against public oracle APIs.

The review corpus has 23 pre-existing classification boundaries: 11 repetitions
of the intentional AVERAGE/cost-merge extensions and 12 unknown-option mutations
accepted by MoonBean's existing raw-option passthrough. Each boundary has a named
manifest entry; every other classification must agree with the oracle, including
the original review exit status. These boundaries are not conformance passes.
