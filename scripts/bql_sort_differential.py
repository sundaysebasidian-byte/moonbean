#!/usr/bin/env python3
"""Seeded key-cache, stable ordering and Unicode scalar oracle comparisons."""
from pathlib import Path
import json,random,subprocess
from bql_object_differential import equivalent

def run(ours,oracle):
    rng=random.Random(20261101)
    words=['same','Alpha','zeta','中文','😀','\ue000','','aa','ß','İ','quote"']
    lines=['2024-01-01 open Assets:A USD','2024-01-01 open Equity:A USD']
    for i in range(648):
        narration=rng.choice(words)+str(rng.randrange(9))
        payee=rng.choice([None,'','A','中文','😀','\ue000'])
        head=f'2024-01-{2+i%28:02} * '
        if payee is not None:head+=json.dumps(payee,ensure_ascii=False)+' '
        lines.extend([head+json.dumps(narration,ensure_ascii=False),'  Assets:A 1 USD','  Equity:A -1 USD'])
    ledger=Path('.oracle-cache/r2-last/sort-corpus.beancount').resolve();ledger.parent.mkdir(parents=True,exist_ok=True);ledger.write_text('\n'.join(lines)+'\n')
    queries=[
        'SELECT narration,payee,date FROM transactions ORDER BY narration,payee,date',
        'SELECT narration,date FROM transactions ORDER BY narration DESC,date DESC LIMIT 100',
        'SELECT narration,payee FROM transactions ORDER BY length(narration),payee DESC,narration',
        'SELECT payee,count(*) FROM transactions GROUP BY payee ORDER BY count(*) DESC,payee',
        'SELECT DISTINCT narration FROM transactions ORDER BY narration LIMIT 20',
        'SELECT min(narration),max(narration) FROM transactions',
        'SELECT position,account ORDER BY position',
        'SELECT narration FROM transactions ORDER BY length(narration)+year(date),date DESC,narration',
    ]
    result=[]
    for q in queries:
        a=subprocess.run([ours,'query',str(ledger),q,'--json'],capture_output=True,text=True)
        b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',str(ledger),q],capture_output=True,text=True)
        try:
            av=json.loads(a.stdout);bv=json.loads(b.stdout)
            ok=a.returncode==0 and b.returncode==0 and equivalent(av['rows'],bv)
            detail='' if ok else str((av,bv))[:1200]
        except Exception as e:ok=False;detail=str(e)
        result.append(dict(query=q,corpus_rows=648,ok=ok,detail=detail))
    # The baseline matrix skips large ORDER BY; prove the new native path separately.
    large=Path('.oracle-cache/r2-last/large-sort.beancount').resolve()
    large_rng=random.Random(7)
    with large.open('w') as out:
        out.write('2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n')
        for _ in range(50000):
            out.write('2024-01-02 * "lot-'+str(large_rng.randrange(1000000))+'"\n  Assets:A 1 USD\n  Equity:A -1 USD\n')
    q='SELECT narration ORDER BY narration'
    a=subprocess.run([ours,'query',str(large),q,'--json'],capture_output=True,text=True)
    b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',str(large),q],capture_output=True,text=True)
    try:
        av=json.loads(a.stdout);bv=json.loads(b.stdout)
        ok=a.returncode==0 and b.returncode==0 and len(av['rows'])==100000 and equivalent(av['rows'],bv)
        detail='' if ok else 'large native ordering differs'
    except Exception as e:ok=False;detail=str(e)
    result.append(dict(query=q,kind='large native sort',postings=100000,ok=ok,detail=detail))
    return result

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--oracle',default='/tmp/moonbean-r4-oracle/bin');p.add_argument('--ours',default='_build/native/debug/build/cmd/main/main.exe');a=p.parse_args()
    r=run(a.ours,a.oracle);print(json.dumps(r,indent=2));raise SystemExit(any(not x['ok'] for x in r))
