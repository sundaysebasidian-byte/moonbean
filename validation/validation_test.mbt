///|
fn validated(source : String) -> @validation.ValidatedLedger {
  @validation.validate_ledger(@syntax.parse_source("test.beancount", source))
}

///|
fn has_error(v : @validation.ValidatedLedger, code : String) -> Bool {
  for diagnostic in v.errors {
    if diagnostic.code == code {
      return true
    }
  }
  false
}

///|
fn find_transaction(
  v : @validation.ValidatedLedger,
  narration : String,
) -> @ast.Transaction? {
  for entry in v.entries {
    match entry.directive {
      DTransaction(txn) => if txn.narration == narration { return Some(txn) }
      _ => ()
    }
  }
  None
}

///|
test "validates accounts and inventories" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"fund\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n",
  )
  inspect(v.errors.length(), content="0")
  inspect(v.accounts.length(), content="2")
  let inventory = v.inventory("Assets:Cash")
  inspect(inventory.quantity("USD").to_string(), content="10")
}

///|
test "reports unknown and inactive accounts with source lines" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-02-01 close Assets:Cash\n" +
    "2023-12-31 * \"early\"\n" +
    "  Assets:Cash 1 USD\n" +
    "  Equity:Opening -1 USD\n" +
    "2024-02-02 * \"late\"\n" +
    "  Assets:Cash 1 USD\n" +
    "  Equity:Opening -1 USD\n" +
    "2024-01-05 * \"unknown\"\n" +
    "  Assets:Missing 1 USD\n" +
    "  Equity:Opening -1 USD\n",
  )
  inspect(v.errors.length(), content="4")
  inspect(has_error(v, "validation.inactive_account"), content="true")
  inspect(has_error(v, "validation.unknown_account"), content="true")
  let inactive_lines = []
  for diagnostic in v.errors {
    if diagnostic.code == "validation.inactive_account" {
      inactive_lines.push(diagnostic.loc.line)
    }
  }
  inspect(inactive_lines.contains(4), content="true")
  inspect(inactive_lines.contains(7), content="true")
}

///|
test "accepts transactions on the close date" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-02-01 close Assets:Cash\n" +
    "2024-02-01 * \"closing day\"\n" +
    "  Assets:Cash 1 USD\n" +
    "  Equity:Opening -1 USD\n",
  )
  inspect(v.errors.length(), content="0")
}

///|
test "infers tolerance from fractional units" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"tiny\"\n" +
    "  Assets:Cash 10.00 USD\n" +
    "  Equity:Opening -10.004 USD\n" +
    "2024-01-03 * \"bad\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -9 USD\n",
  )
  inspect(v.errors.length(), content="1")
  inspect(v.errors[0].code, content="validation.unbalanced")
  inspect(v.errors[0].message.contains("(1 USD)"), content="true")
}

///|
test "interpolates one missing posting amount" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"one missing\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening\n",
  )
  inspect(v.errors.length(), content="0")
  let txn = match find_transaction(v, "one missing") {
    Some(txn) => txn
    None => abort("transaction not found")
  }
  inspect(txn.postings[1].units is Some(_), content="true")
  match txn.postings[1].units {
    Some(units) => inspect(units.to_string(), content="-10 USD")
    None => abort("missing units")
  }
}

///|
test "infers a posting currency from the rest of the transaction" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"infer currency\"\n" +
    "  Assets:Cash -10.00\n" +
    "  Equity:Opening 10.00 USD\n",
  )
  inspect(v.errors.length(), content="0")
  let txn = match find_transaction(v, "infer currency") {
    Some(txn) => txn
    None => abort("transaction not found")
  }
  match txn.postings[0].units {
    Some(units) => inspect(units.to_string(), content="-10.00 USD")
    None => abort("missing units")
  }
}

///|
test "rejects a transaction whose currencies cannot be inferred" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"no currency\"\n" +
    "  Assets:Cash -10.00\n" +
    "  Equity:Opening 10.00\n",
  )
  inspect(has_error(v, "validation.cost"), content="true")
  inspect(has_error(v, "validation.unbalanced"), content="false")
}

///|
test "rejects more than one missing posting" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"two missing\"\n" +
    "  Assets:Cash\n" +
    "  Equity:Opening\n",
  )
  inspect(has_error(v, "validation.missing"), content="true")
}

///|
test "infers an empty cost from the residual" {
  let v = validated(
    "2024-01-01 open Assets:Stock HOOL\n" +
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 * \"buy\"\n" +
    "  Assets:Stock 10 HOOL {}\n" +
    "  Assets:Cash -1000 USD\n",
  )
  inspect(v.errors.length(), content="0")
  let inventory = v.inventory("Assets:Stock")
  inspect(inventory.positions.length(), content="1")
  match inventory.positions[0].cost {
    Some(cost) => {
      inspect(cost.number.to_string(), content="100")
      inspect(cost.currency, content="USD")
    }
    None => abort("expected an inferred cost")
  }
}

