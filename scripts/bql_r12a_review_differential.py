#!/usr/bin/env python3
"""R12-A independent differential probes for MoonBean 0.2.6 (f1cb94a).

Run from the repository root with --ours and --oracle overrides as needed.
The original cases are retained, including the former duplicate controls.
Oracle calls use the public cursor worker. Rows and columns retain their order.
"""
import argparse, glob, importlib, itertools, json, os, subprocess, sys
from decimal import Decimal

from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bql_r11_review_differential as review
equivalent, error_category = review.equivalent, review.error_category

PRICES = 'tests/r11/prices.beancount'
TX = 'tests/r9/tx.beancount'
ALL_LEDGERS = sorted(glob.glob('tests/ledgers/*.beancount')) + [TX] + sorted(glob.glob('tests/r11/*.beancount')) + sorted(glob.glob('tests/r12/*.beancount'))
TX_LEDGERS = [TX, 'tests/ledgers/001-basic.beancount', 'tests/ledgers/015-tags-links.beancount',
              'tests/ledgers/024-cost-per.beancount', 'tests/ledgers/117-bql-tables.beancount', PRICES,
              'tests/r12/clear-cost.beancount', 'tests/r12/from-price.beancount']

_CASES = []
def add(q, feature, ledgers=(PRICES,)):
    for l in ledgers:
        _CASES.append(dict(query=q, feature=feature, ledger=l))
def scalar(expr, feature):
    add('SELECT ' + expr + ' LIMIT 1', feature)

# --- parse_date(str) ---
for s in ['2024.03.05', '05 Mar 2024', 'Tuesday, March 5, 2024', 'March 5th, 2024', '5th of March 2024',
          '3/5/2024', '13/13/2024', '2024-13-01', '2024-02-30', '', ' ', '  2024-03-05  ',
          '2024-03-05T10:00:00+05:30', '2024-03-05 10:00 PM', '05-Mar-2024', '2024 Mar 5', '5.3.2024',
          '0001-01-01', '9999-12-31', '10000-01-01', '99-12-31', '00-01-01', '68-01-01', '69-01-01',
          'Dec 2023', '2023 Dec', 'tomorrow', 'abc', '2024--03-05', '2024-3-5', 'Sep. 5, 2024', 'Sept 5 2024',
          '240305', '2024-065', '2024-W10-2', '1/1/1', '2024-03-05Z', '2024-03-05 25:00', 'Mon 2024-03-05']:
    scalar('parse_date(' + repr(s) + ')', 'parse_date1')
scalar('parse_date(NULL)', 'parse_date1')
scalar("parse_date(narration)", 'parse_date1')
# --- parse_date(str, fmt) ---
for s, f in [('05.03.2024', '%d.%m.%Y'), ('2024 065', '%Y %j'), ('2024 366', '%Y %j'), ('2023 366', '%Y %j'),
             ('2024-02-30', '%Y-%m-%d'), ('Wed 05 Mar 2024', '%a %d %b %Y'), ('69', '%y'), ('68', '%y'),
             ('2024', '%Y'), ('', '%Y'), ('2024-03-05', ''), ('2024-03-05x', '%Y-%m-%d'),
             ('2024-03-05', '%Y-%m-%d %H'), ('12/31/99', '%m/%d/%y'), ('2024-3-5', '%Y-%m-%d'),
             (' 2024-03-05', '%Y-%m-%d'), ('2024-03-05', ' %Y-%m-%d'), ('2024%03', '%Y%%%m'), ('5', '%d'),
             ('Feb 29', '%b %d'), ('12 AM', '%I %p'), ('2024-03-05', '%F'), ('2024-03-05', '%Q'),
             ('0', '%w'), ('march 5 2024', '%B %d %Y'), ('MAR 5 2024', '%b %d %Y'), ('2024-03-05', '%Y-%m-%d%'),
             ('20240305', '%Y%m%d'), ('2024035', '%Y%m%d'), ('2024-03-05 23:59:59.999999', '%Y-%m-%d %H:%M:%S.%f')]:
    scalar('parse_date(' + repr(s) + ',' + repr(f) + ')', 'parse_date2')
