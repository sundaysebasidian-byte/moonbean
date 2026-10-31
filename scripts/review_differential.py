#!/usr/bin/env python3
"""R1 report and booked-posting checks against external Beancount executables."""
import argparse
from collections import Counter, defaultdict
from decimal import Decimal
import json
from pathlib import Path
import re
import conformance as c


def position(number, currency, cost=None, cost_currency=None, date=None, label=None):
    return (Decimal(number), currency, Decimal(cost) if cost is not None else None, cost_currency, date, label)


def oracle_position(text):
    m = re.fullmatch(rf'\s*({c.NUMBER})\s+(\S+?)(?:\s+\{{(.*)\}})?\s*', text)
    if not m:
        raise ValueError(f'unparsed position {text!r}')
    if m[3] is None:
        return position(m[1], m[2])
    cost = re.fullmatch(rf'({c.NUMBER})\s+([^,\s]+)(?:,\s*(\d{{4}}-\d{{2}}-\d{{2}}))?(?:,\s*"(.*)")?', m[3])
    if not cost:
        raise ValueError(f'unparsed cost {m[3]!r}')
    return position(m[1], m[2], cost[1], cost[2], cost[3], cost[4])


def our_position(value):
    units = value['units']
    cost = value.get('cost') or {}
    return position(units['number'], units['currency'], cost.get('number'), cost.get('currency'), cost.get('date'), cost.get('label'))


def compare_postings(exe, oracle, path):
    ours = c.ours_query(exe, path, 'SELECT date, account, position ORDER BY date, account')
    expected = c.oracle_query(oracle, path, 'SELECT date, account, str(position) ORDER BY date, account')
    if ours is None or expected is None:
        return False, 'posting query failed'
    actual = [(r[0], r[1], our_position(r[2])) for r in ours['rows']]
    wanted = [(r[0], r[1], oracle_position(r[2])) for r in expected[1:]]
    ok = Counter(actual) == Counter(wanted)
    return ok, '' if ok else f'expected {len(wanted)} rows {wanted!r}; got {len(actual)} rows {actual!r}'


def compare_booked_views(exe, oracle, path):
    expected = c.oracle_query(oracle,path,'SELECT date, account, str(position) ORDER BY date, account')
    if expected is None:
        return [('booked-views',False,'oracle query failed')]
    wanted = [(r[0],r[1],oracle_position(r[2])) for r in expected[1:]]
    export = json.loads(c.run([exe,'export',path,'--json']).stdout)
    actual=[]
    for entry in export['entries']:
        if entry['type']=='transaction':
            for posting in entry['postings']:
                units=posting['units'];cost=posting['cost'] or {}
                actual.append((entry['date'],posting['account'],position(units['number'],units['currency'],cost.get('per'),cost.get('currency'),cost.get('date'),cost.get('label'))))
    checks=[('export-booked-details',Counter(actual)==Counter(wanted),'')]
    account = 'Assets:Stock' if any(r[1]=='Assets:Stock' for r in wanted) else 'Assets:Cash'
    wanted=[r for r in wanted if r[1]==account]
    journal=c.ours_query(exe,path,'JOURNAL '+account)
    actual=[(r[0],r[4],our_position(r[5])) for r in journal['rows']]
    checks.append(('journal-booked-details',Counter(actual)==Counter(wanted),''))
    register=report(exe,path,'register',account)
    actual=[]
    for r in register:
        amount=r['amount']; suffix=' '+r['cost'] if r['cost'] else ''
        actual.append((r['date'],r['account'],oracle_position(amount['number']+' '+amount['currency']+suffix)))
    checks.append(('register-booked-details',Counter(actual)==Counter(wanted),''))
    return checks


def report(exe, path, command, *args):
    proc = c.run([exe, command, path, '--json', *args])
    if proc.returncode:
        raise RuntimeError(proc.stderr)
    return json.loads(proc.stdout)


def report_balances(value):
    sums = defaultdict(Decimal)
    for row in value['rows']:
        a = row['amount']
        sums[row['account'], a['currency']] += Decimal(a['number'])
    return {k: v for k, v in sums.items() if v}


