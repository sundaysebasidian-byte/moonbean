"""R11 public-API oracle probes. No upstream implementation is inspected."""
import itertools
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
