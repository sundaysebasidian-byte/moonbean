"""Typed public oracle value comparisons, including every advertised column."""
from pathlib import Path
import json,re,subprocess
from decimal import Decimal


def equivalent(a,b):
    if isinstance(b,dict) and set(b)=={'_decimal'} and not isinstance(a,dict):
        return not isinstance(a,bool) and a is not None and Decimal(str(a))==Decimal(b['_decimal'])
    if isinstance(b,dict) and set(b)=={'_date'} and isinstance(a,str):return a==b['_date']
    if isinstance(a,dict) and isinstance(b,dict):
        if set(a)!=set(b):return False
        return all(equivalent(a[k],b[k]) for k in a)
    if isinstance(a,list) and isinstance(b,list):
        return len(a)==len(b) and all(equivalent(x,y) for x,y in zip(a,b))
    return type(a)==type(b) and a==b


def run(ours,oracle,full=False):
    inventory=json.loads(Path('docs/evidence/compatibility-inventory.json').read_text())
    ledger=str(Path('tests/bql-sources/tables.beancount').resolve())
    cases=[]
    for name,description in inventory['tables'].items():
        cols=re.findall(r'^  (\w+) \(',description,re.M)
        for col in cols:cases.append((ledger,f'SELECT {col} FROM #{name}'))
    cases.extend((ledger,q) for q in ['SELECT * FROM #accounts','SELECT * FROM #commodities','SELECT * FROM #balances','SELECT * FROM #entries',
        "SELECT getitem(meta,'lineno'),getitem(meta,'missing'),getitem(meta,'missing',42) FROM #events",
        "SELECT meta(lower('SITE')) FROM #events", "SELECT balance,balance WHERE account='Assets:Cash'"])
    for file in ['005-balance-fail','006-pad','019-posting-metadata','025-cost-total','044-tolerance-options','059-plugin-auto-basic','063-plugin-implicit-cost']:
        f=str(Path('tests/ledgers/'+file+'.beancount').resolve())
        cases.extend((f,q) for q in ['SELECT id,meta FROM #entries','SELECT entry FROM #postings','SELECT discrepancy FROM #balances'])
    if full:
        for f in sorted(Path('tests/ledgers').glob('*.beancount')):
            if f.name.startswith(('035-','058-')):continue
            ok=subprocess.run([str(Path(oracle)/'bean-check'),str(f)],capture_output=True).returncode==0
            if ok:cases.append((str(f.resolve()),'SELECT id,meta FROM #entries'))
    results=[]
    for f,q in cases:
        a=subprocess.run([ours,'query',f,q,'--json'],capture_output=True,text=True)
        b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',f,q],capture_output=True,text=True)
        try:
            av=json.loads(a.stdout,parse_float=Decimal);bv=json.loads(b.stdout,parse_float=Decimal)
            ok=a.returncode==0 and b.returncode==0 and equivalent(av['rows'],bv)
            detail='' if ok else str((av,bv))[:1200]
        except Exception as e:ok=False;detail=str(e)+a.stdout[-250:]+b.stdout[-250:]
        results.append(dict(ledger=f,query=q,ok=ok,detail=detail))
    return results

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--oracle',default='/tmp/moonbean-r4-oracle/bin');p.add_argument('--ours',default='_build/native/debug/build/cmd/main/main.exe');p.add_argument('--full',action='store_true');a=p.parse_args()
    r=run(a.ours,a.oracle,a.full);print(json.dumps(r,indent=2,default=str));raise SystemExit(any(not x['ok'] for x in r))
