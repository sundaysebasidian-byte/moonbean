///|
fn realized(
  source : String,
  at~ : String? = None,
) -> @realization.RealizedLedger {
  let ledger = @validation.validate_ledger(
    @syntax.parse_source("test.beancount", source),
  )
  let date = match at {
    Some(text) => @ast.Date::parse(text)
    None => None
  }
  @realization.realize(ledger, at=date)
}

///|
fn row_for(
  rows : Array[@realization.ReportRow],
  label : String,
) -> @realization.ReportRow? {
  for row in rows {
    if row.label == label {
      return Some(row)
    }
  }
  None
}

///|
test "inventory keeps cost lots and price database converts market value" {
  let r = realized(
    "2024-01-01 open Assets:Stock HOOL\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"buy\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Equity:Opening -1000 USD\n" +
    "2024-02-01 price HOOL 120 USD\n",
  )
  let inventory = r.inventory("Assets:Stock")
  inspect(inventory.positions.length(), content="1")
  inspect(inventory.positions[0].units.to_string(), content="10 HOOL")
  inspect(
    inventory.positions[0].cost.unwrap().to_string(),
    content="{100 USD, 2024-01-02}",
  )
  let converted = r.convert(
    @ast.Amount::new(@decimal.Decimal::from_int(10), "HOOL"),
    "USD",
  )
  inspect(converted.unwrap().to_string(), content="1200 USD")
  let report = @realization.trial_balance(r, convert=Some("USD"))
  inspect(
    row_for(report.rows, "Assets:Stock").unwrap().amount.to_string(),
    content="1200 USD",
  )
  inspect(
    row_for(report.rows, "Equity:Opening").unwrap().amount.to_string(),
    content="-1000 USD",
  )
  inspect(
    row_for(report.totals, "Total").unwrap().amount.to_string(),
    content="200 USD",
  )
}

///|
test "explicit prices are inverse convertible" {
  let r = realized(
    "2024-01-01 open Assets:Euro EUR\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"buy euros\"\n" +
    "  Assets:Euro 100 EUR {1.10 USD}\n" +
    "  Equity:Opening -110 USD\n",
  )
  inspect(r.rate("EUR", "USD").unwrap().to_string(), content="1.10")
  let usd = r.rate("USD", "EUR").unwrap()
  inspect(usd.to_string().contains("0.9090"), content="true")
}

///|
test "historical realization filters transactions and prices by date" {
  let source = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"first\"\n" +
    "  Assets:Cash 100 USD\n" +
    "  Equity:Opening -100 USD\n" +
    "2024-03-01 * \"second\"\n" +
    "  Assets:Cash 50 USD\n" +
    "  Equity:Opening -50 USD\n"
  let early = realized(source, at=Some("2024-02-01"))
  inspect(
    early.inventory("Assets:Cash").quantity("USD").to_string(),
    content="100",
  )
  let all = realized(source)
  inspect(
    all.inventory("Assets:Cash").quantity("USD").to_string(),
    content="150",
  )
}

///|
test "balance sheet totals each root and converts positions" {
  let r = realized(
    "2024-01-01 open Assets:Stock HOOL\n" +
    "2024-01-01 open Liabilities:Loan USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"buy on margin\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Liabilities:Loan -500 USD\n" +
    "  Equity:Opening -500 USD\n" +
    "2024-02-01 price HOOL 150 USD\n",
  )
  let report = @realization.balance_sheet(r, convert=Some("USD"))
  inspect(
    row_for(report.rows, "Assets:Stock").unwrap().amount.to_string(),
    content="1500 USD",
  )
  inspect(
    row_for(report.rows, "Liabilities:Loan").unwrap().amount.to_string(),
    content="-500 USD",
  )
  inspect(
    row_for(report.totals, "Total Assets").unwrap().amount.to_string(),
    content="1500 USD",
  )
  inspect(
    row_for(report.totals, "Total Liabilities").unwrap().amount.to_string(),
    content="-500 USD",
  )
  inspect(
    row_for(report.totals, "Total Equity").unwrap().amount.to_string(),
    content="-500 USD",
  )
}

///|
test "income statement computes totals and net income" {
  let r = realized(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Income:Salary USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-02-01 * \"salary\"\n" +
    "  Assets:Cash 1000 USD\n" +
    "  Income:Salary -1000 USD\n" +
    "2024-02-05 * \"lunch\"\n" +
    "  Expenses:Food 20 USD\n" +
    "  Assets:Cash -20 USD\n",
  )
  let report = @realization.income_statement(r)
  inspect(
    row_for(report.rows, "Income:Salary").unwrap().amount.to_string(),
    content="-1000 USD",
  )
  inspect(
    row_for(report.rows, "Expenses:Food").unwrap().amount.to_string(),
    content="20 USD",
  )
  inspect(
    row_for(report.totals, "Total Income").unwrap().amount.to_string(),
    content="-1000 USD",
  )
  inspect(
    row_for(report.totals, "Total Expenses").unwrap().amount.to_string(),
    content="20 USD",
  )
  inspect(
    row_for(report.totals, "Net Income").unwrap().amount.to_string(),
    content="980 USD",
  )
  let early = @realization.income_statement(
    r,
    start=Some(@ast.Date::parse("2024-02-04").unwrap()),
  )
  inspect(row_for(early.rows, "Income:Salary") is None, content="true")
}