///|
test "books reductions with FIFO during validation" {
  let v = validated(
    "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n" +
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 * \"buy1\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Assets:Cash -1000 USD\n" +
    "2024-01-03 * \"buy2\"\n" +
    "  Assets:Stock 10 HOOL {120 USD}\n" +
    "  Assets:Cash -1200 USD\n" +
    "2024-01-04 * \"sell\"\n" +
    "  Assets:Stock -4 HOOL {}\n" +
    "  Assets:Cash 400 USD\n",
  )
  inspect(v.errors.length(), content="0")
  let inventory = v.inventory("Assets:Stock")
  inspect(inventory.quantity("HOOL").to_string(), content="16")
  inspect(inventory.positions.length(), content="2")
  inspect(inventory.positions[0].units.number.to_string(), content="6")
  inspect(inventory.positions[1].units.number.to_string(), content="10")
}

///|
test "reports ambiguous lot matching under STRICT" {
  let v = validated(
    "2024-01-01 open Assets:Stock HOOL \"STRICT\"\n" +
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 * \"buy1\"\n" +
    "  Assets:Stock 10 HOOL {100 USD}\n" +
    "  Assets:Cash -1000 USD\n" +
    "2024-01-03 * \"buy2\"\n" +
    "  Assets:Stock 10 HOOL {120 USD}\n" +
    "  Assets:Cash -1200 USD\n" +
    "2024-01-04 * \"sell\"\n" +
    "  Assets:Stock -4 HOOL {}\n" +
    "  Assets:Cash 400 USD\n",
  )
  inspect(has_error(v, "validation.booking"), content="true")
  for diagnostic in v.errors {
    if diagnostic.code == "validation.booking" {
      inspect(diagnostic.message.contains("Ambiguous matches"), content="true")
    }
  }
}

///|
test "checks balance assertions including subaccounts" {
  let v = validated(
    "2024-01-01 open Assets:Bank USD\n" +
    "2024-01-01 open Assets:Bank:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"fund\"\n" +
    "  Assets:Bank:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n" +
    "2024-01-03 balance Assets:Bank 10 USD\n" +
    "2024-01-04 balance Assets:Bank 11 USD\n",
  )
  inspect(v.errors.length(), content="1")
  inspect(v.errors[0].code, content="validation.balance")
  inspect(v.errors[0].loc.line, content="8")
}

///|
test "balance assertions see the pre-transaction state on the same day" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 balance Assets:Cash 0 USD\n" +
    "2024-01-02 * \"fund\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n",
  )
  inspect(v.errors.length(), content="0")
}

///|
test "inserts a padding transaction for a balance assertion" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 pad Assets:Cash Equity:Opening\n" +
    "2024-01-03 balance Assets:Cash 100.00 USD\n",
  )
  inspect(v.errors.length(), content="0")
  inspect(
    v.inventory("Assets:Cash").quantity("USD").to_string(),
    content="100.00",
  )
  let mut padding_count = 0
  for entry in v.entries {
    match entry.directive {
      DTransaction(txn) =>
        if txn.flag == "P" {
          padding_count = padding_count + 1
          inspect(txn.narration.contains("Padding inserted"), content="true")
        }
      _ => ()
    }
  }
  inspect(padding_count, content="1")
}

///|
test "reports unused pads when no padding is inserted" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 pad Assets:Cash Equity:Opening\n" +
    "2024-01-03 balance Assets:Cash 0.00 USD\n",
  )
  inspect(has_error(v, "validation.pad"), content="true")
  inspect(v.errors.length(), content="1")
}

///|
test "a booking failure suppresses the balancing error" {
  let v = validated(
    "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n" +
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 * \"buy\"\n" +
    "  Assets:Stock  10 HOOL {10.00 USD}\n" +
    "  Assets:Cash  -100.00 USD\n" +
    "2024-01-03 * \"sell too many\"\n" +
    "  Assets:Stock  -20 HOOL {10.00 USD}\n" +
    "  Assets:Cash  200.00 USD\n",
  )
  inspect(has_error(v, "validation.booking"), content="true")
  inspect(has_error(v, "validation.unbalanced"), content="false")
}

///|
test "detects duplicate balance assertions with different amounts" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"fund\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n" +
    "2024-01-03 balance Assets:Cash 10 USD\n" +
    "2024-01-03 balance Assets:Cash 11 USD\n",
  )
  inspect(has_error(v, "validation.duplicate_balance"), content="true")
}

///|
test "reports duplicate open directives and invalid booking methods" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 open Assets:Cash USD\n" +
    "2024-01-03 open Assets:Stock HOOL \"BADBOOK\"\n",
  )
  inspect(has_error(v, "validation.duplicate_open"), content="true")
  inspect(has_error(v, "validation.booking_method"), content="true")
}

