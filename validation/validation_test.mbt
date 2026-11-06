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
