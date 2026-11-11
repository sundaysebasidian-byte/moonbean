#!/usr/bin/env python3
"""Oracle comparisons for extended BQL, using independently authored inputs."""
import argparse
import json
import subprocess
from pathlib import Path
import conformance as c
import report_differential as reports
import bql_table_differential as tables
import bql_unicode_differential as unicode_cases
import bql_object_differential as object_cases
import bql_function_differential as function_cases
import bql_sort_differential as sort_cases
import bql_r9_differential as r9_cases
import bql_r10_differential as r10_cases


def compare_bql(ours, oracle):
    if oracle is None or len(ours['rows']) != len(oracle) - 1:
        return False, 'oracle failed or row count differs'
    normalized = dict(ours, rows=[list(row) for row in ours['rows']])
    expected = [list(row) for row in oracle]
    for i, row in enumerate(normalized['rows']):
        for j, cell in enumerate(row):
            if isinstance(cell, dict) and 'units' in cell:
                if reports.our_position(cell) != reports.oracle_position(expected[i+1][j]):
                    return False, 'position differs'
                row[j] = expected[i+1][j]
    return c.compare_scalar_query(normalized, expected)


queries = [
    'SELECT first(payee),last(payee),min(payee),max(payee) FROM transactions',
    'SELECT upper(first(payee)),lower(last(payee)) FROM transactions',
    'SELECT min(true),max(false),first(true),last(false) FROM transactions',
    'SELECT first(NULL),last(NULL),min(NULL),max(NULL) FROM transactions',
    'SELECT DISTINCT account ORDER BY account LIMIT 3',
    'SELECT DISTINCT date ORDER BY date DESC LIMIT 2',
    'SELECT DISTINCT tags, links FROM transactions',
    'SELECT DISTINCT payee FROM transactions ORDER BY payee',
    'SELECT count(payee), count(*) FROM transactions',
    'SELECT accounts FROM transactions ORDER BY date LIMIT 3',
    "SELECT meta('absent') FROM transactions LIMIT 2",
    "SELECT entry_meta('absent') LIMIT 2",
    'SELECT account, count(*) GROUP BY account HAVING count(*) > 1 ORDER BY account',
    'SELECT account, count(*) * 2 + 1 GROUP BY account HAVING count(*) >= 1 ORDER BY account',
    "SELECT account WHERE account ~ '^assets:' ORDER BY account LIMIT 3",
    "SELECT account WHERE account ~ '(Income|Expenses):' ORDER BY account LIMIT 3",
    "SELECT tags, links WHERE date = 2024-01-03 ORDER BY account",
    "SELECT meta('receipt'), meta('note') WHERE date = 2024-01-03 ORDER BY account",
    'SELECT 1+2*3, (1+2)*3, -2+5, 6/4 LIMIT 1',
    'SELECT year(date)-2000, month(date)*2 ORDER BY date, account LIMIT 4',
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle', default='.oracle-venv/bin')
    parser.add_argument('--ours', default='_build/native/debug/build/cmd/main/main.exe')
    args = parser.parse_args()
    results = []
    for mode, expr in [('units', 'units(position)'), ('cost', 'cost(position)')]:
        for period in ['CLOSE ON 2024-03-01', 'OPEN ON 2024-02-01 CLOSE ON 2024-06-01']:
            ours_text = f'BALANCES AT {mode} FROM {period}'
            oracle_text = f'SELECT account, str(sum({expr})) FROM {period} GROUP BY account ORDER BY account'
            ours = c.ours_query(args.ours, 'examples/full-year-2024.beancount', ours_text)
            oracle = c.oracle_query(args.oracle, 'examples/full-year-2024.beancount', oracle_text)
            ok, detail = c.compare_units_query(ours, oracle) if ours else (False, 'moonbean failed')
            results.append(dict(query=ours_text, ok=ok, detail=detail))
    for query in queries:
        ledger = 'tests/ledgers/015-tags-links.beancount' if 'tags, links' in query else 'tests/ledgers/019-posting-metadata.beancount' if 'meta(' in query else 'examples/full-year-2024.beancount'
        ours = c.ours_query(args.ours, ledger, query)
        oracle = c.oracle_query(args.oracle, ledger, query)
        ok, detail = compare_bql(ours, oracle) if ours else (False, 'moonbean failed')
        results.append(dict(query=query, ok=ok, detail=detail))
    fixture = json.loads((Path(__file__).resolve().parent.parent / 'tests/bql-strings.json').read_text(encoding='utf-8'))
    for case in fixture['cases']:
        query = case['query']
        oracle = c.oracle_query(args.oracle, fixture['ledger'], query)
        ours = c.ours_query(args.ours, fixture['ledger'], query)
        ok, detail = compare_bql(ours, oracle) if ours else (False, 'moonbean failed')
        if oracle is None or oracle[1:] != case['expected']:
            ok, detail = False, 'oracle output differs from checked-in expectation'
        results.append(dict(query=query, ok=ok, detail=detail))
    for case in fixture['boundaries']:
        query = case['query']
        oracle = c.oracle_query(args.oracle, fixture['ledger'], query)
        proc = subprocess.run([args.ours, 'query', fixture['ledger'], query, '--json'], capture_output=True, text=True)
        output = proc.stdout + proc.stderr
        ok = (oracle is not None) == case['oracle_supported']
        if case['oracle_supported']:
            ok = ok and oracle[1:] == case['oracle_rows']
        code = 'query.invalid_signature' if case['kind']=='compilation' else 'query.unsupported.'+case['kind']
        ok = ok and proc.returncode != 0 and code in output and 'BQL:' in output
        results.append(dict(query=query, ok=ok, detail='' if ok else 'boundary or oracle capability changed'))
    sources = json.loads((Path(__file__).resolve().parent.parent / 'tests/bql-sources.json').read_text(encoding='utf-8'))
    for case in sources['cases'] + sources['boundaries']:
        query, ledger = case['query'], case['ledger']
        oracle = c.oracle_query(args.oracle, ledger, query)
        proc = subprocess.run([args.ours, 'query', ledger, query, '--json'], capture_output=True, text=True)
        ok = oracle == case['oracle']
        if 'kind' in case:
            output = proc.stdout + proc.stderr
            code = 'query.invalid_source' if case['kind'] == 'syntax' else 'query.unsupported.' + case['kind']
            ok = ok and proc.returncode == 1 and code in output and 'BQL:' in output
        else:
            ours = json.loads(proc.stdout) if proc.returncode == 0 else None
            equal, _ = compare_bql(ours, oracle) if ours else (False, '')
            ok = ok and equal
            if 'tags, links' in query:
                text = subprocess.run([args.ours, 'query', ledger, query], capture_output=True, text=True)
                # Compare the actual text renderer, not just normalized JSON sets.
                ok = ok and text.returncode == 0 and all(cell in text.stdout for row in oracle[1:] for cell in row)
                ok = ok and all(row == [['shop', 'cafe'], ['zulu', 'alpha']] for row in ours['rows'])
        results.append(dict(query=query, ledger=ledger, ok=ok, detail='' if ok else 'source/set oracle regression'))
    for case in json.loads(Path('tests/bql-r2.json').read_text()):
        oracle = c.oracle_query(args.oracle, case['ledger'], case.get('oracle_query', case['query']))
        ours = c.ours_query(args.ours, case['ledger'], case['query'])
        if 'kind' in case:
            proc = subprocess.run([args.ours, 'query', case['ledger'], case['query'], '--json'], capture_output=True, text=True)
            ok = proc.returncode == 1 and ('query.unsupported.' + case['kind']) in (proc.stdout + proc.stderr)
            detail = '' if ok else 'expected explicit unsupported boundary'
        else:
            ok, detail = compare_bql(ours, oracle) if ours else (False, 'moonbean failed')
        ok = ok and oracle == case['oracle']
        results.append(dict(query=case['query'], ledger=case['ledger'], ok=ok, detail=detail))
    results.extend(tables.run(args.ours, args.oracle))
    results.extend(unicode_cases.run(args.ours, args.oracle))
    results.extend(object_cases.run(args.ours, args.oracle, full=True))
    results.extend(function_cases.run(args.ours,args.oracle))
    results.extend(sort_cases.run(args.ours,args.oracle))
    results.extend(r9_cases.run(args.ours,args.oracle))
    results.extend(r10_cases.run(args.ours,args.oracle))
    print(json.dumps(results, indent=2))
    return int(any(not r['ok'] for r in results))

if __name__ == '__main__':
    raise SystemExit(main())
