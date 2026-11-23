///|
fn queried(source : String, statement : String) -> @query.QueryResult {
  let ledger = @validation.validate_ledger(
    @syntax.parse_source("test.beancount", source),
  )
  let realized = @realization.realize(ledger)
  @query.run_query(realized, statement, diagnostics=ledger.errors)
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

///|
test "regex is case insensitive and rejects invalid patterns" {
  let r = queried(ledger_source(), "SELECT account WHERE account ~ '^assets:'")
  inspect(r.rows.length(), content="2")
  inspect(
    queried(ledger_source(), "SELECT account WHERE account ~ '['").is_ok(),
    content="false",
  )
}

///|
test "tags links and posting metadata retain structured values" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 * \"opening\" #shop ^receipt\n  Assets:Cash 1 USD\n    receipt: \"abc\"\n  Equity:Opening -1 USD\n"
  let r = queried(
    source, "SELECT tags, links, meta('receipt') WHERE account = 'Assets:Cash'",
  )
  inspect(r.rows[0][0].to_json(), content="[\"shop\"]")
  inspect(r.rows[0][1].to_json(), content="[\"receipt\"]")
  inspect(r.rows[0][2].to_text(), content="abc")
}

///|
test "CLOSE ON is exclusive and BALANCES AT supports unit and cost views" {
  let r = queried(ledger_source(), "BALANCES AT units FROM CLOSE ON 2024-03-05")
  inspect(r.is_ok(), content="true")
  inspect(r.rows.length(), content="2")
  inspect(r.rows[0][1].to_text(), content="1000 USD")
  let c = queried(
    ledger_source(),
    "BALANCES AT cost FROM CLOSE ON 2024-03-06 WHERE account = 'Expenses:Food'",
  )
  inspect(c.is_ok(), content="true")
  inspect(c.rows[0][1].to_text(), content="20 USD")
}

///|
test "unsupported columns fail instead of returning null" {
  inspect(
    queried(ledger_source(), "SELECT misspelled").is_ok(),
    content="false",
  )
}

///|
test "OPEN ON carries assets and clears earlier earnings" {
  let r = queried(
    ledger_source(),
    "BALANCES AT units FROM OPEN ON 2024-03-01 CLOSE ON 2024-03-06",
  )
  inspect(r.is_ok(), content="true")
  let mut found = false
  for row in r.rows {
    if row[0].to_text() == "Equity:Earnings:Previous" {
      inspect(row[1].to_text(), content="-1000 USD")
      found = true
    }
  }
  inspect(found, content="true")
  inspect(
    queried(ledger_source(), "BALANCES FROM OPEN ON 0001-01-01").is_ok(),
    content="false",
  )
}

///|
test "hosts can match query failure categories" {
  let result = queried(ledger_source(), "SELECT unknown_column")
  inspect(result.failure() is Some(@query.Compilation(_)), content="true")
  inspect(
    queried(ledger_source(), "SELECT").failure() is Some(@query.Syntax(_)),
    content="true",
  )
  inspect(
    queried(ledger_source(), "SELECT account").failure() is None,
    content="true",
  )
}

///|
test "transaction source emits one row per transaction" {
  inspect(
    queried(ledger_source(), "SELECT date, narration FROM transactions").rows.length(),
    content="2",
  )
}

///|
test "FIFO reduction preserves separate booked posting costs" {
  let source = "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n2024-01-01 open Assets:Cash USD\n2024-01-02 * \"first\"\n  Assets:Stock 10 HOOL {10 USD}\n  Assets:Cash -100 USD\n2024-01-03 * \"second\"\n  Assets:Stock 10 HOOL {20 USD}\n  Assets:Cash -200 USD\n2024-01-04 * \"sell\"\n  Assets:Stock -15 HOOL {}\n  Assets:Cash 200 USD\n"
  let r = queried(
    source, "SELECT position WHERE date = 2024-01-04 AND account = 'Assets:Stock'",
  )
  inspect(r.rows.length(), content="2")
  inspect(r.rows[0][0].to_text(), content="-10 HOOL {10 USD, 2024-01-02}")
  inspect(r.rows[1][0].to_text(), content="-5 HOOL {20 USD, 2024-01-03}")
  let journal = queried(source, "JOURNAL Assets:Stock")
  inspect(journal.rows.length(), content="4")
}

///|
test "migration BQL boundaries carry codes and query locations" {
  for
    (text, expected) in [
      (
        "SELECT account FROM postings JOIN postings", "unsupported query.unsupported.join at BQL:1:30",
      ),
    ] {
    let result = queried(ledger_source(), text)
    assert_eq(result.error, Some(expected))
    assert_true(result.failure() is Some(@query.Unsupported(_)))
  }
  assert_true(queried(ledger_source(), "SELECT 'JOIN SELECT PIVOT'").is_ok())
  assert_true(
    queried(ledger_source(), "SELECT 'SELECT' WHERE narration = 'JOIN'").is_ok(),
  )
}

///|
test "non BMP strings survive and cannot hide trailing syntax" {
  let result = queried(ledger_source(), "SELECT '😀x😀', 'a\\😀b'")
  assert_true(result.is_ok())
  assert_eq(result.rows[0][0].to_text(), "😀x😀")
  assert_eq(result.rows[0][1].to_text(), "a\\😀b")
  assert_eq(
    queried(ledger_source(), "SELECT '😀' JOIN x").error,
    Some("unsupported query.unsupported.join at BQL:1:13"),
  )
  for
    (text, position) in [
      ("SELECT 1 😀", "1:10"),
      ("SELECT 1\n😀 JOIN x", "2:1"),
      ("SELECT 😀 JOIN x", "1:8"),
    ] {
    let result = queried(ledger_source(), text)
    assert_eq(
      result.error,
      Some("lexical query.invalid_character at BQL:" + position),
    )
    assert_true(result.failure() is Some(@query.Syntax(_)))
  }
}

///|
test "string length and slicing count Unicode code points" {
  let r = queried(
    ledger_source(),
    "SELECT length('😀中abc'), substr('abcdef',1,3), substr('abcdef',-4,-1), substr('😀中abc',0,2), substr('abc',99,100), substr('abc',2,1) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "5", "bc", "cde", "😀中", "", "",
  ])
}

///|
test "string functions distinguish null and empty payees" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 * \"\" \"😀中abc\"\n  Assets:Cash 1 USD\n  Equity:Opening -1 USD\n2024-01-03 * \"absent payee\"\n  Assets:Cash 1 USD\n  Equity:Opening -1 USD\n"
  let r = queried(
    source, "SELECT payee, length(payee), substr(payee,0,2), narration FROM transactions ORDER BY date",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 2)
  assert_true(r.rows[0][0] is @query.QText(""))
  assert_eq(r.rows[0][1].to_text(), "0")
  assert_eq(r.rows[0][3].to_text(), "😀中abc")
  assert_true(r.rows[1][0] is @query.QNull)
  assert_true(r.rows[1][1] is @query.QNull)
  assert_true(r.rows[1][2] is @query.QNull)
  let grouped = queried(
    source, "SELECT payee, count(*) FROM transactions GROUP BY payee ORDER BY payee",
  )
  assert_eq(grouped.rows.length(), 2)
  assert_true(grouped.rows[0][0] is @query.QNull)
  assert_true(grouped.rows[1][0] is @query.QText(""))
  assert_eq(grouped.rows[0][1].to_text(), "1")
  assert_eq(grouped.rows[1][1].to_text(), "1")
}

///|
test "BQL string backslashes and doubled quotes match oracle literally" {
  let r = queried(
    ledger_source(),
    "SELECT length('a\\tb'), substr('a''b',0,4) LIMIT 1",
  )
  assert_eq(r.rows[0][0].to_text(), "4")
  assert_eq(r.rows[0][1].to_text(), "a''b")
}

///|
test "new unsupported boundaries preserve positions" {
  for (q, code) in [("SELECT account WHERE account LIKE 'A%'", "like")] {
    let r = queried(ledger_source(), q)
    assert_true(r.failure() is Some(@query.Unsupported(_)))
    assert_true(r.error.unwrap().contains("query.unsupported." + code))
    assert_true(r.error.unwrap().contains("BQL:1:"))
  }
  assert_eq(
    queried(ledger_source(), "SELECT narration\nWHERE narration ~ '['").error,
    Some(
      "unsupported query.unsupported.regex: invalid or unsupported regular expression at BQL:2:19",
    ),
  )
}

///|
test "hash sources and star reject ambiguous results" {
  for q in ["SELECT count(*) FROM #Transactions"] {
    let r = queried(ledger_source(), q)
    assert_true(r.failure() is Some(@query.Compilation(_)))
    assert_true(r.error.unwrap().contains("BQL:1:"))
  }
  for
    q in [
      "SELECT count(*) FROM # transactions", "SELECT count(*) FROM #\npostings",
    ] {
    assert_true(queried(ledger_source(), q).failure() is Some(@query.Syntax(_)))
  }
  for
    q in [
      "SELECT count(*) FROM #transactions", "SELECT count(*) FROM #postings", "SELECT account FROM balances",
    ] {
    assert_true(queried(ledger_source(), q).is_ok())
  }
}

///|
test "set text is sorted without mutating JSON order" {
  let v = @query.QSet(["shop", "cafe"])
  assert_eq(v.to_text(), "cafe,shop")
  assert_eq(@query.QSet(["zulu", "alpha"]).to_text(), "alpha,zulu")
  assert_eq(v.to_json(), "[\"shop\",\"cafe\"]")
}

///|
test "only count accepts a star argument on either source" {
  for source in ["postings", "transactions"] {
    for
      expr in [
        "sum(*)", "year(*)", "meta(*)", "root(*)", "unknown(*)", "sum(year(*))",
      ] {
      let r = queried(ledger_source(), "SELECT " + expr + " FROM " + source)
      assert_true(r.failure() is Some(@query.Syntax(_)))
      assert_true(r.error.unwrap().contains("unexpected star"))
      assert_true(r.error.unwrap().contains("BQL:1:"))
    }
    let r = queried(ledger_source(), "SELECT count(*) FROM " + source)
    assert_true(r.is_ok())
    assert_eq(
      r.rows[0][0].to_text(),
      if source == "postings" {
        "4"
      } else {
        "2"
      },
    )
  }
  assert_eq(
    queried(ledger_source(), "SELECT\n  sum(*) FROM postings").error,
    Some("unexpected star at BQL:2:7"),
  )
}

///|
test "distinct star and nullable transaction counts" {
  let result = queried(
    ledger_source(),
    "SELECT DISTINCT account ORDER BY account LIMIT 2",
  )
  assert_true(result.is_ok())
  assert_eq(result.rows.length(), 2)
  assert_eq(result.rows[0][0].to_text(), "Assets:Cash")
  let star = queried(ledger_source(), "SELECT * FROM transactions")
  assert_true(star.is_ok())
  assert_eq(star.columns.length(), 7)
  assert_eq(star.rows.length(), 2)
  let counts = queried(
    ledger_source(),
    "SELECT count(payee), count(*), meta('absent') FROM transactions",
  )
  assert_true(counts.is_ok())
  assert_eq(counts.rows[0][0].to_text(), "0")
  assert_eq(counts.rows[0][1].to_text(), "2")
}

///|
test "distinct position uses exact oracle representation" {
  let r = queried(ledger_source(), "SELECT DISTINCT position")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 4)
}

///|
test "opening summaries retain transaction account sets" {
  let r = queried(ledger_source(), "SELECT accounts FROM OPEN ON 2024-03-01")
  assert_true(r.is_ok())
  assert_true(r.rows.length() > 0)
  assert_true(r.rows[0][0].to_text().contains("Equity:Opening-Balances"))
}

///|
test "directive tables preserve NULLs and validate schemas" {
  let r = queried(
    ledger_source(),
    "SELECT type, flag FROM entries ORDER BY date",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 5)
  assert_eq(r.rows[0][0].to_text(), "open")
  assert_eq(r.rows[0][1].to_json(), "null")
  assert_true(
    queried(ledger_source(), "SELECT account FROM prices").error
    .unwrap()
    .contains("query.invalid_column"),
  )
  assert_true(queried(ledger_source(), "SELECT meta FROM entries").is_ok())
  let empty = queried(ledger_source(), "SELECT count(*) FROM prices")
  assert_true(empty.is_ok())
  assert_eq(empty.rows.length(), 0)
}

