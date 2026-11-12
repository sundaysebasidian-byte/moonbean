"""Independent review regressions, including implicit grouping and period sources."""
import json,subprocess
from pathlib import Path
from bql_object_differential import equivalent
from bql_table_differential import error_category

def compare(ours,oracle,ledger,q):
 a=subprocess.run([ours,'query',ledger,q,'--json'],capture_output=True,text=True)
 b=subprocess.run([str(Path(oracle)/'python'),'scripts/oracle_query_values.py',ledger,q],capture_output=True,text=True)
 try:
  if a.returncode or b.returncode:
   bc=json.loads(b.stdout).get('error_type','');cat='compilation' if bc=='CompilationError' else 'syntax' if bc in ['ParseError','FailedParse'] else 'evaluation'
   ok=a.returncode!=0 and b.returncode!=0 and (error_category(a.stdout+a.stderr,True)==cat or cat=='syntax' and 'HAVING requires' in a.stdout+a.stderr)
  else:ok=equivalent(json.loads(a.stdout)['rows'],json.loads(b.stdout))
 except Exception:ok=False
 return dict(query=q,ok=ok,detail='' if ok else (a.stdout+a.stderr+b.stdout)[-1000:])

def run(ours,oracle):
 queries=[]
 for source in ['#postings','OPEN ON 2024-01-01 CLOSE ON 2024-01-10','OPEN ON 2024-01-06 CLOSE ON 2024-01-31']:
  for projection in ['account,sum(position)','account,count(*)','year(date),count(*)','1,count(*)','count(*),sum(number)']:
   for tail in ['', ' WHERE false',' ORDER BY count(*) DESC']:
    queries.append(f'SELECT {projection} FROM {source}{tail}')
 queries += ['SELECT payee,count(*) FROM transactions','SELECT payee,count(*) FROM transactions ORDER BY payee','SELECT account ORDER BY count(*)','SELECT account,count(*) HAVING count(*)>1','SELECT account,count(*) GROUP BY account HAVING count(*)>1 ORDER BY count(*) DESC','SELECT account,sum(number)+number','SELECT sum(number) WHERE count(*)>0','SELECT account,count(*) WHERE sum(number)>0','SELECT bool(balance)','SELECT round(125.0,-1)','SELECT round(-0.1,-1)']
 results=[compare(ours,oracle,'tests/r9/tx.beancount',q) for q in queries]
 return results
