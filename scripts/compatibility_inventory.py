#!/usr/bin/env python3
"""Capture public oracle metadata and CLI behavior; never inspect oracle source.

Run with the pinned oracle virtualenv's Python. Metadata is data, not implementation.
"""
import argparse
import importlib.metadata
import json
from pathlib import Path
import re
import subprocess
import sys
import unicodedata
from beancount.parser import options, parser
from beancount.core import data as bean_data


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', default='docs/evidence/compatibility-inventory.json')
    a = p.parse_args()
    oracle = Path(sys.executable).parent / 'bean-query'
    ledger = 'tests/bql-sources/empty.beancount'
    def query(text):
        proc = subprocess.run([str(oracle), ledger, text], capture_output=True, text=True, check=False)
        stderr=proc.stderr
        if 'Traceback (most recent call last)' in stderr:
            stderr=stderr.strip().splitlines()[-1]+'\n'
        return dict(exit=proc.returncode, stdout=proc.stdout, stderr=stderr)
    tables = query('.tables')['stdout'].split()
    opts = []
    for name, desc in options.OPTIONS.items():
        value = desc.default_value
        if name in options.READ_ONLY_OPTIONS:
            continue
        sample = str(desc.example_value)
        text = ('option '+json.dumps(name)+' '+json.dumps(sample)+'\n') * 2
        _, errors, parsed = parser.parse_string(text)
        opts.append(dict(probe_errors=[e.message for e in errors],
                         probe_value=str(parsed.get(name)), name=name, type=type(value).__name__, default=str(value),
                         repeatable=isinstance(value, (list, dict, set)), alias=desc.alias,
                         example=str(desc.example_value), deprecated=desc.deprecated))
    targets = query('.help targets')['stdout']
    functions, aggregates = targets.split('Functions\n---------\n', 1)[1].split('Aggregate functions\n-------------------\n')
    data = dict(versions={k: importlib.metadata.version(k) for k in ['beancount','beanquery']},
                python=sys.version.split()[0], unicode=unicodedata.unidata_version, options=opts, directives={c.__name__: list(c._fields) for c in bean_data.ALL_DIRECTIVES}, tables={name: query('.describe '+name)['stdout'] for name in tables},
                functions=re.findall(r'^\w+\([^\n]*\)$', functions, re.M),
                aggregates=re.findall(r'^\w+\([^\n]*\)$', aggregates, re.M),
                help={name: query('.help '+name)['stdout'] for name in ['select','from','where','print','journal','balances','explain','run']},
                probes={text: query(text) for text in [
                    "SELECT narration WHERE narration LIKE 'x'", 'SELECT date FROM postings JOIN transactions',
                    'SELECT DISTINCT date', 'SELECT account, sum(position) GROUP BY account FLATTEN',
                    'SELECT account, currency, sum(number) GROUP BY account, currency PIVOT BY account, currency',
                    'SELECT date FROM (SELECT date)', 'SELECT date FROM OPEN ON 2024-01-01 CLOSE ON 2024-02-01 CLEAR',
                    "SELECT \"date\" FROM entries", "SELECT 'date' FROM entries", 'SELECT count(*) FROM accounts', 'SELECT count(*) FROM #accounts', 'SELECT count(accounts) FROM entries', 'PRINT', 'EXPLAIN SELECT date', '.explain SELECT date', 'BALANCES', 'JOURNAL',
                    *['SELECT '+expr for expr in [
                        '1+2', '1-2', '1*2', '1/2', '1%2', '1//2', '1^2', '1&2', '1|2',
                        '1=2', '1!=2', '1<>2', '1<2', '1<=2', '1>2', '1>=2',
                        'TRUE AND FALSE', 'TRUE OR FALSE', 'NOT TRUE', 'NULL IS NULL',
                        'NULL IS NOT NULL', "'a' ~ 'a'", '1 IN (1,2)', '1 NOT IN (1,2)',
                        '1 BETWEEN 0 AND 2', "'a'||'b'", "'a' ?~ 'a'"]]]})
    Path(a.out).write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n')
    print(f'{len(opts)} writable options, {len(tables)} tables, {len(data["functions"])} function signatures, {len(data["aggregates"])} aggregate signatures')

if __name__ == '__main__':
    main()
