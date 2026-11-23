///|
fn parse_ok(source : String) -> @ast.Ledger {
  let ledger = @syntax.parse_source("test.beancount", source)
  if ledger.errors.length() > 0 {
    abort("unexpected parse errors: " + ledger.errors[0].to_string())
  }
  ledger
}

///|
test "infer_tolerance_from_cost follows generic option booleans" {
  let enabled = parse_ok("option \"infer_tolerance_from_cost\" \"ON\"\n")
  inspect(enabled.options.infer_tolerance_from_cost, content="true")
  let repeated = parse_ok(
    "option \"infer_tolerance_from_cost\" \"ON\"\noption \"infer_tolerance_from_cost\" \"yes\"\n",
  )
  inspect(repeated.options.infer_tolerance_from_cost, content="false")
}

///|
test "lexer splits strings, tags, links and punctuation" {
  let tokens = @syntax.tokenize(
    "Assets:Cash -1,234.50 USD {10 USD} #trip ^doc @ 7 CNY ; comment",
  )
  inspect(tokens.length(), content="13")
  inspect(tokens[0].kind is @syntax.Word("Assets:Cash"), content="true")
  inspect(tokens[1].kind is @syntax.Word("-1,234.50"), content="true")
  inspect(tokens[3].kind is @syntax.LBrace, content="true")
  inspect(tokens[7].kind is @syntax.Tag("trip"), content="true")
  inspect(tokens[8].kind is @syntax.Link("doc"), content="true")
  inspect(tokens[9].kind is @syntax.At, content="true")
}

///|
test "display_precision accepts and overwrites a wildcard key" {
  let ledger = parse_ok(
    "option \"display_precision\" \"*:0.01\"\noption \"display_precision\" \"USD:0.0001\"\noption \"display_precision\" \"*:0.001\"\n",
  )
  inspect(
    ledger.options.display_precision.get("*").unwrap().to_string(),
    content="0.001",
  )
  inspect(
    ledger.options.display_precision.get("USD").unwrap().to_string(),
    content="0.0001",
  )
}

///|
test "lexer preserves escapes in strings" {
  let tokens = @syntax.tokenize("\"a\\\"b\\n\"")
  inspect(tokens[0].kind is @syntax.Str("a\"b\n"), content="true")
}

///|
test "popmeta restores the previous value and rejects an absent key" {
  let ledger = @syntax.parse_source(
    "stack.bean", "pushmeta project: 1\npushmeta project: 2\n2024-01-01 * \"inner\"\npopmeta project:\n2024-01-02 * \"outer\"\npopmeta project:\n2024-01-03 * \"none\"\npopmeta project:\n",
  )
  inspect(ledger.entries.length(), content="3")
  inspect(
    ledger.entries[0].meta.get("project").unwrap().to_string(),
    content="2",
  )
  inspect(
    ledger.entries[1].meta.get("project").unwrap().to_string(),
    content="1",
  )
  inspect(ledger.entries[2].meta.get("project") is None, content="true")
  inspect(ledger.errors.length(), content="1")
  inspect(ledger.errors[0].loc.line, content="8")
}

///|
test "plugin processing mode accepts only the two upstream spellings" {
  let ledger = @syntax.parse_source(
    "mode.bean", "option \"plugin_processing_mode\" \"raw\"\noption \"plugin_processing_mode\" \"RAW\"\noption \"plugin_processing_mode\" \"default\"\noption \"title\" \"After\"\n",
  )
  inspect(ledger.errors.length(), content="1")
  inspect(ledger.errors[0].loc.line, content="2")
  inspect(ledger.options.title is Some("After"), content="true")
}

///|
test "empty decimal option resets the tolerance multiplier to zero" {
  let ledger = parse_ok(
    "option \"tolerance_multiplier\" \"0.25\"\noption \"tolerance_multiplier\" \"\"\n",
  )
  inspect(ledger.options.tolerance_multiplier.to_string(), content="0")
}

///|
test "parse options, plugins, includes and push stacks" {
  let ledger = parse_ok(
    "option \"title\" \"Test Ledger\"\noption \"inferred_tolerance_default\" \"USD:0.005\"\noption \"operating_currency\" \"USD\"\nplugin \"beancount.plugins.auto\" \"config\"\ninclude \"other.beancount\"\npushtag #trip\npushmeta project: \"moonbean\"\n2024-01-01 open Assets:Cash USD \"FIFO\"\n2024-01-02 * \"Coffee\"\n  Assets:Cash -3.00 USD\n  Expenses:Food 3.00 USD\npoptag #trip\npopmeta project:\n",
  )
  inspect(ledger.options.title is Some("Test Ledger"), content="true")
  inspect(ledger.options.operating_currencies.length(), content="1")
  inspect(
    ledger.options.inferred_tolerance_default.get("USD") is Some(_),
    content="true",
  )
  inspect(ledger.plugins.length(), content="1")
  inspect(ledger.includes.length(), content="1")
  inspect(ledger.entries.length(), content="2")
  match ledger.entries[0].directive {
    @ast.DOpen(open) => inspect(open.booking is Some("FIFO"), content="true")
    _ => abort("expected open")
  }
  match ledger.entries[1].directive {
    @ast.DTransaction(txn) => {
      inspect(txn.tags.contains("trip"), content="true")
      inspect(ledger.entries[1].meta.get("project") is Some(_), content="true")
    }
    _ => abort("expected transaction")
  }
}

