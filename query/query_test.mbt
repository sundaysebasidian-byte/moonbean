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
    assert_true(r.failure() is Some(@query.Unsupported(_)))
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
      assert_true(r.failure() is Some(@query.Unsupported(_)))
      assert_true(r.error.unwrap().contains("query.unsupported.star"))
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
    Some("unsupported query.unsupported.star at BQL:2:7"),
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
test "opening summaries reject unavailable transaction account sets" {
  let r = queried(ledger_source(), "SELECT accounts FROM OPEN ON 2024-03-01")
  assert_true(r.failure() is Some(@query.Unsupported(_)))
  assert_true(r.error.unwrap().contains("query.unsupported.period_column"))
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
  assert_true(r.failure() is Some(@query.Unsupported(_)))
  let source = "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"one\" #a #b\n  Assets:A 1 USD\n  Equity:A -1 USD\n2024-01-03 * \"two\" #b #a\n  Assets:A 1 USD\n  Equity:A -1 USD\n"
  let r = queried(source, "SELECT count(*) GROUP BY tags")
  assert_true(r.failure() is Some(@query.Compilation(_)))
}

///|
test "signed zero numeric results reject exact representation" {
  for expression in ["0.0/-1", "safediv(0.0,-1)", "0.0*-1"] {
    let r = queried(ledger_source(), "SELECT repr(" + expression + ") LIMIT 1")
    assert_true(r.failure() is Some(@query.Unsupported(_)))
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
