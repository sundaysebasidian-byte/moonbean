#!/usr/bin/env bash
# Measure parse + booking throughput on a generated 100k-transaction ledger.
# The ledger is written to a temporary directory and never committed.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="${HOME}/.moon/bin:${PATH}"

count="${MOONBEAN_BENCH_TXNS:-100000}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 - "$tmp/ledger.beancount" "$count" <<'PY'
import sys

path, count = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    f.write('option "title" "benchmark"\n')
    f.write("2024-01-01 open Assets:Cash USD\n")
    f.write("2024-01-01 open Equity:Opening USD\n")
    f.write("2024-01-01 open Expenses:Food USD\n")
    f.write('2024-01-01 * "Opening"\n')
    f.write("  Assets:Cash    1000000.00 USD\n")
    f.write("  Equity:Opening -1000000.00 USD\n")
    for i in range(count):
        f.write(f'2024-01-02 * "Purchase {i}"\n')
        f.write("  Assets:Cash     -1.00 USD\n")
        f.write("  Expenses:Food    1.00 USD\n")
PY

echo "==> building moonbean (native release)"
moon build --target native --release >/dev/null
bin="_build/native/release/build/cmd/main/main.exe"

run() {
  local label="$1"
  shift
  echo "==> ${label}"
  /usr/bin/time -p "$@" 2>&1 >/dev/null | sed -n 's/^real /real      /p;s/^user /user      /p;s/^sys /sys       /p'
}

run "check (parse + validate + booking), ${count} transactions" \
  "$bin" check "$tmp/ledger.beancount"
run "bal (realization + trial balance)" \
  "$bin" bal "$tmp/ledger.beancount"
run "query (BQL aggregate)" \
  "$bin" query "$tmp/ledger.beancount" \
  'SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account'

echo "==> ledger size: $(wc -l < "$tmp/ledger.beancount") lines, $(du -h "$tmp/ledger.beancount" | cut -f1)"
