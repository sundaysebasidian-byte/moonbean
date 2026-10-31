#!/usr/bin/env python3
"""Exercise actual CLI report commands and display options; retain fixture."""
import json
from pathlib import Path
import subprocess

exe = '_build/native/debug/build/cmd/main/main.exe'
path = Path('.oracle-cache/cli-options.beancount')
path.parent.mkdir(exist_ok=True)
path.write_text('''option "operating_currency" "CNY"
option "display_precision" "CNY:0.01"
2024-01-01 open Assets:Cash USD
2024-01-01 open Equity:Opening USD
2024-01-01 open Expenses:Food USD
2024-01-01 price USD 7 CNY
2024-01-02 * "opening"
  Assets:Cash 10 USD
  Equity:Opening -10 USD
2024-01-03 * "food"
  Assets:Cash -1 USD
  Expenses:Food 1 USD
2024-01-03 * "food"
  Assets:Cash -1 USD
  Expenses:Food 1 USD
''')
def run(*args):
    return subprocess.run([exe, *args], check=True, text=True, capture_output=True).stdout
for command, title in [('bal', 'Trial Balance'), ('bs', 'Balance Sheet'), ('is', 'Income Statement')]:
    output = run(command, str(path))
    assert title in output and 'CNY' in output and '.00' in output, output
    json.loads(run(command, str(path), '--json'))
assert '56' in run('bs', str(path))
assert '8 USD' in run('bs', str(path), '--convert', 'USD')
assert len(json.loads(run('register', str(path), 'Assets:Cash', '--json'))) == 3
assert 'duplicate of' in run('dups', str(path))
print('CLI reports, JSON, register, duplicates, operating_currency, display_precision: PASS')
