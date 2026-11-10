"""Public oracle type probes: vary each argument of every advertised signature."""
import json,subprocess,sys
from pathlib import Path
from bql_table_differential import error_category

def cases():
 inv=json.loads(Path('docs/evidence/compatibility-inventory.json').read_text())
 samples={'str':"'USD'",'int':'1','decimal':'1.25','bool':'true','date':'2024-01-02','dict':'meta','set':'tags','inventory':'balance','position':'position','amount':'units(position)','any':'position','object':"meta('missing')",'list':"getitem(entry_meta(),'x')",'relativedelta':"interval('1d')"}
 variants=dict(samples,nonetype='NULL',record='entry',frozenset='tags')
 out={}
 for sig in inv['functions']:
  name,args=sig[:-1].split('(');types=args.split(', ') if args else []
  base=[samples[t] for t in types]
  for i in range(max(1,len(types))):
   for kind,value in variants.items():
    values=base.copy()
    if types:values[i]=value
    q='SELECT '+name+'('+','.join(values)+') LIMIT 1'
    out.setdefault(q,dict(signatures=[],argument=i,type=kind,query=q))['signatures'].append(sig)
 return list(out.values())

def run(ours,oracle):
 probes=cases();ledger='tests/bql-sources/tables.beancount'
 worker=subprocess.run([str(Path(oracle)/'python'),__file__,'--worker',ledger],input=json.dumps([p['query'] for p in probes]),text=True,capture_output=True,check=True)
 expected=json.loads(worker.stdout);out=[]
 for p,bc in zip(probes,expected):
  a=subprocess.run([ours,'query',ledger,p['query'],'--json'],capture_output=True,text=True)
  ac='success' if a.returncode==0 else error_category(a.stdout+a.stderr,True)
  p.update(oracle=bc,ours=ac,permissive=bc!='success' and ac=='success',classification_match=bc==ac)
  out.append(p)
 return out
if __name__=='__main__':
 if '--worker' in sys.argv:
  from beanquery import connect
  c=connect('beancount:'+sys.argv[-1]);results=[]
  for q in json.load(sys.stdin):
   try:c.execute(q).fetchall();results.append('success')
   except Exception as e:results.append('compilation' if type(e).__name__=='CompilationError' else 'syntax' if type(e).__name__ in ['ParseError','FailedParse'] else 'evaluation')
  print(json.dumps(results))
 else:
  r=run('_build/native/debug/build/cmd/main/main.exe','/tmp/moonbean-r4-oracle/bin');print(json.dumps(r,indent=2));sys.exit(any(x['permissive'] for x in r))
