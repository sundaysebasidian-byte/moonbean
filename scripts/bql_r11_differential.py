"""R11 public-API oracle probes. No upstream implementation is inspected."""
import itertools
import random
import re
import json
import subprocess
import sys
from pathlib import Path
from bql_object_differential import equivalent
from bql_table_differential import error_category


def cases():
    out = []
    def add(query, feature, schema=False, ledger='tests/r9/tx.beancount'):
        out.append(dict(query=query, ledger=ledger, feature=feature, schema=schema))
    for source in ['#postings', '#transactions', '#notes', '#prices']:
        for tail in ['', ' WHERE false', ' LIMIT 0', ' LIMIT 2']:
            add(f'SELECT * FROM (SELECT * FROM {source}{tail})', 'relation', True,
                'tests/ledgers/117-bql-tables.beancount')
    for inner in ['account AS a,number AS n', 'account AS a,sum(number) AS n GROUP BY 1',
                  'account AS a,count(*) AS n GROUP BY a HAVING count(*)>1 ORDER BY n DESC LIMIT 2']:
        for outer in ['a,n', 'a,sum(n) AS total', 'a,count(*) AS total']:
            for tail in ['', ' WHERE n>0 ORDER BY 1', ' WHERE false']:
                add(f'SELECT {outer} FROM (SELECT {inner}){tail}', 'relation', True)
    for query in [
        'SELECT a FROM (SELECT a FROM (SELECT account AS a LIMIT 2))',
        'SELECT a FROM (SELECT account AS A LIMIT 1)',
        'SELECT a FROM (SELECT account AS a,number AS a LIMIT 2)',
        'SELECT account AS a,number AS a ORDER BY a LIMIT 2',
        'SELECT account AS a WHERE a=1',
        'SELECT account AS a ORDER BY upper(a)',
        'SELECT account AS a,count(*) AS n GROUP BY 1 HAVING n>1',
        'SELECT account FROM (SELECT account) AS t',
        'SELECT account FROM (SELECT account',
        'SELECT account)',
        'SELECT missing FROM (SELECT account)',
        "SELECT meta('x') FROM (SELECT account)",
    ]:
        add(query, 'relation', True)
    for clause in ['GROUP BY', 'ORDER BY']:
        for ref in ['0', '1', '2', '3', '-1', '1.0', 'a', 'n']:
            add(f'SELECT account AS a,count(*) AS n {clause} {ref}', 'reference', True)
    for projection in ['account,currency,sum(number)', 'account AS a,currency AS c,sum(number) AS n,count(*) AS k',
                       'number,currency,count(*)', 'account,currency,number GROUP BY 1,2,3',
                       'account,currency GROUP BY 1,2', 'payee,currency,count(*)']:
        for tail in ['PIVOT BY 1,2', 'PIVOT BY 2,1', 'ORDER BY 1 DESC PIVOT BY 1,2',
                     'PIVOT BY 1,2 LIMIT 1', 'PIVOT BY 1,2 LIMIT 0']:
            add(f'SELECT {projection} {tail}', 'pivot', True)
    for query in [
        'SELECT account,currency,sum(number) WHERE false PIVOT BY 1,2',
        'SELECT account,currency,sum(number) PIVOT BY account,currency',
        'SELECT account AS a,currency AS c,sum(number) PIVOT BY a,c',
        'SELECT account,currency,sum(number) PIVOT BY 0,2',
        'SELECT account,currency,sum(number) PIVOT BY 1,4',
        'SELECT account,currency,sum(number) PIVOT BY 1,1',
        'SELECT account,currency,sum(number) PIVOT BY account,number',
        'SELECT account,currency,sum(number) PIVOT BY 1',
        'SELECT account,currency,sum(number) PIVOT BY 1,2 ORDER BY 1',
        'SELECT account,currency,sum(number) LIMIT 1 PIVOT BY 1,2',
        'SELECT account,currency PIVOT BY 1,2',
        'SELECT * FROM (SELECT account,currency,sum(number) PIVOT BY 1,2)',
    ]:
        add(query, 'pivot', True)
    for expr in ["units(position)", "position", "sum(position)"]:
        for target in ['USD', 'EUR', 'JPY', 'HOOL']:
            for date in ['', ',2024-01-02', ',2023-12-31']:
                expression = f"convert({expr},'{target}'{date})"
                add('SELECT repr('+expression+'),'+expression, 'price', ledger='tests/r11/prices.beancount')
        if expr != 'units(position)':
            for date in ['', ',2024-01-02', ',2023-12-31']:
                expression = f'value({expr}{date})'
                add('SELECT repr('+expression+'),'+expression, 'price', ledger='tests/r11/prices.beancount')
    for base, quote in itertools.product(['USD','EUR','HOOL','ZERO','JPY'], repeat=2):
        for date in ['', ',2024-01-02', ',2024-01-04', ',2023-12-31']:
            add(f"SELECT repr(getprice('{base}','{quote}'{date})) LIMIT 1", 'price', ledger='tests/r11/prices.beancount')
    for expr, account in itertools.product(['2.0','units(position)','position','sum(position)'],
                                         ['Assets:X','Expenses:X','Income:X','Equity:X','Liabilities:X','Unknown:X','assets:X']):
        add(f"SELECT repr(possign({expr},'{account}'))", 'sign', ledger='tests/r11/prices.beancount')
    rng = random.Random(20261111)
    dates = ['0001-01-01','0009-01-01','0099-12-31','1900-03-01','2000-02-29','2021-01-01','9999-12-31']
    dates += [f'{rng.randrange(1,10000):04}-{rng.randrange(1,13):02}-{rng.randrange(1,29):02}' for _ in range(30)]
    for name in ['date_part','date_trunc']:
        for date in dates:
            expressions = [f"repr({name}('{part}',{date}))" for part in
                          ['year','month','day','quarter','week','dow','isodow','epoch','decade','century','millennium','invalid','YEAR']]
            add('SELECT '+','.join(expressions)+' LIMIT 1', 'calendar')
    for text, width in itertools.product(['abcdef','a😀中b','',' a   b cdef ghi ','abcdef ghijkl','a-b-c-d-e-f', 'ab cd ef gh', 'a　b　c'],
                                         [-1,0,1,4,5,6,8,10,100]):
        add(f"SELECT maxwidth('{text}',{width}) LIMIT 1", 'string')
    for expression in ["joinstr(tags)", "findfirst('alpha',tags)", "findfirst('absent',tags)",
                       "grep('a(.)','bacd')", "grepn('a(.)','bacd',1)", "grepn('a(.)','bacd',0)",
                       "grepn('a(.)','bacd',2)", "grepn('a(.)','zzz',2)", "grepn('(a)?b','b',1)",
                       "grep('a','BACD')", "grep('[','abc')", "has_account('assets')", "has_account('cash')", "has_account('absent')"]:
        add('SELECT '+expression, 'regex', ledger='tests/r11/prices.beancount')
    # Exercise every previously unsupported advertised signature with typed inputs,
    # literal NULLs, and invalid argument types. Remaining capability boundaries
    # are recorded separately and never counted as conformance successes.
    old = subprocess.check_output(['git','show','d53b8b5:query/types.mbt'], text=True).split('fn function_implemented',1)[1].split('///|',1)[0]
    supported_before = set(re.findall(r'"([a-z_]+)"',old))
    inventory = json.loads(Path('docs/evidence/compatibility-inventory.json').read_text())
    samples = dict(amount='units(position)', position='position', inventory='sum(position)',
                   str="'USD'", date='2024-01-02', relativedelta="interval('1 day')", set='tags', decimal='1.0', int='1')
    for sig in inventory['functions']:
        name, arguments = sig[:-1].split('(')
        if name in supported_before:
            continue
        types = arguments.split(', ') if arguments else []
        args = [samples[t] for t in types]
        for values in [args, ['NULL' for _ in args], ['true' for _ in args]]:
            add('SELECT '+name+'('+','.join(values)+')', 'signature:'+sig, ledger='tests/r11/prices.beancount')
    for expr in ['number>0','payee IS NULL','payee IS NOT NULL',"payee~'acme'",'NOT payee',
                 'number>0 AND account=account', 'NULL AND true','NULL OR true','NOT NULL',
                 'false AND NULL','false OR NULL', 'true AND NULL','NULL AND false',
                 "meta('missing')=1", 'NULL=1','true=true',"1~'a'", "'x'=1",
                 '(number>0) OR NOT (number>0)', 'sum(number)>0','count(*)=count(*)']:
        add('SELECT '+expr+' AS result', 'predicate', True)
        if 'sum(' not in expr and 'count(' not in expr:
            add('SELECT '+expr+' AS result,count(*) AS n ORDER BY 1', 'predicate', True)
    for expr in ['number>0','payee IS NULL',"payee~'acme'",'NOT payee']:
        add('SELECT * FROM (SELECT '+expr+' AS result) WHERE result ORDER BY 1', 'predicate', True)
    for query in ['SELECT * FROM (SELECT 1 + 2, UPPER( account ),account AS "A B" LIMIT 1)',
                  'SELECT * FROM (SELECT ACCOUNT LIMIT 1)', 'SELECT account AS "account" LIMIT 1',
                  "SELECT account AS 'a' LIMIT 1", "SELECT findfirst('.',tags)",
                  "SELECT has_account('Assets') FROM #transactions", "SELECT has_account('Assets') FROM #entries",
                  "SELECT has_account('Assets') FROM #prices", "SELECT has_account('Assets') FROM (SELECT accounts)"]:
        add(query, 'edge', not any(x in query for x in ['findfirst','has_account']), ledger='tests/r11/prices.beancount')
    for pattern, text in itertools.product(['a(.)','(a)?b','a|ab','(a|ab)+','a*?','a+','^a','$','[a-z]+', '.', '[', '(a)(b)'],
                                         ['ab','b','aba','BACD','😀','']):
        for expression in [f"grep('{pattern}','{text}')", f"grepn('{pattern}','{text}',1)", f"subst('{pattern}','X','{text}')"]:
            add('SELECT '+expression+' LIMIT 1', 'regex')
    return out


