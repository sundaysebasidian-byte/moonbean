///|
fn dec(text : String) -> @decimal.Decimal {
  match @decimal.Decimal::parse(text) {
    Some(value) => value
    None => abort("invalid decimal in test: " + text)
  }
}

///|
test "decimal parse preserves scale" {
  inspect(dec("10.00").to_string(), content="10.00")
  inspect(dec("10").to_string(), content="10")
  inspect(dec("0.000").to_string(), content="0.000")
  inspect(dec("-12.5").to_string(), content="-12.5")
  inspect(dec("1,234,567.89").to_string(), content="1234567.89")
  inspect(dec(".5").to_string(), content="0.5")
  inspect(dec("5.").to_string(), content="5")
  inspect(@decimal.Decimal::parse("1e3") is None, content="true")
  inspect(@decimal.Decimal::parse("--1") is None, content="true")
  inspect(@decimal.Decimal::parse("1.2.3") is None, content="true")
}

///|
test "decimal addition keeps coarsest scale" {
  inspect(dec("1.0").add(dec("2.00")).to_string(), content="3.00")
  inspect(dec("0.1").add(dec("0.2")).to_string(), content="0.3")
  inspect(dec("5.5").sub(dec("2.25")).to_string(), content="3.25")
}

///|
test "decimal multiplication" {
  inspect(dec("1.0").mul(dec("2.00")).to_string(), content="2.000")
  inspect(dec("10.22626").mul(dec("37.61")).to_string(), content="384.6096386")
  inspect(
    dec("999999999999999").mul(dec("999999999999999")).to_string(),
    content="999999999999998000000000000000",
  )
}

///|
test "decimal division matches python decimal" {
  inspect(dec("10.00").div(dec("4")).unwrap().to_string(), content="2.50")
  inspect(dec("1.00").div(dec("4")).unwrap().to_string(), content="0.25")
  inspect(dec("1").div(dec("8")).unwrap().to_string(), content="0.125")
  inspect(dec("2").div(dec("4")).unwrap().to_string(), content="0.5")
  inspect(dec("100").div(dec("8")).unwrap().to_string(), content="12.5")
  inspect(dec("1.234").div(dec("1.0")).unwrap().to_string(), content="1.234")
  inspect(
    dec("1").div(dec("3")).unwrap().to_string(),
    content="0.3333333333333333333333333333",
  )
  inspect(
    dec("10.00").div(dec("3")).unwrap().to_string(),
    content="3.333333333333333333333333333",
  )
  inspect(dec("1").div(dec("0")) is None, content="true")
}

///|
test "decimal quantize is half even" {
  inspect(dec("2.5").quantize(2).to_string(), content="2.50")
  inspect(dec("2.345").quantize(2).to_string(), content="2.34")
  inspect(dec("2.355").quantize(2).to_string(), content="2.36")
  inspect(dec("2.365").quantize(2).to_string(), content="2.36")
  inspect(dec("1.005").quantize(2).to_string(), content="1.00")
  inspect(dec("1.015").quantize(2).to_string(), content="1.02")
}

///|
test "decimal comparison is numeric" {
  inspect(dec("1.0").compare(dec("1.00")), content="0")
  inspect(dec("1.01").compare(dec("1.0")), content="1")
  inspect(dec("-2").compare(dec("-1.5")), content="-1")
  inspect(dec("1.0").equal(dec("1.00")), content="true")
}

///|
test "decimal least significant place" {
  inspect(dec("10.00").last_digit_place().to_string(), content="0.01")
  inspect(dec("10").last_digit_place().to_string(), content="1")
  inspect(dec("0.005").last_digit_place().to_string(), content="0.001")
  inspect(dec("10.00").has_fractional_digits(), content="true")
  inspect(dec("10").has_fractional_digits(), content="false")
}

///|
test "decimal display trims zeros" {
  inspect(dec("10.00").to_display(), content="10")
  inspect(dec("10.00").to_display(min_scale=1), content="10.0")
  inspect(dec("0.500").to_display(), content="0.5")
  inspect(dec("100").to_display(), content="100")
  inspect(dec("0.000").to_display(), content="0")
}

///|
test "decimal negative zero and signs" {
  inspect(dec("-0.00").to_string(), content="0.00")
  inspect(dec("-0.00").signum(), content="0")
  inspect(dec("-1.5").abs().to_string(), content="1.5")
  inspect(dec("1.5").neg().to_string(), content="-1.5")
}

///|
test "single-buffer decimal parser preserves scale and signs" {
  for text in [".50", "-.50", "+1,234.500", "0.", "000.0010"] {
    let value = @decimal.Decimal::parse(text).unwrap()
    inspect(
      @decimal.Decimal::parse(value.to_string()).unwrap().equal(value),
      content="true",
    )
  }
  inspect(@decimal.Decimal::parse("1.2300").unwrap().scale(), content="4")
  inspect(@decimal.Decimal::parse("1,,2") is None, content="true")
}
