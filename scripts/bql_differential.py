#!/usr/bin/env python3
"""Oracle comparisons for extended BQL, using independently authored inputs."""
import argparse
import json
import subprocess
from pathlib import Path
import conformance as c

queries = [
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
        ok, detail = c.compare_scalar_query(ours, oracle) if ours else (False, 'moonbean failed')
        results.append(dict(query=query, ok=ok, detail=detail))
    fixture = json.loads((Path(__file__).resolve().parent.parent / 'tests/bql-strings.json').read_text(encoding='utf-8'))
    for case in fixture['cases']:
        query = case['query']
        oracle = c.oracle_query(args.oracle, fixture['ledger'], query)
        ours = c.ours_query(args.ours, fixture['ledger'], query)
        ok, detail = c.compare_scalar_query(ours, oracle) if ours else (False, 'moonbean failed')
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
        ok = ok and proc.returncode != 0 and ('query.unsupported.' + case['kind']) in output and 'BQL:' in output
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
            ok = ok and proc.returncode != 0 and code in output and 'BQL:' in output
        else:
            ours = json.loads(proc.stdout) if proc.returncode == 0 else None
            equal, _ = c.compare_scalar_query(ours, oracle) if ours else (False, '')
            ok = ok and equal
            if 'tags, links' in query:
                text = subprocess.run([args.ours, 'query', ledger, query], capture_output=True, text=True)
                # Compare the actual text renderer, not just normalized JSON sets.
                ok = ok and text.returncode == 0 and all(cell in text.stdout for row in oracle[1:] for cell in row)
                ok = ok and all(row == [['shop', 'cafe'], ['zulu', 'alpha']] for row in ours['rows'])
        results.append(dict(query=query, ledger=ledger, ok=ok, detail='' if ok else 'source/set oracle regression'))
    print(json.dumps(results, indent=2))
    return int(any(not r['ok'] for r in results))

if __name__ == '__main__':
    raise SystemExit(main())