///|
test "Unicode casing expands codepoints and handles contextual final sigma" {
  let r = queried(
    ledger_source(),
    "SELECT upper('ßıﬃ𐐨'), lower('ΟΣ ΟΣΑ İ𐐀') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "SSIFFI𐐀")
  assert_eq(r.rows[0][1].to_text(), "ος οσα i̇𐐨")
}

///|
test "last preserves final NULL and boolean results retain their type" {
  let source = ledger_source().replace(
    old="\"salary\"",
    new="\"Shop\" \"salary\"",
  )
  let r = queried(
    source, "SELECT first(payee),last(payee),min(true),max(false) FROM transactions",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "Shop")
  assert_eq(r.rows[0][1].to_json(), "null")
  assert_eq(r.rows[0][2].to_json(), "true")
  assert_eq(r.rows[0][3].to_text(), "FALSE")
}

///|
test "query errors distinguish compilation and oracle engine failures" {
  assert_true(
    queried(ledger_source(), "SELECT account FROM #prices").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT count(accounts) FROM entries").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "typed metadata directive references and failed assertion snapshots" {
  let r = queried(
    ledger_source(),
    "SELECT open,close FROM #accounts ORDER BY account",
  )
  assert_true(r.is_ok())
  assert_true(r.rows[0][0] is @query.QRecord("Open", _))
  assert_true(r.rows[0][1] is @query.QNull)
  let m = queried(
    ledger_source(),
    "SELECT getitem(meta,'lineno'),meta FROM #entries LIMIT 1",
  )
  assert_true(m.is_ok())
  assert_eq(m.rows[0][0].to_text(), "1")
  assert_true(m.rows[0][1] is @query.QDict(_))
  let b = queried(
    ledger_source() + "2024-04-01 balance Assets:Cash 0 USD\n",
    "SELECT discrepancy FROM #balances",
  )
  assert_true(
    b.rows[0][0] is @query.QAmount(a) && a.number.to_string() == "980",
  )
}

///|
test "function arguments use resolved source types" {
  assert_true(
    queried(ledger_source(), "SELECT length(NULL)").failure()
    is Some(@query.Compilation(_)),
  )
  let r = queried(
    ledger_source(),
    "SELECT repr(1),repr(1.0),repr(year(date)),str(cost(position)) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "1")
  assert_eq(r.rows[0][1].to_text(), "Decimal('1.0')")
  assert_eq(r.rows[0][2].to_text(), "2024")
}

///|
test "signed zero input rejects exact object and fingerprint projections" {
  let source = "2024-01-01 event \"kind\" \"value\"\n  signed: -0.00\n"
  let r = queried(source, "SELECT id,meta FROM #entries")
  assert_true(r.failure() is Some(@query.Unsupported(_)))
  assert_true(
    r.error.unwrap().contains("query.unsupported.decimal_representation"),
  )
  assert_true(
    queried(source, "SELECT DISTINCT position").failure()
    is Some(@query.Unsupported(_)),
  )
}

///|
test "nonhashable groups and structural comparisons fail explicitly" {
  let r = queried(ledger_source(), "SELECT meta FROM #entries GROUP BY meta")
  assert_true(r.failure() is Some(@query.Compilation(_)))
  let r = queried(ledger_source(), "SELECT meta FROM #entries WHERE meta=meta")
  assert_true(r.failure() is Some(@query.Compilation(_)))
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"one\" #a #b\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-03 * \"two\" #b #a\n  Assets:A 1 USD\n  Equity:A -1 USD\n"
  let r = queried(source, "SELECT count(*) GROUP BY tags")
  assert_true(r.failure() is Some(@query.Compilation(_)))
}

///|
test "signed zero query arithmetic preserves exact representation" {
  for expression in ["0.0/-1", "safediv(0.0,-1)", "0.0*-1"] {
    let r = queried(ledger_source(), "SELECT repr(" + expression + ") LIMIT 1")
    assert_true(r.is_ok())
    assert_eq(r.rows[0][0].to_text(), "Decimal('-0.0')")
  }
}

///|
test "legacy multi currency inventory HAVING does not become an object error" {
  let source = "2024-01-01 open Assets:A\n2024-01-01 open Equity:A\n2024-01-02 * \"USD\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-03 * \"EUR\"\n  Assets:A 1 EUR\n  Equity:A -1 EUR\n"
  let r = queried(
    source, "SELECT account,sum(units) GROUP BY account HAVING sum(units)>0",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 0)
}

///|
test "date and text metadata groups preserve their Python types" {
  let source = "2024-01-01 event \"date\" \"one\"\n  value: 2024-01-01\n2024-01-02 event \"text\" \"two\"\n  value: \"2024-01-01\"\n"
  let r = queried(source, "SELECT count(*) FROM #events GROUP BY meta('value')")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 2)
  assert_eq(r.rows[0][0].to_text(), "1")
  assert_eq(r.rows[1][0].to_text(), "1")
}

///|
test "cached sorting preserves duplicate order and Unicode scalar order" {
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n" +
    "2024-01-02 * \"😀\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n" +
    "2024-01-03 * \"\"\n  Assets:A 2 USD\n  Equity:A -2 USD\n" +
    "2024-01-04 * \"\"\n  Assets:A 3 USD\n  Equity:A -3 USD\n"
  let r = queried(
    source, "SELECT narration,date FROM transactions ORDER BY narration",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][1].to_text(), "2024-01-03")
  assert_eq(r.rows[1][1].to_text(), "2024-01-04")
  assert_eq(r.rows[2][1].to_text(), "2024-01-02")
  let r = queried(
    source, "SELECT narration FROM transactions ORDER BY length(narration),date DESC",
  )
  assert_eq(r.rows[0][0].to_text(), "")
}

///|
test "integer arithmetic and aggregates preserve more than 28 digits" {
  let n = "123456789012345678901234567890"
  let r = queried(
    ledger_source(),
    "SELECT " + n + "+1," + n + "-1," + n + "*10,sum(" + n + ")",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "123456789012345678901234567891")
  assert_eq(r.rows[0][1].to_text(), "123456789012345678901234567889")
  assert_eq(r.rows[0][2].to_text(), "1234567890123456789012345678900")
  let count = queried(ledger_source(), "SELECT count(*)").rows[0][0].to_text()
  let expected = queried(
    ledger_source(),
    "SELECT " + n + "*" + count + " LIMIT 1",
  )
  assert_eq(r.rows[0][3].to_text(), expected.rows[0][0].to_text())
}

///|
test "implicit grouping preserves first key order and NULL groups" {
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"one\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-03 * \"Shop\" \"two\"\n  Assets:A 2 USD\n  Equity:A -2 USD\n"
  let r = queried(source, "SELECT account,count(*)")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 2)
  assert_eq(r.rows[0][0].to_text(), "Assets:A")
  assert_eq(r.rows[0][1].to_text(), "2")
  assert_eq(
    queried(source, "SELECT payee,count(*) FROM transactions").rows.length(),
    2,
  )
  assert_eq(queried(source, "SELECT count(*) WHERE false").rows.length(), 0)
  assert_true(
    queried(source, "SELECT count(*) WHERE count(*)>0").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT bool(balance)").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "aggregate clauses validate grouping targets and HAVING" {
  for
    text in [
      "SELECT account,count(*) ORDER BY payee", "SELECT account,count(*) ORDER BY account_sortkey(account)",
      "SELECT count(*) ORDER BY number", "SELECT account,count(*) GROUP BY account HAVING account ~ 'Assets'",
      "SELECT account,count(*) GROUP BY account HAVING true",
    ] {
    assert_true(
      queried(ledger_source(), text).failure() is Some(@query.Compilation(_)),
    )
  }
  for
    text in [
      "SELECT count(DISTINCT number)", "SELECT account,count(*) LIMIT -1",
    ] {
    assert_true(
      queried(ledger_source(), text).failure() is Some(@query.Syntax(_)),
    )
  }
}

///|
test "implicit set groups use membership equality and preserve first encounter" {
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"one\" #b #a ^x\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-03 * \"two\" #a #b ^x\n  Assets:A 2 USD\n  Equity:A -2 USD\n2024-01-04 * \"empty\"\n  Assets:A 3 USD\n  Equity:A -3 USD\n"
  let r = queried(source, "SELECT tags,links,count(*) FROM transactions")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 2)
  assert_eq(r.rows[0][2].to_text(), "2")
  assert_eq(r.rows[1][2].to_text(), "1")
  assert_true(
    queried(source, "SELECT tags,count(*) FROM transactions GROUP BY tags").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "relation schema aliases positions and nested aggregation" {
  let r = queried(
    ledger_source(),
    "SELECT a,sum(n) AS total FROM (SELECT account AS a,number AS n WHERE number>0) GROUP BY 1 ORDER BY 2 DESC",
  )
  assert_true(r.is_ok())
  assert_eq(r.columns, ["a", "total"])
  assert_eq(r.rows.length(), 2)
  assert_eq(r.rows[0][0].to_text(), "Assets:Cash")
  assert_eq(r.rows[0][1].to_text(), "1000")
  let nested = queried(
    ledger_source(),
    "SELECT * FROM (SELECT * FROM (SELECT account AS a LIMIT 1))",
  )
  assert_eq(nested.columns, ["a"])
  assert_eq(nested.rows.length(), 1)
  for
    q in [
      "SELECT account AS a WHERE a='x'", "SELECT account ORDER BY 0", "SELECT account ORDER BY 2",
      "SELECT missing FROM (SELECT account)", "SELECT meta('x') FROM (SELECT account)",
    ] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Compilation(_)),
    )
  }
}

///|
test "pivot creates sorted schema after limit and fills missing cells" {
  let r = queried(
    ledger_source(),
    "SELECT account AS a,currency AS c,sum(number) AS n,count(*) AS k PIVOT BY a,c",
  )
  assert_true(r.is_ok())
  assert_eq(r.columns, ["a/c", "USD/n", "USD/k"])
  assert_eq(r.rows.length(), 3)
  assert_eq(r.rows[0][0].to_text(), "Assets:Cash")
  assert_eq(r.rows[0][1].to_text(), "980")
  let empty = queried(
    ledger_source(),
    "SELECT account,currency,count(*) WHERE false PIVOT BY 1,2",
  )
  assert_eq(empty.columns, ["account/currency"])
  assert_eq(empty.rows.length(), 0)
  let limited = queried(
    ledger_source(),
    "SELECT account,currency,count(*) PIVOT BY 1,2 LIMIT 1",
  )
  assert_eq(limited.rows.length(), 1)
  assert_eq(limited.rows[0][0].to_text(), "Assets:Cash")
  assert_true(
    queried(ledger_source(), "SELECT account,currency,count(*) PIVOT BY 1,1").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "query prices preserve inverse precision dates and cost-currency conversion" {
  let source = ledger_source() +
    "2024-01-01 price EUR 2 USD\n2024-01-02 price USD 0.6 EUR\n"
  let r = queried(
    source, "SELECT repr(getprice('USD','EUR')),repr(getprice('EUR','USD')),getprice('USD','USD'),getprice('USD','JPY') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "Decimal('0.5999999999999999999999999999')")
  assert_eq(r.rows[0][1].to_text(), "Decimal('1.666666666666666666666666667')")
  assert_eq(r.rows[0][2].to_text(), "1")
  assert_true(r.rows[0][3] is @query.QNull)
  let old = queried(source, "SELECT getprice('EUR','USD',2024-01-01) LIMIT 1")
  assert_eq(old.rows[0][0].to_text(), "2")
  let converted = queried(
    source, "SELECT convert(units(position),'EUR'),possign(number,'Income:X') WHERE account='Assets:Cash' LIMIT 1",
  )
  assert_true(converted.is_ok())
  assert_eq(converted.rows[0][0].to_text(), "599.9999999999999999999999999 EUR")
  assert_eq(converted.rows[0][1].to_text(), "-1000")
}

///|
test "date parts ISO week boundaries and truncation errors" {
  let r = queried(
    ledger_source(),
    "SELECT date_part('week',2021-01-01),date_part('dow',2024-02-29),date_part('epoch',0001-01-01),date_trunc('week',2024-02-29),date_part('day',date) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "53", "3", "-62135596800", "2024-02-26", "",
  ])
  assert_true(
    queried(ledger_source(), "SELECT date_trunc('decade',0001-01-01)").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "string functions preserve declared unsupported boundaries" {
  let r = queried(
    ledger_source(),
    "SELECT maxwidth(' a  b cdef ghi ',10),grep('a(.)','bacd'),grepn('a(.)','bacd',1),has_account('assets'),joinstr(tags) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "a b [...]", "ac", "c", "TRUE", "",
  ])
  for q in ["SELECT grep('(?=a)','a')"] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Unsupported(_)),
    )
  }
  assert_true(
    queried(ledger_source(), "SELECT grepn('a','a',1)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT maxwidth('',4)").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "predicate projections preserve NULL and group through the relation schema" {
  let r = queried(
    ledger_source(),
    "SELECT number>0 AS positive,payee IS NULL AS missing,payee~'x' AS matches,NULL AND true AS a,NULL OR true AS b,NOT NULL AS c LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.columns, ["positive", "missing", "matches", "a", "b", "c"])
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "TRUE", "TRUE", "", "", "TRUE", "TRUE",
  ])
  let grouped = queried(
    ledger_source(),
    "SELECT number>0 AS positive,count(*) AS n ORDER BY 1",
  )
  assert_true(grouped.is_ok())
  assert_eq(grouped.rows.map(fn(r) { r.map(fn(v) { v.to_text() }) }), [
    ["FALSE", "2"],
    ["TRUE", "2"],
  ])
  let nested = queried(
    ledger_source(),
    "SELECT count(*)>0 AS nonempty FROM (SELECT number>0 AS positive) WHERE positive",
  )
  assert_true(nested.is_ok())
  assert_eq(nested.rows[0][0].to_text(), "TRUE")
  for q in ["SELECT NULL=1", "SELECT true=true", "SELECT 1~'x'"] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Compilation(_)),
    )
  }
  for q in ["SELECT sum(position) AND true", "SELECT NOT sum(position)"] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Evaluation(_)),
    )
  }
}