///|
test "applies account currency constraints" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening\n" +
    "2024-01-02 * \"euro\"\n" +
    "  Assets:Cash 10 EUR\n" +
    "  Equity:Opening -10 EUR\n",
  )
  inspect(v.errors.length(), content="1")
  inspect(v.errors[0].code, content="validation.currency")
  inspect(v.errors[0].message.contains("EUR"), content="true")
}

///|
test "warns about unsupported plugins" {
  let v = validated(
    "plugin \"beancount.plugins.unsupported\"\n" +
    "2024-01-01 open Assets:Cash USD\n",
  )
  inspect(v.warnings.length(), content="1")
  inspect(v.warnings[0].code, content="validation.plugin")
  inspect(v.warnings[0].loc.line, content="1")
}

///|
test "finds exact duplicate transactions on request" {
  let ledger = @syntax.parse_source(
    "test.beancount",
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Equity:Opening USD\n" +
    "2024-01-02 * \"dup\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n" +
    "2024-01-02 * \"dup\"\n" +
    "  Assets:Cash 10 USD\n" +
    "  Equity:Opening -10 USD\n",
  )
  let duplicates = @validation.find_duplicate_transactions(ledger.entries)
  inspect(duplicates.length(), content="1")
  inspect(
    has_error(
      validated(
        "2024-01-01 open Assets:Cash USD\n" +
        "2024-01-01 open Equity:Opening USD\n" +
        "2024-01-02 * \"dup\"\n" +
        "  Assets:Cash 10 USD\n" +
        "  Equity:Opening -10 USD\n" +
        "2024-01-02 * \"dup\"\n" +
        "  Assets:Cash 10 USD\n" +
        "  Equity:Opening -10 USD\n",
      ),
      "validation.duplicate",
    ),
    content="false",
  )
}

///|
test "migration document warns that receipt storage is unchecked" {
  let v = validated(
    "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-02 document Assets:Cash \"missing-receipt.pdf\"\n",
  )
  assert_eq(v.errors.length(), 0)
  assert_eq(v.warnings.length(), 1)
  assert_eq(v.warnings[0].code, "validation.document_unchecked")
  assert_eq(v.warnings[0].loc.line, 2)
}

///|
test "native plugins preserve included origins and declaration order" {
  let source = "plugin \"beancount.plugins.implicit_prices\"\n" +
    "plugin \"beancount.plugins.unique_prices\"\n" +
    "plugin \"beancount.plugins.auto_accounts\"\n" +
    "2024-01-02 * \"exchange\"\n" +
    "  Assets:Foreign 2 EUR @ 3 USD\n" +
    "  Assets:Cash -6 USD\n" +
    "2024-01-02 price EUR 4 USD\n"
  let mapping = Array::make(7, @ast.Loc::new("included.bean", 42))
  let v = @validation.validate_ledger(
    @syntax.parse_source("root.bean", source, source_map=mapping),
  )
  assert_eq(v.warnings.length(), 0)
  assert_eq(v.errors.length(), 1)
  assert_eq(v.errors[0].code, "validation.unique_prices")
  assert_eq(v.errors[0].loc.file, "included.bean")
  assert_eq(v.errors[0].loc.line, 42)
  for e in v.entries {
    if e.directive is DPrice(_) || e.directive is DOpen(_) {
      assert_eq(e.loc.file, "included.bean")
      assert_eq(e.loc.line, 42)
    }
  }
  let reversed = source.replace_all(
    old="plugin \"beancount.plugins.implicit_prices\"\nplugin \"beancount.plugins.unique_prices\"",
    new="plugin \"beancount.plugins.unique_prices\"\nplugin \"beancount.plugins.implicit_prices\"",
  )
  assert_eq(validated(reversed).errors.length(), 0)
}

///|
test "commodity and leaf diagnostics and unsupported names remain distinct" {
  let v = validated(
    "plugin \"beancount.plugins.auto_accounts\"\n" +
    "plugin \"beancount.plugins.check_commodity\"\n" +
    "plugin \"beancount.plugins.leafonly\"\n" +
    "plugin \"example.python\"\n" +
    "2024-01-02 * \"hierarchy\"\n" +
    "  Assets:Wallet 3 USD\n" +
    "  Assets:Wallet:Cash -3 USD\n",
  )
  assert_true(has_error(v, "validation.check_commodity"))
  assert_true(has_error(v, "validation.leafonly"))
  assert_eq(v.warnings.length(), 1)
  assert_true(v.warnings[0].message.contains("未实现的插件"))
  assert_true(v.warnings[0].message.contains("example.python"))
  for e in v.errors {
    assert_eq(e.loc.line, 5)
  }
}