scalar("parse_date('2024-03-05',NULL)", 'parse_date2')
scalar("parse_date(NULL,'%Y')", 'parse_date2')
# --- date_bin ---
for iv, d, o in [('7 days', '2024-03-05', '2024-01-01'), ('10 days', '2023-12-25', '2024-01-01'),
                 ('365 days', '2025-01-01', '2024-01-01'), ('3 months', '2024-05-31', '2024-01-31'),
                 ('12 months', '2025-02-28', '2024-02-29'), ('2 years', '2027-02-28', '2024-02-29'),
                 ('1 year', '2028-02-28', '2024-02-29'), ('1 year', '2028-02-29', '2024-02-29'),
                 ('-7 days', '2024-03-05', '2024-01-01'), ('0 months', '2024-03-05', '2024-01-01'),
                 ('0 years', '2024-03-05', '2024-01-01'), ('1 week', '2024-03-05', '2024-01-01'),
                 ('1 month', '2024-01-01', '2024-01-01'), ('1 month', '2023-12-31', '2024-01-31'),
                 ('1 month', '2023-11-30', '2024-01-31'), ('-1 year', '2024-03-05', '2024-01-01'),
                 ('1 year', '9999-12-31', '0001-01-01'), ('1 day', '0001-01-01', '9999-12-31'),
                 ('3 days', '0001-01-02', '0001-01-01'), ('1 month', '9999-12-31', '9999-12-01'),
                 ('', '2024-03-05', '2024-01-01'), ('1', '2024-03-05', '2024-01-01'),
                 ('13 months', '2023-01-15', '2024-03-31'), ('5 years', '1990-06-15', '2024-02-29')]:
    scalar(f'date_bin({iv!r},{d},{o})', 'date_bin')
scalar("date_bin(NULL,2024-03-05,2024-01-01)", 'date_bin')
scalar("date_bin('1 day',NULL,2024-01-01)", 'date_bin')
scalar("date_bin('1 day',2024-03-05,NULL)", 'date_bin')
scalar("date_bin(interval('1 week'),2024-03-05,2024-01-01)", 'date_bin')
scalar("date_bin(interval('-13 months'),2024-03-05,2024-01-01)", 'date_bin')
add("SELECT date,date_bin('1 month',date,2023-12-15) FROM #transactions", 'date_bin', TX_LEDGERS[:4])
add("SELECT date_bin('2 days',date,2024-01-01) AS b,count(*) GROUP BY b ORDER BY b", 'date_bin', TX_LEDGERS[:3])
# --- interval ---
for s in ['1 week', '2 weeks', '3 months', '-3 months', '13 months', '-13 months', '25 months', '-1 years',
          '1 day 2 months', '1.5 days', '1e2 days', '', '  ', 'days', '1', '1 DAY', '1 Days', 'one day',
          '--1 day', '1 hour', '0 months', '0 years', '-0 days', '1  days', ' 1 day', '1 day ', '12 months',
          '-12 months', '1 yr', '1 mon', '1_000 days']:
    scalar('interval(' + repr(s) + ')', 'interval')
    scalar('str(interval(' + repr(s) + '))', 'interval-str')
scalar('interval(NULL)', 'interval')
scalar("interval('1 day')=interval('1 day')", 'interval')
scalar("2024-01-31+interval('1 month')", 'interval')
scalar("2024-03-31-interval('1 month')", 'interval')
# --- today ---
for e in ['today()', 'today()=today()', 'year(today())', 'today()+1', 'today()-today()', "date_diff(today(),2024-01-01)>0",
          'str(today())', 'month(today())', "date_bin('1 month',today(),2024-01-01)", "parse_date(str(today()))=today()",
          "today()>2026-01-01", "weekday(today())"]:
    scalar(e, 'today')
add("SELECT count(*) WHERE date<today()", 'today', [TX])
add("SELECT today() FROM #transactions LIMIT 2", 'today', [TX])
# --- round ---
for e in ['round(-0.4)', 'round(-0.0)', 'round(0.5)', 'round(-0.5)', 'round(1.5)', 'round(2.5)', 'round(-2.5)',
          'round(0.4999999999999999999)', 'round(12345678901234567890123.5)', 'round(99999999999999999999999999.5)',
          'round(9999999999999999999999999999.5)', 'round(-0.0,2)', 'round(0.125,2)', 'round(-0.125,2)',
          'round(1234.5678,-2)', 'round(5,-1)', 'round(15,-1)', 'round(25,-1)', '-round(-0.4)', 'abs(round(-0.4))',
          'round(-0.4)*-1', 'str(round(-0.0))', 'round(NULL)', 'round(1.5,NULL)', 'round(1,100)', 'round(1.5,-100)',
          'round(0.5,0)', 'round(-0.0)=0', 'round(-0.4)<0', 'round(true)', "round('1.5')", 'round(-0)',
          'round(-0.4,0)', 'round(-0.00001,3)', 'round(1e3)', 'round(0.05,1)', 'round(-0.05,1)',
          'repr(round(-0.0))', 'round(-0.4)+0', 'max(round(-0.4))']:
    scalar(e, 'round')
