"""Black-box directive-table comparisons, including shared compilation errors."""
import ast
from decimal import Decimal
from pathlib import Path
import re
import subprocess
import conformance as c


def error_category(text, ours=False):
    if ours and 'query.oracle_type_error' in text: return 'evaluation'
    if 'CompilationError' in text or (ours and ('compilation ' in text or 'query.invalid_column' in text or 'query.invalid_signature' in text or 'query.invalid_aggregate' in text or 'unsupported column' in text)):
        return 'compilation'
    if 'ParseError' in text or 'FailedParse' in text or 'query.invalid_character' in text:
        return 'syntax'
    if ours and 'query.unsupported.' in text:
        return 'unsupported'
    return 'evaluation'


def compare(ours, oracle):
    if oracle is None or len(ours['rows']) != len(oracle)-1:
        return False, 'row count or oracle failure'
    for actual, expected in zip(ours['rows'], oracle[1:]):
        if len(actual)!=len(expected): return False, 'column count differs'
        for a, b in zip(actual, expected):
            if isinstance(a, dict) and set(a) == {'number','currency'}:
                m = re.fullmatch(r'\s*([-+]?\d+(?:\.\d+)?)\s+([^\s]+)\s*', b)
                if not m or Decimal(a['number']) != Decimal(m[1]) or a['currency'] != m[2]:
                    return False, 'amount differs'
            elif isinstance(a, list):
                if b == 'frozenset()': values = []
                elif b.startswith('frozenset('): values = ast.literal_eval(b[len('frozenset('):-1])
                else: values = b.split(',') if b else []
                if sorted(a) != sorted(values): return False, 'set differs'
            elif isinstance(a,bool):
                if ("TRUE" if a else "FALSE")!=b:return False,"boolean differs"
            elif isinstance(a,(int,float,Decimal)):
                if Decimal(str(a))!=Decimal(b.strip()):return False,'number differs'
            elif ('' if a is None else str(a)) != b:
                return False, f'scalar differs: {a!r}, {b!r}'
    return True, ''