///|
test "commodity exemptions use anchored account and currency patterns" {
  let v = validated(
    "plugin \"beancount.plugins.check_commodity\" \"{'Assets:.*': 'US.*'}\"\n" +
    "2024-01-01 commodity EUR\n2024-01-01 open Assets:Cash USD,EUR\n",
  )
  assert_eq(v.errors.length(), 0)
  assert_eq(v.warnings.length(), 0)
  let price = validated(
    "plugin \"beancount.plugins.check_commodity\" \"{'Price Directive Context': '.*'}\"\n2024-01-02 price XYZ 2 USD\n",
  )
  assert_eq(price.errors.length(), 2)
  let bad = validated(
    "plugin \"beancount.plugins.check_commodity\" \"{'Cash': 'USD'}\"\n2024-01-01 open Assets:Cash USD\n",
  )
  assert_true(has_error(bad, "validation.check_commodity"))
}

///|
test "implicit prices distinguish short augmentation from reduction" {
  let v = validated(
    "plugin \"beancount.plugins.implicit_prices\"\n2024-01-01 open Assets:Stock \"NONE\"\n2024-01-01 open Assets:Cash\n2024-01-02 * \"independent short position\"\n  Assets:Stock -2 XYZ {3 USD, 2024-01-02}\n  Assets:Cash 6 USD\n2024-01-03 * \"independent short reduction\"\n  Assets:Stock 1 XYZ {3 USD, 2024-01-02}\n  Assets:Cash -3 USD\n",
  )
  assert_eq(v.errors.length(), 0)
  let prices = v.entries.filter(fn(e) { e.directive is DPrice(_) })
  assert_eq(prices.length(), 1)
  assert_eq(prices[0].loc.line, 4)
}

///|
test "interpolated postings update inventories before padding and balances" {
  let opens = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-01 open Expenses:Food USD\n"
  let spend = "2024-01-15 * \"spend\"\n  Expenses:Food 3.00 USD\n  Assets:Cash\n"
  let plain = validated(
    opens + spend + "2024-01-31 balance Assets:Cash -3.00 USD\n",
  )
  assert_eq(plain.errors.length(), 0)
  assert_eq(plain.inventory("Assets:Cash").quantity("USD").to_string(), "-3.00")
  for prefix in [opens, "plugin \"beancount.plugins.auto_accounts\"\n"] {
    let padded = validated(
      prefix +
      "2024-01-01 pad Assets:Cash Equity:Opening\n" +
      spend +
      "2024-01-31 balance Assets:Cash 100.00 USD\n",
    )
    assert_eq(padded.errors.length(), 0)
    assert_eq(
      padded.inventory("Assets:Cash").quantity("USD").to_string(),
      "100.00",
    )
    assert_eq(
      padded.inventory("Equity:Opening").quantity("USD").to_string(),
      "-103.00",
    )
  }
}

///|
test "configured no-configuration plugins warn by name and do not execute" {
  let body = "2024-01-01 open Assets:Parent\n2024-01-01 open Assets:Parent:Child\n2024-01-01 open Equity:Opening\n2024-01-02 note Assets:Parent \"parent\"\n2024-01-02 price XYZ 1 USD\n2024-01-02 price XYZ 2 USD\n2024-01-03 * \"unopened priced posting\"\n  Assets:Missing 1 XYZ @ 3 USD\n  Equity:Opening -3 USD\n"
  for name in ["auto_accounts", "implicit_prices", "unique_prices", "leafonly"] {
    for config in ["ignored", ""] {
      let full = "beancount.plugins." + name
      let v = validated("plugin \"" + full + "\" \"" + config + "\"\n" + body)
      assert_eq(v.warnings.length(), 1)
      assert_eq(v.warnings[0].code, "validation.plugin")
      assert_true(v.warnings[0].message.contains(full))
      assert_eq(v.warnings[0].loc.line, 1)
      assert_true(has_error(v, "validation.unknown_account"))
      assert_true(!has_error(v, "validation.leafonly"))
      assert_true(!has_error(v, "validation.unique_prices"))
      assert_eq(
        v.entries.filter(fn(e) { e.directive is DPrice(_) }).length(),
        2,
      )
    }
  }
}

///|
test "account exemptions suppress price uses but preserve other account errors" {
  for
    suffix in [
      "2024-01-01 open Assets:Cash USD\n2024-01-02 price USD 7 EUR\n", "2024-01-01 price USD 7 EUR\n2024-01-02 open Assets:Cash USD\n",
    ] {
    let v = validated(
      "plugin \"beancount.plugins.check_commodity\" \"{'Assets:.*': 'USD'}\"\n" +
      suffix,
    )
    assert_eq(v.errors.length(), 1)
    assert_true(v.errors[0].message.contains("'EUR'"))
  }
}

