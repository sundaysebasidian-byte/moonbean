"""Review B source, validation and portable parser resource regressions."""
import itertools
import json
import random
import subprocess
from decimal import Decimal
from pathlib import Path
import bql_r11_review_differential as review
import bql_r12b_fuzz_parser as fuzz
import bql_r12b_deep_nesting as deep


def cases():
    out = []
    def add(query, ledger='tests/r11/prices.beancount'):
        out.append(dict(query=query, ledger=ledger, feature='review-b-regression'))
    operands = ['2024-01-31', "interval('1 month')", "interval('2 days')", '1', '1.5', 'NULL']
    for a, b, op in itertools.product(operands, operands, ['+', '-', '*', '/']):
        add('SELECT repr(' + a + op + b + ') LIMIT 1')
    for text in ['99-12-31','99/12/31','50-06-15','32-01-01','68-01-01','69-01-01']:
        add('SELECT parse_date(' + repr(text) + ') LIMIT 1')
    delta = "(interval('1 month')-interval('2 days'))"
    for f in ['year','month','day','quarter','weekday','yearmonth','date']:
        add('SELECT repr(' + f + '(' + delta + ')) LIMIT 1')
    for field in ['year','month','day','quarter','week']:
        add('SELECT repr(date_part(' + repr(field) + ',' + delta + ')) LIMIT 1')
    for expr in [delta+'+1', delta+'='+delta, delta+'<'+delta,
                 "date_bin(interval('1 month')+interval('-2 days'),2024-03-20,2024-01-01)",
                 "date_bin(interval('-1 month')+interval('40 days'),2024-03-20,2024-01-01)",
                 "coalesce(payee,'x')", "coalesce(NULL,NULL)", "coalesce(NULL,'x')", "coalesce()",
                 "coalesce(1,2.0)", "coalesce('x',parse_date('bad'))", "coalesce(1)",
                 "round(9999999999999999999999999999.5)", "round(9999999999999999999999999999.5,0)"]:
        add('SELECT '+expr+' LIMIT 1')
    for q in ["SELECT date,narration,lineno FROM OPEN ON 2024-01-05 WHERE date=2024-02-10",
              "JOURNAL FROM OPEN ON 2024-01-05 CLOSE ON 2024-02-15"]:
        add(q, 'examples/full-year-2024.beancount')
    for q in ["SELECT date,flag,account FROM CLOSE ON 2024-03-01 CLEAR WHERE flag='T'",
              "SELECT date,account,position FROM OPEN ON 2024-01-05"]:
        add(q,'tests/r12/clear-cost.beancount')
    for file in ['cafe','uacct','small','dupbal','astral-account']:
        add('SELECT account,sum(number) GROUP BY account', 'tests/r12/review-b/'+file+'.beancount')
        add('SELECT account FROM #accounts','tests/r12/review-b/'+file+'.beancount')
    return out


def run(ours, oracle):
    probes = cases()
    p = subprocess.run([str(Path(oracle)/'python'), 'scripts/bql_r11_review_differential.py','--worker'],
                       input=json.dumps(probes),capture_output=True,text=True,check=True)
    results = []
    for case, expected in zip(probes,json.loads(p.stdout)):
        a = subprocess.run([ours,'query',case['ledger'],case['query'],'--json'],capture_output=True,text=True,timeout=30)
        actual = json.loads(a.stdout,parse_float=Decimal) if a.returncode == 0 else None
        category = 'success' if actual is not None else review.error_category(a.stdout+a.stderr,True)
        ok = category == expected['category'] and a.returncode == (0 if category == 'success' else 1)
        if ok and category == 'success': ok = len(actual['rows']) == len(expected['rows']) and all(len(a) == len(b) and all(review.equivalent(x,y) for x,y in zip(a,b)) for a,b in zip(actual['rows'],expected['rows']))
        results.append(dict(**case,ok=ok,detail='' if ok else dict(actual=actual or a.stdout+a.stderr,oracle=expected)))
    for file in ['dupbal','cafe','uacct','small','astral-account']:
        ledger='tests/r12/review-b/'+file+'.beancount'
        a=subprocess.run([ours,'check',ledger],capture_output=True,text=True)
        b=subprocess.run([str(Path(oracle)/'bean-check'),ledger],capture_output=True,text=True)
        results.append(dict(ledger=ledger,feature='review-b-check',ok=a.returncode==b.returncode,
                            ours_exit=a.returncode,oracle_exit=b.returncode,detail='' if a.returncode==b.returncode else a.stdout+a.stderr+b.stdout+b.stderr))
    fuzz.OURS, fuzz.LEDGER = ours, 'tests/r9/tx.beancount'
    for query in fuzz.mutants(random.Random(1212))+fuzz.special():
        result=fuzz.run(query)
        results.append(dict(feature='review-b-parser-robustness',ok=not result['defect'],**result))
    for name, generate in deep.C.items():
        for depth in [1000,20000]:
            try:
                p=subprocess.run([ours,'query','tests/r9/tx.beancount',generate(depth),'--json'],capture_output=True,text=True,timeout=20)
                ok=p.returncode==1 and 'syntax query.depth_limit' in p.stdout
                detail=p.stdout[-300:]+p.stderr[-300:]
            except OSError as e:
                import errno
                ok=e.errno==errno.E2BIG
                detail=str(e)
            results.append(dict(feature='review-b-depth-limit',construct=name,depth=depth,ok=ok,detail=detail))
    return results


if __name__ == '__main__':
    import sys
    rows=run(sys.argv[1] if len(sys.argv)>1 else '_build/native/debug/build/cmd/main/main.exe','/tmp/moonbean-r4-oracle/bin')
    print(json.dumps(rows,indent=2,default=str))
    sys.exit(any(not r['ok'] for r in rows))
