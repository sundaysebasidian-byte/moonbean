///|
fn set_tolerance(
  values : Array[(String, @decimal.Decimal)],
  currency : String,
  value : @decimal.Decimal,
  add : Bool,
) -> Unit {
  for i in 0..<values.length() {
    if values[i].0 == currency {
      let old = values[i].1
      values[i] = (
        currency,
        if add {
          old.add(value)
        } else if old.less_than(value) {
          value
        } else {
          old
        },
      )
      return
    }
  }
  values.push((currency, value))
}

///|
/// Captures inferred transaction tolerances before automatic amounts are filled.
/// Currency defaults precede inferred keys; wildcard defaults are lookup-only.
fn infer_transaction_tolerances(
  ctx : Context,
  postings : Array[@ast.Posting],
) -> Array[(String, @decimal.Decimal)] {
  let options = ctx.options
  let values : Array[(String, @decimal.Decimal)] = []
  if options.inferred_tolerance_default.length() > 0 {
    for (name, raw) in options.raw {
      if name == "inferred_tolerance_default" {
        let parts = raw.split(":").to_array()
        if parts.length() == 2 {
          let currency = String::from_iter(parts[0].iter())
          if currency != "*" &&
            options.inferred_tolerance_default.get(currency) is Some(n) {
            set_tolerance(values, currency, n, false)
          }
        }
      }
    }
    for (currency, n) in options.inferred_tolerance_default {
      if currency != "*" {
        set_tolerance(values, currency, n, false)
      }
    }
  }
  let costs : Array[(String, @decimal.Decimal)]? = if options.infer_tolerance_from_cost {
    Some([])
  } else {
    None
  }
  for p in postings {
    if p.units is Some(units) && units.number.has_fractional_digits() {
      let scale = units.number.scale()
      let tolerance = match ctx.tolerance_cache.get(scale) {
        Some(n) => n
        None => {
          let n = units.number
            .last_digit_place()
            .mul(options.tolerance_multiplier)
          ctx.tolerance_cache.set(scale, n)
          n
        }
      }
      set_tolerance(values, units.currency, tolerance, false)
      if costs is Some(costs) {
        if p.cost is Some(cost) &&
          cost.number_per is Some(n) &&
          cost.currency is Some(currency) {
          set_tolerance(costs, currency, cost_tolerance(tolerance.mul(n)), true)
        }
        let price = match p.price {
          Some(PerUnit(a)) => Some(a)
          Some(Total(a)) =>
            match a.number.div(units.number.abs()) {
              Some(n) => Some(@ast.Amount::new(n, a.currency))
              None => None
            }
          None => None
        }
        if price is Some(a) {
          set_tolerance(
            costs,
            a.currency,
            cost_tolerance(tolerance.mul(a.number.abs())),
            true,
          )
        }
      }
    }
  }
  if costs is Some(costs) {
    for (currency, n) in costs {
      set_tolerance(values, currency, n, false)
    }
  }
  values
}

///|
fn cost_tolerance(value : @decimal.Decimal) -> @decimal.Decimal {
  let cap = @decimal.Decimal::parse("0.5").unwrap()
  if value.less_than(cap) {
    value
  } else if value.equal(cap) {
    value
  } else {
    cap
  }
}