///|
test "parse transaction postings, cost specs and prices" {
  let ledger = parse_ok(
    "2024-02-01 * \"Cafe\" \"Coffee\" #food ^r1\n  date: 2024-02-01\n  published: TRUE\n  Assets:Cash  -12.50 USD\n  Expenses:Food  12.50 USD\n    receipt: \"x\"\n\n2024-02-02 ! \"Grocery\"\n  Assets:Cash  -30.00 USD\n  Expenses:Food  30.00 USD\n\n2024-02-03 * \"Buy shares\"\n  Assets:Brokerage  10 HOOL {100.00 USD, 2024-02-03, \"lot\"} @@ 1001.00 USD\n  Assets:Cash  -1001.00 USD\n",
  )
  inspect(ledger.entries.length(), content="3")
  match ledger.entries[0].directive {
    @ast.DTransaction(txn) => {
      inspect(txn.flag, content="*")
      inspect(txn.payee is Some("Cafe"), content="true")
      inspect(txn.narration, content="Coffee")
      inspect(txn.tags.length(), content="1")
      inspect(txn.links.length(), content="1")
      inspect(
        ledger.entries[0].meta.get("published") is Some(@ast.MBool(true)),
        content="true",
      )
      inspect(txn.postings.length(), content="2")
      inspect(txn.postings[1].meta.get("receipt") is Some(_), content="true")
    }
    _ => abort("expected transaction")
  }
  match ledger.entries[2].directive {
    @ast.DTransaction(txn) => {
      let cost = match txn.postings[0].cost {
        Some(c) => c
        None => abort("expected cost")
      }
      inspect(cost.number_per is Some(_), content="true")
      inspect(cost.date is Some(_), content="true")
      inspect(cost.label is Some("lot"), content="true")
      match txn.postings[0].price {
        Some(@ast.Total(amount)) =>
          inspect(amount.number.to_string(), content="1001.00")
        _ => abort("expected total price")
      }
    }
    _ => abort("expected transaction")
  }
}

///|
test "parse arithmetic amount expressions" {
  let ledger = parse_ok(
    "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 * \"expr\"\n  Assets:Cash  (10 + 5) * 2 / 3 USD\n  Equity:Opening  -10 USD\n2024-01-03 * \"precedence\"\n  Assets:Cash  2 * 3 + 4 - 5 USD\n  Equity:Opening  -5 USD\n2024-01-03 balance Assets:Cash 10.00 ~ 0.01 USD\n",
  )
  match ledger.entries[2].directive {
    @ast.DTransaction(txn) =>
      match txn.postings[0].units {
        Some(units) => inspect(units.to_string(), content="10 USD")
        None => abort("expected units")
      }
    _ => abort("expected transaction")
  }
  match ledger.entries[3].directive {
    @ast.DTransaction(txn) =>
      match txn.postings[0].units {
        Some(units) => inspect(units.to_string(), content="5 USD")
        None => abort("expected units")
      }
    _ => abort("expected transaction")
  }
}

///|
test "parse balance tolerance and other directives" {
  let ledger = parse_ok(
    "2024-01-01 commodity USD\n2024-01-02 balance Assets:Cash 100.00 ~ 0.01 USD\n2024-01-03 price USD 7.20 CNY\n2024-01-04 event \"location\" \"Beijing\"\n2024-01-05 query \"q\" \"SELECT 1\"\n2024-01-06 note Assets:Cash \"hello\"\n2024-01-07 document Assets:Cash \"receipt.pdf\" #doc\n2024-01-08 custom \"budget\" \"food\" 10 USD TRUE 2024-01-01\n2024-01-09 pad Assets:Cash Equity:Opening\n2024-01-10 close Assets:Cash\n",
  )
  inspect(ledger.entries.length(), content="10")
  match ledger.entries[1].directive {
    @ast.DBalance(balance) => {
      inspect(balance.tolerance is Some(_), content="true")
      inspect(balance.amount.to_string(), content="100.00 USD")
    }
    _ => abort("expected balance")
  }
  match ledger.entries[7].directive {
    @ast.DCustom(custom) => {
      inspect(custom.custom_type, content="budget")
      inspect(custom.values.length(), content="4")
    }
    _ => abort("expected custom")
  }
}

///|
test "parse errors carry file and line" {
  let ledger = @syntax.parse_source(
    "bad.beancount", "2024-01-01 open assets:cash\n2024-13-01 open Assets:Cash\n2024-01-02 frobnicate Assets:Cash\n2024-01-03 close\n",
  )
  inspect(ledger.errors.length(), content="4")
  inspect(ledger.errors[0].loc.file, content="bad.beancount")
  inspect(ledger.errors[0].loc.line, content="1")
  inspect(ledger.errors[1].loc.line, content="2")
  inspect(ledger.errors[2].loc.line, content="3")
  inspect(ledger.errors[3].loc.line, content="4")
}

///|
test "metadata lines outside a directive are rejected" {
  let ledger = @syntax.parse_source("x.beancount", "  key: \"value\"\n")
  inspect(ledger.errors.length(), content="1")
  inspect(ledger.errors[0].code, content="parse.indent")
}

///|
test "oracle option boolean spellings and wildcard tolerance" {
  let ledger = @syntax.parse_source(
    "options.bean", "option \"infer_tolerance_from_cost\" \"True\"\noption \"render_commas\" \"yes\"\noption \"inferred_tolerance_default\" \"*:0.01\"\n",
  )
  assert_eq(ledger.errors.length(), 0)
  assert_true(ledger.options.infer_tolerance_from_cost)
  assert_true(ledger.options.render_commas)
  assert_true(ledger.options.inferred_tolerance_default.contains("*"))
}

///|
test "Unicode accounts retain lexer accepted semantic errors" {
  assert_true(@syntax.is_valid_account("Assets:Café"))
  assert_true(@syntax.is_valid_account("Assets:𐐀"))
  assert_true(@syntax.is_valid_account("Assets:꟎"))
  assert_true(@syntax.is_valid_account("Assets:A՘"))
  let astral = parse_ok("2024-01-01 open Assets:𐐀 USD\n")
  assert_eq(astral.entries.length(), 1)
  assert_true(@syntax.is_valid_account("Assets:Ünïcode-1"))
  assert_true(@syntax.is_valid_account("Assets:١abc"))
  assert_false(@syntax.is_valid_account("Assets:日本"))
  let ledger = @syntax.parse_source(
    "unicode.bean", "2024-01-01 open Assets:Café\n2024-01-01 open Assets:日本\n2024-01-01 open Assets:Ünïcode-1\n",
  )
  assert_eq(ledger.entries.length(), 3)
  let single = @syntax.parse_source(
    "meta.bean", "2024-01-01 open Assets:A\n  s: \"bad\"\n",
  )
  assert_eq(single.entries.length(), 0)
  assert_true(single.errors.length() > 0)
}

