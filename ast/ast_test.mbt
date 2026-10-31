///|
fn date(text : String) -> @ast.Date {
  match @ast.Date::parse(text) {
    Some(value) => value
    None => abort("invalid date in test: " + text)
  }
}

///|
test "date parsing and formatting" {
  inspect(date("2024-02-29").to_string(), content="2024-02-29")
  inspect(date("0099-01-05").to_string(), content="0099-01-05")
  inspect(@ast.Date::parse("2023-02-29") is None, content="true")
  inspect(@ast.Date::parse("2024-13-01") is None, content="true")
  inspect(@ast.Date::parse("2024-1-01") is None, content="true")
  inspect(@ast.Date::parse("garbage") is None, content="true")
}

///|
test "date comparison and ordinal" {
  inspect(
    @ast.Date::compare(date("2024-01-31"), date("2024-02-01")),
    content="-1",
  )
  inspect(date("2024-02-01").equal(date("2024-02-01")), content="true")
  inspect(date("2023-03-01").day_of_year(), content="60")
  inspect(date("2024-03-01").day_of_year(), content="61")
  inspect(date("2024-12-31").day_of_year(), content="366")
}

///|
test "metadata preserves insertion order and deduplicates" {
  let meta = @ast.Meta::new()
  meta.set("date", @ast.MDate(date("2024-01-01")))
  meta.set("name", @ast.MString("coffee"))
  meta.set("date", @ast.MDate(date("2024-01-02")))
  inspect(meta.entries.length(), content="2")
  inspect(meta.get("name") is Some(_), content="true")
  inspect(meta.has("missing"), content="false")
  meta.remove("name")
  inspect(meta.entries.length(), content="1")
  inspect(meta.has("name"), content="false")
}

///|
test "amount and meta value rendering" {
  let amount = @ast.Amount::new(
    @decimal.Decimal::parse("12.50").unwrap(),
    "CNY",
  )
  inspect(amount.to_string(), content="12.50 CNY")
  inspect(@ast.MetaValue::MString("a\"b").to_string(), content="\"a\\\"b\"")
  inspect(@ast.MetaValue::MBool(true).to_string(), content="TRUE")
  inspect(@ast.MetaValue::MTag("trip").to_string(), content="#trip")
}

///|
test "cost spec rendering" {
  let spec = @ast.CostSpec::new_per(
    @decimal.Decimal::parse("10.5").unwrap(),
    "USD",
    Some(date("2024-01-02")),
    Some("lot"),
  )
  inspect(spec.to_string(), content="{10.5 USD, 2024-01-02, \"lot\"}")
  let total = @ast.CostSpec::new_total(
    @decimal.Decimal::parse("105").unwrap(),
    "USD",
  )
  inspect(total.to_string(), content="{{105 USD}}")
  inspect(@ast.CostSpec::empty().to_string(), content="{}")
  inspect(@ast.CostSpec::empty().is_empty_spec(), content="true")
}

///|
test "account name helpers" {
  inspect(@ast.account_parts("Assets:Bank:Checking").length(), content="3")
  inspect(@ast.account_root("Assets:Bank:Checking"), content="Assets")
  inspect(@ast.account_leaf("Assets:Bank:Checking"), content="Checking")
  inspect(@ast.account_parent("Assets:Bank:Checking"), content="Assets:Bank")
  inspect(@ast.account_parent("Assets"), content="")
  inspect(@ast.account_root(""), content="")
}
