#!/usr/bin/env python3
"""Seeded, independently authored ledgers; external pinned oracle only.

Generated inputs and complete failures remain in the ignored output directory.
No upstream implementation or test corpus is read.
"""
import argparse
import ast
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import random
import conformance as c

METHODS = ['STRICT', 'STRICT_WITH_SIZE', 'FIFO', 'LIFO', 'HIFO', 'NONE', 'AVERAGE']


def generate(rng, index):
    method = METHODS[index % len(METHODS)]
    currency = rng.choice(['USD', 'EUR', 'CNY'])
    n, cost = rng.randint(3, 40), rng.randint(5, 200)
    kind = index % 11
    lines = [f'option "title" "random {index}"',
             f'2024-01-01 open Assets:Cash {currency}',
             f'2024-01-01 open Equity:Opening {currency}',
             f'2024-01-01 open Expenses:Food {currency}',
             f'2024-01-01 open Assets:Stock AAA "{method}"',
             '2024-01-01 open Assets:Foreign',
             '2024-01-01 open Equity:Foreign',
             f'2024-01-02 pad Assets:Cash Equity:Opening',
             f'2024-01-03 balance Assets:Cash {n * cost * 10} {currency}']
    for day in range(4, rng.randint(7, 15)):
        amount = Decimal(rng.randint(1, 10000)) / 100
        lines += [f'2024-01-{day:02} * "purchase {rng.randrange(100000)}" #shop ^receipt',
                  f'  Assets:Cash -{amount:.2f} {currency}',
                  f'  Expenses:Food {amount:.2f} {currency}']
    for day, price in [(16, cost), (17, cost + rng.randint(1, 10))]:
        lines += [f'2024-01-{day} * "buy"',
                  f'  Assets:Stock {n} AAA {{{price} {currency}}}',
                  f'  Assets:Cash {-n * price} {currency}']
    # Exact-size STRICT_WITH_SIZE; explicit lot selection for STRICT/NONE.
    reduction = n if method == 'STRICT_WITH_SIZE' else rng.randint(1, n)
    selector = f'{{{cost} {currency}}}' if method in ['STRICT', 'NONE'] else '{}'
    lines += ['2024-01-18 * "sell"', f'  Assets:Stock -{reduction} AAA {selector}',
              '  Assets:Cash', f'2024-01-19 price AAA {cost + 7} {currency}',
              '2024-01-20 * "foreign"', '  Assets:Foreign 17.25 GBP',
              '  Equity:Foreign -17.25 GBP']
    if kind in [0, 1, 2]:
        residual = ['0.004', '0.005', '0.006'][kind]
        lines += ['2024-01-21 * "tolerance"', f'  Assets:Cash 1.00 {currency}',
                  f'  Expenses:Food -{Decimal(1) + Decimal(residual)} {currency}']
    elif kind == 3:
        lines += [f'2024-01-22 balance Assets:Cash 999999 ~ 0.01 {currency}']
    elif kind == 4:
        lines += ['2024-01-22 * "unknown"', f'  Assets:Unknown 1 {currency}',
                  f'  Assets:Cash -1 {currency}']
    elif kind == 5:
        lines += ['2024-01-22 * "currency"', '  Expenses:Food 2 JPY', '  Assets:Foreign -2 JPY']
    elif kind == 6:
        lines += ['2024-01-22 close Expenses:Food', '2024-01-23 * "closed"',
                  f'  Expenses:Food 1 {currency}', f'  Assets:Cash -1 {currency}']
    return '\n'.join(lines) + '\n', method, kind


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--allow-known-extensions', action='store_true')
    p.add_argument('--seed', type=int, default=20261031)
    p.add_argument('--count', type=int, default=1000)
    p.add_argument('--workers', type=int, default=8)
    p.add_argument('--out', default='.oracle-cache/random')
    p.add_argument('--ours', default='_build/native/debug/build/cmd/main/main.exe')
    p.add_argument('--oracle', default='.oracle-venv/bin')
    a = p.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)
    inputs = []
    for i in range(a.count):
        source, method, kind = generate(rng, i)
        path = out / f'{i:04}.beancount'
        path.write_text(source)
        inputs.append((str(path.resolve()), method, kind, hashlib.sha256(source.encode()).hexdigest()))
    def compare(item):
        path, method, kind, digest = item
        result = c.compare_ledger(str(Path(a.ours).resolve()), str(Path(a.oracle).resolve()), path, False)
        result.update(method=method, kind=kind, sha256=digest)
        result['ok'] = c.format_result(result)[2]
        return result
    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        results = []
        for result in pool.map(compare, inputs):
            results.append(result)
            if len(results) % 100 == 0:
                print(f'compared {len(results)}; mismatches {sum(not r["ok"] for r in results)}', flush=True)
    summary = dict(seed=a.seed, count=a.count, mismatches=sum(not r['ok'] for r in results),
                   clean_queries=sum(bool(r['queries']) and r['queries'][0][0] != 'skip' for r in results),
                   results=results)
    (out / 'results.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({k: v for k, v in summary.items() if k != 'results'}))
    def known_extension(r):
        if r['method'] != 'AVERAGE' or r['diagnostics'][0]:
            return False
        expected = ast.literal_eval(r['diagnostics'][1].removeprefix('expected '))
        actual = ast.literal_eval(r['diagnostics'][2].removeprefix('got '))
        return any(e[1] == 'average_unsupported' for e in expected) and sorted(e for e in expected if e[1] != 'average_unsupported') == sorted(actual)
    unexpected = [r for r in results if not r['ok'] and not known_extension(r)]
    return int(bool(unexpected) if a.allow_known_extensions else summary['mismatches'] != 0)

if __name__ == '__main__':
    raise SystemExit(main())
