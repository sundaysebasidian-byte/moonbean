# Ungrouped ORDER BY quadratic scaling

Reproduction (offline; selected MoonBit toolchain already on PATH):

```sh
python3 scripts/bench-matrix.py --targets native --sizes 1000 10000 --out .oracle-cache/order-repro
python3 scripts/bench-summary.py .oracle-cache/order-repro
```

Read `stages.order` in each FIFO JSON. Query: `SELECT narration ORDER BY narration`.
The generator uses seed 20261101 and alternating Buy/Sell narrations, so rows are
not already sorted. The committed baseline retains all warmups and 21 samples.
The observed 10x input / roughly 100x time is explained by insertion sorting in
`query/eval.mbt:583–622`, with row-expression evaluation inside the comparison loop.
`LIMIT` is applied after sorting (`run_select`), so it does not avoid the work.
This is a small reproduction (500 / 5000 transactions), not an estimate presented
as a measured million-posting result. No engine change or optimization was made.
For this query only, 100k/1m runs are explicitly skipped after observing the lower
sizes; their execution is **not completed** on any backend. Other stages run at
all requested sizes. This is a known scaling limitation, distinct from transient
query timing variation on the older grouped-query workload.
