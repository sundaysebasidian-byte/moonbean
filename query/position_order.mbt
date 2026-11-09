///|
fn position_sort_compare(a : @booking.Position, b : @booking.Position) -> Int32 {
  let rank = fn(currency : String) {
    match currency {
      "USD" => 0
      "EUR" => 1
      "JPY" => 2
      "CAD" => 3
      "GBP" => 4
      "AUD" => 5
      "NZD" => 6
      "CHF" => 7
      _ => 8 + currency.iter().count()
    }
  }
  let currency = rank(a.units.currency).compare(rank(b.units.currency))
  if currency != 0 {
    return currency
  }
  let zero = @decimal.Decimal::zero()
  let number = a.cost
    .map(fn(c) { c.number })
    .unwrap_or(zero)
    .compare(b.cost.map(fn(c) { c.number }).unwrap_or(zero))
  if number != 0 {
    return number
  }
  let currency = a.cost
    .map(fn(c) { c.currency })
    .unwrap_or("")
    .lexical_compare(b.cost.map(fn(c) { c.currency }).unwrap_or(""))
  if currency != 0 {
    return currency
  }
  a.units.number.compare(b.units.number)
}

///|
fn inventory_repr(inv : @booking.Inventory) -> String {
  let indexed : Array[(Int32, @booking.Position)] = []
  for i in 0..<inv.positions.length() {
    indexed.push((i, inv.positions[i]))
  }
  indexed.sort_by(fn(a, b) {
    let order = position_sort_compare(a.1, b.1)
    if order == 0 {
      a.0.compare(b.0)
    } else {
      order
    }
  })
  "(" + indexed.map(fn(p) { python_position(p.1) }).join(", ") + ")"
}

///|
fn portable_repr(value : QueryValue) -> Bool {
  match value {
    QSet(v) | QFrozenSet(v) => v.length() < 2
    QDict(v) | QRecord(_, v) => v.all(fn(p) { portable_repr(p.1) })
    QList(v) => v.all(portable_repr)
    _ => true
  }
}