def run(ours, oracle):
    probes = cases()
    p = subprocess.run([str(Path(oracle)/'python'), __file__, '--worker'],
                       input=json.dumps(probes), text=True, capture_output=True, check=True)
    results = []
    for case, expected in zip(probes, json.loads(p.stdout)):
        proc = subprocess.run([ours, 'query', case['ledger'], case['query'], '--json'],
                              capture_output=True, text=True)
        actual = json.loads(proc.stdout) if proc.returncode == 0 else None
        category = 'success' if actual is not None else error_category(proc.stdout+proc.stderr, True)
        boundary = None
        if category == 'unsupported':
            if case['query'].startswith(('SELECT date_bin(', 'SELECT interval(', 'SELECT parse_date(', 'SELECT subst(', 'SELECT today(')):
                boundary = 'calendar parser, Python replacement, or clock remains unimplemented'
        if category == 'unsupported' and 'query.unsupported.regex' in proc.stdout:
            boundary = 'Python-only regex/replacement or empty replacement match'
        if category == 'unsupported' and ('query.unsupported.set_representation' in proc.stdout or 'query.unsupported.maxwidth' in proc.stdout):
            boundary = 'Python set iteration or hyphen wrapping remains unsupported'
        ok = category == expected['category']
        if category == expected['category'] == 'success':
            ok = equivalent(actual['rows'], expected['rows'])
            if case['schema']:
                ok = ok and actual['columns'] == expected['columns']
        if category != 'success':
            ok = ok and proc.returncode == 1
            if category in ['syntax','compilation']:
                ok = ok and 'BQL:' in proc.stdout+proc.stderr
        conformant = ok
        if boundary:
            ok = True
        results.append(dict(**case, ok=ok, conformant=conformant, boundary=boundary, ours=category, oracle=expected['category'],
                            detail='' if ok else dict(actual=actual or proc.stdout+proc.stderr, expected=expected)))
    return results


if __name__ == '__main__':
    if '--worker' in sys.argv:
        from beanquery import connect
        from oracle_query_values import encode
        conns = {}
        results = []
        for case in json.load(sys.stdin):
            conn = conns.setdefault(case['ledger'], None)
            if conn is None:
                conn = conns[case['ledger']] = connect('beancount:'+case['ledger'])
            try:
                cursor = conn.execute(case['query'])
                results.append(dict(category='success', columns=[d.name for d in cursor.description],
                                    rows=[[encode(v) for v in row] for row in cursor.fetchall()]))
            except Exception as error:
                name = type(error).__name__
                category = 'compilation' if name == 'CompilationError' else 'syntax' if name in ['ParseError', 'FailedParse'] else 'evaluation'
                results.append(dict(category=category, error=name, message=str(error)))
        print(json.dumps(results))
    else:
        results = run('_build/native/debug/build/cmd/main/main.exe', '/tmp/moonbean-r4-oracle/bin')
        print(json.dumps(results, indent=2))
        sys.exit(any(not case['ok'] for case in results))
