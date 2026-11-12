///|
fn price_key(base : String, quote : String) -> String {
  base + "\u{1f}" + quote
}

///|
fn ensure_query_prices(ctx : QueryContext) -> Unit {
  if ctx.prices is Some(_) {
    return
  }
  let raw : Map[String, Array[(@ast.Date, @decimal.Decimal)]] = Map([])
  let pairs : Array[(String, String)] = []
  for entry in ctx.realized.entries {
    if entry.directive is DPrice(p) {
      let key = price_key(p.currency, p.amount.currency)
      if !raw.contains(key) {
        raw.set(key, [])
        pairs.push((p.currency, p.amount.currency))
      }
      raw.get(key).unwrap().push((entry.date, p.amount.number))
    }
  }
  let result : Map[String, Array[(@ast.Date, @decimal.Decimal)]] = Map([])
  for (a, b) in pairs {
    if result.contains(price_key(a, b)) {
      continue
    }
    let forward = raw.get(price_key(a, b)).unwrap_or([])
    let reverse = raw.get(price_key(b, a)).unwrap_or([])
    let (base, quote, direct, inverse) = if forward.length() >= reverse.length() {
      (a, b, forward, reverse)
    } else {
      (b, a, reverse, forward)
    }
    let rates = direct.copy()
    for (date, number) in inverse {
      if @decimal.Decimal::one().div(number) is Some(n) {
        rates.push((date, n))
      }
    }
    // Stable order retains the last quote on a repeated date.
    rates.sort_by(fn(a, b) { a.0.to_string().compare(b.0.to_string()) })
    let inverted : Array[(@ast.Date, @decimal.Decimal)] = []
    for (date, number) in rates {
      if @decimal.Decimal::one().div(number) is Some(n) {
        inverted.push((date, n))
      }
    }
    result.set(price_key(base, quote), rates)
    result.set(price_key(quote, base), inverted)
  }
  ctx.prices = Some(result)
}

///|
fn query_price(
  ctx : QueryContext,
  base : String,
  quote : String,
  date : @ast.Date?,
) -> @decimal.Decimal? {
  if base == quote {
    return Some(@decimal.Decimal::one())
  }
  ensure_query_prices(ctx)
  let rates = ctx.prices.unwrap().get(price_key(base, quote)).unwrap_or([])
  let mut found = None
  for (at, number) in rates {
    if date is Some(end) && end.less_than(at) {
      break
    }
    found = Some(number)
  }
  found
}

///|
fn convert_query_amount(
  ctx : QueryContext,
  amount : @ast.Amount,
  target : String,
  date : @ast.Date?,
  via : String?,
) -> @ast.Amount {
  if amount.currency == target {
    return amount
  }
  let mut rate = query_price(ctx, amount.currency, target, date)
  if rate is None && via is Some(currency) {
    if query_price(ctx, amount.currency, currency, date) is Some(a) &&
      query_price(ctx, currency, target, date) is Some(b) {
      rate = Some(a.mul(b).round_to_significant(28))
    }
  }
  match rate {
    Some(n) =>
      @ast.Amount::new(amount.number.mul(n).round_to_significant(28), target)
    None => amount
  }
}

///|
fn query_conversion(
  ctx : QueryContext,
  value : QueryValue,
  target : String?,
  date : @ast.Date?,
) -> QueryValue {
  let convert_position = fn(p : @booking.Position) {
    let currency = match target {
      Some(s) => Some(s)
      None => p.cost.map(fn(c) { c.currency })
    }
    match currency {
      Some(s) =>
        convert_query_amount(
          ctx,
          p.units,
          s,
          date,
          p.cost.map(fn(c) { c.currency }),
        )
      None => p.units
    }
  }
  match value {
    QAmount(a) =>
      QAmount(convert_query_amount(ctx, a, target.unwrap(), date, None))
    QPosition(p) => QAmount(convert_position(p))
    QInventory(inv) => {
      let result = @booking.Inventory::new()
      for p in inv.positions {
        result.add(@booking.Position::new(convert_position(p), None))
      }
      QInventory(result)
    }
    _ => QNull
  }
}
