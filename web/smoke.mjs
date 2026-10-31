// Smoke test for the browser bundle.
//
//   scripts/build-web.sh && node web/smoke.mjs [dist-dir]
//
// Calls the exported functions the page uses against the repository's example
// ledger and checks the answers, then exercises the page helpers in lib.js.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  addDecimal,
  buildTree,
  cellLines,
  decimalToString,
  group,
  highlightLine,
  nodeCount,
  parseDecimal,
  negate,
  sumRoots,
} from "./lib.js";

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(process.argv[2] ?? resolve(here, "dist"));
const api = await import(pathToFileURL(resolve(dist, "moonbean.js")).href);
const source = readFileSync(resolve(here, "../examples/full-year-2024.beancount"), "utf8");

const call = (name, request) => JSON.parse(api[name](JSON.stringify({ source, ...request })));
const names = ["check", "balance_sheet", "income_statement", "trial_balance", "register", "query", "format"];
const text = (amount) => `${amount.number} ${amount.currency}`;
let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok   ${name}`);
  } catch (error) {
    console.error(`FAIL ${name}\n${error.stack}`);
    process.exitCode = 1;
  }
}

test("bundle has no node: imports", () => {
  const bundle = readFileSync(resolve(dist, "moonbean.js"), "utf8");
  assert.doesNotMatch(bundle, /(from|import\()\s*"node:/);
});

test("check: the example ledger is valid", () => {
  const res = call("check", {});
  assert.equal(res.ok, true);
  assert.equal(res.valid, true);
  assert.deepEqual(res.errors, []);
  assert.deepEqual(res.warnings, []);
  assert.equal(res.title, "MoonBean household ledger 2024");
  assert.deepEqual(res.operating_currencies, ["CNY"]);
  assert.equal(res.entries, 165);
  assert.equal(res.accounts.length, 22);
  assert.ok(res.accounts.includes("Assets:Bank:Checking"));
});

test("check: errors carry line numbers", () => {
  const bad = '2024-01-01 open Assets:A\n2024-01-02 * "x"\n  Assets:A 1 USD\n  Assets:B -1 USD\n2024-13-45 open X\n';
  const res = call("check", { source: bad });
  assert.equal(res.ok, true);
  assert.equal(res.valid, false);
  const byLine = Object.fromEntries(res.errors.map((e) => [e.line, e.code]));
  assert.equal(byLine[2], "validation.unknown_account");
  assert.equal(byLine[5], "parse.date");
});

test("check: include is reported on its own line", () => {
  const res = call("check", { source: 'option "title" "t"\ninclude "other.beancount"\n' });
  assert.equal(res.valid, true);
  assert.equal(res.warnings.length, 1);
  assert.equal(res.warnings[0].line, 2);
  assert.equal(res.warnings[0].code, "include.unavailable");
});

test("balance_sheet: converts to the operating currency by default", () => {
  const res = call("balance_sheet", {});
  assert.equal(res.ok, true);
  assert.equal(res.convert, "CNY");
  const rows = Object.fromEntries(res.report.rows.map((r) => [r.account, text(r.amount)]));
  assert.equal(rows["Assets:Bank:Checking"], "166600.00 CNY");
  assert.equal(rows["Assets:Broker:Cash"], "13578.0000 CNY");
  assert.equal(rows["Assets:Broker:Stocks"], "55 AAPL");
  assert.equal(rows["Liabilities:CreditCard"], "-3200.00 CNY");
});

test("balance_sheet: empty convert keeps original currencies", () => {
  const res = call("balance_sheet", { convert: "" });
  assert.equal(res.convert, null);
  const cash = res.report.rows.filter((r) => r.account === "Assets:Broker:Cash");
  assert.deepEqual(cash.map((r) => text(r.amount)), ["1860.00 USD"]);
  const opening = res.report.rows.filter((r) => r.account === "Equity:Opening");
  assert.deepEqual(opening.map((r) => text(r.amount)).sort(), ["-10000.00 USD", "-175400.00 CNY"]);
});

test("balance_sheet: at limits the report to a date", () => {
  const res = call("balance_sheet", { at: "2024-06-30" });
  const rows = Object.fromEntries(res.report.rows.map((r) => [r.account, text(r.amount)]));
  assert.equal(rows["Assets:Bank:Checking"], "92200.00 CNY");
  assert.equal(rows["Assets:Broker:Stocks"], "45 AAPL");
});

test("income_statement: totals and period start", () => {
  const full = call("income_statement", {});
  const totals = Object.fromEntries(full.report.totals.map((r) => [r.account, text(r.amount)]));
  assert.equal(totals["Total Income"], "-274123.0000 CNY");
  assert.equal(totals["Total Expenses"], "131000.00 CNY");
  assert.equal(totals["Net Income"], "143123.0000 CNY");
  const half = call("income_statement", { start: "2024-07-01" });
  const net = half.report.totals.find((r) => r.account === "Net Income");
  assert.equal(text(net.amount), "85800.00 CNY");
});

test("trial_balance: every account and no ledger errors", () => {
  const res = call("trial_balance", { convert: "" });
  assert.equal(res.ok, true);
  assert.equal(new Set(res.report.rows.map((r) => r.account)).size, 22);
});

test("register: running balance ends at the account balance", () => {
  const res = call("register", { account: "Assets:Bank:Checking" });
  assert.equal(res.ok, true);
  assert.equal(res.rows.length, 82);
  assert.equal(text(res.rows.at(-1).running), "166600.00 CNY");
  assert.equal(res.rows[0].narration, "Opening balances");
});

test("register: subtree includes child accounts", () => {
  assert.equal(call("register", { account: "Expenses:Food", subtree: true }).rows.length, 36);
  assert.equal(call("register", { account: "Expenses:Food" }).rows.length, 0);
});

test("query: aggregate, HAVING and period balances", () => {
  const sums = call("query", { bql: "SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account" });
  assert.equal(sums.ok, true);
  assert.deepEqual(sums.columns, ["account", "sum_units"]);
  assert.equal(sums.rows.length, 22);
  assert.deepEqual(sums.rows[0], ["Assets:Bank:Checking", { number: "166600.00", currency: "CNY" }]);
  const big = call("query", { bql: "SELECT account, sum(units) FROM postings GROUP BY account HAVING sum(units) > 100000" });
  assert.deepEqual(big.rows.map((r) => r[0]), ["Assets:Bank:Checking", "Assets:Bank:Savings"]);
  const period = call("query", { bql: "BALANCES AT cost FROM OPEN ON 2024-03-01 CLOSE ON 2024-06-01" });
  assert.equal(period.ok, true);
  assert.ok(period.rows.length > 0);
});

test("query: engine errors come back as JSON", () => {
  const res = call("query", { bql: "SELECT nothing FROM postings" });
  assert.equal(res.ok, false);
  assert.equal(res.error.code, "query");
  assert.equal(typeof res.error.message, "string");
  const join = call("query", { bql: "SELECT account FROM postings JOIN x" });
  assert.equal(join.ok, false);
});

test("reports and queries refuse a ledger with errors", () => {
  const bad = { source: '2024-01-01 open Assets:A\n2024-01-02 * "x"\n  Assets:A 1 USD\n  Assets:B -1 USD\n' };
  for (const [name, extra] of [["balance_sheet", {}], ["register", { account: "Assets:A" }], ["query", { bql: "BALANCES" }]]) {
    const res = call(name, { ...bad, ...extra });
    assert.equal(res.ok, false, name);
    assert.equal(res.error.code, "ledger_invalid", name);
    assert.equal(res.errors[0].line, 2, name);
  }
});

test("format: aligns amounts, is idempotent and keeps the ledger", () => {
  const first = call("format", {});
  assert.equal(first.ok, true);
  assert.equal(first.changed, true);
  const second = call("format", { source: first.output });
  assert.equal(second.changed, false);
  assert.equal(second.output, first.output);
  const after = call("check", { source: first.output });
  assert.equal(after.valid, true);
  assert.equal(after.entries, 165);
  assert.deepEqual(call("balance_sheet", { source: first.output }).report, call("balance_sheet", {}).report);
});

test("bad requests are JSON errors, never exceptions", () => {
  for (const name of names) {
    const garbage = JSON.parse(api[name]("not json"));
    assert.equal(garbage.ok, false, name);
    assert.equal(garbage.error.code, "bad_request", name);
    const empty = JSON.parse(api[name]("{}"));
    assert.equal(empty.ok, false, name);
    assert.equal(typeof empty.error.message, "string", name);
    const array = JSON.parse(api[name]("[1]"));
    assert.equal(array.ok, false, name);
  }
  assert.equal(call("balance_sheet", { at: "yesterday" }).ok, false);
  assert.equal(call("balance_sheet", { convert: 5 }).ok, false);
});

test("odd input does not throw", () => {
  const samples = ["", "\n\n", "; only a comment", "\u0000\u0001", "2024-01-01", "2024-01-01 open", '"unterminated', "  Assets:A 1 USD", "x".repeat(10000)];
  for (const sample of samples) {
    for (const name of ["check", "format"]) {
      const res = call(name, { source: sample });
      assert.equal(typeof res.ok, "boolean", `${name}: ${JSON.stringify(sample).slice(0, 30)}`);
    }
  }
});

test("lib: exact decimal sums and grouping", () => {
  const sum = addDecimal(parseDecimal("0.1"), parseDecimal("0.20"));
  assert.equal(decimalToString(sum), "0.30");
  assert.equal(decimalToString(addDecimal(parseDecimal("-5"), parseDecimal("2.50"))), "-2.50");
  assert.equal(group("-1234567.50"), "-1,234,567.50");
  assert.equal(group("999"), "999");
});

test("lib: account tree sums children per currency", () => {
  const res = call("balance_sheet", { convert: "" });
  const forest = buildTree(res.report.rows);
  assert.deepEqual(forest.map((n) => n.name), ["Assets", "Equity", "Liabilities"]);
  const assets = forest[0];
  assert.equal(decimalToString(assets.totals.get("CNY")), "318000.00");
  assert.equal(decimalToString(assets.totals.get("USD")), "1860.00");
  assert.equal(decimalToString(assets.totals.get("AAPL")), "55");
  assert.equal(nodeCount(forest), 12);
  const income = buildTree(call("income_statement", {}).report.rows).filter((n) => ["Income", "Expenses"].includes(n.name));
  const net = negate(sumRoots(income));
  assert.deepEqual(net.map(([c, d]) => `${decimalToString(d)} ${c}`), ["143123.0000 CNY"]);
});

test("lib: highlighter keeps the text and marks tokens", () => {
  for (const line of source.split("\n")) {
    const html = highlightLine(line);
    const plain = html.replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    assert.equal(plain, line);
  }
  const html = highlightLine('2024-01-01 * "Rent <b>" #trip');
  assert.match(html, /t-d">2024-01-01/);
  assert.match(html, /t-s">"Rent &lt;b&gt;"/);
  assert.match(html, /t-t">#trip/);
});

test("lib: query cells", () => {
  assert.deepEqual(cellLines(null), { lines: [], numeric: false });
  assert.deepEqual(cellLines({ number: "1234.5", currency: "CNY" }), { lines: ["1,234.5 CNY"], numeric: true });
  const position = { units: { number: "40", currency: "AAPL" }, cost: { number: "150.00", currency: "USD" } };
  assert.deepEqual(cellLines(position).lines, ["40 AAPL {150.00 USD}"]);
  assert.equal(cellLines([position, position]).lines.length, 2);
  assert.deepEqual(cellLines(["a", "b"]), { lines: ["a, b"], numeric: false });
  assert.deepEqual(cellLines(2024), { lines: ["2024"], numeric: true });
});

console.log(`${passed} checks passed`);
if (process.exitCode) console.error("smoke test failed");
