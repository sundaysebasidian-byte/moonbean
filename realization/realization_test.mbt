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
    content="-1000 USD",
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

///|
fn assert_balanced_report(report : @realization.Report) -> Unit raise {
  let sums : Map[String, @decimal.Decimal] = Map([])
  for row in report.rows {
    let currency = row.amount.currency
    sums.set(
      currency,
      sums
      .get(currency)
      .unwrap_or(@decimal.Decimal::zero())
      .add(row.amount.number),
    )
  }
  for (_, number) in sums {
    inspect(number.is_zero(), content="true")
  }
}

///|
test "balance sheet closes current and prior earnings and respects account options" {
  let prefix = "option \"account_current_earnings\" \"Profit:This\"\noption \"account_previous_earnings\" \"Profit:Prior\"\n2023-01-01 open Assets:Cash USD,EUR\n2023-01-01 open Equity:Opening USD\n2023-01-01 open Income:Salary USD,EUR\n2023-01-01 open Expenses:Food USD,EUR\n2023-02-01 * \"prior\"\n  Assets:Cash 50 USD\n  Income:Salary -50 USD\n"
  for expense in [0, 200, 1200] {
    let source = prefix +
      "2024-01-01 * \"salary\"\n  Assets:Cash 1000 USD\n  Income:Salary -1000 USD\n2024-01-02 * \"food\"\n  Assets:Cash -" +
      expense.to_string() +
      " USD\n  Expenses:Food " +
      expense.to_string() +
      " USD\n2024-01-03 * \"foreign\"\n  Assets:Cash 10 EUR\n  Income:Salary -10 EUR\n"
    let report = @realization.balance_sheet(realized(source))
    assert_balanced_report(report)
    inspect(
      row_for(report.rows, "Equity:Profit:Prior").unwrap().amount.number.equal(
        @decimal.Decimal::from_int(-50),
      ),
      content="true",
    )
    inspect(
      report.rows.any(fn(r) { r.label == "Equity:Profit:This" }),
      content="true",
    )
    assert_balanced_report(
      @realization.balance_sheet(realized(source, at=Some("2023-12-31"))),
    )
  }
}

///|
test "incomplete conversion has structured diagnostics and currency totals" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Assets:Foreign EUR\n2024-01-01 open Equity:Opening\n2024-01-02 * \"cash\"\n  Assets:Cash 10.00 USD\n  Assets:Foreign 3 EUR\n  Equity:Opening -10.00 USD\n  Equity:Opening -3 EUR\n"
  let report = @realization.trial_balance(realized(source), convert=Some("USD"))
  inspect(report.diagnostics.length(), content="2")
  inspect(report.diagnostics[0].code, content="report.conversion_incomplete")
  inspect(report.totals.length(), content="2")
  inspect(report.totals.any(fn(r) { r.label == "Total" }), content="false")
  inspect(report.to_json().contains("\"complete\":false"), content="true")
  assert_balanced_report(@realization.balance_sheet(realized(source)))
}

///|
test "text precision is inferred per currency and JSON preserves source scale" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 * \"initial\"\n  Assets:Cash 10.00 USD\n  Equity:Opening -10.00 USD\n2024-01-03 * \"extra\"\n  Assets:Cash 1.2340 USD\n  Equity:Opening -1.2340 USD\n"
  let report = @realization.trial_balance(realized(source))
  inspect(report.display_scales.get("USD").unwrap(), content="4")
  inspect(report.to_text().contains("0.0000 USD"), content="true")
  inspect(report.to_json().contains("11.2340"), content="true")
}

///|
test "report combines explicit retained earnings and computed closing earnings" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Earnings:Current USD\n2024-01-01 open Income:Salary USD\n2024-01-02 * \"closed\"\n  Assets:Cash 50 USD\n  Equity:Earnings:Current -50 USD\n2024-01-03 * \"current\"\n  Assets:Cash 100 USD\n  Income:Salary -100 USD\n"
  let report = @realization.balance_sheet(realized(source))
  inspect(
    report.rows.filter(fn(r) { r.label == "Equity:Earnings:Current" }).length(),
    content="1",
  )
  inspect(
    row_for(report.rows, "Equity:Earnings:Current").unwrap().amount.to_string(),
    content="-150 USD",
  )
  assert_balanced_report(report)
}

///|
test "split total price stays per unit and cost does not override sale price" {
  let source = "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n2024-01-01 open Assets:Cash USD\n2024-01-01 open Income:Gains USD\n2024-01-02 * \"first\"\n  Assets:Stock 10 HOOL {10 USD}\n  Assets:Cash -100 USD\n2024-01-03 * \"second\"\n  Assets:Stock 10 HOOL {20 USD}\n  Assets:Cash -200 USD\n2024-01-04 * \"sell\"\n  Assets:Stock -15 HOOL {} @@ 300 USD\n  Assets:Cash 300 USD\n  Income:Gains -100 USD\n"
  let r = realized(source)
  inspect(r.rate("HOOL", "USD").unwrap().to_string(), content="20")
  inspect(@realization.register_rows(r, "Assets:Stock").length(), content="4")
  assert_balanced_report(@realization.balance_sheet(r))
}

///|
test "explicit price wins over same-day inferred cost and total price" {
  let r = realized(
    "2024-01-01 open Assets:Stock HOOL\n2024-01-01 open Assets:Cash USD\n2024-01-02 price HOOL 25 USD\n2024-01-02 * \"buy\"\n  Assets:Stock 10 HOOL {10 USD} @@ 200 USD\n  Assets:Cash -100 USD\n",
  )
  inspect(r.rate("HOOL", "USD").unwrap().to_string(), content="25")
}

///|
test "cost merge extension retains its booked inventory during replay" {
  let r = realized(
    "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n2024-01-01 open Assets:Cash USD\n2024-01-02 * \"a\"\n  Assets:Stock 10 HOOL {10 USD}\n  Assets:Cash -100 USD\n2024-01-03 * \"b\"\n  Assets:Stock 10 HOOL {20 USD}\n  Assets:Cash -200 USD\n2024-01-04 * \"merge\"\n  Assets:Stock -10 HOOL {*}\n  Assets:Cash 150 USD\n",
  )
  let inv = r.inventory("Assets:Stock")
  inspect(inv.positions.length(), content="1")
  inspect(inv.positions[0].units.to_string(), content="10 HOOL")
  inspect(inv.positions[0].cost.unwrap().number.to_string(), content="15")
}