///|
test "relation names retain expression spelling and quoted aliases" {
  let r = queried(
    ledger_source(),
    "SELECT * FROM (SELECT 1 + 2, UPPER( account ),account AS \"A B\" LIMIT 1)",
  )
  assert_true(r.is_ok())
  assert_eq(r.columns, ["1 + 2", "UPPER( account )", "A B"])
  assert_eq(r.rows[0][0].to_text(), "3")
  let sub = queried(ledger_source(), "SELECT subst('(a)','x','banana') LIMIT 1")
  assert_true(sub.is_ok())
  assert_eq(sub.rows[0][0].to_text(), "bxnxnx")
}

///|
test "pivot retains first equal axis representation and last cell" {
  let source = "2024-01-01 open Assets:Cash\n2024-01-01 open Equity:Opening\n2024-01-02 * \"USD\"\n  Assets:Cash 1.00 USD\n  Equity:Opening -1.00 USD\n2024-01-03 * \"EUR\"\n  Assets:Cash 1.0 EUR\n  Equity:Opening -1.0 EUR\n"
  let r = queried(source, "SELECT currency,number,count(*) PIVOT BY 1,2")
  assert_true(r.is_ok())
  assert_eq(r.columns, ["currency/number", "-1.00", "1.00"])
  let sorted = queried(
    source, "SELECT currency,number,count(*) ORDER BY 1 PIVOT BY 1,2",
  )
  assert_eq(sorted.columns, ["currency/number", "-1.0", "1.0"])
}

///|
test "relation metadata functions bind schema columns instead of ledger row state" {
  let r = queried(
    ledger_source(),
    "SELECT any_meta('lineno'),entry_meta('lineno') FROM (SELECT entry,meta) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_true(r.rows[0][0].to_text() != "")
  assert_true(r.rows[0][1].to_text() != "")
  assert_true(
    queried(ledger_source(), "SELECT any_meta('lineno') FROM (SELECT entry)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "transaction unknown columns are compilation errors" {
  for
    q in [
      "SELECT missing FROM #transactions", "SELECT payee AS account,account AS payee FROM #transactions",
    ] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Compilation(_)),
    )
  }
}

///|
test "round preserves negative zero without changing Decimal arithmetic" {
  let r = queried(
    ledger_source(),
    "SELECT repr(round(-0.4)),repr(round(-0.04,1)),repr(round(round(-0.4),2)),bool(round(-0.4)),round(-0.4)=0 LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "Decimal('-0')")
  assert_eq(r.rows[0][1].to_text(), "Decimal('-0.0')")
  assert_eq(r.rows[0][2].to_text(), "Decimal('-0.00')")
  assert_eq(r.rows[0][3].to_text(), "FALSE")
  assert_eq(r.rows[0][4].to_text(), "TRUE")
}

///|
test "calendar scalar evaluators preserve types NULLs and interval boundaries" {
  let r = queried(
    ledger_source(),
    "SELECT repr(interval('14 months')),interval('invalid'),date_bin('1 month',2024-02-29,2024-01-31),date_bin(interval('1 month'),2024-03-31,2024-01-31),date_bin('2 days',2024-01-01,2024-01-04) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "relativedelta(years=+1, months=+2)", "", "2024-01-31", "2024-03-29", "2023-12-31",
  ])
  assert_true(
    queried(ledger_source(), "SELECT date_bin('0 days',2024-01-01,2024-01-01)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT interval(NULL)").failure()
    is Some(@query.Compilation(_)),
  )
  let r = queried(
    ledger_source(),
    "SELECT today(),parse_date('March 2024'),parse_date('Feb 29, 2024'),parse_date('29/02/2024','%d/%m/%Y'),parse_date('2024-060','%Y-%j') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_true(r.rows[0][0] is @query.QDate(_))
  if @env.get_env_var("MOONBEAN_ORACLE_TODAY") is Some(expected) {
    assert_eq(r.rows[0][0].to_text(), expected)
  }
  assert_eq(r.rows[0][2].to_text(), "2024-02-29")
  assert_eq(r.rows[0][3].to_text(), "2024-02-29")
  assert_eq(r.rows[0][4].to_text(), "2024-02-29")
  assert_true(
    queried(ledger_source(), "SELECT parse_date('2024-02-30')").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "PRINT carries directives through its distinct text result" {
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"one\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n"
  let r = queried(source, "PRINT FROM date=2024-01-02")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 1)
  assert_eq(r.columns, ["ROW(*)"])
  assert_true(r.kind is @query.DirectiveText(_))
  assert_true(r.to_json().contains("\"kind\":\"print\""))
  assert_eq(
    r.to_text(),
    "\n2024-01-02 * \"one\"\n  Assets:A   1 USD\n  Equity:A  -1 USD\n",
  )
  assert_eq(queried(source, "PRINT FROM false").to_text(), "")
  assert_true(
    queried(source, "PRINT WHERE account='Assets:A'").failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(source, "PRINT FROM missing=1").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "empty substitution and hyphen shortening match oracle" {
  let r = queried(
    ledger_source(),
    "SELECT subst('','X','ab'),subst('a*','X','aba'),maxwidth('abc-def ghi',10),maxwidth('a-b-c-d-e-f',10) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "XaXbX", "XXbXX", "abc- [...]", "a-b- [...]",
  ])
}

///|
test "scalar aggregate DISTINCT uses computed grouping keys" {
  let r = queried(ledger_source(), "SELECT DISTINCT upper(account),sum(number)")
  assert_true(r.is_ok())
  assert_true(r.rows.length() > 0)
}

///|
test "NULL object conversions and signed interval parsing" {
  let r = queried(
    ledger_source(),
    "SELECT date(NULL),int(NULL),decimal(NULL),repr(interval('+2 days')),repr(round(-1,-2)) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "", "", "", "relativedelta(days=+2)", "0",
  ])
}

///|
test "dateutil time labels discard validated time components" {
  let r = queried(
    ledger_source(),
    "SELECT parse_date('2024-02-29 12h30m'),parse_date('2024-02-29 12:30 UTC+3'),parse_date('2024-02-29 12:30 EST') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "2024-02-29", "2024-02-29", "2024-02-29",
  ])
}

///|
test "rounded negative zero survives numeric consumers" {
  let r = queried(
    ledger_source(),
    "SELECT repr(round(-0.4)*1),repr(round(-0.4)*-1),repr(round(-0.4)-0),repr(round(-0.4)+0),repr(safediv(round(-0.4),2)) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "Decimal('-0')", "Decimal('0')", "Decimal('-0')", "Decimal('0')", "Decimal('-0')",
  ])
}