///|
test "leafonly checks account directives and custom account values" {
  let base = "plugin \"beancount.plugins.leafonly\"\n2024-01-01 open Assets:Parent\n2024-01-01 open Assets:Parent:Child\n2024-01-01 open Equity:Opening\n"
  for
    directive in [
      "note Assets:Parent \"memo\"", "document Assets:Parent \"memo.txt\"", "close Assets:Parent",
      "pad Assets:Parent Equity:Opening", "pad Equity:Opening Assets:Parent", "custom \"x\" Assets:Parent",
    ] {
    assert_true(
      has_error(
        validated(base + "2024-01-02 " + directive + "\n"),
        "validation.leafonly",
      ),
    )
  }
  assert_true(
    has_error(
      validated(
        "plugin \"beancount.plugins.leafonly\"\n2024-01-01 open Assets:Parent\n2024-01-02 note Assets:Parent \"memo\"\n2024-01-03 custom \"x\" Assets:Parent:Child\n",
      ),
      "validation.leafonly",
    ),
  )
  assert_true(
    !has_error(
      validated(base + "2024-01-02 balance Assets:Parent 0 USD\n"),
      "validation.leafonly",
    ),
  )
}

///|
test "costed shorts open under every booking method and emit implicit prices" {
  for
    booking_method in [
      "STRICT", "FIFO", "LIFO", "HIFO", "STRICT_WITH_SIZE", "AVERAGE", "NONE",
    ] {
    for
      setting in [
        "option \"booking_method\" \"" +
        booking_method +
        "\"\n2024-01-01 open Assets:Stock HOOL\n",
        "2024-01-01 open Assets:Stock HOOL \"" + booking_method + "\"\n",
      ] {
      let v = validated(
        "plugin \"beancount.plugins.implicit_prices\"\n" +
        setting +
        "2024-01-01 open Assets:Cash USD\n2024-01-02 * \"short\"\n  Assets:Stock -2 HOOL {100 USD}\n  Assets:Cash 200 USD\n",
      )
      assert_eq(v.errors.length(), 0)
      assert_eq(v.inventory("Assets:Stock").quantity("HOOL").to_string(), "-2")
      assert_eq(
        v.entries.filter(fn(e) { e.directive is DPrice(_) }).length(),
        1,
      )
    }
  }
}

///|
test "zero total price on zero units emits zero implicit price" {
  let v = validated(
    "plugin \"beancount.plugins.implicit_prices\"\n2024-01-01 open Assets:Stock\n2024-01-01 open Assets:Cash\n2024-01-02 * \"zero\"\n  Assets:Stock 0 XYZ @@ 0 USD\n  Assets:Cash 0 USD\n",
  )
  assert_eq(v.errors.length(), 0)
  let prices = v.entries.filter(fn(e) { e.directive is DPrice(_) })
  assert_eq(prices.length(), 1)
  match prices[0].directive {
    DPrice(p) => assert_true(p.amount.number.is_zero())
    _ => fail("expected price")
  }
}

///|
test "padding costed inventory reports exact errors only when a difference is needed" {
  let header = "2024-01-01 open Assets:Stock\n2024-01-01 open Assets:Cash\n2024-01-01 open Equity:Opening\n2024-01-01 pad Assets:Stock Equity:Opening\n"
  for
    (units, cash, expected, target) in [
      ("-1", "10", "-1 HOOL {10 USD, 2024-01-15}", "0"),
      ("2", "-20", "2 HOOL {10 USD, 2024-01-15}", "5"),
    ] {
    let v = validated(
      header +
      "2024-01-15 * \"trade\"\n  Assets:Stock " +
      units +
      " HOOL {10 USD}\n  Assets:Cash " +
      cash +
      " USD\n2024-12-31 balance Assets:Stock " +
      target +
      " HOOL\n",
    )
    assert_eq(v.errors.length(), 1)
    assert_eq(v.errors[0].code, "validation.pad")
    assert_eq(
      v.errors[0].message,
      "Attempt to pad an entry with cost for balance: (" + expected + ")",
    )
    assert_eq(v.errors[0].loc.line, 8)
    assert_eq(v.inventory("Assets:Stock").quantity("HOOL").to_string(), target)
  }
  let unused = validated(
    header +
    "2024-01-15 * \"buy\"\n  Assets:Stock 2 HOOL {10 USD}\n  Assets:Cash -20 USD\n2024-12-31 balance Assets:Stock 2 HOOL\n",
  )
  assert_eq(unused.errors.length(), 1)
  assert_eq(unused.errors[0].message, "Unused Pad entry")
  let plain = validated(
    header +
    "2024-01-15 * \"plain\"\n  Assets:Stock 2 USD\n  Assets:Cash -2 USD\n2024-12-31 balance Assets:Stock 5 USD\n",
  )
  assert_eq(plain.errors.length(), 0)
}

