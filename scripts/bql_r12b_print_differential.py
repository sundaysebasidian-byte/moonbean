"""R12-B PRINT byte differential (independent of bql_r12_differential r12-print-bytes)."""
import glob, json, subprocess, sys, os
from concurrent.futures import ThreadPoolExecutor
ROOT = str(__import__("pathlib").Path(__file__).resolve().parents[1])
OURS = ROOT + "/_build/native/debug/build/cmd/main/main.exe"
ORACLE = "/tmp/moonbean-r4-oracle/bin/bean-query"
QUERIES = [
 "PRINT", "print", "PRINT FROM true", "PRINT FROM NULL", "PRINT FROM 1", "PRINT FROM 0",
 "PRINT FROM type = 'open'", "PRINT FROM type = 'close'", "PRINT FROM type = 'balance'", "PRINT FROM type = 'pad'",
 "PRINT FROM type = 'note'", "PRINT FROM type = 'document'", "PRINT FROM type = 'event'", "PRINT FROM type = 'query'",
 "PRINT FROM type = 'custom'", "PRINT FROM type = 'commodity'", "PRINT FROM type = 'price'", "PRINT FROM type != 'transaction'",
 "PRINT FROM type ~ 'o'", "PRINT FROM year = 2024", "PRINT FROM year >= 2025", "PRINT FROM month = 1", "PRINT FROM day > 15",
 "PRINT FROM date < 2024-01-05", "PRINT FROM date BETWEEN 2024-01-02 AND 2024-01-10", "PRINT FROM date = 2024-01-04",
 "PRINT FROM flag = '!'", "PRINT FROM flag = '*'", "PRINT FROM flag IS NULL", "PRINT FROM flag IS NOT NULL",
 "PRINT FROM payee IS NOT NULL", "PRINT FROM payee ~ 'a'", "PRINT FROM narration ~ '(?i)buy'", "PRINT FROM narration = ''",
 "PRINT FROM description ~ 'e'", "PRINT FROM length(narration) > 40", "PRINT FROM 'coffee' IN tags", "PRINT FROM 'trip' IN tags",
 "PRINT FROM length(tags) > 0", "PRINT FROM length(links) > 0", "PRINT FROM 'sale' IN links", "PRINT FROM NOT ('coffee' IN tags)",
 "PRINT FROM year = 2024 AND month = 1", "PRINT FROM year = 2023 OR day = 1", "PRINT FROM NOT type = 'open'",
 "PRINT FROM id IS NOT NULL", "PRINT FROM lineno > 10", "PRINT FROM filename ~ 'beancount'",
 "PRINT FROM entry_meta('bank') IS NOT NULL", "PRINT FROM meta('memo') IS NOT NULL", "PRINT FROM str(date) ~ '-01-'",
 "PRINT FROM OPEN ON 2024-01-05", "PRINT FROM CLOSE ON 2024-01-10", "PRINT FROM CLOSE", "PRINT FROM CLEAR",
 "PRINT FROM OPEN ON 2024-01-05 CLOSE ON 2024-01-15 CLEAR", "PRINT FROM year=2024 OPEN ON 2024-02-01",
 "PRINT FROM OPEN ON 2023-01-01", "PRINT FROM CLOSE ON 2030-01-01", "PRINT FROM OPEN ON 2024-01-01 CLOSE ON 2024-01-01",
 "PRINT FROM year = 2024 CLOSE ON 2024-01-08 CLEAR", "PRINT FROM type='transaction' CLEAR",
 "PRINT FROM date > 2024-01-03 OPEN ON 2024-01-03", "PRINT FROM ANY_META('bank') IS NOT NULL",
 "PRINT FROM year IN (2023, 2024)", "PRINT FROM month IN (1,2,3) AND flag = '*'",
 "PRINT FROM date >= 2024-12-01", "PRINT FROM day = 31", "PRINT FROM upper(type) = 'TRANSACTION'",
 "PRINT FROM narration ~ 'é|日|😀'", "PRINT FROM coalesce(payee, '') = ''", "PRINT FROM weekday(date) = 'Mon'",
 "PRINT FROM date_bin('1 month', date, 2024-01-01) = 2024-01-01", "PRINT FROM date >= parse_date('2024-01-05')",
 "PRINT FROM date < today()", "PRINT FROM date + interval('1 day') > 2024-01-10",
 "PRINT FROM  year  =  2024  ", "PRINT\tFROM\ttrue", "PRINT FROM (year = 2024)", "PRINT FROM type = 'transaction' AND NOT flag = '*'",
 "PRINT FROM year = 2024 OPEN ON 2024-01-04 CLOSE CLEAR",
]
QUERIES += ["PRINT FROM narration='One' CLEAR", "PRINT FROM date>=2024-01-05 CLEAR", "PRINT FROM narration='One' OPEN ON 2024-01-03"]