add("SELECT account,round(number) FROM #postings", 'round', [TX, 'tests/ledgers/021-arithmetic.beancount'])
add("SELECT round(sum(number),-2) GROUP BY account ORDER BY account", 'round', [TX])
# --- missing columns / alias shadowing on #transactions ---
for q in ['SELECT missing FROM #transactions', 'SELECT missing FROM #postings', 'SELECT missing FROM #entries',
          'SELECT missing FROM #prices', 'SELECT missing FROM #nope', 'SELECT missing() FROM #transactions',
          'SELECT DATE FROM #transactions', 'SELECT "missing" FROM #transactions', 'SELECT account FROM #transactions',
          'SELECT date FROM #transactions AS t', 'SELECT t.date FROM #transactions',
          'SELECT narration AS date FROM #transactions WHERE date>2024-01-06',
          'SELECT narration AS date FROM #transactions ORDER BY date',
          'SELECT date AS narration, narration FROM #transactions',
          'SELECT narration AS payee, payee FROM #transactions',
          'SELECT 1 AS date FROM #transactions ORDER BY date',
          'SELECT payee AS d FROM #transactions ORDER BY d',
          'SELECT date AS x FROM #transactions WHERE x>2024-01-06',
          'SELECT date AS d, d FROM #transactions',
          'SELECT narration AS x, count(*) FROM #transactions GROUP BY x',
          'SELECT upper(narration) AS narration FROM #transactions ORDER BY narration',
          'SELECT count(*) AS date, date FROM #transactions GROUP BY date',
          'SELECT date AS payee FROM #transactions GROUP BY payee',
          'SELECT payee AS narration, count(*) FROM #transactions GROUP BY narration',
          'SELECT payee AS narration, count(*) FROM #transactions GROUP BY 1',
          'SELECT date, count(*) AS c FROM #transactions GROUP BY date HAVING c>0',
          'SELECT date AS flag FROM #transactions WHERE flag=\'*\'',
          'SELECT missing AS date FROM #transactions',
          'SELECT date AS missing FROM #transactions ORDER BY missing DESC',
          'SELECT * FROM (SELECT narration AS date FROM #transactions) WHERE date=\'Groceries\'',
          'SELECT date FROM (SELECT narration AS date FROM #transactions)',
          'SELECT missing FROM (SELECT date FROM #transactions)',
          'SELECT tags AS links, links FROM #transactions',
          'SELECT date AS date FROM #transactions ORDER BY date DESC',
          'SELECT narration AS NARRATION FROM #transactions ORDER BY narration']:
    add(q, 'transactions-alias', [TX, 'tests/ledgers/117-bql-tables.beancount'])

# --- narrowing probes added after first pass ---
for s in ['99-1-1', '99/12/31', '32-01-01', '50-06-15', '31-12-99', '99 Dec 31']:
    scalar('parse_date(' + repr(s) + ')', 'parse_date1')
for e in ['2024-01-01+1', '2024-01-05-1', '2024-01-05-2024-01-01', "parse_date('2024-01-01')+1",
          'round(999999999999999999999999999.5)', 'round(9999999999999999999999999999.5,0)',
          'round(9999999999999999999999999999.4)']:
    scalar(e, 'date-arith' if '-0' in e[:12] or '+1' in e else 'round')
add('SELECT date, date-2024-01-01 FROM #transactions', 'date-arith', [TX])
add('SELECT count(*) WHERE date>today()-1000', 'date-arith', [TX])

def cases():
    return [dict(c) for c in _CASES]

def run(ours, oracle):
    probes = cases()
    worker = subprocess.run([str(Path(oracle) / 'python'), 'scripts/bql_r11_review_differential.py', '--worker'],
                            input=json.dumps(probes), text=True, capture_output=True, check=True, timeout=600)
    results = []
    for case, expected in zip(probes, json.loads(worker.stdout)):
        p = subprocess.run([ours, 'query', case['ledger'], case['query'], '--json'], capture_output=True, text=True, timeout=30)
        actual = json.loads(p.stdout, parse_float=Decimal) if p.returncode == 0 else None
        category = 'success' if actual is not None else error_category(p.stdout+p.stderr, True)
        ok = category == expected['category'] and p.returncode == (0 if category == 'success' else 1)
        if ok and category == 'success':
            ok = len(actual['rows']) == len(expected['rows']) and all(len(a) == len(b) and all(equivalent(x,y) for x,y in zip(a,b)) for a,b in zip(actual['rows'],expected['rows']))
        results.append(dict(**case, ok=ok, detail='' if ok else dict(exit=p.returncode,actual=actual or p.stdout+p.stderr,oracle=expected)))
    return results

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--oracle', default='/tmp/moonbean-r4-oracle/bin')
    ap.add_argument('--ours', default='_build/native/debug/build/cmd/main/main.exe')
    args = ap.parse_args()
    results = run(args.ours, args.oracle)
    print(json.dumps(results, indent=2, default=str))
    sys.exit(any(not r['ok'] for r in results))
