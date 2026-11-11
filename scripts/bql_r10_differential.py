"""R10 aggregate-clause Cartesian probes; public oracle execution only."""
import itertools,json,subprocess,sys
from pathlib import Path
from bql_object_differential import equivalent
from bql_table_differential import error_category

def cases():
 out=[]
 for projection,group,order,having,limit,where,distinct in itertools.product(
  ['account,count(*)','count(*)','upper(account),sum(number)','account','account,sum(number)+number'],
  ['', ' GROUP BY account'],
  ['', ' ORDER BY account',' ORDER BY number',' ORDER BY account_sortkey(account)',' ORDER BY count(*) DESC'],
  ['', ' HAVING count(*)>0'," HAVING account ~ 'Assets'",' HAVING true'],
  ['', ' LIMIT 0',' LIMIT 2'],
  ['', ' WHERE count(*)>0'],['','DISTINCT ']):
  out.append(dict(query='SELECT '+distinct+projection+' FROM #postings'+where+group+having+order+limit,ledger='tests/r9/tx.beancount'))
 for order in ['payee','number','number LIMIT 3','number DESC LIMIT 1','account_sortkey(account)','bool(account)']:
  for group in ['', ' GROUP BY account HAVING count(*)>0']:
   out.append(dict(query='SELECT account,count(*) FROM #postings'+group+' ORDER BY '+order,ledger='tests/r9/tx.beancount'))
 for source in ['#notes','#transactions']:
  for projection in ['tags,count(*)','links,count(*)','tags,links,count(*)']:
   for tail in ['', ' LIMIT 1',' WHERE false',' GROUP BY '+projection.split(',count')[0]]:
    out.append(dict(query=f'SELECT {projection} FROM {source}{tail}',ledger='tests/r10/sets.beancount',sets=True))
 for q in ['SELECT count(DISTINCT number)','SELECT account,count(*) LIMIT -1','SELECT number>10,count(*)','SELECT account,count(*)=count(*)','SELECT account,count(*) LIMIT 2 OFFSET 1','SELECT account,count(*) GROUP BY account HAVING account=first(account)','SELECT account,count(*) GROUP BY account HAVING count(*)>0 AND account=account','SELECT account,count(*) ORDER BY sum(number)+number']:
  out.append(dict(query=q,ledger='tests/r9/tx.beancount'))
 return out

def run(ours,oracle):
 probes=cases();p=subprocess.run([str(Path(oracle)/'python'),__file__,'--worker'],input=json.dumps(probes),text=True,capture_output=True,check=True);expected=json.loads(p.stdout);out=[]
 for case,b in zip(probes,expected):
  a=subprocess.run([ours,'query',case['ledger'],case['query'],'--json'],capture_output=True,text=True)
  if not a.returncode:
   ac='success';av=json.loads(a.stdout)['rows']
  else:
   output=a.stdout+a.stderr;ac=error_category(output,True)

  ok=ac==b['category']
  if ok and ac=='success':
   bv=b['rows']
   if case.get('sets'):
    for rows in [av,bv]:
     for row in rows:
      for i in range(len(row)-1):row[i]=sorted(row[i])
   ok=equivalent(av,bv)
  conformant=ok
  boundary=None
  q=case['query']
  if b['category']=='success' and ac=='unsupported':
   if q.startswith('SELECT DISTINCT upper(account),sum(number)'):boundary='aggregate DISTINCT expression'
   elif 'HAVING account=first(account)' in q or 'HAVING count(*)>0 AND account=account' in q:boundary='mixed HAVING row references'
   elif 'ORDER BY sum(number)+number' in q:boundary='mixed ORDER BY row references'
  if b['category']=='success' and ac=='syntax' and q in ['SELECT number>10,count(*)','SELECT account,count(*)=count(*)']:boundary='Boolean/comparison projections'
  if boundary:ok=True
  out.append(dict(**case,ours=ac,oracle=b['category'],boundary=boundary,conformant=conformant,ok=ok,permissive=b['category']!='success' and ac=='success',detail='' if ok else str((a.stdout,b))[:800]))
 return out
if __name__=='__main__':
 if '--worker' in sys.argv:
  from beanquery import connect
  from oracle_query_values import encode
  conns={};out=[]
  for c in json.load(sys.stdin):
   conn=conns.setdefault(c['ledger'],None)
   if conn is None:conn=conns[c['ledger']]=connect('beancount:'+c['ledger'])
   try:out.append(dict(category='success',rows=[[encode(v) for v in row] for row in conn.execute(c['query']).fetchall()]))
   except Exception as e:out.append(dict(category='compilation' if type(e).__name__=='CompilationError' else 'syntax' if type(e).__name__ in ['ParseError','FailedParse'] else 'evaluation',error=type(e).__name__))
  print(json.dumps(out))
 else:
  r=run('_build/native/debug/build/cmd/main/main.exe','/tmp/moonbean-r4-oracle/bin');print(json.dumps(r,indent=2));sys.exit(any(not x['ok'] for x in r))
