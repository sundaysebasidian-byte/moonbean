"""R12 black-box oracle regression corpus, including the independent R11 review."""
import itertools
import json
import os
import random
import subprocess
import sys
from decimal import Decimal
from pathlib import Path
import bql_r11_review_differential as review
from bql_object_differential import equivalent
from bql_table_differential import error_category


def cases():
    out = review.cases()
    def add(expression, feature="r12-scalar"):
        out.append(dict(query="SELECT " + expression + " LIMIT 1", feature=feature,
                        ledger="tests/r11/prices.beancount", schema=False))
    for text in ["1000000 days", "1234567 days", "100000000000 days", "100000000000 months", "1\tday", "1\nday", "1\u00a0day", "1 day", "0 days", "-2 days", "+2 days", "12 months", "14 months", "-14 months", "1 year", "01 days", "", "1d", "P1D", "1.5 days", "2 weeks", "1 hour", "2 years 3 months", " 2 days", "2 days ", "2  days", "2 DAY", "2 Days"]:
        add("interval(" + repr(text) + ")")
        add("repr(interval(" + repr(text) + "))")
    rng = random.Random(20261112)
    origins = ["2024-01-01", "2024-01-15", "2024-01-31", "2024-02-29", "2023-01-31"]
    dates = ["2024-01-01", "2024-02-15", "2024-02-29", "2024-03-01", "2024-03-31", "2023-12-30", "2025-02-28"]
    dates += [f"{rng.randrange(2022,2027):04}-{rng.randrange(1,13):02}-{rng.randrange(1,29):02}" for _ in range(8)]
    for interval, origin, date in itertools.product(["1 day", "2 days", "31 days", "1 month", "2 months", "14 months", "1 year", "-1 month", "0 days", "invalid"], origins, dates):
        for arg in [repr(interval), "interval(" + repr(interval) + ")"]:
            add(f"date_bin({arg},{date},{origin})", "r12-date-bin")
    for text in ["Feb 29, 2024", "2024-02-29", "20240229", "02/03/24", "31/12/24", "01-02-03", "March 2024", "2024", "2024-02", "1", "Feb", "2024/12/31", "2024-01-02T14:30:00Z", "Thu Jan 02 2024", "2024-02-30", "foo 2024-01-01", "", "today", "USD", "991231", "240229", "32", "99", "May 1st 2024"]:
        add("parse_date(" + repr(text) + ")", "r12-parse-date")
    for text, fmt in [("29/02/2024", "%d/%m/%Y"), ("2024-02-29", "%Y-%m-%d"), ("Feb 29, 2024", "%b %d, %Y"), ("February 29, 2024", "%B %d, %Y"), ("24/02/29", "%y/%m/%d"), ("2024-060", "%Y-%j"), ("2024-366", "%Y-%j"), ("2023-366", "%Y-%j"), ("2024 01 1", "%G %V %u"), ("2024 01 1", "%Y %W %w"), ("2024-02-29 13:45:01.123", "%Y-%m-%d %H:%M:%S.%f"), ("2024-02-29 +0530", "%Y-%m-%d %z"), ("2024-02-30", "%Y-%m-%d"), ("2024", "%Q"), ("2024x", "%Y"), ("", ""), ("02/29", "%m/%d"), ("2024-02-29 +05:30", "%Y-%m-%d %z"), ("2024 +0530 02", "%Y %z %m"), ("2024 01", "%Y %W"), ("2024 01", "%G %V"), ("Feb", "%B"), ("February", "%b"), ("2024 7", "%Y %w"), ("00 PM", "%I %p"), ("2024", "%Y%"), ("2024 2024", "%Y %Y")]:
        add(f"parse_date({text!r},{fmt!r})", "r12-strptime")
    for expression in ["date_bin('100000000000 days',2024-01-02,2024-01-01)", "date_bin('100000000000 days',2023-12-31,2024-01-01)", "date(NULL)", "int(NULL)", "decimal(NULL)", "date_bin(NULL,2024-01-01,2024-01-01)", "interval(NULL)", "parse_date(NULL)", "parse_date(NULL,NULL)", "today(NULL)", "interval(1)", "parse_date(1)", "date_bin('1 day',NULL,2024-01-01)", "today()", "repr(today())", "bool(interval('0 days'))", "bool(interval('1 day'))"]:
        add(expression)
    for number, digits in itertools.product(["-0.4", "-0.5", "-0.04", "-1.4", "0.4", "-12.5", "-1", "-5", "-15"], [None, -2, -1, 0, 1, 2, 8]):
        expression = "round(" + number + ("" if digits is None else "," + str(digits)) + ")"
        add("repr(" + expression + "),str(" + expression + "),bool(" + expression + ")", "r12-round")
    for a, op, b in itertools.product(["round(-0.4)", "round(-0.04,1)", "0", "0.0", "-1"], ["+", "-", "*", "/"], ["round(-0.4)", "0.0", "1", "-1"]):
        if "round(" in a or "round(" in b:
            add("repr(" + a + op + b + ")", "r12-round-consumers")
    add("repr(safediv(round(-0.4),2)),repr(safediv(round(-0.4),-2)),repr(safediv(round(-0.4),0))", "r12-round-consumers")
    for pattern in ["", "a*", "a?", "^", "$", "[ab]*"]:
        for text in ["", "ab", "😀a"]:
            add(f"subst({pattern!r},'X',{text!r})", "r12-subst")
    for text, width in itertools.product(["abc-def ghi", "ab-cdefgh ij", "a-bcdef gh", "ab-c gh", "abc--def ghi", "foo-bar-baz qux", "a--b cdefghi", "abc---def ghi", "a-b-c-d-e-f"], range(4,14)):
        add(f"maxwidth({text!r},{width})", "r12-maxwidth")
    for query in ["PRINT FROM count(*)>0", "PRINT FROM sum(1)>0", "PRINT FROM accounts~'Assets'", "PRINT FROM date='2024'", "PRINT FROM OPEN ON 0001-01-01", "PRINT WHERE account='Assets:Cash'", "PRINT FROM #transactions", "PRINT LIMIT 1", "PRINT FROM missing=1", "PRINT FROM account='Assets:Cash'"]:
        out.append(dict(query=query, feature="r12-print-errors", ledger="tests/r11/prices.beancount", schema=False))
    for text in ["2024-02-29 12h30m", "2024-02-29 12:30 UTC+3", "2024-02-29 12:30 EST", "2024-02-29T23:59:60Z", "20240229T123000", "20240229123000", "12:30", "1 PM", "12am", "Monday", "02/2024", "010203", "2024-02-29T12", "2024-02-29 1230"]:
        add("parse_date(" + repr(text) + ")", "r12-dateutil-forms")
    for expr in ["(1,2)", "(3,1,2,3)", "(NULL,NULL)", "length((1,NULL,true))", "(account,2)", "(-1,2)", "(+1,2)", "((1,2),(3,4))", "1 IN (1,2)", "1 NOT IN (2,3)", "NULL IN (1,2)", "1 IN (NULL,2)", "1 IN NULL", "1 IN 2", "1 IN '123'", "'a' IN 'abc'", "1 IN tags", "'a' IN meta", "'USD' IN units(position)", "units(position) IN position", "'USD' IN position", "position IN balance", "1 BETWEEN 0.0 AND 2", "1 BETWEEN NULL AND 2", "true BETWEEN false AND true", "'b' BETWEEN 'a' AND 'c'", "getitem(balance,'USD')", "getitem(balance,'USD',position)", "repr(decimal('-0.00'))", "repr(-0.0)", "repr(0.0/decimal('-0.01'))", "repr(decimal('-0E+3'))"]:
        add(expr, "r12-operators")
    for a, b in itertools.product(["-6", "-5", "0", "1", "5", "-6.0", "-5.0", "0.0", "1.25", "123456789012345678901234567890123456789.0"], ["-3", "0", "2", "0.2"]):
        add("repr(" + a + "%" + b + ")", "r12-modulo")
    for query in ["SELECT DISTINCT upper(account),sum(number)", "SELECT DISTINCT sum(number)", "SELECT DISTINCT upper(account),sum(number) GROUP BY upper(account)"]:
        out.append(dict(query=query, feature="r12-distinct", ledger="tests/r9/tx.beancount", schema=False))
    for query in [
        'SELECT "account" LIMIT 1', 'SELECT "missing" LIMIT 1',
        'SELECT "ACCOUNT" LIMIT 1', 'SELECT upper("account") LIMIT 1',
        'SELECT "account" FROM #transactions LIMIT 1',
        "SELECT \"date\" FROM #entries WHERE \"type\"='open' LIMIT 1",
        'SELECT *,account LIMIT 1', 'SELECT account,* LIMIT 1',
        'SELECT DISTINCT meta LIMIT 3', 'SELECT DISTINCT entry LIMIT 3',
        'SELECT DISTINCT sum(position) GROUP BY account',
        'SELECT DISTINCT sum(units(position)) GROUP BY account',
        'SELECT DISTINCT balance LIMIT 3', 'SELECT DISTINCT (1,2)',
        'SELECT account,count(*) GROUP BY account HAVING account=first(account)',
        'SELECT account,count(*) GROUP BY account HAVING count(*)>0 AND account=account',
        'SELECT account,sum(number) GROUP BY account ORDER BY sum(number)+number',
        "SELECT account,count(*) WHERE account!='Income:Salary' GROUP BY account HAVING account=last(account)",
        'SELECT account,number FROM accounts',
        'SELECT account,number FROM date>=2024-01-08',
        "SELECT account FROM account='Assets:Cash'",
        'SELECT account,number FROM CLOSE', 'SELECT account,number FROM CLEAR',
        'SELECT account,number FROM OPEN ON 2024-01-07 CLOSE ON 2024-02-01 CLEAR',
        'SELECT meta,accounts FROM OPEN ON 2024-01-07 LIMIT 2',
        'SELECT filename,lineno,location FROM OPEN ON 2024-01-07 LIMIT 1',
        'SELECT id FROM OPEN ON 2024-01-07 LIMIT 2',
        'JOURNAL', 'JOURNAL "Cash"', 'JOURNAL AT units',
        'JOURNAL FROM CLOSE ON 2024-01-08',
        'BALANCES', 'BALANCES AT cost', "BALANCES FROM account='Assets:Cash'",
    ]:
        out.append(dict(query=query, feature="r12-language", ledger="tests/r9/tx.beancount", schema=False))
    for pattern in ["a{2}", "(?:a)(b)", "(?i:a)", "a.b", r"\.", r"(a)(b)?"]:
        for text in ["aaab", "a.b", "a\nb"]:
            add("repr(grep(" + ("'" + pattern + "'") + "," + ("'" + text + "'") + "))", "r12-regex")
            for replacement in [r"\1", r"\g<0>", r"\n", r"\g<2>", r"\100", r"\777", r"\q", r"\&"]:
                add("repr(subst(" + ("'" + pattern + "'") + "," + ("'" + replacement + "'") + "," + ("'" + text + "'") + "))", "r12-regex-replacement")
    for expression in ["meta", "entry", "balance", "(1,2)", "units(position)", "position", "tags", "accounts"]:
        for op in ["=", "!=", "<", "<=", ">", ">="]:
            add(expression + op + expression, "r12-comparison-types")
    for expression in ["meta('lineno')=meta('lineno')", "meta('lineno')=10", "entry_meta('__tolerances__')=1", "entry_meta('__tolerances__')<1"]:
        add(expression, "r12-dynamic-comparisons")
    for expression in ["max(position)", "min(position)", "max(units(position))", "min(units(position))"]:
        out.append(dict(query="SELECT repr(" + expression + ") WHERE account='Assets:Stock' AND number=2", feature="r12-cost-order", ledger="tests/regression/cost-date-label.beancount", schema=False))
    return out


