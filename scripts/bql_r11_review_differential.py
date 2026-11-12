#!/usr/bin/env python3
"""R11 reviewer-authored differential probes, reused by the R12 main differential.

Run from the repo root:
  python3 scripts/bql_r11_review_differential.py --oracle /tmp/moonbean-r4-oracle/bin \
      [--ours _build/native/debug/build/cmd/main/main.exe] [--json-out file]

Each case runs against the pinned beanquery worker (black box, public cursor API
only) and against the MoonBean CLI with --json. Compares observable category
(success / compilation / syntax / evaluation / unsupported), exit status, rows
and (for schema cases) column names. 'boundary' cases are documented MoonBean
explicit rejections where the oracle succeeds; they are reported but not
counted as defects. Anything else that differs is a defect.
"""
import argparse
import itertools
import json
import subprocess
import sys
from pathlib import Path
from decimal import Decimal


def equivalent(a, b):
    if isinstance(b, dict) and set(b) == {'_decimal'} and not isinstance(a, dict):
        return not isinstance(a, bool) and a is not None and Decimal(str(a)) == Decimal(b['_decimal'])
    if isinstance(b, dict) and set(b) == {'_date'} and isinstance(a, str):
        return a == b['_date']
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return False
        return all(equivalent(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return False
        if all(equivalent(x, y) for x, y in zip(a, b)):
            return True
        # Set-valued cells have no iteration-order contract (documented in
        # docs/compatibility.md); compare as multisets via canonical forms.
        key = lambda x: json.dumps(x, sort_keys=True, default=str)
        return sorted(a, key=key) == sorted(b, key=key)
    return type(a) == type(b) and a == b


def error_category(text, ours=False):
    if ours:
        try:
            message = json.JSONDecoder().raw_decode(text.lstrip())[0]['error']
            if message.startswith('compilation '):
                return 'compilation'
            if message.startswith('query.oracle_type_error'):
                return 'evaluation'
            if message.startswith(('unsupported ', 'unknown function ', 'unknown FROM source ', 'BALANCES AT supports ')):
                return 'unsupported'
            return 'syntax'
        except (ValueError, KeyError, TypeError):
            pass
    if ours and 'query.oracle_type_error' in text:
        return 'evaluation'
    if 'CompilationError' in text or (ours and ('compilation ' in text or 'query.invalid_column' in text or 'query.invalid_signature' in text or 'query.invalid_aggregate' in text or 'unsupported column' in text)):
        return 'compilation'
    if 'ParseError' in text or 'FailedParse' in text or 'query.invalid_character' in text:
        return 'syntax'
    if ours and 'query.unsupported.' in text:
        return 'unsupported'
    return 'evaluation'


TX = 'tests/r9/tx.beancount'
PRICES = 'tests/r11/prices.beancount'
TABLES = 'tests/ledgers/117-bql-tables.beancount'
PIVOTR = 'tests/r11/pivot-repr.beancount'


def cases():
    out = []

    def add(query, feature, schema=False, ledger=TX):
        out.append(dict(query=query, ledger=ledger, feature=feature, schema=schema))

    # --- nested subqueries (3+ levels, rename chains) ---
    add('SELECT a FROM (SELECT a FROM (SELECT a FROM (SELECT account AS a)))', 'nested')
    add('SELECT a FROM (SELECT a FROM (SELECT a FROM (SELECT account AS a) WHERE a IS NOT NULL))', 'nested')
    add('SELECT a,b FROM (SELECT a,b FROM (SELECT account AS a,currency AS b))', 'nested')
    add('SELECT * FROM (SELECT * FROM (SELECT account AS a,number AS n)) WHERE n>0', 'nested', True)
    add('SELECT * FROM (SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) WHERE n>0) WHERE a~\'^A\'', 'nested', True)
    add('SELECT x FROM (SELECT y AS x FROM (SELECT account AS y))', 'nested')
    add('SELECT * FROM (SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1 ORDER BY 2 DESC LIMIT 1))', 'nested', True)
    add('SELECT * FROM (SELECT * FROM (SELECT * FROM #transactions LIMIT 2))', 'nested', True, TABLES)
    add('SELECT n FROM (SELECT account AS n,number FROM #postings) WHERE n~\'Asset\'', 'nested', ledger=TABLES)
    add('SELECT * FROM (SELECT a FROM (SELECT account AS a) ORDER BY a) ORDER BY 1 DESC', 'nested', True)
    add('SELECT a FROM (SELECT a FROM (SELECT a FROM (SELECT a FROM (SELECT account AS a LIMIT 3))))', 'nested')

    # --- aliases shadowing real column names ---
    add('SELECT number FROM (SELECT account AS number)', 'alias-shadow', True)
    add('SELECT account AS number,number AS account LIMIT 2', 'alias-shadow', True)
    add('SELECT account AS date,date AS account LIMIT 1', 'alias-shadow', True)
    add('SELECT payee AS account,account AS payee FROM #transactions LIMIT 2', 'alias-shadow', True, TABLES)
    add('SELECT account AS number,count(*) FROM #postings GROUP BY number', 'alias-shadow', ledger=TABLES)
    add('SELECT account AS payee,payee AS account GROUP BY payee', 'alias-shadow')
    add('SELECT account AS number,number FROM #postings ORDER BY number LIMIT 3', 'alias-shadow', ledger=TABLES)
    add('SELECT account AS a,account AS b,count(*) GROUP BY 1,2', 'alias-shadow')
    add('SELECT account AS n,count(*) AS c GROUP BY 1 HAVING n>0', 'alias-shadow')
    add('SELECT * FROM (SELECT account AS number) WHERE number~\'Cash\'', 'alias-shadow', True)
    add('SELECT * FROM (SELECT account AS currency,currency AS account) ORDER BY 1 LIMIT 1', 'alias-shadow', True)

    # --- positional refs beyond the R11 grid ---
    add('SELECT account,currency,sum(number),count(*) GROUP BY 1,2 ORDER BY 3 DESC', 'posref')
    add('SELECT a,b,c FROM (SELECT account AS a,currency AS b,sum(number) AS c GROUP BY 1,2) ORDER BY 3 DESC LIMIT 1', 'posref')
    add('SELECT account,currency ORDER BY 0,1', 'posref')
    add('SELECT account,currency ORDER BY 1,0', 'posref')
    add('SELECT account,currency,count(*) GROUP BY 1,2 ORDER BY 5', 'posref')
    add('SELECT * FROM #transactions ORDER BY 1', 'posref', ledger=TABLES)
    add('SELECT * FROM (SELECT account AS a) GROUP BY 1', 'posref', True)
    add('SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) ORDER BY 2', 'posref')
    add('SELECT account,currency,sum(number) GROUP BY 1.5', 'posref')
    add('SELECT account AS a,count(*) AS n GROUP BY 2', 'posref')
    add('SELECT account,currency ORDER BY 01', 'posref')
    add('SELECT account AS a,count(*) AS n GROUP BY 1 ORDER BY -1', 'posref')
    add('SELECT account AS a,count(*) AS n GROUP BY 1 ORDER BY 2,1', 'posref')

    # --- PIVOT: NULL / sparse / duplicate / representation cells ---
    add('SELECT payee,currency,count(*) PIVOT BY 1,2', 'pivot-null')
    add('SELECT payee,number,count(*) PIVOT BY 1,2', 'pivot-null')
    add('SELECT account,currency,sum(number) WHERE account!=\'Assets:Cash\' PIVOT BY 1,2', 'pivot-null')
    add('SELECT account,currency,number PIVOT BY 1,2', 'pivot-dup', PIVOTR)
    add('SELECT currency,number,count(*) PIVOT BY 1,2', 'pivot-dup', PIVOTR)
    add('SELECT number,currency,count(*) PIVOT BY 1,2', 'pivot-dup', PIVOTR)
    add('SELECT account,currency,payee PIVOT BY 1,2', 'pivot-null')
    add('SELECT account,currency,sum(number) FROM #prices PIVOT BY 1,2', 'pivot-null', PRICES)
    add('SELECT upper(account),currency,count(*) PIVOT BY 1,2', 'pivot-null')
    add('SELECT account,currency,sum(number) PIVOT BY 1 DESC,2', 'pivot-null')
    add('SELECT account,currency,sum(number) PIVOT BY 1,2,3', 'pivot-null')
    add('SELECT account AS a,currency,sum(number) AS s PIVOT BY 1,2', 'pivot-null', True)
    add('SELECT account,currency,count(*) PIVOT BY 1,2 LIMIT 2', 'pivot-null')

    # --- aggregate subquery feeding outer WHERE / HAVING / grouping ---
    add('SELECT * FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) WHERE n>0 AND a~\'^Assets\'', 'agg-subquery', True)
    add('SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) WHERE n>=1000 OR a~\'Income\'', 'agg-subquery')
    add('SELECT * FROM (SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1)) WHERE n>0 ORDER BY n DESC', 'agg-subquery', True)
    add('SELECT count(*) FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) WHERE n>0', 'agg-subquery')
    add('SELECT a,count(*) AS c FROM (SELECT account AS a,number AS n) GROUP BY 1 HAVING count(*)>1', 'agg-subquery')
    add('SELECT * FROM (SELECT account AS a,number AS n) WHERE upper(a)~\'ASSET\'', 'agg-subquery', True)
    add('SELECT a,count(*) FROM (SELECT account AS a,currency AS c) GROUP BY 1 ORDER BY 2 DESC', 'agg-subquery')
    add('SELECT sum(n) FROM (SELECT account AS a,sum(number) AS n GROUP BY 1)', 'agg-subquery')
    add('SELECT max(n),min(n),count(*) FROM (SELECT account AS a,sum(number) AS n GROUP BY 1)', 'agg-subquery')
    add('SELECT * FROM (SELECT account AS a,sum(number) AS n GROUP BY 1 HAVING sum(number)>0)', 'agg-subquery', True)

    # --- empty subqueries ---
    add('SELECT count(*) FROM (SELECT account WHERE false)', 'empty-subquery')
    add('SELECT * FROM (SELECT account WHERE false)', 'empty-subquery', True)
    add('SELECT a FROM (SELECT a FROM (SELECT account AS a WHERE false))', 'empty-subquery')
    add('SELECT sum(n) FROM (SELECT number AS n WHERE false)', 'empty-subquery')
    add('SELECT count(*),sum(n) FROM (SELECT account AS a,number AS n WHERE false)', 'empty-subquery')
    add('SELECT * FROM (SELECT * FROM #transactions WHERE false)', 'empty-subquery', True, TABLES)
    add('SELECT * FROM (SELECT account AS a,number AS n WHERE false) WHERE n>0', 'empty-subquery', True)
    add('SELECT a FROM (SELECT account AS a LIMIT 0)', 'empty-subquery')
    add('SELECT count(*) FROM (SELECT account AS a LIMIT 0) WHERE a~\'Asset\'', 'empty-subquery')

    # --- new scalar functions: wrong arity ---
    for query in [
        "SELECT convert(units(position))",
        "SELECT convert(units(position),'USD',2024-01-01,2024-01-02)",
        "SELECT getprice('USD')",
        "SELECT getprice('USD','EUR',2024-01-01,2024-01-02)",
        "SELECT maxwidth('abc')",
        "SELECT maxwidth('abc',5,6)",
        "SELECT date_part('year')",
        "SELECT date_part('year',2024-01-01,2024-01-01)",
        "SELECT date_trunc('year')",
        "SELECT date_trunc()",
        "SELECT joinstr()",
        "SELECT joinstr(tags,',')",
        "SELECT grep('a')",
        "SELECT grep('a','b','c')",
        "SELECT grepn('a','b')",
        "SELECT grepn('a','b',1,2)",
        "SELECT subst('a','b')",
        "SELECT subst('a','b','c','d')",
        "SELECT findfirst('a')",
        "SELECT findfirst()",
        "SELECT has_account()",
        "SELECT has_account('Assets','Cash')",
        "SELECT possign(position)",
        "SELECT value(position,2024-01-01,2024-01-02)",
        "SELECT getprice('USD','EUR',2024-01-01) LIMIT 1",
    ]:
        add(query, 'func-arity', ledger=PRICES)

    # --- new scalar functions: literal NULL args ---
    for query in [
        "SELECT convert(NULL,'USD')",
        "SELECT convert(units(position),NULL)",
        "SELECT getprice(NULL,'USD')",
        "SELECT getprice('USD',NULL)",
        "SELECT getprice(NULL,NULL)",
        "SELECT possign(NULL,'Assets:X')",
        "SELECT possign(2.0,NULL)",
        "SELECT value(NULL)",
        "SELECT value(position,NULL)",
        "SELECT date_part(NULL,2024-01-01)",
        "SELECT date_part('year',NULL)",
        "SELECT date_trunc('year',NULL)",
        "SELECT maxwidth(NULL,5)",
        "SELECT maxwidth('abc',NULL)",
        "SELECT joinstr(NULL)",
        "SELECT grep(NULL,'abc')",
        "SELECT grep('a',NULL)",
        "SELECT grepn('a',NULL,1)",
        "SELECT grepn(NULL,'a',1)",
        "SELECT subst('a','b',NULL)",
        "SELECT subst(NULL,'b','a')",
        "SELECT findfirst('a',NULL)",
        "SELECT findfirst(NULL,tags)",
        "SELECT has_account(NULL)",
    ]:
        add(query, 'func-null', ledger=PRICES)

    # --- new scalar functions: empty-string args ---
    for query in [
        "SELECT maxwidth('',5)",
        "SELECT maxwidth('  ',3)",
        "SELECT grep('','abc')",
        "SELECT grepn('','abc',1)",
        "SELECT subst('a','','abc')",
        "SELECT getprice('','USD')",
        "SELECT getprice('USD','')",
        "SELECT convert(units(position),'')",
        "SELECT possign(2.0,'')",
        "SELECT has_account('')",
        "SELECT date_part('',2024-01-01)",
    ]:
        add(query, 'func-empty', ledger=PRICES)

    # --- new scalar functions: negative / out-of-range numeric args ---
    for query in [
        "SELECT grepn('a(.)','bacd',-1)",
        "SELECT grepn('a','bacd',-5)",
        "SELECT maxwidth('abcdef',-2)",
        "SELECT maxwidth('abcdef',1000000)",
        "SELECT grepn('(a)','a',99)",
        "SELECT convert(neg(sum(position)),'USD')",
        "SELECT value(neg(sum(position)))",
    ]:
        add(query, 'func-negative', ledger=PRICES)

    # --- new scalar functions: unicode args ---
    for query in [
        "SELECT maxwidth('😀中😀中😀中',4)",
        "SELECT grep('中','a中b')",
        "SELECT grepn('(中)','a中b',1)",
        "SELECT subst('中','X','a中b')",
        "SELECT findfirst('中',tags)",
        "SELECT has_account('资产')",
        "SELECT grep('😀','a😀b')",
        "SELECT maxwidth('　中　中　',3)",
        "SELECT getprice('€','USD')",
    ]:
        add(query, 'func-unicode', ledger=PRICES)

    # --- new scalar functions: wrong-type args ---
    for query in [
        "SELECT convert('USD','USD')",
        "SELECT getprice(1,'USD')",
        "SELECT getprice('USD',2.0)",
        "SELECT date_part(2024-01-01,'year')",
        "SELECT date_trunc(2024-01-01,'year')",
        "SELECT maxwidth(5,'abc')",
        "SELECT grepn('a','abc','x')",
        "SELECT has_account(2)",
        "SELECT possign('str','Assets:X')",
        "SELECT possign(position,2)",
        "SELECT value('str')",
        "SELECT joinstr('str')",
        "SELECT subst(1,'a','b')",
        "SELECT findfirst(2,tags)",
        "SELECT grep('a',tags)",
    ]:
        add(query, 'func-type', ledger=PRICES)

    # --- price conversion beyond the R11 grid ---
    for query in [
        "SELECT repr(convert(position,'HOOL'))",
        "SELECT repr(convert(units(position),'EUR'))",
        "SELECT repr(value(position,2024-01-03))",
        "SELECT repr(convert(2.0 USD,'EUR',2024-01-03))",
        "SELECT repr(convert(2.0 HOOL,'USD',2024-01-03))",
        "SELECT repr(convert(2.0 USD,'USD'))",
        "SELECT repr(convert(sum(position),'EUR'))",
        "SELECT repr(value(sum(position),2024-01-05))",
        "SELECT repr(convert(position,'ZERO'))",
    ]:
        add(query, 'func-price', ledger=PRICES)

    # --- relation/schema shapes ---
    add('SELECT * FROM (SELECT account,sum(number) GROUP BY 1)', 'schema', True)
    add('SELECT * FROM (SELECT 1+2 AS x, upper(\'a\') AS y)', 'schema', True)
    add('SELECT x,y FROM (SELECT 1+2 AS x,upper(\'a\') AS y) WHERE x=3', 'schema')
    add('SELECT * FROM (SELECT \'a\' AS "quoted name", 2 AS n)', 'schema', True)
    add('SELECT * FROM (SELECT DISTINCT account) ORDER BY 1', 'schema', True)
    add('SELECT * FROM (SELECT date,meta(\'income\') AS m) WHERE m=\'2024-01\'', 'schema', True)
    add('SELECT a,n FROM (SELECT account AS a,sum(number) AS n GROUP BY 1) ORDER BY a DESC LIMIT 1', 'schema')
    add('SELECT * FROM (SELECT date,account AS a) WHERE year(date)=2024 ORDER BY 1 LIMIT 2', 'schema', True)
    add('SELECT * FROM (SELECT account AS a,currency AS c) WHERE a=\'Assets:Cash\' AND c=\'USD\' LIMIT 2', 'schema', True)
    add('SELECT a,count(*) AS k FROM (SELECT account AS a,number AS n) GROUP BY 1 HAVING count(*)>1', 'schema')
    add('SELECT * FROM (SELECT account AS a ORDER BY a DESC LIMIT 1)', 'schema', True)
    add('SELECT a,n FROM (SELECT account AS a,count(*) AS n GROUP BY 1 ORDER BY 2) ORDER BY 2 DESC', 'schema')
    add('SELECT * FROM (SELECT entry_meta(\'income\') AS m) WHERE m IS NOT NULL', 'schema', True)
    add('SELECT * FROM (SELECT payee AS p,date AS d FROM #transactions) WHERE p IS NOT NULL LIMIT 1', 'schema', True, TABLES)
    add('SELECT * FROM (SELECT account AS a) AS t', 'schema', True)
    add('SELECT * FROM (SELECT account AS a) t', 'schema', True)
    add('SELECT * FROM (SELECT count(*) FROM #postings)', 'schema', True, ledger=TABLES)
    add('SELECT * FROM (SELECT count(*) FROM #transactions)', 'schema', True, ledger=TABLES)
    add('SELECT * FROM (SELECT sum(number) FROM #postings)', 'schema', True, ledger=TABLES)
    add('SELECT * FROM (SELECT account,count(*) FROM #postings GROUP BY 1)', 'schema', True, ledger=TABLES)

    # --- boolean/comparison/NULL/regex projection shapes ---
    add('SELECT payee IS NULL,count(*) FROM #transactions GROUP BY 1', 'predicate', ledger=TABLES)
    add('SELECT number>0 AS p ORDER BY p DESC LIMIT 2', 'predicate')
    add('SELECT * FROM (SELECT number>0 AS p,account AS a) WHERE p LIMIT 2', 'predicate', True)
    add('SELECT account~\'^A\' AS m,count(*) FROM #postings GROUP BY 1', 'predicate', ledger=TABLES)
    add('SELECT payee IS NOT NULL AS p,account FROM #postings ORDER BY 1,2 LIMIT 2', 'predicate', ledger=TABLES)

    # --- documented explicit-boundary markers (oracle succeeds, MoonBean rejects) ---
    # These are claims in docs/compatibility.md; a PASS here means the boundary
    # claim still holds. They are reported separately, not counted as defects.
    for query, why in [
        ("SELECT subst('','x','abc')", 'empty-match substitution'),
        ("SELECT findfirst('',tags)", 'ambiguous empty-pattern set match'),
        ("SELECT joinstr(tags)", 'multi-element set iteration (seed-dependent)'),
        ("SELECT findfirst('a',tags)", 'multi-member set match'),
        ("SELECT maxwidth('a-b-c-d',4)", 'Python hyphen wrapping'),
        ("SELECT date_bin('1 month',2024-03-20,2024-01-15)", 'relativedelta parsing'),
        ("SELECT interval('1 day')", 'relativedelta parsing'),
        ("SELECT parse_date('Feb 29, 2024')", 'strptime parsing'),
        ("SELECT today()", 'no injected clock'),
    ]:
        add(query, 'boundary', ledger=PRICES)
    return out


def run_case(ours, case):
    proc = subprocess.run([ours, 'query', case['ledger'], case['query'], '--json'],
                          capture_output=True, text=True, timeout=30)
    return proc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--oracle', default='/tmp/moonbean-r4-oracle/bin')
    parser.add_argument('--ours', default='_build/native/debug/build/cmd/main/main.exe')
    parser.add_argument('--json-out', help='write machine readable results here')
    args = parser.parse_args()
    probes = cases()
    worker = subprocess.run([str(Path(args.oracle) / 'python'), __file__, '--worker'],
                            input=json.dumps(probes), text=True, capture_output=True, check=True)
    expected_list = json.loads(worker.stdout)
    results = []
    for case, expected in zip(probes, expected_list):
        try:
            proc = run_case(args.ours, case)
        except subprocess.TimeoutExpired:
            results.append(dict(**case, ok=False, defect='timeout>30s', ours='timeout', oracle=expected['category']))
            continue
        actual = json.loads(proc.stdout, parse_float=Decimal) if proc.returncode == 0 else None
        if proc.returncode == 0 and actual is None:
            results.append(dict(**case, ok=False, defect='rc=0 but no JSON',
                                ours='bad-json:' + (proc.stdout + proc.stderr)[:120], oracle=expected['category']))
            continue
        if proc.returncode not in (0, 1):
            results.append(dict(**case, ok=False, defect='crash rc=%d' % proc.returncode,
                                ours='crash', oracle=expected['category']))
            continue
        text = proc.stdout + proc.stderr
        if 'panic' in text or 'abort' in text or 'stack overflow' in text:
            results.append(dict(**case, ok=False, defect='panic/abort in output',
                                ours=text[:120], oracle=expected['category']))
            continue
        category = 'success' if actual is not None else error_category(text, True)
        ok = category == expected['category']
        if ok and category == 'success':
            ok = equivalent(actual['rows'], expected['rows'])
            if not ok:
                results.append(dict(**case, ok=False, defect='rows differ',
                                    ours='rows differ', oracle=expected['category']))
                continue
            if case.get('schema') and actual['columns'] != expected['columns']:
                results.append(dict(**case, ok=False, defect='columns differ: %r vs %r' % (actual['columns'], expected['columns']),
                                    ours=actual['columns'], oracle=expected['columns']))
                continue
        if ok and category != 'success' and proc.returncode != 1:
            results.append(dict(**case, ok=False, defect='error exit status %d' % proc.returncode,
                                ours=category, oracle=expected['category']))
            continue
        results.append(dict(**case, ok=ok, defect='' if ok else 'category %s vs oracle %s' % (category, expected['category']),
                            ours=category, oracle=expected['category']))
    defects = [r for r in results if not r['ok'] and r['feature'] != 'boundary']
    boundaries = [r for r in results if not r['ok'] and r['feature'] == 'boundary']
    passed = [r for r in results if r['ok']]
    print(json.dumps(results, indent=2, default=str))
    print('total=%d pass=%d defects=%d boundary-diffs=%d' % (len(results), len(passed), len(defects), len(boundaries)))
    if args.json_out:
        with open(args.json_out, 'w', encoding='utf-8') as handle:
            json.dump({'total': len(results), 'pass': len(passed), 'defects': len(defects),
                       'boundary_diffs': len(boundaries), 'results': results}, handle, indent=2, default=str)
    sys.exit(1 if defects else 0)


if __name__ == '__main__':
    if '--worker' in sys.argv:
        from beanquery import connect
        from oracle_query_values import encode
        conns = {}
        results = []
        for case in json.load(sys.stdin):
            conn = conns.setdefault(case['ledger'], None)
            if conn is None:
                conn = conns[case['ledger']] = connect('beancount:' + case['ledger'])
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
        main()
