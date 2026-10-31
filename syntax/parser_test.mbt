///|
fn parse_ok(source : String) -> @ast.Ledger {
  let ledger = @syntax.parse_source("test.beancount", source)
  if ledger.errors.length() > 0 {
    abort("unexpected parse errors: " + ledger.errors[0].to_string())
  }
  ledger
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
test "lexer preserves escapes in strings" {
  let tokens = @syntax.tokenize("\"a\\\"b\\n\"")
  inspect(tokens[0].kind is @syntax.Str("a\"b\n"), content="true")
}

///|
test "parse options, plugins, includes and push stacks" {
  let ledger = parse_ok(
    "option \"title\" \"Test Ledger\"\noption \"inferred_tolerance_default\" \"USD:0.005\"\noption \"operating_currency\" \"USD\"\nplugin \"beancount.plugins.auto\" \"config\"\ninclude \"other.beancount\"\npushtag #trip\npushmeta project: \"moonbean\"\n2024-01-01 open Assets:Cash USD,FIFO\n2024-01-02 * \"Coffee\"\n  Assets:Cash -3.00 USD\n  Expenses:Food 3.00 USD\npoptag #trip\npopmeta project:\n",
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