///|
test "empty cost short openings infer the residual under every booking method" {
  for
    booking_method in [
      "STRICT", "FIFO", "LIFO", "HIFO", "STRICT_WITH_SIZE", "AVERAGE", "NONE",
    ] {
    for spec in ["{}", "{USD}"] {
      let v = validated(
        "option \"booking_method\" \"" +
        booking_method +
        "\"\n2024-01-01 open Assets:Stock HOOL\n2024-01-01 open Assets:Cash USD\n2024-01-02 * \"sell\"\n  Assets:Stock -2 HOOL " +
        spec +
        "\n  Assets:Cash 200 USD\n",
      )
      assert_eq(v.errors.length(), 0)
      assert_eq(
        v.inventory("Assets:Stock").to_string(),
        "-2 HOOL {100 USD, 2024-01-02}",
      )
    }
  }
}

///|
test "zero automatic residual postings are omitted in either round trip order" {
  for
    legs in [
      "  Assets:Stock 2 HOOL {100 USD}\n  Assets:Stock -2 HOOL {100 USD}\n", "  Assets:Stock -2 HOOL {100 USD}\n  Assets:Stock 2 HOOL {100 USD}\n",
    ] {
    let v = validated(
      "option \"booking_method\" \"FIFO\"\n2024-01-01 open Assets:Stock HOOL\n2024-01-01 open Assets:Cash USD\n2024-01-02 * \"round\"\n" +
      legs +
      "  Assets:Cash\n",
    )
    assert_eq(v.errors.length(), 0)
    assert_eq(find_transaction(v, "round").unwrap().postings.length(), 2)
  }
}

///|
test "same day balances distinguish currencies and Unicode names validate" {
  let ledger = @validation.validate_ledger(
    @syntax.parse_source(
      "balances.bean", "2024-01-01 open Assets:A USD,EUR\n2024-01-01 open Equity:O\n2024-01-02 pad Assets:A Equity:O\n2024-01-03 balance Assets:A 10 USD\n2024-01-03 balance Assets:A 0 EUR\n",
    ),
  )
  assert_false(ledger.has_errors())
  let invalid = @validation.validate_ledger(
    @syntax.parse_source("unicode.bean", "2024-01-01 open Assets:日本\n"),
  )
  assert_true(invalid.has_errors())
  assert_eq(invalid.entries.length(), 1)
}

///|
test "empty transaction and automatic posting have no residual" {
  let ledger = validated(
    "2024-01-01 open Assets:A USD\n2024-01-02 *\n2024-01-03 * \"empty\"\n  Assets:A\n",
  )
  assert_eq(ledger.errors.length(), 0)
  assert_eq(ledger.entries.length(), 3)
  guard ledger.entries[2].directive is @ast.DTransaction(txn) else {
    abort("txn")
  }
  assert_eq(txn.postings.length(), 0)
}

///|
test "bare quantity currency follows a stock transaction weight" {
  let v = validated(
    "2024-01-01 open Assets:Stock HOOL \"FIFO\"\n2024-01-01 open Assets:Cash USD\n2024-01-01 open Income:Gains USD\n\n2024-01-02 * \"Buy shares\"\n  Assets:Stock    10 HOOL {100.00 USD}\n  Assets:Cash  -1000.00 USD\n\n2024-01-03 * \"Sell with a total price\"\n  Assets:Stock    -5 HOOL {100.00 USD} @@ 600.00 USD\n  Assets:Cash    600.00 USD\n  Income:Gains  -100.",
  )
  inspect(v.errors.length(), content="0")
  inspect(v.entries.length(), content="5")
  let txn = find_transaction(v, "Sell with a total price").unwrap()
  inspect(txn.postings[2].units.unwrap().to_string(), content="-100 USD")
}

///|
test "deprecated tolerance diagnostics retain each physical include location" {
  let locs = [
    @ast.Loc::new("section-a.bean", 14),
    @ast.Loc::new("section-b.bean", 71),
  ]
  let source = "option \"inferred_tolerance_multiplier\" \"0.2\"\noption \"inferred_tolerance_multiplier\" \"0.3\"\n"
  let ledger = @validation.validate_ledger(
    @syntax.parse_source("combined.bean", source, source_map=locs),
  )
  assert_eq(ledger.warnings.length(), 2)
  assert_eq(ledger.errors.length(), 0)
  for i in 0..<2 {
    assert_eq(ledger.warnings[i].code, "validation.deprecated_option")
    assert_eq(ledger.warnings[i].loc.to_string(), locs[i].to_string())
  }
}

///|
test "a public ledger without physical option locations still reports the deprecated alias" {
  let ledger = @ast.Ledger::new()
  ledger.options.add_raw("inferred_tolerance_multiplier", "0.25")
  let checked = @validation.validate_ledger(ledger)
  assert_eq(checked.warnings.length(), 1)
  assert_eq(checked.warnings[0].code, "validation.deprecated_option")
  assert_eq(checked.warnings[0].loc.to_string(), "<ledger>:0")
}

