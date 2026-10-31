///|
fn queried(source : String, statement : String) -> @query.QueryResult {
  let ledger = @validation.validate_ledger(
    @syntax.parse_source("test.beancount", source),
  )
  let realized = @realization.realize(ledger)
  @query.run_query(realized, statement)
}

///|
fn ledger_source() -> String {
  "2024-01-01 open Assets:Cash USD\n" +
  "2024-01-01 open Income:Salary USD\n" +
  "2024-01-01 open Expenses:Food USD\n" +
  "2024-02-01 * \"salary\"\n" +
  "  Assets:Cash 1000 USD\n" +
  "  Income:Salary -1000 USD\n" +
  "2024-03-05 * \"lunch\"\n" +
  "  Expenses:Food 20 USD\n" +
  "  Assets:Cash -20 USD\n"
}

///|
test "select projects columns and filters postings" {
  let result = queried(
    ledger_source(),
    "SELECT account, units WHERE account = 'Assets:Cash' ORDER BY date",
  )
  inspect(result.columns.length(), content="2")
  inspect(result.rows.length(), content="2")
  inspect(result.rows[0][0].to_text(), content="Assets:Cash")
  inspect(result.rows[0][1].to_text(), content="1000 USD")
  inspect(result.rows[1][1].to_text(), content="-20 USD")
}

///|
test "date functions and descending order with limit" {
  let result = queried(
    ledger_source(),
    "SELECT date, account, units WHERE year(date) = 2024 ORDER BY date DESC LIMIT 1",
  )
  inspect(result.rows.length(), content="1")
  inspect(result.rows[0][0].to_text(), content="2024-03-05")
  inspect(result.rows[0][1].to_text(), content="Expenses:Food")
  inspect(result.rows[0][2].to_text(), content="20 USD")
}

///|
test "multiple order keys use the first key as primary" {
  let result = queried(
    ledger_source(),
    "SELECT date, account, units ORDER BY date, account",
  )
  inspect(result.rows.length(), content="4")
  inspect(result.rows[0][0].to_text(), content="2024-02-01")
  inspect(result.rows[0][1].to_text(), content="Assets:Cash")
  inspect(result.rows[1][1].to_text(), content="Income:Salary")
  inspect(result.rows[2][1].to_text(), content="Assets:Cash")
  inspect(result.rows[3][1].to_text(), content="Expenses:Food")
}

///|
test "group by account aggregates units" {
  let result = queried(
    ledger_source(),
    "SELECT account, sum(units) GROUP BY account ORDER BY account",
  )
  inspect(result.rows.length(), content="3")
  inspect(result.rows[0][0].to_text(), content="Assets:Cash")
  inspect(result.rows[0][1].to_text(), content="980 USD")
  inspect(result.rows[1][0].to_text(), content="Expenses:Food")
  inspect(result.rows[1][1].to_text(), content="20 USD")
  inspect(result.rows[2][0].to_text(), content="Income:Salary")
  inspect(result.rows[2][1].to_text(), content="-1000 USD")
}

///|
test "root and parent functions group accounts" {
  let result = queried(
    ledger_source(),
    "SELECT root(account), sum(units) GROUP BY root(account) ORDER BY root(account)",
  )
  inspect(result.rows.length(), content="3")
  inspect(result.rows[0][0].to_text(), content="Assets")
  inspect(result.rows[0][1].to_text(), content="980 USD")
  inspect(result.rows[2][0].to_text(), content="Income")
  let parents = queried(
    ledger_source(),
    "SELECT parent(account), account FROM postings LIMIT 1",
  )
  inspect(parents.rows[0][0].to_text(), content="Assets")
  inspect(parents.rows[0][1].to_text(), content="Assets:Cash")
}

///|
test "sum position returns an inventory" {
  let result = queried(
    ledger_source(),
    "SELECT account, sum(position) GROUP BY account ORDER BY account",
  )
  inspect(result.rows[0][1].to_text(), content="980 USD")
  inspect(result.rows[2][1].to_text(), content="-1000 USD")
}