def run(ours, oracle):
    probes = cases()
    worker = subprocess.run([str(Path(oracle) / "python"), str(Path(review.__file__)), "--worker"],
                            input=json.dumps(probes), text=True, capture_output=True, check=True, timeout=120)
    results = []
    for case, expected in zip(probes, json.loads(worker.stdout)):
        proc = subprocess.run([ours, "query", case["ledger"], case["query"], "--json"], capture_output=True, text=True, timeout=10)
        actual = json.loads(proc.stdout, parse_float=Decimal) if proc.returncode == 0 else None
        category = "success" if actual is not None else error_category(proc.stdout + proc.stderr, True)
        ok = category == expected["category"]
        if ok and category == "success":
            ok = equivalent(actual["rows"], expected["rows"])
            if case.get("schema"):
                ok = ok and actual["columns"] == expected["columns"]
        elif category != "success":
            ok = ok and proc.returncode == 1
        boundary = proc.returncode == 1 and category == "unsupported" and "query.unsupported.set_representation" in proc.stdout
        results.append(dict(**case, ok=ok or boundary, conformant=ok, boundary="CPython randomized set iteration" if boundary else None,
                            detail="" if ok or boundary else dict(actual=actual or proc.stdout + proc.stderr, expected=expected)))
    for timezone in ["UTC", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Auckland"]:
        env = dict(os.environ, TZ=timezone)
        query = "SELECT today(),parse_date('February 2024') LIMIT 1"
        a = subprocess.run([ours, "query", "tests/r11/prices.beancount", query, "--json"], env=env, capture_output=True, text=True)
        b = subprocess.run([str(Path(oracle) / "python"), "scripts/oracle_query_values.py", "tests/r11/prices.beancount", query], env=env, capture_output=True, text=True)
        ok = a.returncode == b.returncode == 0 and equivalent(json.loads(a.stdout)["rows"], json.loads(b.stdout))
        results.append(dict(query=query, timezone=timezone, feature="r12-local-clock", ok=ok,
                            detail="" if ok else dict(actual=a.stdout, expected=b.stdout)))
    for ledger in sorted(Path("tests/ledgers").glob("*.beancount")):
        if ledger.name.startswith(("035-", "058-")):
            continue
        for query in ["PRINT", "PRINT FROM date>=2024-01-03", "PRINT FROM type='transaction'", "PRINT FROM false", "PRINT FROM CLOSE ON 2024-01-04", "PRINT FROM OPEN ON 2024-01-04", "PRINT FROM OPEN ON 2024-01-03 CLOSE ON 2024-01-05", "PRINT FROM CLEAR", "PRINT FROM CLOSE"]:
            a = subprocess.run([ours, "query", str(ledger), query], capture_output=True)
            b = subprocess.run([str(Path(oracle) / "bean-query"), str(ledger), query], capture_output=True)
            ok = a.returncode == b.returncode == 0 and a.stdout == b.stdout
            results.append(dict(ledger=str(ledger), query=query, feature="r12-print-bytes", ok=ok,
                                detail="" if ok else dict(actual=a.stdout.decode(), expected=b.stdout.decode())))
    return results


if __name__ == "__main__":
    results = run("_build/native/debug/build/cmd/main/main.exe", "/tmp/moonbean-r4-oracle/bin")
    print(json.dumps(results, indent=2, default=str))
    sys.exit(any(not r["ok"] for r in results))