///|
test "FIFO short covering keeps acquisition dates and balances the remaining lot" {
  let source =
    #|2024-01-01 open Assets:Stock HOOL "FIFO"
    #|2024-01-01 open Assets:Cash USD
    #|2024-01-02 * "Sell short at 12"
    #|  Assets:Stock -2 HOOL {12 USD}
    #|  Assets:Cash 24 USD
    #|2024-01-03 * "Sell short at 15"
    #|  Assets:Stock -3 HOOL {15 USD}
    #|  Assets:Cash 45 USD
    #|2024-01-04 * "Cover"
    #|  Assets:Stock 3 HOOL {}
    #|  Assets:Cash -39 USD
    #|
  let result = validated(source)
  assert_eq(result.errors.length(), 0)
  let covering = find_transaction(result, "Cover").unwrap()
  assert_eq(covering.postings.map(fn(p) { p.units.unwrap().to_string() }),
    ["2 HOOL", "1 HOOL", "-39 USD"])
  assert_eq(covering.postings[:2].to_array().map(fn(p) {
    let c = p.cost.unwrap()
    (c.number_per.unwrap().to_string(), c.date.unwrap().to_string())
  }), [("12", "2024-01-02"), ("15", "2024-01-03")])
  let remaining = result.inventory("Assets:Stock").positions
  assert_eq(remaining.length(), 1)
  assert_eq(remaining[0].units.to_string(), "-2 HOOL")
  assert_eq(remaining[0].cost.unwrap().number.to_string(), "15")
}

///|
test "only the newest pad applies independently to each currency's first assertion" {
  let prefix = "2024-01-01 open Assets:Cash\n2024-01-01 open Equity:Opening\n"
  let ledger = validated(prefix +
    #|2024-01-02 pad Assets:Cash Equity:Opening
    #|2024-01-03 balance Assets:Cash 30.00 USD
    #|2024-01-03 balance Assets:Cash 20.00 EUR
    #|2024-01-04 balance Assets:Cash 0 CAD
    #|2024-01-05 balance Assets:Cash 1 CAD
    #|
  )
  assert_eq(ledger.errors.map(fn(d) { (d.code, d.loc.line) }), [("validation.balance",7)])
  let cash = ledger.inventory("Assets:Cash")
  assert_eq(cash.quantity("USD").to_string(), "30.00")
  assert_eq(cash.quantity("EUR").to_string(), "20.00")
  assert_true(cash.quantity("CAD").is_zero())
  let superseded = validated(prefix +
    #|2024-01-02 pad Assets:Cash Equity:Opening
    #|2024-01-03 pad Assets:Cash Equity:Opening
    #|2024-01-04 balance Assets:Cash 30.00 USD
    #|2024-01-05 balance Assets:Cash 31.00 USD
    #|
  )
  assert_true(superseded.errors.any(fn(d) { d.loc.line == 3 && d.code == "validation.pad" }))
  assert_true(superseded.errors.any(fn(d) { d.loc.line == 6 && d.code == "validation.balance" }))
  assert_eq(superseded.inventory("Assets:Cash").quantity("USD").to_string(), "30.00")
}

///|
test "strict booking allows full liquidation across otherwise ambiguous lots" {
  for method in ["STRICT", "STRICT_WITH_SIZE"] {
    let header =
      "2024-01-01 open Assets:Stock HOOL \"\{method}\"\n" +
      #|2024-01-01 open Assets:Cash USD
      #|2024-01-02 * "Buy 2"
      #|  Assets:Stock 2 HOOL {12 USD}
      #|  Assets:Cash -24 USD
      #|2024-01-03 * "Buy 3"
      #|  Assets:Stock 3 HOOL {15 USD}
      #|  Assets:Cash -45 USD
      #|
    let liquidation = validated(header +
      #|2024-01-04 * "Sell both"
      #|  Assets:Stock -5 HOOL {}
      #|  Assets:Cash
      #|
    )
    assert_eq(liquidation.errors.length(), 0)
    assert_eq(find_transaction(liquidation, "Sell both").unwrap().postings.map(fn(p) {
      p.units.unwrap().to_string()
    }), ["-2 HOOL", "-3 HOOL", "69 USD"])
    assert_true(liquidation.inventory("Assets:Stock").is_empty())
    let partial = validated(header +
      #|2024-01-04 * "Ambiguous partial"
      #|  Assets:Stock -4 HOOL {}
      #|  Assets:Cash
      #|
    )
    assert_true(has_error(partial, "validation.booking"))
  }
}

///|
test "one explicitly typed automatic posting per currency balances mixed opening balances" {
  let source =
    #|2024-01-01 open Assets:Cash
    #|2024-01-01 open Equity:Opening
    #|2024-01-01 open Equity:Euro
    #|2024-01-02 * "opening"
    #|  Assets:Cash 10 USD
    #|  Assets:Cash 5 EUR
    #|  Equity:Opening USD
    #|  Equity:Euro EUR
    #|
  let checked = validated(source)
  assert_eq(checked.errors.length(), 0)
  let txn = find_transaction(checked, "opening").unwrap()
  assert_eq(txn.postings.map(fn(p) {(p.account,p.units.unwrap().to_string())}),
    [("Assets:Cash","10 USD"),("Equity:Opening","-10 USD"),
     ("Assets:Cash","5 EUR"),("Equity:Euro","-5 EUR")])
  assert_eq(checked.inventory("Equity:Euro").quantity("EUR").to_string(), "-5")
  let malformed = validated(source.replace_all(old="Equity:Euro EUR",new="Equity:Euro USD"))
  assert_true(has_error(malformed, "validation.missing"))
}