///|
test "streamed lines and bounded literals preserve independent parse values" {
  let source = StringBuilder()
  for i in 0..<1030 {
    source.write_string("2024-01-01 * \"row\"\r\n  Assets:A \{i}.00 USD\r\n")
  }
  source.write_string(
    "\n; boundary\n2024-01-02 * \"𐐀\"\n  Assets:A (1.00 + 2.00) USD\n    detail: \"first\"\n  Assets:A 1 USD\n  Assets:A 1.00 USD\n2024-01-03 note Assets:A \"last\"",
  )
  let ledger = parse_ok(source.to_string())
  assert_eq(ledger.entries.length(), 1032)
  assert_eq(ledger.entries[1029].loc.line, 2059)
  let entry = ledger.entries[1030]
  assert_eq(entry.loc.line, 2063)
  guard entry.directive is @ast.DTransaction(txn) else { abort("transaction") }
  assert_eq(txn.narration, "𐐀")
  assert_eq(txn.postings[0].units.unwrap().number.to_string(), "3.00")
  assert_eq(txn.postings[1].units.unwrap().number.to_string(), "1")
  assert_eq(txn.postings[2].units.unwrap().number.to_string(), "1.00")
  assert_eq(txn.postings[0].loc.line, 2064)
  assert_eq(txn.postings[0].meta.entries.length(), 1)
  assert_eq(txn.postings[1].meta.entries.length(), 0)
  assert_eq(ledger.entries[1031].loc.line, 2068)
  let mapped = @syntax.parse_source(
    "expanded.bean",
    "\n2024-01-01 open Assets:A\n",
    source_map=[@ast.Loc::new("skip.bean", 10), @ast.Loc::new("child.bean", 42)],
  )
  assert_eq(mapped.entries[0].loc.file, "child.bean")
  assert_eq(mapped.entries[0].loc.line, 42)
  let negative = parse_ok("2024-01-01 balance Assets:A -0.00 USD\n")
  assert_false(negative.entries[0].query_exact_decimal)
}

///|
test "multiline strings preserve physical source positions and escapes" {
  let ledger = parse_ok(
    "2024-01-01 open Assets:A USD\n2024-01-02 note Assets:A \"one\n  two\n\n; text\nthree\"\n2024-01-03 open Assets:B\n",
  )
  assert_eq(ledger.entries.length(), 3)
  assert_eq(ledger.entries[1].loc.line, 2)
  assert_eq(ledger.entries[2].loc.line, 7)
  guard ledger.entries[1].directive is @ast.DNote(note) else { abort("note") }
  assert_eq(note.comment, "one\n  two\n\n; text\nthree")
  let crlf = parse_ok(
    "2024-01-01 open Assets:A\r\n2024-01-02 note Assets:A \"a\r\nb\"\r\n",
  )
  guard crlf.entries[1].directive is @ast.DNote(note) else { abort("note") }
  assert_eq(note.comment, "a\r\nb")
}

///|
test "unterminated strings report a token error and recover following directives" {
  let ledger = @syntax.parse_source(
    "bad.bean", "2024-01-01 open Assets:A\n2024-01-02 note Assets:A \"bad\n2024-01-03 open Assets:B\n",
  )
  assert_eq(ledger.errors[0].code, "parse.token")
  assert_eq(ledger.errors[0].loc.line, 2)
  assert_eq(ledger.entries.length(), 2)
}

///|
test "metadata retains amounts expressions and empty values" {
  let ledger = parse_ok(
    "pushmeta stack: 2.50 USD\n2024-01-01 open Assets:A USD\n  value: (1+2)*3 USD\n  empty:\n  memo: \"a\nb\"\n2024-01-02 * \"stack\"\npopmeta stack:\n",
  )
  assert_true(ledger.entries[0].meta.get("empty") is Some(@ast.MNull))
  guard ledger.entries[0].meta.get("value") is Some(@ast.MAmount(amount)) else {
    abort("amount")
  }
  assert_eq(amount.number.to_string(), "9")
  assert_eq(amount.currency, "USD")
  assert_eq(
    ledger.entries[1].meta.get("stack").unwrap().to_string(),
    "2.50 USD",
  )
}

///|
test "transaction and posting flags follow the oracle alphabet" {
  for flag in ["A", "Z", "!", "#", "%", "&", "*", "?", "txn"] {
    let ledger = parse_ok("2024-01-02 " + flag + "\n")
    inspect(ledger.entries.length(), content="1")
  }
  for flag in ["a", "c", "o", "z", "'", "0"] {
    for narration in ["", " \"n\""] {
      let ledger = @syntax.parse_source(
        "flags.bean",
        "2024-01-02 " + flag + narration + "\n2024-01-03 open Assets:A\n",
      )
      inspect(ledger.errors.length() > 0, content="true")
      inspect(ledger.entries.length(), content="1")
    }
  }
}

///|
test "attached unknown word quotes recover at the invalid token line" {
  let ledger = @syntax.parse_source(
    "quotes.bean", "option \"title\" \"T\noption \"render_commas\" \"TRUE\"\n2024-01-01 open Assets:A\n2024-01-02 open Assets:B\n2024-01-03 note Assets:A \"n\"\n",
  )
  inspect(ledger.errors.length(), content="1")
  inspect(ledger.errors[0].loc.line, content="2")
  inspect(ledger.errors[0].message, content="Invalid token: 'render_commas\"'")
  inspect(ledger.entries.length(), content="3")
  inspect(
    @syntax.logical_line_end("option \"T\nword\" \"TRUE\"\nnext\n"),
    content="22",
  )
}