def run(ours, oracle):
    ledger = str(Path('tests/bql-sources/tables.beancount').resolve())
    projections = {
        'entries': 'type,date,year,month,day,filename,lineno,flag,payee,narration,description,tags,links,accounts',
        'accounts': 'account', 'balances':'date,account,amount,tolerance',
        'commodities':'date,name', 'documents':'date,account,filename,tags,links',
        'events':'date,type,description', 'notes':'date,account,comment,tags,links',
        'prices':'date,currency,amount',
    }
    results=[]
    for table,cols in projections.items():
        for query in [f'SELECT {cols} FROM #{table}', f'SELECT count(*) FROM #{table}',
                      f'SELECT count(*) FROM #{table} WHERE 1 = 0']:
            a = c.ours_query(ours,ledger,query); b = c.oracle_query(oracle,ledger,query)
            ok,detail=compare(a,b) if a else (False,'ours failed')
            if ok and query == f'SELECT {cols} FROM #{table}' and a['columns'] != b[0]:
                ok,detail=False,'source projection column labels differ'
            results.append(dict(query=query,ok=ok,detail=detail))
        query=f'SELECT narration FROM #{table}' if table!='entries' else 'SELECT account FROM #entries'
        a=subprocess.run([ours,'query',ledger,query,'--json'],capture_output=True,text=True)
        b=c.run([str(Path(oracle)/'bean-query'),'-f','csv',ledger,query])
        ac=error_category(a.stdout+a.stderr,True);bc=error_category(b.stdout+b.stderr)
        results.append(dict(query=query,ok=a.returncode!=0 and b.returncode!=0 and ac==bc,detail=f'{ac}/{bc}'))
    for query in ['SELECT year,month,day FROM postings ORDER BY date','SELECT * FROM events','SELECT * FROM prices','SELECT * FROM notes','SELECT * FROM documents',
                  'SELECT type,count(*) FROM entries GROUP BY type ORDER BY type',
                  "SELECT meta('filename'),meta('lineno') FROM entries ORDER BY date",
                  'SELECT name FROM commodities WHERE name = "EUR"',
                  'SELECT count(flag),count(narration) FROM entries',
                  'SELECT first(type),last(type),min(type),max(type) FROM entries',
                  'SELECT min(date),max(date),first(date),last(date) FROM prices']:
        a=c.ours_query(ours,ledger,query);b=c.oracle_query(oracle,ledger,query)
        ok,detail=compare(a,b) if a else (False,'ours failed')
        results.append(dict(query=query,ok=ok,detail=detail))
    query='SELECT count(accounts) FROM entries'
    a=subprocess.run([ours,'query',ledger,query,'--json'],capture_output=True,text=True)
    b=c.run([str(Path(oracle)/'bean-query'),'-f','csv',ledger,query])
    ac=error_category(a.stdout+a.stderr,True);bc=error_category(b.stdout+b.stderr)
    results.append(dict(query=query,ok=a.returncode!=0 and b.returncode!=0 and ac==bc,detail=f'{ac}/{bc}'))
    for query in ['SELECT count(*) GROUP BY tags','SELECT count(*) GROUP BY meta','SELECT count(*) GROUP BY balance','SELECT count(*) GROUP BY entry','SELECT count(*) FROM #accounts GROUP BY open','SELECT count(*) FROM #notes GROUP BY tags','SELECT first(accounts) FROM entries','SELECT upper(accounts) FROM entries',
                  'SELECT sum(date) FROM entries','SELECT sum(type) FROM entries',
                  'SELECT count() FROM entries','SELECT first() FROM entries',
                  'SELECT min(date,date) FROM entries','SELECT sum(count(*)) FROM entries',
                  'SELECT date FROM entries WHERE count(*) > 0',
                  'SELECT count(*) FROM entries GROUP BY count(*)']:
        a=subprocess.run([ours,'query',ledger,query,'--json'],capture_output=True,text=True)
        b=c.run([str(Path(oracle)/'bean-query'),'-f','csv',ledger,query])
        ac=error_category(a.stdout+a.stderr,True);bc=error_category(b.stdout+b.stderr)
        results.append(dict(query=query,ok=a.returncode!=0 and b.returncode!=0 and ac==bc,detail=f'{ac}/{bc}'))
    query='SELECT filename,lineno FROM #entries ORDER BY lineno'
    relative='tests/bql-sources/tables.beancount'
    a=c.ours_query(ours,relative,query);b=c.oracle_query(oracle,relative,query)
    ok,detail=compare(a,b) if a else (False,'ours failed')
    results.append(dict(query=query,ok=ok,detail=detail))
    query='SELECT currency,sum(amount) FROM prices GROUP BY currency'
    a=c.ours_query(ours,ledger,query);b=c.oracle_query(oracle,ledger,query)
    ok,detail=c.compare_units_query(a,b) if a else (False,'ours failed')
    results.append(dict(query=query,ok=ok,detail=detail))
    query='SELECT sum(tolerance) FROM #balances'
    assertion='tests/bql-sources/assertion.beancount'
    a=c.ours_query(ours,assertion,query);b=c.oracle_query(oracle,assertion,query)
    ok,detail=compare(a,b) if a else (False,'ours failed')
    results.append(dict(query=query,ok=ok,detail=detail))
    query='SELECT count(*) GROUP BY tags'
    grouped_ledger=str(Path('tests/bql-sources/set-groups.beancount').resolve())
    a=subprocess.run([ours,'query',grouped_ledger,query,'--json'],capture_output=True,text=True)
    b=c.run([str(Path(oracle)/'bean-query'),'-f','csv',grouped_ledger,query])
    ac=error_category(a.stdout+a.stderr,True);bc=error_category(b.stdout+b.stderr)
    results.append(dict(query=query,ledger=grouped_ledger,ok=a.returncode!=0 and b.returncode!=0 and ac==bc=='compilation',detail=f'{ac}/{bc}'))
    return results