///|
test "PRINT validates entry predicates and period lower bounds" {
  for
    q in [
      "PRINT FROM count(*)>0", "PRINT FROM sum(1)>0", "PRINT FROM accounts~'Assets'",
      "PRINT FROM date='2024'",
    ] {
    assert_true(
      queried(ledger_source(), q).failure() is Some(@query.Compilation(_)),
    )
  }
  assert_true(
    queried(ledger_source(), "PRINT FROM OPEN ON 0001-01-01").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "PRINT preserves failed balance discrepancies and recovery" {
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"opening\"\n  Assets:A 10 USD\n  Equity:A -10 USD\n2024-01-03 balance Assets:A 9 USD\n"
  assert_true(
    queried(source, "PRINT").to_text().contains("9 USD   ; Diff: 1 USD"),
  )
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"two missing\"\n  Assets:A\n  Equity:A\n"
  assert_true(!queried(source, "PRINT").to_text().contains("two missing"))
  let source = "2024-01-01 open Assets:A USD\n2024-01-02 open Assets:A USD\n"
  let r = queried(source, "PRINT FROM OPEN ON 2024-01-04")
  assert_true(r.is_ok())
  assert_eq(r.rows.length(), 1)
  assert_true(r.to_text().has_prefix("2024-01-01 open"))
}

///|
test "membership lists BETWEEN modulo and inventory getitem" {
  let r = queried(
    ledger_source(),
    "SELECT 1 IN (1,2),1 NOT IN (2,3),NULL IN (1,2),1 BETWEEN 0.0 AND 2,length((1,NULL,true)),repr(-5%3),repr(-5.0%3.0),getitem(balance,'USD'),repr(decimal('-0.00')),repr(-0.0),repr(0.0/decimal('-0.01')) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "TRUE", "TRUE", "", "TRUE", "2", "1", "Decimal('-2.0')", "", "Decimal('-0.00')",
    "Decimal('0.0')", "Decimal('-0E+1')",
  ])
  assert_true(
    queried(ledger_source(), "SELECT (account,2)").failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT (-1,2)").failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT 1 BETWEEN NULL AND 2").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "FROM filters and closing clearing transform posting sources" {
  let filtered = queried(
    ledger_source(),
    "SELECT account FROM account='Assets:Cash'",
  )
  assert_true(filtered.is_ok())
  assert_eq(filtered.rows.length(), 2)
  let cleared = queried(
    ledger_source(),
    "SELECT account,number FROM CLEAR WHERE flag='T'",
  )
  assert_true(cleared.is_ok())
  assert_eq(cleared.rows.length(), 4)
  let closed = queried(
    ledger_source(),
    "SELECT account FROM CLOSE ON 2024-03-01",
  )
  assert_true(closed.is_ok())
  assert_eq(closed.rows.length(), 2)
}

///|
test "quoted words resolve case sensitively in their source schema" {
  let rows = queried(
    ledger_source(),
    "SELECT \"account\",\"ACCOUNT\",'account' LIMIT 1",
  )
  assert_true(rows.is_ok())
  assert_eq(rows.rows[0][0].to_text(), "Assets:Cash")
  assert_eq(rows.rows[0][1].to_text(), "ACCOUNT")
  assert_eq(rows.rows[0][2].to_text(), "account")
  let transaction = queried(
    ledger_source(),
    "SELECT \"account\" FROM #transactions LIMIT 1",
  )
  assert_true(transaction.is_ok())
  assert_eq(transaction.rows[0][0].to_text(), "account")
}

///|
test "mixed aggregate clauses bind ordinary columns to the final source row" {
  let result = queried(
    ledger_source(),
    "SELECT account,count(*) GROUP BY account HAVING account=first(account)",
  )
  assert_true(result.is_ok())
  assert_eq(result.rows.length(), 1)
  assert_eq(result.rows[0][0].to_text(), "Assets:Cash")
  let ordered = queried(
    ledger_source(),
    "SELECT account,sum(number) GROUP BY account ORDER BY sum(number)+number",
  )
  assert_true(ordered.is_ok())
  assert_eq(ordered.rows[0][0].to_text(), "Income:Salary")
}

///|
test "canonical JOURNAL BALANCES and structural DISTINCT share the select plan" {
  let journal = queried(ledger_source(), "JOURNAL")
  assert_true(journal.is_ok())
  assert_eq(journal.columns.length(), 7)
  assert_eq(journal.rows.length(), 4)
  let balances = queried(ledger_source(), "BALANCES AT cost")
  assert_true(balances.is_ok())
  assert_eq(balances.columns[1], "SUM(cost(position))")
  let inventories = queried(
    ledger_source(),
    "SELECT DISTINCT sum(position) GROUP BY date",
  )
  assert_true(inventories.is_ok())
  assert_eq(inventories.rows.length(), 1)
  assert_true(queried(ledger_source(), "SELECT DISTINCT meta").is_ok())
}

///|
test "portable regex captures quantifiers and Python replacement escapes" {
  let result = queried(
    ledger_source(),
    "SELECT subst('(a)(b)?','\\2-\\1-\\g<0>','a'),grep('a{2}','aaab'),grep('(?:a)(b)','ab'),grep('a.b','a\nb') LIMIT 1",
  )
  assert_true(result.is_ok())
  assert_eq(result.rows[0][0].to_text(), "-a-a")
  assert_eq(result.rows[0][1].to_text(), "aa")
  assert_eq(result.rows[0][2].to_text(), "ab")
  assert_eq(result.rows[0][3].to_json(), "null")
  assert_true(
    queried(ledger_source(), "SELECT subst('(a)','\\2','a')").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "structural comparison signatures match compilation and dynamic values" {
  for expr in ["meta", "entry", "balance", "position", "tags", "(1,2)"] {
    assert_true(
      queried(ledger_source(), "SELECT " + expr + "=" + expr).failure()
      is Some(@query.Compilation(_)),
    )
    assert_true(
      queried(ledger_source(), "SELECT account WHERE " + expr + "=" + expr).failure()
      is Some(@query.Compilation(_)),
    )
  }
  let value = queried(ledger_source(), "SELECT meta('lineno')=5 LIMIT 1")
  assert_true(value.is_ok())
}

///|
test "lazy substitutions execute when no adjacent nonempty retry is needed" {
  let result = queried(
    ledger_source(),
    "SELECT subst('a+?','X','aaab'),subst('a*?','X',''),subst('(a*)+?','X','aaa') LIMIT 1",
  )
  assert_true(result.is_ok())
  assert_eq(result.rows[0].map(fn(v) { v.to_text() }), ["XXXb", "X", "XX"])
  assert_true(
    queried(ledger_source(), "SELECT subst('a*?','X','ab')").failure()
    is Some(@query.Unsupported(_)),
  )
}

///|
test "review date and calendar interval arithmetic" {
  let r = queried(
    ledger_source(),
    "SELECT 2024-01-01+1,1+2024-01-01,2024-01-05-1,2024-01-05-2024-01-01,2024-01-31+interval('1 month'),interval('1 month')+2024-01-31,repr(interval('13 months')+interval('2 days')) LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "2024-01-02", "2024-01-02", "2024-01-04", "4", "2024-02-29", "2024-02-29", "relativedelta(years=+1, months=+1, days=+2)",
  ])
  assert_true(
    queried(ledger_source(), "SELECT count(*) WHERE date>today()-1000").is_ok(),
  )
  assert_true(
    queried(ledger_source(), "SELECT interval('1 day')-2024-01-01").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT 9999-12-31+1").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "review leading two digit years and round carry overflow" {
  let r = queried(
    ledger_source(),
    "SELECT parse_date('99-12-31'),parse_date('99/12/31'),parse_date('50-06-15') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "1999-12-31", "1999-12-31", "2050-06-15",
  ])
  assert_true(
    queried(ledger_source(), "SELECT round(9999999999999999999999999999.5)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT round(999999999999999999999999999.5)").is_ok(),
  )
  assert_true(
    queried(ledger_source(), "SELECT missing FROM #nope").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "review OPEN preserves source order and CLEAR uses the last retained date" {
  let source = "2024-01-01 open Assets:A\n2024-01-01 open Equity:A\n2024-01-02 * \"Z\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-02 * \"A\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n"
  let r = queried(source, "SELECT narration FROM OPEN ON 2024-01-01")
  assert_true(r.is_ok())
  assert_eq(r.rows.map(fn(row) { row[0].to_text() }), ["Z", "Z", "A", "A"])
  let cost = "2024-01-01 open Assets:A\n2024-01-01 open Income:Stock XXX \"NONE\"\n2024-01-02 * \"income\"\n  Income:Stock -5 XXX {100 USD}\n  Assets:A 500 USD\n"
  let clear = queried(
    cost, "SELECT date FROM CLOSE ON 2024-03-01 CLEAR WHERE flag='T'",
  )
  assert_true(clear.is_ok())
  assert_eq(clear.rows[0][0].to_text(), "2024-01-02")
  let opening = queried(
    cost, "SELECT str(position) FROM OPEN ON 2024-01-05 WHERE account='Equity:Earnings:Previous'",
  )
  assert_true(opening.is_ok())
  assert_eq(opening.rows[0][0].to_text(), "-500 USD")
}

///|
test "review PRINT preserves narration fields tags and directive grouping" {
  let source = "2024-01-01 open Assets:A\n2024-01-02 * \"Payee\" \"\" #zulu #alpha ^ref.2 ^receipt-1\n  Assets:A 1 USD\n  Assets:A -1 USD\n2024-01-03 query \"q1\" \"SELECT 1\"\n2024-01-03 query \"q2\" \"SELECT 2\"\n"
  let printed = queried(source, "PRINT").to_text()
  assert_true(
    printed.contains("* \"Payee\" \"\" #alpha #zulu ^receipt-1 ^ref.2"),
  )
  assert_true(printed.contains("query \"q1\" \"SELECT 1\"\n2024-01-03 query"))
  let reparsed = queried(printed, "SELECT payee,narration LIMIT 1")
  assert_eq(reparsed.rows[0].map(fn(v) { v.to_text() }), ["Payee", ""])
  assert_true(
    queried(source, "PRINT FROM entry_meta('bank') IS NOT NULL").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "PRINT FROM any_meta('bank') IS NOT NULL").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "review coalesce evaluates uniform arguments and scoped global case flags" {
  let r = queried(
    ledger_source(),
    "SELECT coalesce(payee,'x'),coalesce(NULL,NULL),grep('(?i)A','a') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_eq(r.rows[0][0].to_text(), "x")
  assert_eq(r.rows[0][1].to_json(), "null")
  assert_eq(r.rows[0][2].to_text(), "a")
  assert_true(
    queried(ledger_source(), "SELECT coalesce(NULL,'x')").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT coalesce()").failure()
    is Some(@query.Evaluation(_)),
  )
}

///|
test "review recursion budgets return clean errors on every target" {
  for
    q in [
      "SELECT " + "(".repeat(20000) + "1" + ")".repeat(20000),
      "SELECT " + "NOT ".repeat(300) + "true",
      "SELECT " + "1+".repeat(300) + "1",
      "PRINT FROM " + "(".repeat(300) + "true" + ")".repeat(300),
    ] {
    assert_true(queried(ledger_source(), q).failure() is Some(@query.Syntax(_)))
  }
  assert_true(
    queried(
      ledger_source(),
      "SELECT " + "(".repeat(256) + "1" + ")".repeat(256),
    ).is_ok(),
  )
}

///|
test "PRINT applies predicates after complete period transformations" {
  let source = "2024-01-01 open Assets:A\n2024-01-01 open Income:A\n2024-01-02 * \"One\"\n  Assets:A 10 USD\n  Income:A -10 USD\n2024-01-10 balance Assets:A 10 USD\n"
  let clear = queried(source, "PRINT FROM narration='One' CLEAR").to_text()
  assert_false(clear.contains("Transfer balance"))
  let dates = queried(source, "PRINT FROM date>=2024-01-05 CLEAR").to_text()
  assert_true(dates.contains("2024-01-10 T"))
  assert_eq(
    queried(source, "PRINT FROM narration='One' OPEN ON 2024-01-03").to_text(),
    "",
  )
}

///|
test "PRINT Unicode account alignment counts complete scalar values" {
  let source = "2024-01-01 open Assets:𐐀 USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"unicode\"\n  Assets:𐐀 1 USD\n  Equity:A -1 USD\n"
  let r = queried(source, "PRINT")
  assert_true(r.is_ok())
  assert_true(r.to_text().contains("open Assets:𐐀" + " ".repeat(40) + "USD"))
  assert_true(r.to_text().contains("Assets:𐐀   1 USD"))
}

///|
test "host calendar applies to today and partial dates and resets safely" {
  defer @query.set_local_date_provider(None)
  let mut date = 20240229
  let mut seen_ms = 0.0
  @query.set_local_date_provider(
    Some(fn(ms) {
      seen_ms = ms
      date
    }),
  )
  let r = queried(
    ledger_source(),
    "SELECT today(),parse_date('March'),parse_date('99-12-31') LIMIT 1",
  )
  assert_true(r.is_ok())
  assert_true(seen_ms > 0.0)
  assert_eq(r.rows[0][0].to_text(), "2024-02-29")
  assert_eq(r.rows[0][1].to_text(), "2024-03-29")
  assert_eq(r.rows[0][2].to_text(), "1999-12-31")
  date = 20250301
  assert_eq(
    queried(ledger_source(), "SELECT today() LIMIT 1").rows[0][0].to_text(),
    "2025-03-01",
  )
  @query.set_local_date_provider(None)
  let default_date = queried(ledger_source(), "SELECT today() LIMIT 1").rows[0][0]
  for invalid in [0, -1, 20250229, 20241301, 100000101] {
    @query.set_local_date_provider(Some(fn(_) { invalid }))
    assert_eq(
      queried(ledger_source(), "SELECT today() LIMIT 1").rows[0][0].to_text(),
      default_date.to_text(),
    )
  }
}

///|
test "amount and empty metadata retain typed query and PRINT values" {
  let source = "2024-01-01 open Assets:A USD\n  value: 1.00 USD\n  empty:\n"
  let result = queried(
    source, "SELECT meta('value'),meta('empty') FROM #entries",
  )
  assert_true(result.error is None)
  assert_eq(result.rows[0][0].to_text(), "1.00 USD")
  assert_true(result.rows[0][1] is @query.QNull)
  let printed = queried(source, "PRINT")
  guard printed.kind is @query.DirectiveText(text) else { abort("PRINT") }
  assert_true(text.contains("  value: 1.00 USD\n  empty: \n"))
}

///|
test "NULLIF handles equal and nullable values without altering COALESCE" {
  let cases = [
    ("SELECT nullif(10.0,10) LIMIT 1", ""),
    ("SELECT nullif(10,NULL) LIMIT 1", "10"),
    ("SELECT nullif(NULL,10) LIMIT 1", ""),
    ("SELECT nullif('VAT','vat') LIMIT 1", "VAT"),
    ("SELECT length(nullif('VAT','NET')) LIMIT 1", "3"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
}

///|
test "AVG performs exact accumulation and one decimal division" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Start USD\n2024-01-02 * \"lo\"\n  Assets:Cash 0.1 USD\n  Equity:Start -0.1 USD\n2024-01-03 * \"hi\"\n  Assets:Cash 0.2 USD\n  Equity:Start -0.2 USD\n"
  let q = queried(
    source, "SELECT avg(number(units)) WHERE account = 'Assets:Cash'",
  )
  assert_true(q.error is None)
  assert_eq(q.rows[0][0].to_text(), "0.15")
  let empty = queried(
    source, "SELECT avg(number(units)) WHERE account = 'Assets:Missing'",
  )
  assert_true(empty.error is None)
  assert_eq(empty.rows.length(), 0)
  let nullable = queried(source, "SELECT avg(NULL)")
  assert_true(nullable.error is None)
  assert_true(nullable.rows[0][0] is @query.QNull)
  let nested = queried(source, "SELECT avg(sum(number(units)))")
  assert_true(nested.error is Some(_))
  let integer = queried(source, "SELECT avg(3)")
  assert_true(integer.error is None)
  assert_eq(integer.rows[0][0].to_text(), "3")
}

///|
test "COUNT_DISTINCT counts scalar identities and discards NULL" {
  let cases = [
    ("SELECT count_distinct(account)", "3"),
    ("SELECT count_distinct(payee)", "0"),
    ("SELECT count_distinct(NULL)", "0"),
    ("SELECT count_distinct(currency)", "1"),
    ("SELECT count_distinct(number(units))", "4"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
}

///|
test "MEDIAN sorts numeric amounts and handles empty/odd/even groups" {
  let cases = [
    ("SELECT median(number(units))", "0"),
    ("SELECT median(number(units)) WHERE account = 'Assets:Cash'", "490"),
    ("SELECT median(number(units)) WHERE account = 'Expenses:Food'", "20"),
    ("SELECT median(NULL)", ""),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
}

///|
test "COLLECT produces a typed list in input order, retaining nulls" {
  let q = queried(
    ledger_source(),
    "SELECT collect(account) WHERE number(units) > 0",
  )
  assert_true(q.error is None)
  assert_eq(q.rows.length(), 1)
  assert_eq(q.rows[0][0].to_json(), "[\"Assets:Cash\",\"Expenses:Food\"]")
  let nested = queried(
    ledger_source(),
    "SELECT length(xs) FROM (SELECT collect(payee) AS xs)",
  )
  assert_true(nested.error is None)
  assert_eq(nested.rows[0][0].to_text(), "4")
  let empty = queried(
    ledger_source(),
    "SELECT collect(account) WHERE number(units) = 0",
  )
  assert_true(empty.error is None)
  assert_eq(empty.rows.length(), 0)
}

///|
test "non-null endpoints pick the first and last known payee, retaining old LAST" {
  let source = "2024-01-01 * \"unknown1\"\n2024-01-02 * \"Bob\" \"dentist\"\n2024-01-03 * \"Alice\" \"clinic\"\n2024-01-04 * \"unknown2\"\n"
  let q = queried(
    source, "SELECT first_non_null(payee), last_non_null(payee), last(payee) FROM transactions",
  )
  assert_true(q.error is None)
  assert_eq(q.rows[0][0].to_text(), "Bob")
  assert_eq(q.rows[0][1].to_text(), "Alice")
  assert_true(q.rows[0][2] is @query.QNull)
  let missing = queried(source, "SELECT last_non_null(NULL) FROM transactions")
  assert_true(missing.error is None)
  assert_true(missing.rows[0][0] is @query.QNull)
}

///|
test "OFFSET slices ordered or distinct output without integer overflow" {
  let page = queried(
    ledger_source(),
    "SELECT DISTINCT account ORDER BY account LIMIT 1 OFFSET 1",
  )
  assert_true(page.error is None)
  assert_eq(page.rows.length(), 1)
  assert_eq(page.rows[0][0].to_text(), "Expenses:Food")
  let inner = queried(
    ledger_source(),
    "SELECT a FROM (SELECT DISTINCT account AS a ORDER BY a OFFSET 1) ORDER BY a",
  )
  assert_true(inner.error is None)
  assert_eq(inner.rows.map(fn(r) { r[0].to_text() }), [
    "Expenses:Food", "Income:Salary",
  ])
  let beyond = queried(
    ledger_source(),
    "SELECT account LIMIT 2147483647 OFFSET 2147483647",
  )
  assert_true(beyond.error is None)
  assert_eq(beyond.rows.length(), 0)
  assert_true(
    queried(ledger_source(), "SELECT account OFFSET -1").error is Some(_),
  )
}

///|
test "NULLS FIRST and NULLS LAST do not flip on descending sort" {
  let source = "2024-01-01 * \"a\"\n2024-01-02 * \"Bob\" \"b\"\n2024-01-03 * \"Alice\" \"c\"\n2024-01-04 * \"d\"\n"
  for
    (suffix, expected) in [
      ("ASC NULLS LAST, narration DESC", ["c", "b", "d", "a"]),
      ("DESC NULLS FIRST, narration ASC", ["a", "d", "b", "c"]),
      ("ASC", ["a", "d", "c", "b"]),
    ] {
    let q = queried(
      source,
      "SELECT narration FROM transactions ORDER BY payee " + suffix,
    )
    assert_true(q.error is None)
    assert_eq(q.rows.map(fn(r) { r[0].to_text() }), expected)
  }
  assert_true(
    queried(
      source, "SELECT narration FROM transactions ORDER BY payee NULLS BOTH",
    ).error
    is Some(_),
  )
}

///|
test "SPLIT_TEXT preserves empty fields in literal separated text" {
  let cases = [
    (
      "SELECT split_text('房租::餐饮::','::') LIMIT 1", "[\"房租\",\"餐饮\",\"\"]",
    ),
    ("SELECT split_text('',';') LIMIT 1", "[\"\"]"),
    ("SELECT split_text('a.b.c','.') LIMIT 1", "[\"a\",\"b\",\"c\"]"),
    ("SELECT split_text('a',NULL) LIMIT 1", "null"),
    ("SELECT length(split_text('a,b,c',',')) LIMIT 1", "3"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_json(), expected)
  }
}

///|
test "JOIN_TEXT composes split or aggregate lists and omits null members" {
  let q = queried(
    ledger_source(),
    "SELECT join_text(split_text('餐饮|交通|','|'), '／') LIMIT 1",
  )
  assert_true(q.error is None)
  assert_eq(q.rows[0][0].to_text(), "餐饮／交通／")
  let ag = queried(
    ledger_source(),
    "SELECT join_text(collect(account), ' / ') WHERE number(units) > 0",
  )
  assert_true(ag.error is None)
  assert_eq(ag.rows[0][0].to_text(), "Assets:Cash / Expenses:Food")
  let empty = queried(ledger_source(), "SELECT join_text(collect(payee), '-')")
  assert_true(empty.error is None)
  assert_eq(empty.rows[0][0].to_text(), "")
  let invalid = queried(ledger_source(), "SELECT join_text(collect(42), '-')")
  assert_true(invalid.error is Some(_))
}

///|
test "TRIM helpers remove only edge whitespace and preserve interior Unicode" {
  let cases = [
    ("SELECT trim('  餐 饮  ') LIMIT 1", "\"餐 饮\""),
    ("SELECT ltrim('  a  ') LIMIT 1", "\"a  \""),
    ("SELECT rtrim('  a  ') LIMIT 1", "\"  a\""),
    ("SELECT trim('  café 　') LIMIT 1", "\"café\""),
    ("SELECT trim(NULL) LIMIT 1", "null"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_json(), expected)
  }
}

///|
test "REPLACE_TEXT substitutes literal characters rather than regex" {
  let cases = [
    ("SELECT replace_text('Food.+Food','.+',' / ') LIMIT 1", "\"Food / Food\""),
    ("SELECT replace_text('账本账本','账本','账') LIMIT 1", "\"账账\""),
    ("SELECT replace_text('aaa','aa','x') LIMIT 1", "\"xa\""),
    ("SELECT replace_text('USD','','X') LIMIT 1", "\"USD\""),
    ("SELECT replace_text('x','x',NULL) LIMIT 1", "null"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_json(), expected)
  }
}

///|
test "Literal prefix and suffix helpers are Unicode-safe and composable in WHERE" {
  let cases = [
    ("SELECT starts_with('账本/月报','账本') LIMIT 1", "TRUE"),
    ("SELECT ends_with('账本/月报','月报') LIMIT 1", "TRUE"),
    ("SELECT ends_with('USD','usd') LIMIT 1", "FALSE"),
    ("SELECT starts_with('USD','') LIMIT 1", "TRUE"),
    ("SELECT starts_with(NULL,'A') LIMIT 1", ""),
    ("SELECT count(*) WHERE starts_with(account,'Assets:')", "2"),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
}

///|
test "DATE_FORMAT renders bounded locale-neutral date directives" {
  let q = queried(
    ledger_source(),
    "SELECT date_format(date('2024-02-29'), '%Y/%m/%d: %j, %% and %F') LIMIT 1",
  )
  assert_true(q.error is None)
  assert_eq(q.rows[0][0].to_text(), "2024/02/29: 060, % and 2024-02-29")
  let early = queried(
    ledger_source(),
    "SELECT date_format(date(1,1,1), '%F %j') LIMIT 1",
  )
  assert_true(early.error is None)
  assert_eq(early.rows[0][0].to_text(), "0001-01-01 001")
  let bad = queried(ledger_source(), "SELECT date_format(date, '%Q') LIMIT 1")
  assert_true(bad.error is Some(_))
  let empty = queried(ledger_source(), "SELECT date_format(NULL, '%F') LIMIT 1")
  assert_true(empty.error is None)
  assert_true(empty.rows[0][0] is @query.QNull)
}

///|
test "Month boundary helpers support leap years and the last representable month" {
  let cases = [
    ("SELECT month_end(date(2024,2,1)) LIMIT 1", "2024-02-29"),
    ("SELECT month_end(date(1900,2,1)) LIMIT 1", "1900-02-28"),
    ("SELECT month_end(date(9999,12,2)) LIMIT 1", "9999-12-31"),
    ("SELECT days_in_month(date(2000,2,1)) LIMIT 1", "29"),
    ("SELECT days_in_month(date(2024,4,1)) LIMIT 1", "30"),
    ("SELECT month_end(NULL) LIMIT 1", ""),
  ]
  for (statement, expected) in cases {
    let q = queried(ledger_source(), statement)
    assert_true(q.error is None)
    assert_eq(q.rows.length(), 1)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
}

///|
test "CLAMP bounds mixed decimal values and rejects inverted ranges" {
  for
    (query, expected) in [
      ("SELECT clamp(-3,0,10)", "0"),
      ("SELECT clamp(12,0,10.5)", "10.5"),
      ("SELECT clamp(2.25,0,10)", "2.25"),
      ("SELECT clamp(NULL,0,1)", ""),
    ] {
    let q = queried(ledger_source(), query + " LIMIT 1")
    assert_true(q.error is None)
    assert_eq(q.rows[0][0].to_text(), expected)
  }
  assert_true(queried(ledger_source(), "SELECT clamp(2,5,1)").error is Some(_))
  assert_true(
    queried(ledger_source(), "SELECT clamp('x',0,1)").error is Some(_),
  )
}

///|
test "RUN SAVED resolves named query directives without recursion or ambiguous matches" {
  let base = ledger_source() +
    "2024-01-09 query \"cash summary\" \"SELECT count(*) WHERE account = 'Assets:Cash'\"\n"
  let q = queried(base, "RUN SAVED 'cash summary'")
  assert_true(q.error is None)
  assert_eq(q.rows.length(), 1)
  assert_eq(q.rows[0][0].to_text(), "2")
  let missing = queried(base, "RUN SAVED 'Cash summary'")
  assert_true(missing.error is Some(_))
  assert_true(missing.error.unwrap().contains("not found"))
  let dup = queried(
    base + "2024-01-10 query \"cash summary\" \"SELECT 3\"\n",
    "RUN SAVED 'cash summary'",
  )
  assert_true(dup.error is Some(_))
  assert_true(dup.error.unwrap().contains("ambiguous"))
  let cycle = queried(
    base + "2024-01-10 query \"cycle\" \"RUN SAVED 'cycle'\"\n",
    "RUN SAVED 'cycle'",
  )
  assert_true(cycle.error is Some(_))
  assert_true(cycle.error.unwrap().contains("nested"))
}

///|
test "unterminated query strings reject at their opening quote" {
  for
    (query, location) in [
      ("SELECT 'incomplete", "BQL:1:8"),
      ("SELECT \"😀", "BQL:1:8"),
      ("SELECT\n  'a''", "BQL:2:3"),
      ("RUN SAVED 'summary", "BQL:1:11"),
    ] {
    let result = queried(ledger_source(), query)
    assert_true(result.failure() is Some(@query.Syntax(_)))
    let message = result.error.unwrap()
    assert_true(message.has_prefix("lexical query.unterminated_string"))
    assert_true(message.has_suffix(location))
  }
  for
    (query, expected) in [
      ("SELECT 'a''b' LIMIT 1", "a''b"),
      ("SELECT \"a\"\"b\" LIMIT 1", "a\"\"b"),
      ("SELECT '' LIMIT 1", ""),
      ("SELECT '😀' LIMIT 1", "😀"),
    ] {
    let result = queried(ledger_source(), query)
    assert_true(result.error is None)
    assert_eq(result.rows[0][0].to_text(), expected)
  }
}

///|
test "allows one terminal query semicolon but never a second statement" {
  for
    query in [
      "SELECT account LIMIT 1;\n ", "SELECT account FROM (SELECT account LIMIT 1);",
      "SELECT ';' LIMIT 1;",
    ] {
    let result = queried(ledger_source(), query)
    assert_true(result.error is None)
    assert_eq(result.rows.length(), 1)
  }
  let quoted = queried(ledger_source(), "SELECT ';' LIMIT 1;")
  assert_eq(quoted.rows[0][0].to_text(), ";")
  let cmp = queried(ledger_source(), "SELECT 1=1;")
  assert_true(cmp.error is None)
  assert_eq(cmp.rows[0][0].to_text(), "TRUE")
  for
    query in [
      "SELECT account LIMIT 1;;", "SELECT account LIMIT 1; SELECT account", "SELECT account FROM (SELECT account LIMIT 1;)",
    ] {
    assert_true(
      queried(ledger_source(), query).failure() is Some(@query.Syntax(_)),
    )
  }
}

///|
test "classifies actual extension evaluation failures separately from invalid query syntax" {
  for
    query in [
      "SELECT split_text('abc','')", "SELECT date_format(date,'%')", "SELECT date_format(date,'%A')",
      "SELECT clamp(2,4,1)", "SELECT join_text(collect(1),',')",
    ] {
    let result = queried(ledger_source(), query)
    assert_true(result.failure() is Some(@query.Evaluation(_)))
    assert_true(result.error.unwrap().has_prefix("evaluation query."))
  }
  assert_true(
    queried(ledger_source(), "SELECT +").failure() is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT split_text(1,'x')").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "null-safe scalar comparisons complement one another in projections and filters" {
  for
    (sql, result) in [
      ("NULL IS DISTINCT FROM NULL", "FALSE"),
      ("NULL IS NOT DISTINCT FROM NULL", "TRUE"),
      ("1 IS DISTINCT FROM NULL", "TRUE"),
      ("NULL IS DISTINCT FROM 1", "TRUE"),
      ("1.00 IS NOT DISTINCT FROM 1", "TRUE"),
      ("'1' IS DISTINCT FROM 1", "TRUE"),
      ("'é' IS DISTINCT FROM 'e'", "TRUE"),
      ("date('2024-01-01') IS NOT DISTINCT FROM date('2024-01-01')", "TRUE"),
    ] {
    let r = queried(ledger_source(), "SELECT " + sql + " LIMIT 1")
    assert_true(r.error is None)
    assert_eq(r.rows[0][0].to_text(), result)
  }
  assert_eq(
    queried(
      ledger_source(),
      "SELECT count(*) WHERE payee IS NOT DISTINCT FROM NULL",
    ).rows[0][0].to_text(),
    "4",
  )
  assert_eq(
    queried(ledger_source(), "SELECT count(*) IS DISTINCT FROM 4").rows[0][0].to_text(),
    "FALSE",
  )
  assert_true(
    queried(ledger_source(), "SELECT tags IS DISTINCT FROM links").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT payee IS DISTINCT NULL").failure()
    is Some(@query.Syntax(_)),
  )
}

///|
test "searched CASE selects the first true branch and skips dead evaluations" {
  for
    (query, expected) in [
      (
        "CASE WHEN 1=1 THEN 'first' WHEN 2=2 THEN 'second' ELSE 'other' END", "first",
      ),
      ("CASE WHEN payee IS NULL THEN 'missing' ELSE payee END", "missing"),
      ("CASE WHEN 0=1 THEN clamp(2,4,1) ELSE 5.0 END", "5.0"),
      ("CASE WHEN 0=1 THEN 'ignore' WHEN NULL THEN 'ignore also' END", "NULL"),
      (
        "CASE WHEN 1=1 THEN CASE WHEN 1=1 THEN 'inner' END ELSE 'outer' END", "inner",
      ),
    ] {
    let r = queried(ledger_source(), "SELECT " + query + " LIMIT 1")
    assert_true(r.error is None)
    if expected == "NULL" {
      assert_true(r.rows[0][0] is @query.QNull)
    } else {
      assert_eq(r.rows[0][0].to_text(), expected)
    }
  }
  let grouped = queried(
    ledger_source(),
    "SELECT CASE WHEN count(*)=4 THEN 'yes' ELSE 'no' END AS answer",
  )
  assert_eq(grouped.rows[0][0].to_text(), "yes")
  let grouped_lazy = queried(
    ledger_source(),
    "SELECT CASE WHEN count(*)<0 THEN clamp(sum(number(units)),4,1) ELSE 5.0 END",
  )
  assert_true(grouped_lazy.error is None)
  assert_eq(grouped_lazy.rows[0][0].to_text(), "5.0")
  for
    q in [
      "SELECT CASE WHEN 1=1 THEN clamp(2,4,1) ELSE 5.0 END", "SELECT CASE WHEN count(*)>0 THEN clamp(sum(number(units)),4,1) ELSE 5.0 END",
    ] {
    let r = queried(ledger_source(), q)
    assert_true(r.failure() is Some(@query.Evaluation(_)))
    assert_true(r.error.unwrap().has_prefix("evaluation query.clamp"))
  }
  assert_true(
    queried(ledger_source(), "SELECT CASE WHEN 1=1 THEN 1 ELSE 'x' END").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(ledger_source(), "SELECT CASE WHEN 1=1 THEN 1").failure()
    is Some(@query.Syntax(_)),
  )
}

///|
test "weighted average accumulates exact signed products before one decimal division" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT weighted_avg(number(units),abs(number(units))) WHERE account='Assets:Cash'",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0][0].to_text(), "980")
  let cancellation = queried(
    source, "SELECT weighted_avg(number(units),number(units))",
  )
  assert_true(cancellation.error is None)
  assert_true(cancellation.rows[0][0] is @query.QNull)
  let absent = queried(source, "SELECT weighted_avg(number(units),NULL)")
  assert_true(absent.error is None)
  assert_true(absent.rows[0][0] is @query.QNull)
  let big = queried(
    source, "SELECT weighted_avg(number(units),100000000000000000000000000000000.001) WHERE account='Assets:Cash'",
  )
  assert_true(big.error is None)
  assert_eq(big.rows[0][0].to_text(), "490")
  assert_true(
    queried(source, "SELECT weighted_avg(narration,1)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "signed zero does not block safe scalar DISTINCT but retains representation boundaries" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Start USD\n2024-01-02 * \"Alice\" \"deposit\"\n  Assets:Cash 1 USD\n  Equity:Start -1 USD\n2024-01-03 * \"Alice\" \"cancelled\"\n  Assets:Cash -0.00 USD\n  Equity:Start 0.00 USD\n2024-01-04 * \"unassigned\"\n  Assets:Cash 2 USD\n  Equity:Start -2 USD\n"
  let distinct = queried(
    source, "SELECT DISTINCT payee FROM transactions ORDER BY payee",
  )
  assert_true(distinct.error is None)
  assert_eq(distinct.rows.length(), 2)
  assert_true(distinct.rows[0][0] is @query.QNull)
  assert_eq(distinct.rows[1][0].to_text(), "Alice")
  let ordinary = queried(
    source, "SELECT DISTINCT account, year(date) ORDER BY account",
  )
  assert_true(ordinary.error is None)
  assert_eq(ordinary.rows.length(), 2)
  for
    q in [
      "SELECT DISTINCT position", "SELECT DISTINCT number(units)", "SELECT DISTINCT repr(payee) FROM transactions",
      "SELECT DISTINCT payee FROM transactions WHERE repr(payee) = 'unused'", "SELECT id FROM #entries",
    ] {
    assert_true(queried(source, q).failure() is Some(@query.Unsupported(_)))
  }
}

///|
test "simple pagination preserves errors outside the returned window" {
  let source = ledger_source()
  assert_eq(
    queried(source, "SELECT account LIMIT 2 OFFSET 1").rows[0][0].to_text(),
    "Income:Salary",
  )
  assert_eq(
    queried(source, "SELECT account LIMIT 2 OFFSET 1").rows[1][0].to_text(),
    "Expenses:Food",
  )
  assert_true(
    queried(source, "SELECT account LIMIT 1 OFFSET 2147483647").rows.is_empty(),
  )
  let q = "SELECT CASE WHEN account='Expenses:Food' THEN clamp(2,4,1) ELSE 5.0 END "
  for suffix in ["LIMIT 0", "LIMIT 1", "LIMIT 1 OFFSET 3", "OFFSET 2147483647"] {
    assert_true(
      queried(source, q + suffix).failure() is Some(@query.Evaluation(_)),
    )
  }
  let ordered = queried(source, "SELECT account ORDER BY account DESC LIMIT 1")
  assert_eq(ordered.rows[0][0].to_text(), "Income:Salary")
  let grouped = queried(
    source, "SELECT account,count(*) GROUP BY account LIMIT 1",
  )
  assert_eq(grouped.rows[0][1].to_text(), "2")
}

///|
test "projection ordinals cannot wrap to a valid column" {
  let source = ledger_source()
  for
    q in [
      "SELECT account ORDER BY 4294967297", "SELECT account GROUP BY 4294967297",
      "SELECT account, currency, sum(number) GROUP BY 1,2 PIVOT BY 4294967297,2",
      "SELECT account, date ORDER BY 18446744073709551618", "SELECT account ORDER BY 0",
    ] {
    let r = queried(source, q)
    assert_true(r.failure() is Some(@query.Compilation(_)))
    assert_true(r.error.unwrap().contains("query.invalid_reference"))
  }
  let good = queried(source, "SELECT account, date ORDER BY 2,1 LIMIT 2")
  assert_true(good.error is None)
  assert_eq(good.rows[0][0].to_text(), "Assets:Cash")
}

///|
test "negative regular expressions preserve null instead of applying truth negation" {
  let source = ledger_source()
  let r = queried(source, "SELECT account, account !~ 'cAsh' ORDER BY account")
  assert_true(r.error is None)
  assert_eq(r.rows[0][1].to_text(), "FALSE")
  assert_eq(r.rows[2][1].to_text(), "TRUE")
  let nulls = queried(
    source, "SELECT payee !~ 'name', NOT payee ~ 'name' LIMIT 1",
  )
  assert_true(nulls.error is None)
  assert_true(nulls.rows[0][0] is @query.QNull)
  assert_eq(nulls.rows[0][1].to_text(), "TRUE")
  assert_true(
    queried(source, "SELECT payee WHERE payee !~ 'name'").rows.is_empty(),
  )
  assert_true(
    queried(
      source, "SELECT account HAVING first(payee) !~ 'x' GROUP BY account",
    ).failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(
      source, "SELECT account GROUP BY account HAVING first(payee) !~ 'x'",
    ).rows.is_empty(),
  )
  assert_true(
    queried(source, "SELECT 1 !~ 'x'").failure() is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT account WHERE 1 !~ 'x'").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT account !~ '['").failure()
    is Some(@query.Unsupported(_)),
  )
}

///|
test "decimal literals accept omitted leading and trailing digits without pretending to be integers" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT repr(.5),repr(1.),repr(-.25),repr(.0),repr(2+.5) LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0][0].to_text(), "Decimal('0.5')")
  assert_eq(r.rows[0][1].to_text(), "Decimal('1')")
  assert_eq(r.rows[0][2].to_text(), "Decimal('-0.25')")
  assert_eq(r.rows[0][3].to_text(), "Decimal('0.0')")
  assert_eq(r.rows[0][4].to_text(), "Decimal('2.5')")
  assert_true(
    queried(source, "SELECT account LIMIT 1.").failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(
    queried(source, "SELECT account ORDER BY 1.").failure()
    is Some(@query.Syntax(_)),
  )
  assert_true(queried(source, "SELECT .").failure() is Some(@query.Syntax(_)))
  assert_true(queried(source, "SELECT 1..2").error is Some(_))
  let list = queried(source, "SELECT (1.,.5) LIMIT 1")
  assert_true(
    list.rows[0][0] is @query.QList([@query.QNumber(_), @query.QNumber(_)]),
  )
}

///|
test "aggregate FILTER computes conditional columns without dropping source groups" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT currency,count(*) FILTER (WHERE number > 0) AS positive,count(*) FILTER (WHERE number < 0) AS negative,sum(number) FILTER (WHERE number > 0) AS total GROUP BY currency",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0][1].to_text(), "2")
  assert_eq(r.rows[0][2].to_text(), "2")
  assert_eq(r.rows[0][3].to_text(), "1020")
  let empty = queried(
    source, "SELECT currency,count(*) FILTER (WHERE account='no'),avg(number) FILTER (WHERE account='no') GROUP BY currency",
  )
  assert_true(empty.error is None)
  assert_eq(empty.rows[0][1].to_text(), "0")
  assert_true(empty.rows[0][2] is @query.QNull)
  let grouped = queried(
    source, "SELECT account GROUP BY account HAVING count(*) FILTER (WHERE number > 0) > 0 ORDER BY account",
  )
  assert_true(grouped.error is None)
  assert_eq(grouped.rows.length(), 2)
  let typed = source +
    "2024-04-01 * \"pattern\"\n  Expenses:Food 1 USD\n    pat: 7\n  Assets:Cash -1 USD\n"
  let filter_error = queried(
    typed, "SELECT count(*) FILTER (WHERE meta('pat') ~ 'x')",
  )
  let where_error = queried(typed, "SELECT count(*) WHERE meta('pat') ~ 'x'")
  assert_true(filter_error.failure() is Some(@query.Evaluation(_)))
  assert_eq(filter_error.error, where_error.error)
  assert_true(
    queried(source, "SELECT length(account) FILTER (WHERE true)").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT count(*) FILTER (WHERE count(*) > 0)").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT count(*) FILTER (number > 0)").failure()
    is Some(@query.Syntax(_)),
  )
}

///|
test "saved query table inventories exact directives without executing them" {
  let source = ledger_source() +
    "2024-01-03 query \"Unsupported\" \"SELECT imaginary\"\n  owner: \"budget\"\n2024-01-02 query \"Monthly\" \"SELECT account LIMIT 1\"\n2024-01-04 query \"Monthly\" \"SELECT 2\"\n"
  let r = queried(source, "SELECT * FROM #queries ORDER BY date")
  assert_true(r.error is None)
  assert_eq(r.columns, ["date", "name", "query_string"])
  assert_eq(r.rows.length(), 3)
  assert_eq(r.rows[0][1].to_text(), "Monthly")
  assert_eq(r.rows[1][2].to_text(), "SELECT imaginary")
  let meta = queried(
    source, "SELECT meta FROM #queries WHERE name='Unsupported'",
  )
  assert_true(meta.rows[0][0].to_text().contains("budget"))
  assert_true(
    queried(ledger_source(), "SELECT * FROM #queries").rows.is_empty(),
  )
  assert_true(
    queried(source, "SELECT account FROM #queries").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(queried(source, "RUN SAVED 'Monthly'").error is Some(_))
}

///|
test "account subtree matches complete case-sensitive components including the ancestor" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT account_in_subtree('Assets:Bank:Checking','Assets:Bank'),account_in_subtree('Assets:Bank','Assets:Bank'),account_in_subtree('Assets:Bank2','Assets:Bank'),account_in_subtree('Assets:Bank','assets'),account_in_subtree(NULL,'Assets'),account_in_subtree('Assets:Bank','') LIMIT 1",
  )
  assert_true(r.error is None)
  assert_true(
    r.rows[0]
    is [
      @query.QBool(true),
      @query.QBool(true),
      @query.QBool(false),
      @query.QBool(false),
      @query.QNull,
      @query.QBool(false),
    ],
  )
  let ledger_rows = queried(
    source, "SELECT account WHERE account_in_subtree(account,'Assets') ORDER BY date",
  )
  assert_eq(ledger_rows.rows.length(), 2)
  assert_eq(ledger_rows.rows[1][0].to_text(), "Assets:Cash")
  assert_true(
    queried(source, "SELECT account_in_subtree(date,'Assets')").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "fiscal calendar uses explicit start month and start-year labels" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT fiscal_year(date('2024-03-31'),4),fiscal_quarter(date('2024-03-31'),4),fiscal_year(date('2024-04-01'),4),fiscal_quarter(date('2024-04-01'),4),fiscal_quarter(date('2024-02-29'),1),fiscal_quarter(date('2024-05-01'),12),fiscal_year(NULL,4) LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "2023", "4", "2024", "1", "1", "2", "",
  ])
  for
    q in [
      "SELECT fiscal_year(date,0)", "SELECT fiscal_quarter(date,13)", "SELECT fiscal_year(date,4294967297)",
      "SELECT fiscal_year(date('0001-01-01'),2)",
    ] {
    assert_true(queried(source, q).failure() is Some(@query.Evaluation(_)))
  }
  assert_true(
    queried(source, "SELECT fiscal_year(date,1.5)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "Boolean aggregates ignore null without confusing all-null with false" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT bool_or(number>0),bool_and(number>0),bool_and(number IS NOT NULL),bool_or(NULL),bool_and(NULL)",
  )
  assert_true(r.error is None)
  assert_true(
    r.rows[0]
    is [
      @query.QBool(true),
      @query.QBool(false),
      @query.QBool(true),
      @query.QNull,
      @query.QNull,
    ],
  )
  let mixed = queried(
    source, "SELECT bool_or(CASE WHEN number>0 THEN TRUE END),bool_and(CASE WHEN number>0 THEN TRUE END),bool_or(FALSE) GROUP BY currency",
  )
  assert_true(
    mixed.rows[0]
    is [@query.QBool(true), @query.QBool(true), @query.QBool(false)],
  )
  let invalid = queried(source, "SELECT bool_or(number)")
  assert_true(invalid.failure() is Some(@query.Compilation(_)))
  let late_error = queried(
    source, "SELECT bool_and(CASE WHEN number>=20 THEN clamp(2,4,1)>0 ELSE FALSE END)",
  )
  assert_true(late_error.failure() is Some(@query.Evaluation(_)))
}

///|
test "dynamic regex patterns use same case and null contract as literal operators" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT account,account ~ upper(root(account)),account !~ upper(root(account)) ORDER BY account",
  )
  assert_true(r.error is None)
  assert_true(
    r.rows[0] is [@query.QText(_), @query.QBool(true), @query.QBool(false)],
  )
  let from_rows = queried(
    source, "SELECT account WHERE account !~ lower(leaf(account))",
  )
  assert_true(from_rows.error is None)
  assert_true(from_rows.rows.is_empty())
  let null_pattern = queried(
    source, "SELECT account !~ nullif(account,account) LIMIT 1",
  )
  assert_true(null_pattern.error is None)
  assert_true(null_pattern.rows[0][0] is @query.QNull)
  assert_true(
    queried(source, "SELECT account ~ upper('[')").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT NULL !~ upper('name')").failure()
    is Some(@query.Compilation(_)),
  )
  let skip = queried(
    source, "SELECT CASE WHEN FALSE THEN account ~ upper('[') ELSE TRUE END LIMIT 1",
  )
  assert_true(skip.error is None)
  assert_true(skip.rows[0][0] is @query.QBool(true))
  assert_true(
    queried(source, "SELECT account ~ year(date)").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT account ~ '['").failure()
    is Some(@query.Unsupported(_)),
  )
}

///|
test "round_increment rounds signed cash amounts to an exact increment using ties to even" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT repr(round_increment(1.025,0.050)),repr(round_increment(1.075,0.050)),repr(round_increment(-1.075,0.050)),repr(round_increment(-0.01,0.05)),repr(round_increment(50000000000000000000000000000.015,0.05)),round_increment(NULL,1) LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0][0].to_text(), "Decimal('1.000')")
  assert_eq(r.rows[0][1].to_text(), "Decimal('1.100')")
  assert_eq(r.rows[0][2].to_text(), "Decimal('-1.100')")
  assert_eq(r.rows[0][3].to_text(), "Decimal('-0.00')")
  assert_eq(
    r.rows[0][4].to_text(),
    "Decimal('50000000000000000000000000000.00')",
  )
  assert_true(r.rows[0][5] is @query.QNull)
  assert_true(
    queried(source, "SELECT round_increment(2,0)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT round_increment(2,-0.05)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT round_increment(narration,1)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "weekday-only business calendar handles weekends, reverse counts and date bounds" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT add_business_days(2024-03-01,1),add_business_days(2024-03-02,1),add_business_days(2024-03-03,-1),add_business_days(2024-03-02,0),add_business_days(2024-03-01,6),business_days_between(2024-03-01,2024-03-04),business_days_between(2024-03-04,2024-03-01),business_days_between(2024-03-02,2024-03-04) LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "2024-03-04", "2024-03-04", "2024-03-01", "2024-03-02", "2024-03-11", "1", "-1",
    "0",
  ])
  assert_true(
    queried(source, "SELECT add_business_days(9999-12-31,1)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT add_business_days(0001-01-01,-1)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT add_business_days(date,4294967297)").failure()
    is Some(@query.Evaluation(_)),
  )
  assert_true(
    queried(source, "SELECT add_business_days(date,1.1)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "UNION ALL appends compatible top-level selects with source order and duplicates intact" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT account AS name ORDER BY account LIMIT 2 UNION ALL SELECT account WHERE number > 0 ORDER BY account DESC LIMIT 2 UNION ALL SELECT NULL LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(r.columns, ["name"])
  assert_eq(r.rows.length(), 5)
  assert_eq(r.rows[0][0].to_text(), "Assets:Cash")
  assert_eq(r.rows[1][0].to_text(), "Assets:Cash")
  assert_eq(r.rows[2][0].to_text(), "Expenses:Food")
  assert_true(r.rows[4][0] is @query.QNull)
  for
    q in [
      "SELECT account UNION ALL SELECT account,date", "SELECT NULL UNION ALL SELECT account UNION ALL SELECT date",
    ] {
    assert_true(queried(source, q).failure() is Some(@query.Compilation(_)))
  }
  for
    q in [
      "SELECT account UNION SELECT account", "SELECT account UNION ALL PRINT", "SELECT account FROM (SELECT account UNION ALL SELECT account)",
    ] {
    assert_true(queried(source, q).failure() is Some(@query.Syntax(_)))
  }
  let late = queried(
    source, "SELECT 5.0 LIMIT 1 UNION ALL SELECT clamp(2,4,1) LIMIT 1",
  )
  assert_true(late.failure() is Some(@query.Evaluation(_)))
  assert_true(late.rows.is_empty())
}

///|
test "associated-value aggregates return first tied row and skip null sort keys" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT arg_max(account,number),arg_min(account,number),arg_max(account,date),arg_min(account,date),arg_max(account,NULL),arg_max(NULL,number)",
  )
  assert_true(r.error is None)
  assert_true(
    r.rows[0]
    is [
      @query.QText("Assets:Cash"),
      @query.QText("Income:Salary"),
      @query.QText("Expenses:Food"),
      @query.QText("Assets:Cash"),
      @query.QNull,
      @query.QNull,
    ],
  )
  let late = queried(
    source, "SELECT arg_max(CASE WHEN number<0 THEN clamp(2,4,1) ELSE 5.0 END, number)",
  )
  assert_true(late.failure() is Some(@query.Evaluation(_)))
  let bad = queried(source, "SELECT arg_max(account,tags)")
  assert_true(bad.failure() is Some(@query.Compilation(_)))
}

///|
test "discrete percentiles rank exact decimal fractions over observed non-null values" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT percentile_disc(number,0),percentile_disc(number,.25),percentile_disc(number,.50),percentile_disc(number,.50000000000000000000000000001),percentile_disc(number,1),percentile_disc(NULL,.5),percentile_disc(number,NULL)",
  )
  assert_true(r.error is None)
  assert_eq(r.rows[0].map(fn(v) { v.to_text() }), [
    "-1000", "-1000", "-20", "20", "1000", "", "",
  ])
  let g = queried(
    source, "SELECT account,percentile_disc(number,.5) GROUP BY account ORDER BY account",
  )
  assert_true(g.error is None)
  assert_eq(g.rows[0][1].to_text(), "-20")
  for
    q in [
      "SELECT percentile_disc(number,1.01)", "SELECT percentile_disc(number,number)",
      "SELECT percentile_disc(account,.5)",
    ] {
    assert_true(queried(source, q).failure() is Some(@query.Compilation(_)))
  }
}

///|
test "LIKE and JOIN are valid aliases while their operator syntax stays unsupported" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT account AS join, date AS like ORDER BY join,like LIMIT 2",
  )
  assert_true(r.error is None)
  assert_eq(r.columns, ["join", "like"])
  assert_eq(r.rows[0][0].to_text(), "Assets:Cash")
  let inner = queried(
    source, "SELECT join FROM (SELECT account AS join) ORDER BY join LIMIT 1",
  )
  assert_true(inner.error is None)
  assert_eq(inner.rows[0][0].to_text(), "Assets:Cash")
  for
    (q, tag) in [
      ("SELECT account WHERE account LIKE 'Assets%'", "like"),
      ("SELECT account WHERE account NOT LIKE 'Assets%'", "like"),
      ("SELECT account FROM postings JOIN postings", "join"),
    ] {
    let r = queried(source, q)
    assert_true(r.failure() is Some(@query.Unsupported(_)))
    assert_true(r.error.unwrap().contains("query.unsupported." + tag))
  }
}