///|
test "amount metadata splits adjacent multiplication and rejects leading dot" {
  let ledger = parse_ok(
    "2024-01-01 open Assets:A\n  amount: (2*3+4)/2 USD\n2024-01-02 * \"n\"\n  Assets:A 2*3 USD\n  Assets:A -6 USD\n",
  )
  inspect(
    ledger.entries[0].meta.get("amount").unwrap().to_string(),
    content="5 USD",
  )
  let bad = @syntax.parse_source(
    "dot.bean", "2024-01-01 open Assets:A\n  amount: .5 USD\n",
  )
  inspect(bad.errors.length(), content="1")
  inspect(bad.entries.length(), content="0")
}

///|
test "duplicate transaction metadata reports an error and retains the first value" {
  let ledger = @syntax.parse_source(
    "duplicate.bean", "2024-01-01 open Assets:A\n  kk: 1 USD\n  kk: 2 USD\n2024-01-02 * \"n\"\n  kk: 3 USD\n  kk: 4 USD\n  Assets:A 0 USD\n    kk: \"first\"\n    kk: \"last\"\n",
  )
  inspect(ledger.errors.length(), content="2")
  inspect(ledger.entries.length(), content="2")
  inspect(
    ledger.entries[0].meta.get("kk").unwrap().to_string(),
    content="2 USD",
  )
  inspect(
    ledger.entries[1].meta.get("kk").unwrap().to_string(),
    content="3 USD",
  )
  match ledger.entries[1].directive {
    @ast.DTransaction(txn) =>
      inspect(
        txn.postings[0].meta.get("kk").unwrap().to_string(),
        content="\"first\"",
      )
    _ => abort("expected transaction")
  }
}

///|
test "posting flags reject lowercase tokens and accept hash" {
  let good = parse_ok("2024-01-02 * \"n\"\n  # Assets:A 0 USD\n")
  inspect(good.entries.length(), content="1")
  let bad = @syntax.parse_source(
    "flags.bean", "2024-01-02 * \"n\"\n  a Assets:A 0 USD\n2024-01-03 open Assets:B\n",
  )
  inspect(bad.errors.length(), content="1")
  inspect(bad.errors[0].loc.line, content="2")
  inspect(bad.entries.length(), content="1")
}

///|
test "duplicate string metadata follows the oracle singleton exceptions" {
  let ledger = @syntax.parse_source(
    "duplicates.bean", "2024-01-01 * \"n\"\n  empty: \"\"\n  empty: \"\"\n  short: \"é\"\n  short: \"é\"\n  long: \"same\"\n  long: \"same\"\n  wide: \"☃\"\n  wide: \"☃\"\n",
  )
  inspect(ledger.entries.length(), content="1")
  inspect(ledger.errors.length(), content="2")
}

///|
test "readonly internal options report errors without consuming later directives" {
  let ledger = @syntax.parse_source(
    "options.bean", "option \"filename\" \"shadow.bean\"\noption \"plugin\" \"unrecognized\"\noption \"title\" \"Recovered\"\n2024-01-01 open Assets:Cash USD\n",
  )
  inspect(ledger.errors.length(), content="2")
  inspect(ledger.errors[0].loc.line, content="1")
  inspect(ledger.errors[1].loc.line, content="2")
  inspect(ledger.options.title is Some("Recovered"), content="true")
  inspect(ledger.plugins.length(), content="0")
  inspect(ledger.entries.length(), content="1")
}

///|
test "one end-of-file diagnostic for each unclosed metadata key" {
  let ledger = @syntax.parse_source(
    "pending.bean", "pushmeta project: \"outer\"\npushmeta project: \"inner\"\npushmeta cleared: 3\npopmeta cleared:\n2024-01-01 * \"still recorded\"\n",
  )
  assert_eq(ledger.entries.length(), 1)
  assert_eq(ledger.errors.length(), 1)
  assert_eq(ledger.errors[0].code, "parse.pushmeta")
  assert_eq(ledger.errors[0].loc.file, "pending.bean")
  assert_eq(ledger.errors[0].loc.line, 0)
  assert_true(ledger.errors[0].message.contains("project"))
}

///|
test "body tags and links accumulate before postings only" {
  for
    posting in [
      "Assets:Cash \"bad\"", "Assets:Cash 1 + USD", "Assets:Cash 1 USD \"extra\"",
    ] {
    let invalid = @syntax.parse_source(
      "broken.bean",
      "2024-01-01 * \"bad posting\"\n  " +
      posting +
      "\n  #late ^link\n2024-01-02 * \"next\"\n",
    )
    assert_eq(invalid.entries.length(), 1)
    assert_eq(invalid.entries[0].loc.line, 4)
    assert_eq(invalid.errors.length(), 1)
    assert_eq(invalid.errors[0].loc.line, 2)
  }
  let ledger = @syntax.parse_source(
    "body.bean", "2024-01-02 * \"body\" #old\n  #alpha ^first #beta ^second #alpha\n  Assets:Cash 0 USD\n  ^late #wrong\n2024-01-03 * \"following\"\n",
  )
  assert_eq(ledger.errors.length(), 1)
  assert_eq(ledger.errors[0].loc.line, 1)
  assert_eq(ledger.entries.length(), 2)
  guard ledger.entries[0].directive is @ast.DTransaction(txn) else {
    abort("transaction")
  }
  assert_eq(txn.tags, ["old", "alpha", "beta"])
  assert_eq(txn.links, ["first", "second"])
  assert_eq(txn.postings.length(), 1)
}

