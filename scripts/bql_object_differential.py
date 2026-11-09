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
    cases.extend((ledger,q) for q in ['SELECT * FROM #accounts','SELECT * FROM #commodities','SELECT * FROM #balances','SELECT * FROM #entries','SELECT DISTINCT position','SELECT DISTINCT first(position) GROUP BY date',
        "SELECT getitem(meta,'lineno'),getitem(meta,'missing'),getitem(meta,'missing',42) FROM #events",
        "SELECT meta(lower('SITE')) FROM #events", "SELECT balance,balance WHERE account='Assets:Cash'"])
    for file in ['024-cost-per','025-cost-total','118-note-stacks','119-cost-tolerance','120-numeric-metadata','005-balance-fail','006-pad','019-posting-metadata','025-cost-total','044-tolerance-options','059-plugin-auto-basic','063-plugin-implicit-cost']:
        f=str(Path('tests/ledgers/'+file+'.beancount').resolve())
        cases.extend((f,q) for q in ['SELECT id,meta FROM #entries','SELECT entry FROM #postings','SELECT discrepancy FROM #balances', 'SELECT DISTINCT position','SELECT DISTINCT position,account','SELECT repr(position),str(units(position))'])
    if full:
        for f in sorted(Path('tests/ledgers').glob('*.beancount')):
            if f.name.startswith(('035-','058-')):continue
            ok=subprocess.run([str(Path(oracle)/'bean-check'),str(f)],capture_output=True).returncode==0
            if ok:cases.append((str(f.resolve()),'SELECT id,meta FROM #entries'))
    ordering=str(Path('tests/bql-sources/value-order.beancount').resolve())
    cases.extend((ordering,q) for q in ["SELECT str(sum(position)),repr(sum(position)) WHERE account='Assets:Cash'", "SELECT min(position),max(position),min(units(position)),max(units(position))"])
    cases.append((str(Path('tests/bql-sources/metadata.beancount').resolve()),"SELECT position,count(*) WHERE account='Assets:Cash' GROUP BY position"))
    cases.append((str(Path('tests/bql-sources/meta-groups.beancount').resolve()),"SELECT count(*) FROM #events GROUP BY meta('value')"))
    cases.append((str(Path('tests/bql-sources/value-order.beancount').resolve()),"SELECT position FROM #postings ORDER BY position"))
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
    boundary=Path('.oracle-cache/r2-last/signed-zero.beancount').resolve()
    boundary.parent.mkdir(parents=True,exist_ok=True)
    boundary.write_text('2024-01-01 event "kind" "value"\n  signed: -0.00\n')
    query='SELECT id,meta FROM #entries'
    a=subprocess.run([ours,'query',str(boundary),query,'--json'],capture_output=True,text=True)
    b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',str(boundary),query],capture_output=True,text=True)
    ok=a.returncode!=0 and b.returncode==0 and 'query.unsupported.decimal_representation' in a.stdout+a.stderr
    results.append(dict(query=query,kind='explicit signed-zero boundary',ok=ok,detail='' if ok else 'signed-zero rejection changed'))
    query='SELECT DISTINCT position'
    a=subprocess.run([ours,'query',str(boundary),query,'--json'],capture_output=True,text=True)
    b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',str(boundary),query],capture_output=True,text=True)
    ok=a.returncode!=0 and b.returncode==0 and 'query.unsupported.decimal_representation' in a.stdout+a.stderr
    results.append(dict(query=query,kind='explicit signed-zero distinct boundary',ok=ok,detail='' if ok else 'signed-zero distinct rejection changed'))
    return results

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--oracle',default='/tmp/moonbean-r4-oracle/bin');p.add_argument('--ours',default='_build/native/debug/build/cmd/main/main.exe');p.add_argument('--full',action='store_true');a=p.parse_args()
    r=run(a.ours,a.oracle,a.full);print(json.dumps(r,indent=2,default=str));raise SystemExit(any(not x['ok'] for x in r))