///|
test "inventory report exposes cost and value" {
  let r = realized(
    "2024-01-01 open Assets:Stock HOOL\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"buy\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Equity:Opening -1000 USD\n" +
    "2024-02-01 price HOOL 90 USD\n",
  )
  let rows = @realization.inventory_rows(r, convert=Some("USD"))
  inspect(rows.length(), content="2")
  let stock = rows[0]
  inspect(stock.account, content="Assets:Stock")
  inspect(stock.units.to_string(), content="10 HOOL")
  inspect(stock.cost.unwrap(), content="{100 USD, 2024-01-02}")
  inspect(stock.value.unwrap().to_string(), content="900 USD")
  let text = @realization.inventory_to_text(rows)
  inspect(text.contains("Assets:Stock"), content="true")
  let json = @realization.inventory_to_json(rows)
  inspect(json.contains("\"cost\":\"{100 USD, 2024-01-02}\""), content="true")
  inspect(
    json.contains("\"value\":{\"number\":\"900\",\"currency\":\"USD\"}"),
    content="true",
  )
}

///|
test "register tracks running balance per currency" {
  let r = realized(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Income:Salary USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-02-01 * \"salary\"\n" +
    "  Assets:Cash 1000 USD\n" +
    "  Income:Salary -1000 USD\n" +
    "2024-02-05 * \"lunch\"\n" +
    "  Expenses:Food 20 USD\n" +
    "  Assets:Cash -20 USD\n",
  )
  let rows = @realization.register_rows(r, "Assets:Cash")
  inspect(rows.length(), content="2")
  inspect(rows[0].amount.to_string(), content="1000 USD")
  inspect(rows[0].running.to_string(), content="1000 USD")
  inspect(rows[1].amount.to_string(), content="-20 USD")
  inspect(rows[1].running.to_string(), content="980 USD")
  inspect(rows[1].narration, content="lunch")
  let text = @realization.register_to_text(rows)
  inspect(text.contains("2024-02-05"), content="true")
  let json = @realization.register_to_json(rows)
  inspect(json.contains("\"running\""), content="true")
  inspect(json.contains("\"narration\":\"lunch\""), content="true")
}

///|
test "reports render text and JSON with exact decimal strings" {
  let r = realized(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"fund\"\n" +
    "  Assets:Cash 10.50 USD\n" +
    "  Equity:Opening -10.50 USD\n",
  )
  let report = @realization.trial_balance(r)
  let text = report.to_text()
  inspect(text.contains("Trial Balance"), content="true")
  inspect(text.contains("Assets:Cash"), content="true")
  inspect(text.contains("10.50 USD"), content="true")
  let json = report.to_json()
  inspect(json.contains("\"number\":\"10.50\""), content="true")
  inspect(json.contains("\"number\":\"-10.50\""), content="true")
}

///|
test "subaccount subtree aggregation" {
  let r = realized(
    "2024-01-01 open Assets:Bank:Checking USD\n" +
    "2024-01-01 open Assets:Bank:Savings USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"split\"\n" +
    "  Assets:Bank:Checking 60 USD\n" +
    "  Assets:Bank:Savings 40 USD\n" +
    "  Equity:Opening -100 USD\n",
  )
  inspect(
    r.combined_inventory("Assets:Bank").quantity("USD").to_string(),
    content="0",
  )
  inspect(
    r
    .combined_inventory("Assets:Bank", subtree=true)
    .quantity("USD")
    .to_string(),
    content="100",
  )
  inspect(
    @realization.is_subaccount("Assets:Bank:Checking", "Assets:Bank"),
    content="true",
  )
  inspect(
    @realization.is_subaccount("Assets:Other", "Assets:Bank"),
    content="false",
  )
}

///|
test "report display precision rounds text and preserves JSON" {
  let ledger = @validation.validate_ledger(
    @syntax.parse_source(
      "precision", "option \"display_precision\" \"USD:0.01\"\n2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 * \"opening\"\n  Assets:Cash 1.234 USD\n  Equity:Opening -1.234 USD\n",
    ),
  )
  let report = @realization.trial_balance(@realization.realize(ledger))
  inspect(
    report.to_text_with_options(ledger.options).contains("1.23 USD"),
    content="true",
  )
  inspect(report.to_json().contains("1.234"), content="true")
}

///|
test "price paths use dated shortest paths inverse edges and terminate on cycles" {
  let db = @realization.PriceDb::new()
  let jan = @ast.Date::parse("2024-01-01").unwrap()
  let feb = @ast.Date::parse("2024-02-01").unwrap()
  db.add(jan, "AAPL", "USD", @decimal.Decimal::from_int(175))
  db.add(jan, "CNY", "USD", @decimal.Decimal::parse("0.2").unwrap())
  db.add(feb, "USD", "CNY", @decimal.Decimal::from_int(7))
  inspect(db.rate("AAPL", "CNY", Some(jan)).unwrap().to_string(), content="875")
  inspect(
    db.rate("AAPL", "CNY", Some(feb)).unwrap().to_string(),
    content="1225",
  )
  db.add(jan, "CNY", "EUR", @decimal.Decimal::from_int(2))
  db.add(jan, "EUR", "AAPL", @decimal.Decimal::from_int(3))
  inspect(db.rate("AAPL", "JPY", None) is None, content="true")
  let tie = @realization.PriceDb::new()
  for currency in ["BBB", "AAA"] {
    tie.add(
      jan,
      "SRC",
      currency,
      @decimal.Decimal::from_int(if currency == "AAA" { 2 } else { 4 }),
    )
    tie.add(jan, currency, "DST", @decimal.Decimal::from_int(3))
  }
  inspect(tie.rate("SRC", "DST", None).unwrap().to_string(), content="6")
}