///|
test "malformed controls do not update options, plugin lists or includes" {
  let ledger = @syntax.parse_source(
    "controls.bean", "option \"title\" \"before\"\noption \"title\" \"lost\" \"extra\"\nplugin \"good\" \"cfg\"\nplugin \"bad\" \"cfg\" \"extra\"\ninclude \"bad.bean\" \"extra\"\ninclude \"good.bean\"\n2024-01-02 * \"next\"\n",
  )
  assert_eq(ledger.errors.length(), 3)
  assert_eq(ledger.options.title, Some("before"))
  assert_eq(ledger.plugins.length(), 1)
  assert_eq(ledger.plugins[0].name, "good")
  assert_eq(ledger.includes.length(), 1)
  assert_eq(ledger.includes[0].0, "good.bean")
  assert_eq(ledger.entries.length(), 1)
}

///|
test "trailing arguments do not leave incomplete dated entries in a ledger" {
  let source = "2024-01-01 close Assets:A USD\n2024-01-02 commodity USD EUR\n2024-01-03 pad Assets:A Equity:B USD\n2024-01-04 balance Assets:A 0 USD EUR\n2024-01-05 price USD 1 EUR GBP\n2024-01-06 event \"a\" \"b\" \"extra\"\n2024-01-07 query \"id\" \"text\" \"extra\"\n2024-01-08 document Assets:A \"x\" \"extra\"\n2024-01-09 open Assets:B USD\n"
  let ledger = @syntax.parse_source("dated.bean", source)
  assert_eq(ledger.errors.length(), 8)
  assert_eq(ledger.entries.length(), 1)
  assert_eq(ledger.entries[0].loc.line, 9)
}

///|
test "custom numbers and amounts evaluate arithmetic without merging later fields" {
  let ledger = @syntax.parse_source(
    "custom.bean", "2024-01-01 custom \"budget\" (2 + 3) * 4 USD \"ok\" (9 - 2) 2 FALSE\n",
  )
  assert_eq(ledger.errors.length(), 0)
  assert_eq(ledger.entries.length(), 1)
  guard ledger.entries[0].directive is @ast.DCustom(c) else { abort("custom") }
  assert_eq(c.values.map(fn(v) { v.to_string() }), [
    "20 USD", "\"ok\"", "7", "2", "FALSE",
  ])
}

///|
test "grouped ledger quantities reject misplaced thousands separators" {
  for bad in ["1,2", "1,23", "1234,567", "12,34,567", "1,23.45"] {
    let ledger = @syntax.parse_source(
      "groups.bean",
      "2024-01-01 price USD " + bad + " EUR\n2024-01-02 commodity GBP\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 2)
    assert_true(ledger.errors.length() > 0)
  }
  for good in ["1,234", "12,345,678.90", "123456.78", "-12,345.00"] {
    assert_eq(
      parse_ok("2024-01-01 price USD " + good + " EUR\n").entries.length(),
      1,
    )
  }
}

///|
test "metadata distinguishes explicit NULL and reserved words from currencies" {
  let ledger = parse_ok(
    "2024-01-01 * \"demo\"\n  empty: NULL\n  truth: TRUE\n  ticker: NULLX\n  zero: 0 USD\n",
  )
  assert_true(ledger.entries[0].meta.get("empty") is Some(@ast.MNull))
  assert_true(ledger.entries[0].meta.get("truth") is Some(@ast.MBool(true)))
  assert_true(
    ledger.entries[0].meta.get("ticker") is Some(@ast.MCurrency("NULLX")),
  )
  for word in ["TRUE", "FALSE", "NULL"] {
    let invalid = @syntax.parse_source(
      "reserved.bean",
      "2024-01-01 * \"bad\"\n  value: 1 " +
      word +
      "\n2024-01-02 commodity USD\n",
    )
    assert_eq(invalid.entries.length(), 1)
    assert_eq(invalid.entries[0].loc.line, 3)
    assert_eq(invalid.errors.length(), 1)
  }
}

///|
test "metadata keys use the grammar in entries, postings and pushed context" {
  for key in ["Mixed", "AB", "a.b", "ab:c", "99", "élan"] {
    let source = "2024-01-01 * \"bad\"\n  " +
      key +
      ": \"value\"\n2024-01-02 commodity USD\n"
    let ledger = @syntax.parse_source("keys.bean", source)
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 3)
    assert_true(ledger.errors.length() > 0)
  }
  let ok = parse_ok(
    "pushmeta a-B_9: \"yes\"\n2024-01-01 * \"ok\"\n  aB: TRUE\n  Assets:Cash 1 USD\n    x9: 7\npopmeta a-B_9:\n",
  )
  assert_true(ok.entries[0].meta.get("a-B_9") is Some(@ast.MString("yes")))
}