///|
test "relation row schemas preserve duplicate last aliases and typed values" {
  let source = ledger_source()
  let statement = "SELECT k, qty FROM (SELECT account AS k,narration AS k,number AS qty) ORDER BY qty LIMIT 2"
  let r = queried(source, statement)
  assert_true(r.error is None)
  assert_eq(r.rows[0][0].to_text(), "salary")
  assert_eq(r.rows[0][1].to_text(), "-1000")
  assert_eq(r.rows[1][0].to_text(), "lunch")
  assert_true(
    queried(source, "SELECT unknown FROM (SELECT account)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "large mixed-currency booking keeps first-encounter groups and posting order within groups" {
  let source = StringBuilder()
  source.write_string(
    "2024-01-01 open Assets:Cash USD, CAD\n2024-01-01 open Income:Salary USD, CAD\n2024-01-02 * \"split\"\n",
  )
  for i in 1..<13 {
    source.write_string(
      "  Assets:Cash \{i} USD\n  Assets:Cash \{i} CAD\n  Income:Salary -\{i} USD\n  Income:Salary -\{i} CAD\n",
    )
  }
  let r = queried(source.to_string(), "SELECT account,number,currency")
  assert_true(r.error is None)
  assert_eq(r.rows.length(), 48)
  for i in 0..<12 {
    assert_eq(r.rows[i * 2][1].to_text(), (i + 1).to_string())
    assert_eq(r.rows[i * 2 + 1][1].to_text(), "-" + (i + 1).to_string())
    assert_eq(r.rows[i * 2][2].to_text(), "USD")
    assert_eq(r.rows[24 + i * 2][2].to_text(), "CAD")
  }
}

///|
test "list coordinates provide negative-index and bounded slices for collected data" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT list_at(split_text('a|b|c','|'),-1),list_at(split_text('a','|'),4294967297),list_slice(split_text('a|b|c','|'),-2,4294967297),list_slice(split_text('a|b|c','|'),2,1),list_at(NULL,1) LIMIT 1",
  )
  assert_true(r.error is None)
  assert_true(
    r.rows[0]
    is [
      @query.QText("c"),
      @query.QNull,
      @query.QList([@query.QText("b"), @query.QText("c")]),
      @query.QList([]),
      @query.QNull,
    ],
  )
  let stat = queried(source, "SELECT int(list_at(collect(year(date)),0))")
  assert_true(stat.error is None)
  assert_eq(stat.rows[0][0].to_text(), "2024")
  assert_true(
    queried(source, "SELECT list_at(account,0)").failure()
    is Some(@query.Compilation(_)),
  )
  assert_true(
    queried(source, "SELECT list_slice(split_text(account,':'),1.0,2)").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "global aggregate HAVING filters a single complete summary group" {
  let source = ledger_source()
  let yes = queried(source, "SELECT count(*) AS total HAVING count(*)=4")
  assert_true(yes.error is None)
  assert_eq(yes.rows[0][0].to_text(), "4")
  let no = queried(source, "SELECT count(*) HAVING count(*)>4")
  assert_true(no.error is None)
  assert_true(no.rows.is_empty())
  let none = queried(
    source, "SELECT count(*) WHERE account='missing' HAVING count(*)=0",
  )
  assert_true(none.error is None)
  assert_true(none.rows.is_empty())
  let mixed = queried(
    source, "SELECT count(*) HAVING count(*) FILTER (WHERE number>0)=2",
  )
  assert_true(mixed.error is None)
  assert_eq(mixed.rows.length(), 1)
  for
    q in [
      "SELECT count(*) HAVING count(*)>0 AND account='Assets:Cash'", "SELECT account,count(*) HAVING count(*)>0",
      "SELECT count(*) HAVING TRUE", "SELECT account HAVING count(*)>0",
    ] {
    assert_true(queried(source, q).error is Some(_))
  }
}

///|
test "table CSV quotes commas, newlines and double quotes without exposing failed results" {
  let source = ledger_source()
  let r = queried(
    source, "SELECT 'x,y' AS \"label, column\", 'a\"b' AS q, 'first\nsecond' AS multi, NULL AS absent LIMIT 1",
  )
  assert_true(r.error is None)
  assert_eq(
    r.to_csv(),
    Some(
      "\"label, column\",q,multi,absent\r\n\"x,y\",\"a\"\"b\",\"first\nsecond\",\r\n",
    ),
  )
  assert_eq(
    queried(source, "SELECT account LIMIT 0").to_csv(),
    Some("account\r\n"),
  )
  assert_true(queried(source, "SELECT invalid_column").to_csv() is None)
  assert_true(queried(source, "PRINT").to_csv() is None)
}

///|
test "custom directives expose typed records and metadata for ledger-specific categories" {
  let source = ledger_source() +
    "2024-02-05 custom \"budget\" \"Apples\" 20 USD TRUE\n  owner: \"Ana\"\n2024-02-06 custom \"threshold\" 9\n"
  let r = queried(
    source, "SELECT date,type,length(values),list_at(values,0) FROM #custom ORDER BY date",
  )
  assert_true(r.error is None)
  assert_eq(r.rows.length(), 2)
  assert_eq(r.rows[0][1].to_text(), "budget")
  assert_eq(r.rows[0][2].to_text(), "3")
  assert_true(r.rows[0][3].to_text().contains("Apples"))
  let metadata = queried(source, "SELECT meta FROM #custom WHERE type='budget'")
  assert_true(metadata.rows[0][0].to_text().contains("Ana"))
  assert_eq(queried(source, "SELECT * FROM #custom LIMIT 0").columns, [
    "date", "type", "values",
  ])
  assert_true(
    queried(source, "SELECT account FROM #custom").failure()
    is Some(@query.Compilation(_)),
  )
}

///|
test "ISO payroll week must exist in its ISO year" {
  for text in ["2024-W00-1", "2024-W53-1", "2021-W53-7", "0000-W01-1"] {
    let r = queried(ledger_source(), "SELECT parse_date('" + text + "', '%G-W%V-%u') LIMIT 1")
    assert_true(r.failure() is Some(@query.Evaluation(_)))
  }
  for (s, expected) in [("2020-W53-7","2021-01-03"),("2024-W01-1","2024-01-01"),("2015-W53-4","2015-12-31")] {
    let r = queried(ledger_source(), "SELECT parse_date('" + s + "', '%G-W%V-%u') LIMIT 1")
    assert_eq(r.rows[0][0].to_text(), expected)
  }
}

///|
test "strptime preserves escaped locale directives and astral separators" {
  for (text, pattern, expected) in [
    ("%x 2024", "%%x %Y", "2024-01-01"),
    ("%c 2024", "%%c %Y", "2024-01-01"),
    ("%X 2024", "%%X %Y", "2024-01-01"),
    ("2024📅07", "%Y📅%m", "2024-07-01"),
    ("02/29/24", "%x", "2024-02-29"),
  ] {
    let r = queried(ledger_source(), "SELECT parse_date('" + text + "', '" + pattern + "') LIMIT 1")
    assert_true(r.is_ok())
    assert_eq(r.rows[0][0].to_text(), expected)
  }
}

///|
test "strptime verifies the full UTC offset even when only the date is returned" {
  for offset in ["+07:30:99", "+07:3045", "+0730:45", "+07:30:15.1234567"] {
    let r = queried(ledger_source(), "SELECT parse_date('2024 " + offset + "', '%Y %z') LIMIT 1")
    assert_true(r.failure() is Some(@query.Evaluation(_)))
  }
  for offset in ["Z", "+0730", "-07:30", "+073045", "-07:30:15.123456"] {
    let r = queried(ledger_source(), "SELECT parse_date('2024 " + offset + "', '%Y %z') LIMIT 1")
    assert_eq(r.rows[0][0].to_text(), "2024-01-01")
  }
}

///|
test "English weekday names must match their requested strptime width" {
  for (text, pattern) in [("Monday", "%a"), ("Mon", "%A"), ("Fri", "%A"), ("Friday", "%a")] {
    let r = queried(ledger_source(), "SELECT parse_date('" + text + "', '" + pattern + "') LIMIT 1")
    assert_true(r.failure() is Some(@query.Evaluation(_)))
  }
  for (text, pattern) in [("MON", "%a"), ("monday", "%A")] {
    let r = queried(ledger_source(), "SELECT parse_date('" + text + "', '" + pattern + "') LIMIT 1")
    assert_eq(r.rows[0][0].to_text(), "1900-01-01")
  }
}

///|
test "positive sign uses the ledger account types rather than English prefixes" {
  let source = "option \"name_assets\" \"Actif\"\noption \"name_income\" \"Recettes\"\noption \"name_expenses\" \"Depenses\"\noption \"name_equity\" \"Capital\"\n2024-01-01 open Actif:Cash USD\n2024-01-01 open Recettes:Fees USD\n2024-01-01 open Depenses:Rent USD\n2024-01-02 * \"fees\"\n  Actif:Cash 80 USD\n  Recettes:Fees -80 USD\n2024-01-03 * \"rent\"\n  Depenses:Rent 15 USD\n  Actif:Cash -15 USD\n"
  let r = queried(source,"SELECT account,possign(number,account) ORDER BY account")
  assert_true(r.is_ok())
  assert_eq(r.rows.map(fn(row) { row[1].to_text() }), ["80","-15","15","80"])
}

///|
test "renamed income accounts transfer to equity at OPEN and CLEAR" {
  let source = "option \"name_assets\" \"Actif\"\noption \"name_income\" \"Recettes\"\noption \"name_expenses\" \"Depenses\"\noption \"name_equity\" \"Capital\"\n2024-01-01 open Actif:Cash USD\n2024-01-01 open Recettes:Fees USD\n2024-01-01 open Depenses:Rent USD\n2024-01-02 * \"fees\"\n  Actif:Cash 80 USD\n  Recettes:Fees -80 USD\n2024-01-03 * \"rent\"\n  Depenses:Rent 15 USD\n  Actif:Cash -15 USD\n"
  for (clause, account) in [("OPEN ON 2024-02-01","Capital:Earnings:Previous"),("CLEAR","Capital:Earnings:Current")] {
    let r = queried(source, "SELECT account, sum(position) FROM " + clause + " GROUP BY account ORDER BY account")
    assert_true(r.is_ok())
    assert_true(r.rows.any(fn(row) { row[0].to_text() == account && row[1].to_text().contains("-65 USD") }))
  }
}

///|
test "anonymous singleton table permits calculations on an empty ledger" {
  for src in ["", ledger_source()] {
    assert_true(queried(src, "SELECT 2*3 FROM #").is_ok())
    assert_eq(queried(src, "SELECT 2*3 FROM #").rows[0][0].to_text(), "6")
    assert_eq(queried(src, "SELECT count(*) FROM #;").rows[0][0].to_text(), "1")
    let all = queried(src, "SELECT * FROM #")
    assert_eq(all.rows.length(), 1)
    assert_eq(all.columns.length(), 0)
    assert_eq(all.rows[0].length(), 0)
    assert_eq(queried(src, "SELECT 1 FROM # WHERE false").rows.length(), 0)
    assert_eq(queried(src, "SELECT 1 FROM # LIMIT 0").rows.length(), 0)
    assert_true(queried(src, "SELECT account FROM #").failure() is Some(@query.Compilation(_)))
    assert_true(queried(src, "SELECT 1 FROM # postings").failure() is Some(@query.Syntax(_)))
    assert_true(queried(src, "SELECT 1 FROM #where").failure() is Some(@query.Compilation(_)))
  }
}