def oracle_balances(rows):
    if rows is None:
        raise RuntimeError('oracle balance query failed')
    sums = defaultdict(Decimal)
    for row in rows[1:]:
        units, _ = c.parse_oracle_cell(row[1])
        for currency, number in units.items():
            sums[row[0], currency] += number
    return {k: v for k, v in sums.items() if v}


def compare_reports(exe, oracle, path):
    results = []
    for command, period, where in [
        ('bs', 'OPEN ON 2024-01-01 CLOSE ON 2025-01-01 CLEAR', ''),
        ('is', 'OPEN ON 2024-01-01 CLOSE ON 2025-01-01', " WHERE account ~ '^(Income|Expenses):'"),
    ]:
        actual = report(exe, path, command, '--convert', '', '--from', '2024-01-01', '--at', '2024-12-31')
        query = f'SELECT account, str(sum(cost(position))) FROM {period}{where} GROUP BY account ORDER BY account'
        expected = oracle_balances(c.oracle_query(oracle, path, query))
        got = report_balances(actual)
        ok = expected == got
        results.append((command, ok, '' if ok else f'expected {expected!r}; got {got!r}'))
        if command == 'bs':
            sums = defaultdict(Decimal)
            for (_, currency), number in got.items():
                sums[currency] += number
            results.append(('balance-sheet-identity', not any(sums.values()), str(dict(sums))))
    return results


def compare_market(exe, oracle, path, bridge, target):
    actual = report(exe, path, 'bal', '--convert', target)
    query = f"SELECT account, str(sum(convert(convert(position,'{bridge}'),'{target}'))) GROUP BY account ORDER BY account"
    expected = oracle_balances(c.oracle_query(oracle, path, query))
    got = report_balances(actual)
    ok = actual['complete'] and expected == got
    return ok, '' if ok else f'expected {expected!r}; got {got!r}; complete={actual["complete"]}'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ours', default='_build/native/debug/build/cmd/main/main.exe')
    p.add_argument('--oracle', default='.oracle-venv/bin')
    p.add_argument('--ledgers', default='tests/review')
    p.add_argument('--out', default='.oracle-cache/r1/review.json')
    a = p.parse_args()
    results = []
    for path in sorted(Path(a.ledgers).glob('*.beancount')):
        base = c.compare_ledger(a.ours,a.oracle,str(path),False)
        checks = [('existing',c.format_result(base)[2],repr(base) if not c.format_result(base)[2] else '')]
        if not c.ours_diagnostics(a.ours,str(path)):
            checks.append(('posting-details',*compare_postings(a.ours,a.oracle,str(path))))
            checks.extend(compare_reports(a.ours,a.oracle,str(path)))
            checks.extend(compare_booked_views(a.ours,a.oracle,str(path)))
        results.append(dict(ledger=path.name,checks=checks))
    chain=str(Path(a.ledgers)/'convert-chain.beancount')
    if Path(chain).exists():
        ok,detail=compare_market(a.ours,a.oracle,chain,'USD','CNY')
        results.append(dict(ledger='price-chain',checks=[('price-path',ok,detail)]))
    minimal=str(Path(a.ledgers)/'report-minimal.beancount')
    if Path(minimal).exists():
        actual=report(a.ours,minimal,'bs','--convert','','--at','2024-01-02','--from','2024-01-01')
        expected=oracle_balances(c.oracle_query(a.oracle,minimal,'SELECT account,str(sum(cost(position))) FROM CLOSE ON 2024-01-03 CLEAR GROUP BY account ORDER BY account'))
        results.append(dict(ledger='historical-balance-sheet',checks=[('snapshot',report_balances(actual)==expected,'')]))
    checks=[v for r in results for v in r['checks']]
    data=dict(ledgers=len(results),checks=len(checks),failures=sum(not x[1] for x in checks),results=results)
    Path(a.out).parent.mkdir(parents=True,exist_ok=True)
    Path(a.out).write_text(json.dumps(data,indent=2))
    print(json.dumps(data,indent=2))
    return int(bool(data['failures']))

if __name__ == '__main__':
    raise SystemExit(main())
