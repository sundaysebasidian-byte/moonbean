///|
fn python_decimal(number : @decimal.Decimal) -> String {
  let negative = number.is_negative()
  let digits = (if negative {
    number.mantissa().neg()
  } else {
    number.mantissa()
  }).to_string()
  let adjusted = digits.length() - 1 - number.scale()
  if number.scale() >= 0 && adjusted >= -6 {
    return number.to_string()
  }
  let out = StringBuilder()
  if negative {
    out.write_char('-')
  }
  out.write_char(digits.get_char(0).unwrap())
  if digits.length() > 1 {
    out.write_char('.')
    out.write_string(digits[1:].to_owned())
  }
  out.write_char('E')
  if adjusted >= 0 {
    out.write_char('+')
  }
  out.write_string(adjusted.to_string())
  out.to_string()
}

///|
fn python_amount(amount : @ast.Amount) -> String {
  amount.number.to_string() + " " + amount.currency
}

///|
fn python_position(position : @booking.Position) -> String {
  python_amount(position.units) +
  (match position.cost {
    None => ""
    Some(cost) =>
      " {" +
      cost.number.to_string() +
      " " +
      cost.currency +
      cost.date.map(fn(d) { ", " + d.to_string() }).unwrap_or("") +
      cost.label.map(fn(s) { ", \"" + s + "\"" }).unwrap_or("") +
      "}"
  })
}
