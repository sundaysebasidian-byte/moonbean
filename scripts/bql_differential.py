#!/usr/bin/env python3
"""Oracle comparisons for extended BQL, using independently authored inputs."""
import argparse
import json
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
    args = parser.parse_args()
    results = []
    for mode, expr in [('units', 'units(position)'), ('cost', 'cost(position)')]:
        for period in ['CLOSE ON 2024-03-01', 'OPEN ON 2024-02-01 CLOSE ON 2024-06-01']:
            ours_text = f'BALANCES AT {mode} FROM {period}'
            oracle_text = f'SELECT account, str(sum({expr})) FROM {period} GROUP BY account ORDER BY account'
            ours = c.ours_query('_build/native/debug/build/cmd/main/main.exe', 'examples/full-year-2024.beancount', ours_text)
            oracle = c.oracle_query(args.oracle, 'examples/full-year-2024.beancount', oracle_text)
            ok, detail = c.compare_units_query(ours, oracle) if ours else (False, 'moonbean failed')
            results.append(dict(query=ours_text, ok=ok, detail=detail))
    for query in queries:
        ledger = 'tests/ledgers/015-tags-links.beancount' if 'tags, links' in query else 'tests/ledgers/019-posting-metadata.beancount' if 'meta(' in query else 'examples/full-year-2024.beancount'
        ours = c.ours_query('_build/native/debug/build/cmd/main/main.exe', ledger, query)
        oracle = c.oracle_query(args.oracle, ledger, query)
        ok, detail = c.compare_scalar_query(ours, oracle) if ours else (False, 'moonbean failed')
        results.append(dict(query=query, ok=ok, detail=detail))
    print(json.dumps(results, indent=2))
    return int(any(not r['ok'] for r in results))

if __name__ == '__main__':
    raise SystemExit(main())