def ledgers():
    pats = ["tests/ledgers/*.beancount", "tests/r9/*.beancount", "tests/r11/*.beancount", "tests/r12/*.beancount",
            "examples/*.beancount", "examples/*/*.beancount"]
    out = []
    for p in pats: out += sorted(glob.glob(os.path.join(ROOT, p)))
    out += sorted(glob.glob(os.path.join(ROOT, "tests/r12/review-b/*.beancount")))
    out = [p for p in out if not os.path.basename(p).startswith(("035-", "058-"))]
    return out
def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=60, cwd=ROOT)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return "timeout", b""
def one(arg):
    led, q = arg
    a = run([OURS, "query", led, q]); b = run([ORACLE, led, q])
    return dict(ledger=os.path.relpath(led, ROOT), query=q, ours_rc=a[0], oracle_rc=b[0],
                ok=(a[0] == b[0] or (a[0] != 0 and b[0] != 0)) and (a[1] == b[1] or b[0] != 0),
                ours=a[1].decode(errors="replace"), oracle=b[1].decode(errors="replace"))
def run_corpus(ours, oracle, cli=False):
    global OURS, ORACLE
    from pathlib import Path
    from bql_table_differential import error_category
    OURS, ORACLE = ours, os.path.join(oracle, 'bean-query')
    if cli:
        work = [(l, q) for l in ledgers() for q in QUERIES]
        with ThreadPoolExecutor(8) as ex:
            return list(ex.map(one, work))
    def ledger_cases(ledger):
        cases = [dict(ledger=ledger, query=q) for q in QUERIES]
        worker = subprocess.run([str(Path(oracle)/'python'), str(Path(__file__).with_name('bql_r12b_print_worker.py'))],
                                input=json.dumps(cases), capture_output=True, text=True, check=True, timeout=180)
        expected = json.loads(worker.stdout)
        results = []
        for case, b in zip(cases, expected):
            p = subprocess.run([ours, 'query', ledger, case['query']], capture_output=True, timeout=30)
            actual_category = 'success' if p.returncode == 0 else error_category((p.stdout+p.stderr).decode(errors='replace'), True)
            expected_category = ('success' if b['exit'] == 0 else 'compilation' if b['error'] == 'CompilationError'
                                 else 'syntax' if b['error'] in ['ParseError','FailedParse'] else 'evaluation')
            equal = p.returncode == b['exit'] and actual_category == expected_category
            if equal and b['exit'] == 0:
                equal = p.stdout == b['output'].encode()
            results.append(dict(ledger=os.path.relpath(ledger, ROOT), query=case['query'], feature='review-b-print',
                                ours_rc=p.returncode, oracle_rc=b['exit'], ok=equal, conformant=equal,
                                ours=p.stdout.decode(errors='replace'), oracle=b['output'],
                                detail='' if equal else dict(ours_category=actual_category, oracle_category=expected_category,
                                                             ours_error=p.stderr.decode(errors='replace'), oracle_error=b.get('message'))))
        return results
    with ThreadPoolExecutor(8) as ex:
        return [case for group in ex.map(ledger_cases, ledgers()) for case in group]

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--ours', default=OURS)
    parser.add_argument('--oracle', default=os.path.dirname(ORACLE))
    parser.add_argument('--cli', action='store_true', help='Run the original per-case oracle CLI comparison')
    args = parser.parse_args()
    results = run_corpus(args.ours, args.oracle, args.cli)
    print(json.dumps(results, indent=2, ensure_ascii=False))
    sys.exit(any(not r['ok'] for r in results))
