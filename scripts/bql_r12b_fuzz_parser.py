"""R12-B parser robustness: truncations + single-token mutations + deep nesting through native CLI."""
import json, random, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
OURS = str(__import__("pathlib").Path(__file__).resolve().parents[1] / "_build/native/debug/build/cmd/main/main.exe")
LEDGER = str(__import__("pathlib").Path(__file__).resolve().parents[1] / "tests/r9/tx.beancount")
SEEDS = [
 "PRINT", "PRINT FROM year = 2024", "PRINT FROM date > 2024-01-01 OPEN ON 2024-01-02 CLOSE ON 2024-02-01 CLEAR",
 "SELECT date_bin('1 month', date, 2024-01-01) AS m, sum(number) GROUP BY m ORDER BY m",
 "SELECT date_bin(interval('2 days'), date, 2024-01-01)", "SELECT interval('3 months'), interval('-1 year')",
 "SELECT date + interval('1 day') WHERE date < today()", "SELECT parse_date('2024-02-29'), parse_date('29/02/2024', '%d/%m/%Y')",
 "SELECT today(), year(today())", "SELECT account FROM (SELECT account, sum(number) AS s GROUP BY account) WHERE s > 0",
 "SELECT * FROM (SELECT * FROM (SELECT account, number))", "SELECT account, year, sum(number) GROUP BY account, year PIVOT BY account, year",
 "SELECT account, currency, sum(position) GROUP BY 1, 2 PIVOT BY 1, 2", "SELECT round(-0.4), round(-1.25, 1), round(number, 2)",
 "SELECT 1 IN (1, 2), NULL IS NULL, 'a' ~ 'A', 5 % 3, -6 // 4" , "SELECT DISTINCT account ORDER BY account DESC LIMIT 3",
 "SELECT account WHERE account ~ '^Assets' AND NOT number < 0 OR flag = '!'", "SELECT count(*), first(date), last(date), min(number), max(number)",
 "SELECT str(position), units(position), cost(position), value(position)", "SELECT coalesce(payee, narration), upper(narration), length(tags)",
 "SELECT * FROM #postings WHERE account = 'Assets:Cash'", "SELECT * FROM #entries WHERE type = 'transaction'",
 "SELECT name FROM #accounts", "SELECT date FROM #prices", "BALANCES", "BALANCES FROM year = 2024", "JOURNAL 'Assets'",
 "JOURNAL 'Assets' AT cost FROM year = 2024", "EXPLAIN SELECT 1", "SELECT 1; SELECT 2",
 "SELECT date_bin('1 week', date, 2024-01-01), count(*) GROUP BY 1 HAVING count(*) > 0",
 "SELECT parse_date(narration) WHERE parse_date(narration) IS NOT NULL", "SELECT interval('1 day') + interval('2 days')",
 "SELECT CAST(1 AS str)", "SELECT \"double\" , 'single', 'it''s'", "SELECT 1.5e3, -0.0, 0x10, 1_000",
 "SELECT account FROM postings WHERE date BETWEEN 2024-01-01 AND 2024-12-31", "SELECT getprice('HOOL','USD',date)",
 "SELECT meta('k'), entry_meta('k'), any_meta('k')", "SELECT date_add(date, 1), date_diff(date, 2024-01-01)",
 "PRINT FROM (year = 2024 AND (month IN (1,2) OR day = 3))",
]
TOKS = ["(", ")", ",", "'", '"', "SELECT", "FROM", "WHERE", "PIVOT", "BY", "GROUP", "ORDER", "NULL", "*", "-", "+", "/", "%", "~",
        "=", "<", ">=", "!", "AND", "OR", "NOT", "IN", "IS", "1", "-1", "1e999", "99999999999999999999999999999999", "2024-13-45",
        "0000-00-00", "9999-12-31", "date_bin(", "interval(", "parse_date(", "today()", "''", "'\\'", "\\", ";", "#", ".", "..",
        "OPEN", "CLOSE", "ON", "CLEAR", "AS", "LIMIT", "HAVING", "DISTINCT", "\x00", "é", "\U0001F600", "\t", "\n", "?", "@", "{", "}", "[", "]"]
