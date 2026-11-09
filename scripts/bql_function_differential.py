#!/usr/bin/env python3
"""Typed function/aggregate checks against the external oracle process."""
from pathlib import Path
import json,re,subprocess,random
from bql_object_differential import equivalent
from bql_table_differential import error_category

SAMPLES={'decimal':'-1.25','int':'2','bool':'true','str':"'USD'",'date':'2024-01-02','object':"meta('missing')",'any':'position','dict':'meta','set':'tags','list':None,'inventory':'sum(position)','position':'position','amount':'units(position)','*':'*','relativedelta':None}
SPECIAL={'account_sortkey':["'Assets:Cash'"], 'splitcomp':["'a:b:c'","':'",'-1'],'round':['2.55','1'],'root': ["'Assets:Cash'",'2'],'date':['2024','2','29'],'getitem':['meta',"'lineno'",'42'],'substr':["'a😀bc'",'1','3'],'safediv':['1.25','0'],'open_meta':["'Assets:Cash'","'lineno'"],'open_date':["'Assets:Cash'"],'close_date':["'Assets:Cash'"],'commodity_meta':["'USD'","'label'"],'currency_meta':["'USD'","'label'"],'meta':["'lineno'"],'entry_meta':["'lineno'"],'any_meta':["'lineno'"],'date_add':['2024-02-28','2'],'date_diff':['2024-03-01','2024-02-28'],'only':["'USD'",'sum(position)'],'filter_currency':['sum(position)',"'USD'"]}

def run(ours,oracle):
    inventory=json.loads(Path('docs/evidence/compatibility-inventory.json').read_text())
    code=Path('query/types.mbt').read_text().split('fn function_implemented',1)[1].split('///|',1)[0]
    implemented=set(re.findall(r'"([a-z_]+)"',code))
    ledger=str(Path('tests/bql-sources/tables.beancount').resolve())
    queries=[]
    for sig in inventory['functions']+inventory['aggregates']:
        name,args=sig[:-1].split('(');types=args.split(', ') if args else []
        if name not in implemented or any(SAMPLES[t] is None for t in types):continue
        values=[SAMPLES[t] for t in types]
        if name=='sum' and types==['inventory']:values=['balance']
        special=SPECIAL.get(name)
        if name=='round' and types[0]=='int':special=['125','-1'][:len(values)]
        if special and len(special)==len(values):
            # Preserve the overload's declared argument types.
            if name not in ['date','filter_currency'] or name=='date' and len(values)==3 or name=='filter_currency' and types[0]=='inventory':values=special
        if name=='date' and types==['str']:values=["'2024-02-29'"]
        if name=='int' and types==['str']:values=["'١_٢٣'"]
        if name=='decimal' and types==['str']:values=["'１２.３'"]
        expression=name+'('+','.join(values)+')'
        queries.append((sig,'SELECT repr('+expression+") WHERE account='Assets:Cash'"))
    extra=["SELECT repr(sum(number)),repr(sum(balance)),repr(sum(1)),repr(sum(1.0))",
        "SELECT repr(first(meta)),repr(last(entry)),str(sum(position))",
        "SELECT any_meta('receipt'),entry_meta('receipt'),meta('receipt')",
        "SELECT repr(decimal('1e-7')),repr(decimal('١.٢E+٣')),str(decimal('100E+5')),repr(decimal('0E-9'))", "SELECT int('١_٢٣'),decimal('１２.３'),int('1,000'),decimal('1,000'),int('1.5'),int(-1.9)",
        "SELECT date('20240102'),date('2024-W01'),date('2024/01/02'),date(2024,2,30)",
        "SELECT str(tags),repr(tags),length(tags)",
        "SELECT date_add(9999-12-31,1),date_add(0001-01-01,-1),date_add(2000-02-28,1),weekday(0001-01-01)",
        "SELECT decimal(true),int(true),int(meta('missing')),bool(meta('missing'))",
        "SELECT root(account,99999999999999999999),root(account,-99999999999999999999),substr(narration,false,true)", "SELECT date_add(date,99999999999999999999)", "SELECT root(account,true),date_add(date,false)", "SELECT min(tags),max(tags)", "SELECT length(tags) FROM #notes", "SELECT min(meta),max(meta)", "SELECT repr(round(true)),repr(round(false,-1))", "SELECT splitcomp('a:b',':',-1),round(2.5),round(3.5),round(125,-1),repr(round(1.0,-1))", "SELECT splitcomp('a:b',':',9)", "SELECT splitcomp('abc','',0)", "SELECT account_sortkey('Unknown:A')", "SELECT round(1.5,100)", "SELECT upper(1)","SELECT length(meta)","SELECT root(1)","SELECT date(1)","SELECT sum(NULL)","SELECT int(position)","SELECT value(1)","SELECT getitem(meta,1)"]
    # Randomized calendar and finite numeric conversions, independently generated.
    rng=random.Random(20261101)
    for _ in range(40):
        y=rng.randrange(1,9999);m=rng.randrange(1,13);d=rng.randrange(1,28);delta=rng.randrange(-365,366)
        extra.append(f'SELECT repr(date_add({y:04}-{m:02}-{d:02},{delta})),weekday({y:04}-{m:02}-{d:02}),quarter({y:04}-{m:02}-{d:02}),repr(int({rng.randrange(-999999,999999)}.25)) LIMIT 1')
    queries.extend(('extra',q) for q in extra)
    result=[]
    for sig,q in queries:
        a=subprocess.run([ours,'query',ledger,q,'--json'],capture_output=True,text=True)
        b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',ledger,q],capture_output=True,text=True)
        try:
            if a.returncode or b.returncode:
                bc=json.loads(b.stdout).get('error_type','');ac=error_category(a.stdout+a.stderr,True)
                category='compilation' if bc=='CompilationError' else 'syntax' if bc in ['ParseError','FailedParse'] else 'evaluation'
                ok=a.returncode!=0 and b.returncode!=0 and ac==category;detail='' if ok else (a.stdout+a.stderr+b.stdout)[-1000:]
            else:
                av=json.loads(a.stdout)['rows'];bv=json.loads(b.stdout)
                ok=equivalent(av,bv);detail='' if ok else str((av,bv))[:1000]
        except Exception as e:ok=False;detail=str(e)
        result.append(dict(signature=sig,query=q,ok=ok,detail=detail))
    for expression in ["decimal('-0.00')","decimal('NaN')"]:
        q='SELECT '+expression
        a=subprocess.run([ours,'query',ledger,q,'--json'],capture_output=True,text=True)
        b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',ledger,q],capture_output=True,text=True)
        ok=a.returncode!=0 and b.returncode==0 and 'query.unsupported.decimal_representation' in a.stdout+a.stderr
        result.append(dict(query=q,kind='explicit numeric boundary',ok=ok,detail='' if ok else 'numeric rejection changed'))
    return result

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--oracle',default='/tmp/moonbean-r4-oracle/bin');p.add_argument('--ours',default='_build/native/debug/build/cmd/main/main.exe');a=p.parse_args()
    r=run(a.ours,a.oracle);print(json.dumps(r,indent=2));raise SystemExit(any(not x['ok'] for x in r))
