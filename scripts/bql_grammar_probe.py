#!/usr/bin/env python3
"""Black-box language inventory probes, independently authored; no grammar source."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--oracle',default='/tmp/moonbean-r4-oracle/bin');p.add_argument('--out',default='docs/evidence/r2-final-grammar.json');a=p.parse_args()
ops=['+','-','*','/','%','//','^','**','&','|','<<','>>','=','==','!=','<>','<','<=','>','>=','IN','NOT IN','BETWEEN','AND','OR','XOR','IS','IS NOT','~','!~','?~','LIKE','ILIKE','||']
queries=['SELECT 1 '+op+' '+(' (1,2)' if 'IN' in op else '2') for op in ops]
queries += ["SELECT account WHERE number "+op+" "+('(1,2)' if 'IN' in op else '2') for op in ops]
queries += ['SELECT NOT true','SELECT NULL IS NULL','SELECT 1 BETWEEN 0 AND 2',"SELECT 'a' ~ 'a'", "SELECT 'a'||'b'", 'SELECT DISTINCT position','SELECT date AS d','SELECT date GROUP BY 1','SELECT date ORDER BY 1',
    'SELECT account FROM (SELECT account)','SELECT account,currency,sum(number) GROUP BY account,currency PIVOT BY 1,2',
    'SELECT sum(position) FLATTEN','SELECT FLATTEN sum(position)','SELECT DISTINCT FLATTEN sum(position)','SELECT sum(position) FROM FLATTEN',
    'SELECT sum(position) FROM CLOSE','SELECT accounts FROM OPEN ON 2024-01-02 CLOSE ON 2024-02-01 CLEAR','SELECT account FROM accounts',
    'SELECT account FROM postings JOIN transactions','SELECT account WHERE account LIKE "Assets%"', 'BALANCES','JOURNAL','PRINT','PRINT FROM year=2024','EXPLAIN SELECT date','.explain SELECT date']
ledger=str(Path('tests/bql-sources/tables.beancount').resolve());rows=[]
for q in queries:
 cmd=[str(Path(a.oracle)/'bean-query'),'-f','csv',ledger,q]
 r=subprocess.run(cmd,capture_output=True,text=True)
 stderr=r.stderr
 if 'Traceback (most recent call last)' in stderr:stderr=stderr.strip().splitlines()[-1]
 rows.append(dict(query=q,exit=r.returncode,stdout=r.stdout,stderr=stderr))
Path(a.out).write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print(len(rows),'grammar probes,',sum(r['exit']==0 for r in rows),'accepted; probe coverage is not grammar completeness')