def tokenize(s):
    return re.findall(r"'[^']*'|\"[^\"]*\"|\d{4}-\d\d-\d\d|[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?|\S", s)
def mutants(rng):
    out = []
    for s in SEEDS:
        for i in range(1, len(s), max(1, len(s) // 6)): out.append(s[:i])
        t = tokenize(s)
        for _ in range(7):
            u = list(t); k = rng.randrange(len(u)); op = rng.randrange(4)
            if op == 0: del u[k]
            elif op == 1: u[k] = rng.choice(TOKS)
            elif op == 2: u.insert(k, rng.choice(TOKS))
            else: u.insert(k, u[k])
            out.append(" ".join(u))
    return out
def special():
    return [
        "SELECT " + "(" * 2000 + "1" + ")" * 2000, "SELECT " + "(" * 20000 + "1" + ")" * 20000,
        "PRINT FROM " + "(" * 2000 + "true" + ")" * 2000,
        "SELECT 1 FROM " + "(SELECT 1 FROM " * 499 + "(SELECT 1)" + ")" * 499,
        "SELECT " + "(SELECT " * 500 + "1" + ")" * 500,
        "SELECT " + "-" * 5000 + "1", "SELECT " + "NOT " * 5000 + "true", "SELECT " + " + ".join(["1"] * 20000),
        "SELECT " + "round(" * 1000 + "1" + ")" * 1000, "SELECT '" + "a" * 200_000 + "'", "SELECT length('" + "😀" * 50_000 + "')",
        "SELECT '" + "a" * 100000, "SELECT " + "a" * 200_000, "SELECT " + ", ".join(["1"] * 50000),
        "SELECT 1 WHERE " + " AND ".join(["true"] * 20000), "SELECT " + "1" * 100000, "SELECT 1." + "0" * 100000 + "1",
        "SELECT interval('" + "9" * 1000 + " days')", "SELECT date_bin('" + "9" * 400 + " days', date, 2024-01-01)",
        "SELECT parse_date('" + "1" * 10000 + "')", "SELECT parse_date('2024', '" + "%Y" * 5000 + "')",
        "SELECT account FROM postings PIVOT BY " + ", ".join(["account"] * 2000), "SELECT 'a' ~ '" + "(" * 5000 + "a" + ")" * 5000 + "'",
        "SELECT 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!' ~ '(a+)+$'", "SELECT 'a' ~ '" + "a?" * 40 + "a" * 40 + "'",
        "SELECT CASE WHEN true THEN 1 END", "PRINT FROM " + " OR ".join(["year = 2024"] * 10000),
        "", " ", "\x00", "SELECT\x00 1", "SELECT '\udcff'".encode("utf-8", "surrogatepass").decode("latin-1"),
    ]
def run(q):
    try:
        p = subprocess.run([OURS, "query", LEDGER, q, "--json"], capture_output=True, timeout=10)
        rc, err = p.returncode, (p.stderr + p.stdout)[-300:].decode(errors="replace")
    except subprocess.TimeoutExpired:
        rc, err = "timeout", ""
    except (ValueError, OSError) as e:  # NUL / E2BIG in argv
        rc, err = "argv", str(e)
    bad = rc == "timeout" or (isinstance(rc, int) and (rc < 0 or rc not in (0, 1, 2))) or re.search(r"panic|abort|Segmentation|stack overflow|RUNTIME|unreachable|index out of bounds", err, re.I)
    return dict(query=q[:300], qlen=len(q), rc=rc, tail=err, defect=bool(bad))
if __name__ == "__main__":
    rng = random.Random(1212)
    qs = mutants(rng) + special()
    with ThreadPoolExecutor(8) as ex: res = list(ex.map(run, qs))
    json.dump(res, open(".oracle-cache/r12-rework/fuzz_results.json", "w"), ensure_ascii=False, indent=1)
    from collections import Counter
    print("cases", len(res), "rc", Counter(str(r["rc"]) for r in res), "defects", sum(r["defect"] for r in res))
    for r in [r for r in res if r["defect"]][:10]: print(r["rc"], r["qlen"], repr(r["query"][:100]), repr(r["tail"][-120:]))