///|
test "an untyped balancing line expands to each nonzero currency group" {
  let result = validated(
    #|2024-01-01 open Assets:Bank
    #|2024-01-01 open Equity:Opening
    #|2024-01-02 * "Import multicurrency opening"
    #|  Assets:Bank 7 EUR
    #|  Assets:Bank 0 JPY
    #|  Assets:Bank 10 USD
    #|  Equity:Opening
    #|
  )
  assert_eq(result.errors.length(), 0)
  let opening = find_transaction(result, "Import multicurrency opening").unwrap()
  assert_eq(opening.postings.map(fn(p) { p.units.unwrap().to_string() }),
    ["7 EUR", "-7 EUR", "0 JPY", "10 USD", "-10 USD"])
  assert_eq(result.inventory("Equity:Opening").quantity("EUR").to_string(), "-7")
  assert_eq(result.inventory("Equity:Opening").quantity("USD").to_string(), "-10")
  assert_true(opening.postings[1].meta.get("__automatic__") is Some(@ast.MBool(true)))
}

///|
test "negative basis and zero costed quantity are reported without changing the source transaction" {
  let result = validated(
    #|2024-01-01 open Assets:Inventory
    #|2024-01-01 open Assets:Bank
    #|2024-01-02 * "negative basis"
    #|  Assets:Inventory 2 HOOL {-3 USD}
    #|  Assets:Bank 6 USD
    #|2024-01-03 * "zero quantity"
    #|  Assets:Inventory 0 ABC {1 USD}
    #|  Assets:Bank 0 USD
    #|2024-01-04 * "free security"
    #|  Assets:Inventory 1 ZZZ {0 USD}
    #|  Assets:Bank 0 USD
    #|
  )
  assert_eq(result.errors.map(fn(err) {(err.loc.line,err.code)}),
    [(3,"validation.negative_cost"),(6,"validation.zero_cost_units")])
  assert_eq(find_transaction(result,"negative basis").unwrap().postings[0]
    .cost.unwrap().number_per.unwrap().to_string(), "-3")
  assert_eq(find_transaction(result,"zero quantity").unwrap().postings[0]
    .units.unwrap().to_string(), "0 ABC")
}

///|
test "explicit balance tolerance is signed and is not an absolute allowance" {
  let result = validated(
    #|2024-01-01 open Assets:Cash
    #|2024-01-02 balance Assets:Cash 0 ~ -0.50 USD
    #|2024-01-03 balance Assets:Cash 0 ~ +0.50 USD
    #|
  )
  assert_eq(result.errors.map(fn(e) { (e.loc.line,e.code) }), [(2,"validation.balance")])
  assert_true(result.errors[0].message.contains("0 too little"))
}

///|
test "compound lot costs retain both terms and match the calculated acquisition basis" {
  let hdr =
    #|2024-01-01 open Assets:Stock HOOL "FIFO"
    #|2024-01-01 open Assets:Cash
    #|2024-01-02 * "Buy with a transaction fee"
    #|  Assets:Stock 4 HOOL {12 # 8 USD}
    #|  Assets:Cash -56 USD
    #|
  let before = @syntax.parse_source("compound.bean", hdr)
  assert_eq(before.errors.length(), 0)
  guard before.entries[2].directive is @ast.DTransaction(bought) else {
    abort("missing buy")
  }
  let spec = bought.postings[0].cost.unwrap()
  assert_eq(spec.to_string(), "{12 # 8 USD}")
  let v = validated(hdr +
    #|2024-01-03 * "Sell match"
    #|  Assets:Stock -2 HOOL {12 # 4 USD}
    #|  Assets:Cash 28 USD
    #|
  )
  assert_eq(v.errors.length(), 0)
  let sold = find_transaction(v,"Sell match").unwrap().postings[0]
  assert_eq(sold.cost.unwrap().number_per.unwrap().to_string(), "14")
  assert_eq(sold.cost.unwrap().date.unwrap().to_string(), "2024-01-02")
  let missing_per = validated(hdr.replace_all(old="{12 # 8 USD}",new="{# 56 USD}"))
  assert_eq(missing_per.errors.length(), 0)
  let no_match = validated(hdr +
    #|2024-01-03 * "Wrong lot"
    #|  Assets:Stock -2 HOOL {12 # 3 USD}
    #|  Assets:Cash 28 USD
    #|
  )
  assert_true(has_error(no_match,"validation.booking"))
}
