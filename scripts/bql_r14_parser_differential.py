#!/usr/bin/env python3
"""R13 review classifications and R14 syntax/value/diagnostic regressions."""
import json
import re
import subprocess
import sys
from decimal import Decimal
from pathlib import Path

from bql_r11_review_differential import equivalent

ROOT = Path(__file__).resolve().parents[1]
QUERY = 'SELECT meta,lineno,type,id FROM #entries ORDER BY lineno'


def worker(paths):
    from beancount.loader import load_file
    from beancount.parser.printer import print_entries
    from beanquery import connect
    from io import StringIO
    from oracle_query_values import encode
    rows = []
    for path in paths:
        entries, errors, _ = load_file(path)
        printed = StringIO()
        print_entries(entries, file=printed)
        cursor = connect('beancount:' + path).execute(QUERY)
        rows.append(dict(printed=printed.getvalue(), rows=[[encode(v) for v in row] for row in cursor.fetchall()],
                         diagnostics=[dict(kind=type(e).__name__, line=e.source.get('lineno'), message=e.message) for e in errors]))
    return rows


def run(ours, oracle):
    results = []
    review = json.loads((ROOT / 'tests/r14/review/cases.json').read_text())
    for case in review:
        path = ROOT / case['ledger']
        a = subprocess.run([ours, 'check', str(path)], capture_output=True, text=True, timeout=30)
        b = subprocess.run([str(Path(oracle) / 'bean-check'), str(path)], capture_output=True, text=True, timeout=30)
        conformant = a.returncode == b.returncode
        boundary = case['boundary']
        ok = (conformant if boundary is None else a.returncode == 0 and b.returncode == 1)
        ok = ok and b.returncode == case['oracle_initial_exit']
        results.append(dict(feature='r14-review-classification', ledger=case['ledger'], ok=ok,
                            conformant=conformant, boundary=boundary, ours_exit=a.returncode, oracle_exit=b.returncode,
                            ours=a.stdout+a.stderr, oracle=b.stdout+b.stderr))
    cases = json.loads((ROOT / 'tests/r14/parser-cases.json').read_text())
    cache = ROOT / '.oracle-cache/r14/parser-corpus'
    cache.mkdir(parents=True, exist_ok=True)
    paths = []
    for case in cases:
        path = cache / (case['name'] + '.beancount')
        path.write_bytes(case['source'].replace('{{repo}}', str(ROOT)).encode())
        paths.append(str(path))
    process = subprocess.run([str(Path(oracle) / 'python'), __file__, '--worker'],
                             input=json.dumps(paths), capture_output=True, text=True, check=True, timeout=180)
    for case, path, expected in zip(cases, paths, json.loads(process.stdout)):
        a = subprocess.run([ours, 'check', path], capture_output=True, text=True, timeout=30)
        b = subprocess.run([str(Path(oracle) / 'bean-check'), path], capture_output=True, text=True, timeout=30)
        results.append(dict(feature='r14-parser-check', case=case['name'], ok=a.returncode == b.returncode,
                            ours_exit=a.returncode, oracle_exit=b.returncode,
                            ours=a.stdout+a.stderr, oracle=b.stdout+b.stderr, oracle_diagnostics=expected['diagnostics']))
        # Syntax failures use the same parse family. Lexical string failures also
        # compare the physical source line, including multiline continuations.
        if expected['diagnostics']:
            lexical = [e for e in expected['diagnostics'] if e['kind'] == 'LexerError']
            ok = all((':'+str(e['line'])+': parse.token:') in a.stderr for e in lexical)
            expected_families = {'parse' if e['kind'] in ['LexerError','ParserSyntaxError'] else 'document' if e['kind'] == 'DocumentError' else 'validation' for e in expected['diagnostics']}
            actual_families = {'parse' if code.startswith('parse.') else 'document' if code == 'validation.document_missing' else 'validation' for code in re.findall(r': ((?:parse|validation)\.[^: ]+):', a.stderr)}
            ok = ok and actual_families == expected_families
            results.append(dict(feature='r14-parser-diagnostic', case=case['name'], ok=ok,
                                ours_families=sorted(actual_families),oracle_families=sorted(expected_families),
                                ours=a.stderr, oracle=expected['diagnostics']))
        printed = subprocess.run([ours, 'query', path, 'PRINT'], capture_output=True, timeout=30)
        results.append(dict(feature='r14-parser-print', case=case['name'],
                            ok=printed.returncode == 0 and printed.stdout == expected['printed'].encode(),
                            ours=printed.stdout.decode(errors='replace'), oracle=expected['printed']))
        query = subprocess.run([ours, 'query', path, QUERY, '--json'], capture_output=True, text=True, timeout=30)
        actual = json.loads(query.stdout, parse_float=Decimal) if query.returncode == 0 else None
        ok = actual is not None and len(actual['rows']) == len(expected['rows'])
        if ok:
            ok = all(len(a) == len(b) and all(equivalent(x,y) for x,y in zip(a,b))
                     for a,b in zip(actual['rows'],expected['rows']))
        results.append(dict(feature='r14-parser-values', case=case['name'], ok=ok,
                            ours=actual or query.stdout+query.stderr, oracle=expected['rows']))
        if not expected['diagnostics']:
            formatted = subprocess.run([ours, 'fmt', path], capture_output=True, timeout=30)
            original = Path(path).read_bytes()
            try:
                Path(path).write_bytes(formatted.stdout)
                after = subprocess.run([ours, 'query', path, QUERY, '--json'], capture_output=True, text=True, timeout=30)
                value = json.loads(after.stdout, parse_float=Decimal) if after.returncode == 0 else None
                equal = formatted.returncode == 0 and value is not None and len(value['rows']) == len(actual['rows'])
                if equal:
                    equal = all(len(a) == len(b) and all(equivalent(x,y) for x,y in zip(a,b)) for a,b in zip(value['rows'],actual['rows']))
                results.append(dict(feature='r14-parser-format', case=case['name'], ok=equal,
                                    ours=value, expected=actual))
            finally:
                Path(path).write_bytes(original)

    return results


if __name__ == '__main__':
    if '--worker' in sys.argv:
        print(json.dumps(worker(json.load(sys.stdin)), ensure_ascii=False))
    else:
        rows = run(sys.argv[1] if len(sys.argv)>1 else '_build/native/release/build/cmd/main/main.exe',
                   '/tmp/moonbean-r4-oracle/bin')
        print(json.dumps(rows, indent=2, default=str, ensure_ascii=False))
        sys.exit(any(not r['ok'] for r in rows))
