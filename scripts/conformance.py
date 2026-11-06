#!/usr/bin/env python3
"""Compare moonbean against a pinned Beancount installation.

Beancount is used strictly as a black-box oracle: this script only executes
`bean-check` and `bean-query` and compares their observable output. No
Beancount source code or test data is imported, linked or redistributed.

For every ledger in tests/ledgers/*.beancount the script compares:

  * diagnostics as sets of (file, category, line),
  * final balances as per-account unit totals,
  * lot structure via BALANCES,
  * fixed BQL queries covering grouping, filtering, ordering and limits.

Ledgers listed in ORACLE_EXCEPTIONS are features moonbean implements but the
pinned oracle refuses (AVERAGE booking, cost merging); they are reported as
extensions instead of compared.
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from decimal import Decimal

NUMBER = r"[-+]?\d+(?:\.\d+)?"

# Ledgers whose behaviour intentionally goes beyond the pinned oracle.
ORACLE_EXCEPTIONS = {
    "035-booking-average.beancount": "beancount 3.2.3 reports 'AVERAGE method is not supported'",
    "058-cost-merge.beancount": "beancount 3.2.3 reports 'Cost merging is not supported yet'",
}

# (name, moonbean query, oracle query, comparison mode)
QUERIES = [
    (
        "totals",
        "SELECT account, sum(units) GROUP BY account ORDER BY account",
        "SELECT account, sum(position) GROUP BY account ORDER BY account",
        "units",
    ),
    (
        "by-date",
        "SELECT date, account, sum(units) GROUP BY date, account ORDER BY date, account",
        "SELECT date, account, sum(position) GROUP BY date, account ORDER BY date, account",
        "units",
    ),
    (
        "year",
        "SELECT account, sum(units) WHERE year(date) = 2024 GROUP BY account ORDER BY account",
        "SELECT account, sum(position) WHERE year(date) = 2024 GROUP BY account ORDER BY account",
        "units",
    ),
    (
        "root",
        "SELECT root(account), sum(units) GROUP BY root(account) ORDER BY root(account)",
        "SELECT root(account), sum(position) GROUP BY root(account) ORDER BY root(account)",
        "units",
    ),
    (
        "limit",
        "SELECT date, account ORDER BY date DESC, account LIMIT 5",
        "SELECT date, account ORDER BY date DESC, account LIMIT 5",
        "scalar",
    ),
    ("balances", "BALANCES", "BALANCES", "lots"),
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30)


def classify_oracle(message):
    text = message.lower()
    if "missing commodity directive" in text:
        return "check_commodity:" + re.search(r"for '([^']+)'", message).group(1)
    if "disagreeing price entries" in text:
        return "unique_prices"
    if "non-leaf account" in text:
        return "leafonly:" + re.search(r"account '([^']+)'", message).group(1)
    if "transaction does not balance" in text:
        return "unbalanced"
    if "balance failed" in text:
        return "balance"
    if "invalid currency" in text and "balance" in text:
        return "balance_currency"
    if "invalid currency" in text:
        return "currency"
    if "unused pad" in text or "attempt to pad an entry with cost" in text:
        return "pad"
    if "duplicate open" in text:
        return "duplicate_open"
    if "duplicate close" in text:
        return "duplicate_close"
    if "duplicate balance" in text:
        return "duplicate_balance"
    if "unopened account" in text:
        return "close_unopened"
    if "inactive account" in text:
        return "inactive_account"
    if "unknown account" in text:
        return "unknown_account"
    if "not enough lots" in text or "ambiguous" in text or "no match" in text:
        return "booking"
    if "invalid booking method" in text:
        return "booking_method"
    if "failed to categorize posting" in text:
        return "cost"
    if "auto-posting" in text:
        return "missing"
    if "average method is not supported" in text:
        return "average_unsupported"
    if "cost merging is not supported" in text:
        return "merge_unsupported"
    if "invalid token" in text or "syntax error" in text or "unexpected" in text:
        return "syntax"
    return "other:" + message.split(":")[0][:40]


def classify_ours(code):
    if code.startswith("parse."):
        return "syntax"
    if code.startswith("validation."):
        return code[len("validation."):]
    if code.startswith("booking."):
        return "booking"
    if "." in code:
        return code.rsplit(".", 1)[1]
    return code


def oracle_diagnostics(oracle_dir, path):
    proc = run([os.path.join(oracle_dir, "bean-check"), path])
    found = set()
    for line in (proc.stdout + "\n" + proc.stderr).splitlines():
        match = re.match(r"^(.+?):(\d+): (.*)$", line)
        if not match:
            continue
        category = classify_oracle(match.group(3))
        found.add(("<check_commodity>", category, 0) if category.startswith("check_commodity:") else ("<leafonly>", category, 0) if category.startswith("leafonly:") else (os.path.basename(match.group(1)), category, int(match.group(2))))
    return found


def ours_diagnostics(exe, path):
    proc = run([exe, "check", path])
    found = set()
    output = proc.stdout + "\n" + proc.stderr
    for line in output.splitlines():
        # Validator warnings are advisory and do not correspond to bean-check
        # errors, so they are not part of the diagnostic comparison.
        if line.startswith("warning: "):
            continue
        match = re.match(r"^(.+?):(\d+): ([a-z_.]+): (.*)$", line)
        if not match:
            continue
        category = classify_ours(match.group(3))
        if category == "check_commodity":
            currency = re.search(r"for '([^']+)'", match.group(4)).group(1)
            found.add(("<check_commodity>", category + ":" + currency, 0))
        elif category == "leafonly":
            account = re.search(r"account '([^']+)'", match.group(4)).group(1)
            found.add(("<leafonly>", category + ":" + account, 0))
        else:
            found.add((os.path.basename(match.group(1)), category, int(match.group(2))))
    return found


def ours_query(exe, path, query):
    proc = run([exe, "query", path, query, "--json"])
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def oracle_query(oracle_dir, path, query):
    # Inventory CSV rendering rounds to display precision. str() preserves
    # exact quantities before the CSV renderer sees the result.
    if query == "BALANCES":
        query = "SELECT account, str(sum(position)) GROUP BY account ORDER BY account"
    else:
        query = query.replace("sum(position)", "str(sum(position))")
    proc = run([os.path.join(oracle_dir, "bean-query"), "-f", "csv", path, query])
    if proc.returncode != 0:
        return None
    return list(csv.reader(io.StringIO(proc.stdout)))


def split_top_level(cell):
    parts = []
    depth = 0
    current = ""
    for char in cell:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    parts.append(current)
    return [part.strip() for part in parts if part.strip()]


def parse_oracle_cell(cell):
    units = defaultdict(Decimal)
    lots = defaultdict(Decimal)
    if cell.startswith("(") and cell.endswith(")"):
        cell = cell[1:-1]
    for fragment in split_top_level(cell):
        lot = re.match(rf"^({NUMBER})\s+(\S+)\s*\{{(.*)\}}$", fragment)
        if lot:
            number = Decimal(lot.group(1))
            currency = lot.group(2)
            inner = re.search(rf"({NUMBER})\s+(\S+)", lot.group(3))
            cost = (Decimal(inner.group(1)), inner.group(2).rstrip(",")) if inner else (None, None)
            units[currency] += number
            lots[(currency, cost[0], cost[1])] += number
            continue
        plain = re.match(rf"^({NUMBER})\s+(\S+)$", fragment)
        if plain:
            number = Decimal(plain.group(1))
            currency = plain.group(2)
            units[currency] += number
            lots[(currency, None, None)] += number
            continue
        raise ValueError(f"unparsed oracle cell fragment: {fragment!r}")
    return units, lots


def ours_units(value):
    totals = defaultdict(Decimal)

    def add_amount(amount):
        if isinstance(amount, dict) and "number" in amount and "currency" in amount:
            totals[amount["currency"]] += Decimal(amount["number"])

    if isinstance(value, dict):
        if "units" in value:
            add_amount(value["units"])
        else:
            add_amount(value)
    elif isinstance(value, list):
        for item in value:
            if isinstance(item, dict) and "units" in item:
                add_amount(item["units"])
            else:
                add_amount(item)
    return {key: number for key, number in totals.items() if number != 0}


def ours_lots(value):
    lots = defaultdict(Decimal)

    def add_position(position):
        if not isinstance(position, dict):
            return
        units = position.get("units")
        if not isinstance(units, dict) or "number" not in units:
            return
        cost = position.get("cost")
        if isinstance(cost, dict) and cost.get("number") is not None:
            key = (units["currency"], Decimal(str(cost["number"])), cost.get("currency"))
        else:
            key = (units["currency"], None, None)
        lots[key] += Decimal(units["number"])

    if isinstance(value, dict):
        if "units" in value:
            add_position(value)
    elif isinstance(value, list):
        for item in value:
            add_position(item)
    return {key: number for key, number in lots.items() if number != 0}


def compare_units_query(ours_rows, oracle_csv):
    if oracle_csv is None or not oracle_csv:
        return False, "oracle query failed"
    header, body = oracle_csv[0], oracle_csv[1:]
    if len(header) < 2:
        return False, "unexpected oracle columns"
    expected = {}
    for row in body:
        if len(row) < 2:
            continue
        try:
            units, _ = parse_oracle_cell(row[-1])
        except ValueError as error:
            return False, str(error)
        key = tuple(row[:-1])
        expected[key] = {name: number for name, number in units.items() if number != 0}
    actual = {}
    for row in ours_rows.get("rows", []):
        key = tuple(str(cell) for cell in row[:-1])
        actual[key] = ours_units(row[-1])
    if expected != actual:
        return False, f"expected {expected} got {actual}"
    return True, ""


def compare_lots_query(ours_rows, oracle_csv):
    if oracle_csv is None or not oracle_csv:
        return False, "oracle query failed"
    body = oracle_csv[1:]
    expected = {}
    for row in body:
        if len(row) < 2:
            continue
        try:
            _, lots = parse_oracle_cell(row[-1])
        except ValueError as error:
            return False, str(error)
        expected[row[0]] = {key: number for key, number in lots.items() if number != 0}
    actual = {}
    for row in ours_rows.get("rows", []):
        actual[str(row[0])] = ours_lots(row[-1])
    expected = {account: lots for account, lots in expected.items() if lots}
    actual = {account: lots for account, lots in actual.items() if lots}
    if expected != actual:
        return False, f"expected {expected} got {actual}"
    return True, ""


def compare_scalar_query(ours_rows, oracle_csv):
    if oracle_csv is None:
        return False, "oracle query failed"
    body = oracle_csv[1:]
    expected = [tuple(row) for row in body]
    actual = [tuple(",".join(cell) if isinstance(cell, list) else "" if cell is None else str(cell) for cell in row) for row in ours_rows.get("rows", [])]
    if expected != actual:
        return False, f"expected {expected} got {actual}"
    return True, ""


def compare_ledger(exe, oracle_dir, path, skip_oracle):
    name = os.path.basename(path)
    result = {"name": name, "diagnostics": None, "queries": [], "note": ""}
    ours_errors = ours_diagnostics(exe, path)
    if skip_oracle:
        result["diagnostics"] = (len(ours_errors) == 0, "", "")
        result["note"] = ORACLE_EXCEPTIONS[name]
        result["queries"] = [("skip", True, "")]
        return result
    oracle_errors = oracle_diagnostics(oracle_dir, path)
    ok = ours_errors == oracle_errors
    result["diagnostics"] = (
        ok,
        "expected " + repr(sorted(oracle_errors)),
        "got " + repr(sorted(ours_errors)),
    )
    if not ok:
        return result
    # Compare raw Price directives, including duplicates, even for error ledgers.
    exported = run([exe, "export", path, "--json"])
    actual_entries = json.loads(exported.stdout)["entries"]
    actual_prices = sorted((e["date"], e["currency"], Decimal(e["amount"]["number"]), e["amount"]["currency"])
                           for e in actual_entries if e["type"] == "price")
    oracle_output = run([os.path.join(oracle_dir, "python"), os.path.join(os.path.dirname(__file__), "oracle_entries.py"), path])
    expected_prices = sorted((d, c, Decimal(n), q) for d, c, n, q in json.loads(oracle_output.stdout))
    result["queries"].append(("prices", actual_prices == expected_prices, f"expected {expected_prices} got {actual_prices}" if actual_prices != expected_prices else ""))
    if ours_errors:
        # Error ledgers have no meaningful balance comparison.
        result["queries"].insert(0, ("skip", True, "error ledger"))
        return result
    for label, our_query, oracle_query_text, mode in QUERIES:
        ours_rows = ours_query(exe, path, our_query)
        if ours_rows is None:
            result["queries"].append((label, False, "moonbean query failed"))
            continue
        oracle_rows = oracle_query(oracle_dir, path, oracle_query_text)
        if mode == "units":
            ok, detail = compare_units_query(ours_rows, oracle_rows)
        elif mode == "lots":
            ok, detail = compare_lots_query(ours_rows, oracle_rows)
        else:
            ok, detail = compare_scalar_query(ours_rows, oracle_rows)
        result["queries"].append((label, ok, detail))
    return result


def format_result(result):
    diagnostics_ok, expected, actual = result["diagnostics"]
    errors = "pass" if diagnostics_ok else f"FAIL ({actual}; {expected})"
    queries = []
    for label, ok, detail in result["queries"]:
        if label == "skip":
            continue
        queries.append(label if ok else f"{label}:FAIL")
    bql = "pass" if all(ok for _, ok, _ in result["queries"]) and queries else "skip"
    overall = diagnostics_ok and all(ok for _, ok, _ in result["queries"])
    return errors, bql, overall


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ours", required=True, help="path to the moonbean executable")
    parser.add_argument("--oracle", required=True, help="directory containing bean-check/bean-query")
    parser.add_argument("--ledgers", required=True, help="directory with *.beancount ledgers")
    parser.add_argument("--oracle-version", default="unknown")
    parser.add_argument("--json-out", help="write machine readable results here")
    parser.add_argument("--markdown", action="store_true", help="print a markdown table")
    args = parser.parse_args()

    paths = sorted(
        os.path.join(args.ledgers, entry)
        for entry in os.listdir(args.ledgers)
        if entry.endswith(".beancount")
    )
    results = []
    for path in paths:
        name = os.path.basename(path)
        results.append(
            compare_ledger(args.ours, args.oracle, path, name in ORACLE_EXCEPTIONS)
        )

    failures = []
    if args.markdown:
        print(f"Oracle: {args.oracle_version}")
        print()
        print("| Ledger | Diagnostics | BQL | Result | Notes |")
        print("| --- | --- | --- | --- | --- |")
    for result in results:
        errors, bql, overall = format_result(result)
        if not overall:
            failures.append(result)
        if args.markdown:
            print(
                f"| `{result['name']}` | {errors} | {bql} | "
                f"{'PASS' if overall else 'FAIL'} | {result['note']} |"
            )
        else:
            status = "PASS" if overall else "FAIL"
            print(f"{status} {result['name']}")
            for label, ok, detail in result["queries"]:
                if not ok:
                    print(f"    {label}: {detail}")
            if not result["diagnostics"][0]:
                print(f"    diagnostics: {result['diagnostics'][2]}")
                print(f"    oracle:      {result['diagnostics'][1]}")
            if result["note"]:
                print(f"    note: {result['note']}")

    compared = len([r for r in results if r["name"] not in ORACLE_EXCEPTIONS])
    passed = len([r for r in results if r["name"] not in ORACLE_EXCEPTIONS and format_result(r)[2]])
    print()
    print(
        f"ledgers: {len(results)}, compared: {compared}, passed: {passed}, "
        f"failed: {len(failures)}, extensions: {len(results) - compared}"
    )
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "oracle": args.oracle_version,
                    "results": [
                        {
                            "name": result["name"],
                            "diagnostics": result["diagnostics"][0],
                            "queries": [
                                {"name": label, "ok": ok, "detail": detail}
                                for label, ok, detail in result["queries"]
                            ],
                            "note": result["note"],
                        }
                        for result in results
                    ],
                },
                handle,
                indent=2,
            )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