///|
test "count aggregates and month filter" {
  let result = queried(
    ledger_source(),
    "SELECT account, count(*) GROUP BY account ORDER BY account",
  )
  inspect(result.rows.length(), content="3")
  inspect(result.rows[0][1].to_text(), content="2")
  let february = queried(
    ledger_source(),
    "SELECT account WHERE month(date) = 2",
  )
  inspect(february.rows.length(), content="2")
}

///|
test "balances statement lists non-empty accounts" {
  let result = queried(ledger_source(), "BALANCES")
  inspect(result.columns.length(), content="2")
  inspect(result.columns[0], content="account")
  inspect(result.rows.length(), content="3")
  inspect(result.rows[0][0].to_text(), content="Assets:Cash")
  inspect(result.rows[0][1].to_text(), content="980 USD")
}

///|
test "journal lists postings for an account with subtree" {
  let result = queried(ledger_source(), "JOURNAL 'Assets:Cash'")
  inspect(result.rows.length(), content="2")
  inspect(result.columns[0], content="date")
  inspect(result.rows[0][0].to_text(), content="2024-02-01")
  inspect(result.rows[0][3].to_text(), content="salary")
  inspect(result.rows[0][5].to_text(), content="1000 USD")
  let limited = queried(ledger_source(), "JOURNAL Assets:Cash LIMIT 1")
  inspect(limited.rows.length(), content="1")
}

///|
test "from balances source exposes inventory positions" {
  let result = queried(
    ledger_source(),
    "SELECT account, position FROM balances WHERE account = 'Assets:Cash'",
  )
  inspect(result.rows.length(), content="1")
  inspect(result.rows[0][1].to_text(), content="980 USD")
}

///|
test "cost and value columns come from cost specs" {
  let source = "2024-01-01 open Assets:Stock HOOL\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"buy\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Equity:Opening -1000 USD\n"
  let result = queried(
    source, "SELECT account, cost, value WHERE account = 'Assets:Stock'",
  )
  inspect(result.rows[0][1].to_text(), content="100 USD")
  inspect(result.rows[0][2].to_text(), content="1000 USD")
}

///|
test "result rendering produces tables and JSON" {
  let result = queried(
    ledger_source(),
    "SELECT account, sum(units) GROUP BY account ORDER BY account",
  )
  let text = result.to_text()
  inspect(text.contains("account"), content="true")
  inspect(text.contains("Assets:Cash"), content="true")
  inspect(text.contains("980 USD"), content="true")
  let json = result.to_json()
  inspect(
    json.contains("\"columns\":[\"account\",\"sum_units\"]"),
    content="true",
  )
  inspect(json.contains("\"Assets:Cash\""), content="true")
  inspect(
    json.contains("\"number\":\"980\",\"currency\":\"USD\""),
    content="true",
  )
}

///|
test "invalid queries report errors" {
  let result = queried(ledger_source(), "DROP TABLE postings")
  inspect(result.is_ok(), content="false")
  inspect(result.to_text().contains("unknown statement"), content="true")
  let broken = queried(ledger_source(), "SELECT account WHERE")
  inspect(broken.is_ok(), content="false")
  let empty = queried(ledger_source(), "  ")
  inspect(empty.is_ok(), content="false")
}

///|
test "arithmetic precedence unary operators and aggregate HAVING" {
  let r = queried(
    ledger_source(),
    "SELECT account, count(*) * 2 + 1 GROUP BY account HAVING count(*) > 1 ORDER BY account",
  )
  inspect(r.is_ok(), content="true")
  inspect(r.rows.length(), content="1")
  inspect(r.rows[0][1].to_text(), content="5")
  let a = queried(ledger_source(), "SELECT 1+2*3, (1+2)*3, -2+5, 6/4 LIMIT 1")
  inspect(a.is_ok(), content="true")
  inspect(a.rows[0][0].to_text(), content="7")
  inspect(a.rows[0][1].to_text(), content="9")
  inspect(a.rows[0][2].to_text(), content="3")
  inspect(a.rows[0][3].to_text(), content="1.5")
}