///|
test "open distinguishes currency lists from a single quoted booking method" {
  for
    tail in [
      "USD EUR", "USD,,EUR", "USD,", "\"FIFO\" USD", "USD \"FIFO\" \"LIFO\"",
    ] {
    let ledger = @syntax.parse_source(
      "open.bean",
      "2024-01-01 open Assets:A " + tail + "\n2024-01-02 commodity USD\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 2)
    assert_eq(ledger.errors.length(), 1)
  }
  let ledger = parse_ok(
    "2024-01-01 open Assets:A ,FIFO,USD \"LIFO\"\n2024-01-02 open Assets:B FIFO\n",
  )
  guard ledger.entries[0].directive is @ast.DOpen(a) else { abort("open") }
  guard ledger.entries[1].directive is @ast.DOpen(b) else { abort("open") }
  assert_eq(a.currencies, ["FIFO", "USD"])
  assert_true(a.booking is Some("LIFO"))
  assert_eq(b.currencies, ["FIFO"])
  assert_true(b.booking is None)
}

///|
test "a narration alone cannot open a transaction" {
  for header in ["\"bare\"", "\"payee\" \"narration\"", "\"tagged\" #trip"] {
    let ledger = @syntax.parse_source(
      "flags.bean",
      "2024-01-01 " + header + "\n  Assets:A 1 USD\n2024-01-02 txn \"valid\"\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 3)
    assert_true(ledger.errors.length() > 0)
  }
  assert_eq(
    parse_ok("2024-01-01 *\n2024-01-02 ! \"payee\" \"narration\"\n").entries.length(),
    2,
  )
}

///|
test "tag and link names have explicit token boundaries and cannot be empty" {
  for tail in ["#", "^", "#bad+word", "^bad:part", "#café", "^a!b"] {
    let ledger = @syntax.parse_source(
      "tags.bean",
      "2024-01-01 * \"bad\" " + tail + "\n2024-01-02 commodity USD\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 2)
    assert_true(ledger.errors.length() > 0)
  }
  let ledger = parse_ok(
    "2024-01-01 # \"ok\" #a/b-C.d_9 ^./x\n  # Assets:A 1 USD\n",
  )
  guard ledger.entries[0].directive is @ast.DTransaction(txn) else {
    abort("transaction")
  }
  assert_eq(txn.tags, ["a/b-C.d_9"])
  assert_eq(txn.links, ["./x"])
  assert_true(txn.postings[0].flag is Some("#"))
}

///|
test "invalid push and pop directives never mutate active tag or metadata stacks" {
  let ledger = @syntax.parse_source(
    "stack.bean", "pushmeta project: \"parent\"\npushtag #parent\npushmeta fake: \"ghost\" \"extra\"\npushtag #ghost \"extra\"\npopmeta project: \"extra\"\npoptag #parent \"extra\"\n2024-01-01 * \"kept\"\npopmeta project:\npoptag #parent\n2024-01-02 * \"clear\"\n",
  )
  assert_eq(ledger.errors.length(), 4)
  for i in 0..<4 {
    assert_eq(ledger.errors[i].loc.line, i + 3)
  }
  guard ledger.entries[0].directive is @ast.DTransaction(txn) else {
    abort("txn")
  }
  assert_eq(txn.tags, ["parent"])
  assert_true(
    ledger.entries[0].meta.get("project") is Some(@ast.MString("parent")),
  )
  assert_true(ledger.entries[0].meta.get("fake") is None)
  assert_true(ledger.entries[1].meta.get("project") is None)
}

///|
test "column-zero org headings and drawers skip only their own physical line" {
  let src = "* Ledger \"unclosed\n:PROPERTIES:\n:owner: example\n:END:\n## note\n! comment\n? heading\n& note\n% note\n2024-01-01 * \"real\"\n  Assets:A 0 USD\n"
  let ledger = @syntax.parse_source("org.bean", src)
  assert_eq(ledger.errors.length(), 0)
  assert_eq(ledger.entries.length(), 1)
  assert_eq(ledger.entries[0].loc.line, 10)
  assert_eq(@syntax.logical_line_end(src), "* Ledger \"unclosed".length())
  for bad in ["#name", "*", ":", "!", "  * heading"] {
    assert_true(
      @syntax.parse_source("head.bean", bad + "\n2024-01-02 commodity USD\n").errors.length() >
      0,
    )
  }
}

///|
test "ledger dates accept slash and variable-width fields without changing divisions" {
  let src = "2024/2/29 open Assets:A\n00002024-002/029 * \"leap\"\n  stamp: 2024/02-29\n2024-03-1 price GBP (12/3) USD\n"
  let ledger = @syntax.parse_source("calendar.bean", src)
  assert_eq(ledger.errors.length(), 0)
  assert_eq(ledger.entries.length(), 3)
  assert_eq(ledger.entries[0].date.to_string(), "2024-02-29")
  assert_eq(ledger.entries[1].date.to_string(), "2024-02-29")
  guard ledger.entries[1].meta.get("stamp") is Some(@ast.MDate(d)) else {
    abort("date")
  }
  assert_eq(d.to_string(), "2024-02-29")
  guard ledger.entries[2].directive is @ast.DPrice(price) else {
    abort("price")
  }
  assert_eq(price.amount.number.to_string(), "4")
  for bad in ["1900/2/29", "99999-1-1", "2024-00-01", "2024-4/31"] {
    let invalid = @syntax.parse_source(
      "calendar.bean",
      bad + " commodity USD\n2024/1/1 commodity EUR\n",
    )
    assert_eq(invalid.entries.length(), 1)
    assert_eq(invalid.entries[0].loc.line, 2)
    assert_true(invalid.errors.length() > 0)
  }
}

///|
test "slash futures symbols stay intact without stealing numeric division" {
  for name in ["/6J", "/NQH21", "/NQH21_QNEG21C13100", "/A", "/A.B-9"] {
    let ledger = @syntax.parse_source(
      "futures.bean",
      "2024-01-01 commodity " +
      name +
      "\n2024-01-02 price " +
      name +
      " (12/3) USD\n",
    )
    assert_eq(ledger.errors.length(), 0)
    assert_eq(ledger.entries.length(), 2)
    guard ledger.entries[0].directive is @ast.DCommodity(c) else {
      abort("commodity")
    }
    assert_eq(c.currency, name)
    guard ledger.entries[1].directive is @ast.DPrice(q) else { abort("price") }
    assert_eq(q.amount.number.to_string(), "4")
  }
  for bad in ["/123", "/6.3", "/A.", "/A_"] {
    let invalid = @syntax.parse_source(
      "futures.bean",
      "2024-01-01 commodity " + bad + "\n2024-01-02 commodity USD\n",
    )
    assert_eq(invalid.entries.length(), 1)
    assert_eq(invalid.entries[0].loc.line, 2)
    assert_true(invalid.errors.length() > 0)
  }
}

///|
test "include source maps keep tag controls and unclosed stacks in their physical file" {
  let source = "pushtag #root\n2024-01-01 * \"outside\"\npoptag #root\n2024-01-02 * \"child\"\n2024-01-03 * \"back\"\npoptag #root\npushtag #twice\npushtag #twice\n"
  let files = [
    "root.bean", "root.bean", "child.bean", "child.bean", "root.bean", "root.bean",
    "grand.bean", "grand.bean",
  ]
  let physical = [1, 2, 1, 2, 4, 5, 10, 11]
  let map = files.mapi((i, f) => @ast.Loc::new(f, physical[i]))
  let ledger = @syntax.parse_source("root.bean", source, source_map=map)
  assert_eq(ledger.entries.length(), 3)
  for i in 0..<3 {
    guard ledger.entries[i].directive is @ast.DTransaction(t) else {
      abort("txn")
    }
    assert_eq(t.tags, if i == 1 { [] } else { ["root"] })
  }
  assert_eq(ledger.errors.length(), 3)
  assert_eq(ledger.errors[0].loc.file, "child.bean")
  assert_eq(ledger.errors[0].loc.line, 1)
  for i in 1..<3 {
    assert_eq(ledger.errors[i].loc.file, "grand.bean")
    assert_eq(ledger.errors[i].loc.line, 0)
  }
}

///|
test "document directives receive active tags without changing link or stack scope" {
  let source = "pushtag #week\npushtag #week\n2024-01-01 document Assets:A \"a.pdf\" #receipt #week ^file\npoptag #week\n2024-01-02 note Assets:A \"accompany\" #note ^memo\npoptag #week\n2024-01-03 document Assets:A \"b.pdf\" #later ^next\n"
  let ledger = @syntax.parse_source("docs.bean", source)
  assert_eq(ledger.errors.length(), 0)
  guard ledger.entries[0].directive is @ast.DDocument(first) else {
    abort("doc")
  }
  guard ledger.entries[1].directive is @ast.DNote(note) else { abort("note") }
  guard ledger.entries[2].directive is @ast.DDocument(second) else {
    abort("doc")
  }
  assert_eq(first.tags, ["week", "receipt"])
  assert_eq(first.links, ["file"])
  assert_eq(note.tags, ["week", "note"])
  assert_eq(second.tags, ["later"])
}

///|
test "custom directives do not turn standalone tags and currency symbols into values" {
  for
    tail in [
      "USD", "#tag", "NULL", "\"start\" EUR", "1 USD #tag", "\"a\" * \"b\"",
    ] {
    let ledger = @syntax.parse_source(
      "custom.bean",
      "2024-01-01 custom \"bad\" " + tail + "\n2024-01-02 commodity USD\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 2)
    assert_true(ledger.errors.length() > 0)
  }
  let good = @syntax.parse_source(
    "custom.bean", "2024-01-01 custom \"ok\" \"item\" 2 USD TRUE 2024-01-01 Assets:Cash (3+4)\n",
  )
  assert_eq(good.errors.length(), 0)
  guard good.entries[0].directive is @ast.DCustom(c) else { abort("custom") }
  assert_eq(c.values.length(), 6)
}

///|
test "commodity tokens cannot end in punctuation or use reserved literal words" {
  for bad in ["USD-", "USD.", "USD_", "USD'", "TRUE", "FALSE", "NULL"] {
    let ledger = @syntax.parse_source(
      "currencies.bean",
      "2024-01-01 commodity " +
      bad +
      "\n2024-01-02 open Assets:A " +
      bad +
      "\n2024-01-03 commodity USD\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 3)
    assert_eq(ledger.errors.length(), 2)
  }
  let controls = @syntax.parse_source(
    "currencies.bean", "2024-01-01 commodity A\n2024-01-01 commodity A-.B\n2024-01-01 commodity A'B\n2024-01-01 commodity NULLX\n2024-01-01 commodity /6J\n2024-01-02 * \"ok\"\n  truth: TRUE\n  absent: NULL\n",
  )
  assert_eq(controls.errors.length(), 0)
  assert_eq(controls.entries.length(), 6)
  assert_true(controls.entries[5].meta.get("truth") is Some(@ast.MBool(true)))
  assert_true(controls.entries[5].meta.get("absent") is Some(@ast.MNull))
}

///|
test "an explicit empty booking method inherits the configured default" {
  let src = "option \"booking_method\" \"FIFO\"\n2024-01-01 open Assets:A USD \"\"\n2024-01-02 open Assets:B \"\"\n2024-01-03 open Assets:C \"LIFO\"\n"
  let ledger = @syntax.parse_source("booking.bean", src)
  assert_eq(ledger.errors.length(), 0)
  guard ledger.entries[0].directive is @ast.DOpen(a) else { abort("open") }
  guard ledger.entries[1].directive is @ast.DOpen(b) else { abort("open") }
  guard ledger.entries[2].directive is @ast.DOpen(c) else { abort("open") }
  assert_true(a.booking is None)
  assert_true(b.booking is None)
  assert_true(c.booking is Some("LIFO"))
  assert_eq(ledger.options.booking_method, "FIFO")
}

///|
test "unclosed or incorrectly separated cost fields cannot leave a posting" {
  for
    malformed in [
      "{5 USD", "{5 USD}}", "{{5 USD}", "{5 USD,}", "{,}", "{5 USD,,2024-01-01}",
      "{5 USD 2024-01-01}", "{#oops}",
    ] {
    let ledger = @syntax.parse_source(
      "cost.bean",
      "2024-01-01 * \"bad\"\n  Assets:A 1 HOOL " +
      malformed +
      "\n2024-01-02 commodity USD\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.entries[0].loc.line, 3)
    assert_eq(ledger.errors.length(), 1)
  }
  for valid in ["{}", "{{5 USD}}", "{5 USD,2024-01-01,\"label\"}", "{,5 USD}"] {
    let ledger = @syntax.parse_source(
      "cost.bean",
      "2024-01-01 * \"ok\"\n  Assets:A 1 HOOL " + valid + "\n",
    )
    assert_eq(ledger.entries.length(), 1)
    assert_eq(ledger.errors.length(), 0)
  }
}

///|
test "duplicate cost fields report each conflict without overwriting first values" {
  let ledger = @syntax.parse_source(
    "lots.bean", "2024-01-01 * \"first wins\"\n  Assets:A 2 HOOL {3 USD,4 EUR,2024-01-01,2024-01-02,\"first\",\"second\"}\n2024-01-02 * \"complete cost is one component\"\n  Assets:A 2 HOOL {USD,5 USD}\n2024-01-03 commodity USD\n",
  )
  assert_eq(ledger.errors.length(), 4)
  assert_eq(ledger.errors[0].loc.line, 2)
  assert_eq(ledger.errors[3].loc.line, 4)
  guard ledger.entries[0].directive is @ast.DTransaction(t) else {
    abort("transaction")
  }
  guard ledger.entries[1].directive is @ast.DTransaction(u) else {
    abort("transaction")
  }
  let lot = t.postings[0].cost.unwrap()
  assert_eq(lot.number_per.unwrap().to_string(), "3")
  assert_eq(lot.currency.unwrap(), "USD")
  assert_eq(lot.date.unwrap().to_string(), "2024-01-01")
  assert_eq(lot.label.unwrap(), "first")
  assert_true(u.postings[0].cost.unwrap().number_per is None)
  assert_eq(u.postings[0].cost.unwrap().currency.unwrap(), "USD")
  let merged = @syntax.parse_source(
    "merge.bean", "2024-01-01 * \"merge\"\n  Assets:A 1 HOOL {*,*}\n",
  )
  assert_eq(merged.errors.length(), 1)
  guard merged.entries[0].directive is @ast.DTransaction(m) else {
    abort("transaction")
  }
  assert_true(m.postings[0].cost.unwrap().merge)
}

///|
test "negative quoted posting prices are diagnosed and normalized for accounting" {
  let source = "2024-01-01 * \"trade\"\n  Assets:A 5 HOOL @ -2 USD\n  Assets:B -2 HOOL @@ -8 USD\n  Assets:C 1 HOOL @ -0 USD\n2024-01-02 price HOOL -10 USD\n"
  let ledger = @syntax.parse_source("price.bean", source)
  assert_eq(ledger.entries.length(), 2)
  assert_eq(ledger.errors.length(), 2)
  assert_eq(ledger.errors[0].loc.line, 2)
  assert_eq(ledger.errors[1].loc.line, 3)
  guard ledger.entries[0].directive is @ast.DTransaction(t) else {
    abort("transaction")
  }
  guard ledger.entries[1].directive is @ast.DPrice(q) else { abort("price") }
  assert_eq(t.postings[0].price.unwrap().amount().number.to_string(), "2")
  assert_eq(t.postings[1].price.unwrap().amount().number.to_string(), "8")
  assert_true(t.postings[1].price is Some(@ast.PriceAnno::Total(_)))
  assert_eq(q.amount.number.to_string(), "-10")
  assert_true(t.postings[2].price.unwrap().amount().number.is_zero())
}

///|
test "legacy pipe separators preserve txn strings and honor explicit opt-in" {
  let source = "2024-01-01 * \"cash | card\"|\"first\"\noption \"allow_pipe_separator\" \"true\"\n2024-01-02 * \"shop\"|\"second\"\n2024-01-03 * |\"single\" #tag\n2024-01-04 * \"too\"|\"many\"|\"strings\"\n2024-01-05 * \"after\"\n"
  let ledger = @syntax.parse_source("pipe.bean", source)
  assert_eq(ledger.entries.length(), 4)
  assert_eq(ledger.errors.length(), 3)
  assert_eq(ledger.errors[0].loc.line, 1)
  assert_eq(ledger.errors[1].loc.line, 2)
  assert_eq(ledger.errors[2].loc.line, 5)
  let payees = [Some("cash | card"), Some("shop"), None, None]
  for i, expected in ["first", "second", "single", "after"] {
    guard ledger.entries[i].directive is @ast.DTransaction(t) else {
      abort("transaction")
    }
    assert_eq(t.payee, payees[i])
    assert_eq(t.narration, expected)
  }
}

///|
test "accepts Beancount's one-digit double-comma leading group only" {
  for
    (raw, exact) in [
      ("1,,234", "1234"),
      ("+1,,234,005.60", "1234005.60"),
      ("-0,,234", "-234"),
      ("1,,234-1", "1233"),
      ("1,,234+1,,002", "2236"),
    ] {
    let parsed = @syntax.parse_source(
      "groups.bean",
      "2024-01-01 price XXX " + raw + " USD\n",
    )
    assert_true(parsed.errors.is_empty())
    assert_true(parsed.entries[0].directive is @ast.DPrice(_))
    if parsed.entries[0].directive is @ast.DPrice(price) {
      assert_eq(price.amount.number.to_string(), exact)
    }
  }
  for
    raw in [
      "12,,345", "01,,234", "1,,,234", "1,234,,567", "1,,23", "1,,234.5,6", "1, ,234",
    ] {
    let parsed = @syntax.parse_source(
      "groups.bean",
      "2024-01-01 price XXX " + raw + " USD\n",
    )
    assert_true(!parsed.errors.is_empty())
  }
}

///|
test "misspelled accounting options are diagnosed without keeping them as live settings" {
  let s = "option \"operating_curency\" \"EUR\"\noption \"name_asset\" \"Banque\"\noption \"operating_currency\" \"USD\"\noption \"allow_deprecated_none_for_tags_and_links\" \"TRUE\"\n"
  let ledger = @syntax.parse_source("opts.bean", s)
  assert_eq(ledger.errors.length(),2)
  assert_eq(ledger.errors.map(fn(d) {d.loc.line}), [1,2])
  assert_eq(ledger.errors.map(fn(d) {d.code}), ["parse.option","parse.option"])
  assert_true(ledger.options.get("operating_curency") is None)
  assert_eq(ledger.options.operating_currencies,["USD"])
}
