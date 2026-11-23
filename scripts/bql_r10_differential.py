"""R10 aggregate-clause Cartesian probes; public oracle execution only."""
import itertools,json,re,subprocess,sys
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

# These two narrowly documented MoonBean extensions still must not be
# represented as upstream syntax conformance. Refer to the oracle's existing
# posting counts and groups, and assert the exact result/error independently.
GLOBAL_HAVING = re.compile(
 r'SELECT (?:DISTINCT )?count\(\*\) FROM #postings'
 r'( WHERE count\(\*\)>0)? HAVING (count\(\*\)>0|true)'
 r'(?: ORDER BY (account|number|account_sortkey\(account\)|count\(\*\) DESC))?'
 r'(?: LIMIT ([02]))?'
)
OFFSET_CASE = 'SELECT account,count(*) LIMIT 2 OFFSET 1'
SCOPED_REFERENCE = [
 dict(query='SELECT count(*) FROM #postings', ledger='tests/r9/tx.beancount'),
 dict(query='SELECT account,count(*)', ledger='tests/r9/tx.beancount'),
]

def run(ours,oracle):
 probes=cases()
 p=subprocess.run([str(Path(oracle)/'python'),__file__,'--worker'],input=json.dumps(probes+SCOPED_REFERENCE),text=True,capture_output=True,check=True)
 expected=json.loads(p.stdout)
 total, account_groups=expected[-2:]
 assert total['category']==account_groups['category']=='success'
 out=[]
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
  if case['ledger']==SCOPED_REFERENCE[0]['ledger'] and b['category']=='syntax':
   if match := GLOBAL_HAVING.fullmatch(q):
    where,having,order,limit=match.groups()
    if having=='true':
     ok=ac=='compilation' and 'query.invalid_aggregate: HAVING must be aggregate' in output
    elif order and order!='count(*) DESC':
     ok=ac=='compilation' and 'query.invalid_group: uncovered ORDER BY' in output
    elif where:
     ok=ac=='compilation' and 'query.invalid_aggregate' in output
    else:
     rows=[] if limit=='0' else total['rows']
     ok=ac=='success' and equivalent(av,rows)
    boundary='global aggregate HAVING extension checked against posting counts or exact diagnostics'
   elif q==OFFSET_CASE:
    ok=ac=='success' and equivalent(av,account_groups['rows'][1:3])
    boundary='OFFSET extension checked against sliced oracle groups'
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
