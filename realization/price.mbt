// Price database.  Prices come from `price` directives and from implicit
// prices on postings (cost basis and `@` annotations).  Conversion uses the
// most recent price at or before the requested date, and falls back to the
// inverse quote when only the opposite direction is available.

///|
pub(all) struct PricePoint {
  date : @ast.Date
  base : String
  quote : String
  rate : @decimal.Decimal
}

///|
pub(all) struct PriceDb {
  points : Array[PricePoint]
}

///|
pub fn PriceDb::new() -> PriceDb {
  { points: [], }
}

///|
pub fn PriceDb::add(
  self : PriceDb,
  date : @ast.Date,
  base : String,
  quote : String,
  rate : @decimal.Decimal,
) -> Unit {
  if base == quote || rate.is_zero() {
    return
  }
  self.points.push({ date, base, quote, rate, })
}

///|
fn add_posting_price(
  db : PriceDb,
  date : @ast.Date,
  posting : @ast.Posting,
) -> Unit {
  let units = match posting.units {
    Some(units) => units
    None => return
  }
  match posting.price {
    Some(price) =>
      match price {
        PerUnit(amount) =>
          db.add(date, units.currency, amount.currency, amount.number)
        Total(amount) =>
          if !units.number.is_zero() {
            match amount.number.abs().div(units.number.abs()) {
              Some(rate) => db.add(date, units.currency, amount.currency, rate)
              None => ()
            }
          }
      }
    None => ()
  }
  match posting.cost {
    Some(spec) =>
      match spec.currency {
        Some(currency) =>
          match spec.number_per {
            Some(number) => db.add(date, units.currency, currency, number)
            None =>
              match spec.number_total {
                Some(total) =>
                  if !units.number.is_zero() {
                    match total.abs().div(units.number.abs()) {
                      Some(rate) => db.add(date, units.currency, currency, rate)
                      None => ()
                    }
                  }
                None => ()
              }
          }
        None => ()
      }
    None => ()
  }
}

///|
pub fn PriceDb::from_entries(entries : Array[@ast.Entry]) -> PriceDb {
  let db = PriceDb::new()
  for entry in entries {
    match entry.directive {
      DPrice(price) =>
        db.add(
          entry.date,
          price.currency,
          price.amount.currency,
          price.amount.number,
        )
      DTransaction(txn) =>
        for posting in txn.postings {
          add_posting_price(db, entry.date, posting)
        }
      _ => ()
    }
  }
  db
}

///|
fn date_allows(entry_date : @ast.Date, at : @ast.Date?) -> Bool {
  match at {
    Some(date) => entry_date.less_equal(date)
    None => true
  }
}

///|
pub fn PriceDb::latest(
  self : PriceDb,
  base : String,
  quote : String,
  at : @ast.Date?,
) -> @decimal.Decimal? {
  let mut result : @decimal.Decimal? = None
  let mut found : @ast.Date? = None
  for point in self.points {
    if point.base == base && point.quote == quote && date_allows(point.date, at) {
      let is_newer = match found {
        Some(found_date) => !point.date.less_than(found_date)
        None => true
      }
      if is_newer {
        result = Some(point.rate)
        found = Some(point.date)
      }
    }
  }
  result
}

///|
fn PriceDb::edge(
  self : PriceDb,
  base : String,
  quote : String,
  at : @ast.Date?,
) -> @decimal.Decimal? {
  let mut latest : PricePoint? = None
  for point in self.points {
    if (
        (point.base == base && point.quote == quote) ||
        (point.base == quote && point.quote == base)
      ) &&
      date_allows(point.date, at) &&
      point.rate.is_positive() {
      let newer = match latest {
        None => true
        Some(old) =>
          old.date.less_than(point.date) ||
          (
            old.date.equal(point.date) &&
            (point.base == base || old.base != base)
          )
      }
      if newer {
        latest = Some(point)
      }
    }
  }
  match latest {
    Some(point) =>
      if point.base == base {
        Some(point.rate)
      } else {
        @decimal.Decimal::one().div(point.rate)
      }
    None => None
  }
}

///|
/// Finds the shortest dated quote path. Equal-length paths use lexical currency order.
/// Each currency is visited once, so cycles cannot cause nontermination.
pub fn PriceDb::rate(
  self : PriceDb,
  base : String,
  quote : String,
  at : @ast.Date?,
) -> @decimal.Decimal? {
  if base == quote {
    return Some(@decimal.Decimal::one())
  }
  let currencies : Array[String] = []
  for point in self.points {
    if date_allows(point.date, at) {
      if !currencies.contains(point.base) {
        currencies.push(point.base)
      }
      if !currencies.contains(point.quote) {
        currencies.push(point.quote)
      }
    }
  }
  currencies.sort()
  let queue = [(base, @decimal.Decimal::one())]
  let seen : Map[String, Bool] = Map([])
  seen.set(base, true)
  let mut index = 0
  while index < queue.length() {
    let (currency, accumulated) = queue[index]
    index += 1
    for next in currencies {
      if seen.get(next) is None {
        if self.edge(currency, next, at) is Some(rate) {
          let combined = accumulated.mul(rate)
          if next == quote {
            return Some(combined)
          }
          seen.set(next, true)
          queue.push((next, combined))
        }
      }
    }
  }
  None
}

///|
/// Converts one amount into a target currency, returning `None` when no price
/// path is known.
pub fn PriceDb::convert(
  self : PriceDb,
  amount : @ast.Amount,
  target : String,
  at : @ast.Date?,
) -> @ast.Amount? {
  match self.rate(amount.currency, target, at) {
    Some(rate) => Some(@ast.Amount::new(amount.number.mul(rate), target))
    None => None
  }
}

///|
pub fn PriceDb::to_json(self : PriceDb) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  let mut first = true
  for point in self.points {
    if !first {
      sb.write_string(",")
    }
    sb.write_string("{\"date\":\"")
    sb.write_string(point.date.to_string())
    sb.write_string("\",\"base\":\"")
    sb.write_string(json_escape(point.base))
    sb.write_string("\",\"quote\":\"")
    sb.write_string(json_escape(point.quote))
    sb.write_string("\",\"rate\":\"")
    sb.write_string(point.rate.to_string())
    sb.write_string("\"}")
    first = false
  }
  sb.write_string("]")
  sb.to_string()
}

///|
pub fn json_escape(text : String) -> String {
  let sb = StringBuilder()
  for i in 0..<text.length() {
    match text.get_char(i) {
      Some(ch) =>
        if ch == '"' {
          sb.write_string("\\\"")
        } else if ch == '\\' {
          sb.write_string("\\\\")
        } else if ch == '\n' {
          sb.write_string("\\n")
        } else if ch == '\r' {
          sb.write_string("\\r")
        } else if ch == '\t' {
          sb.write_string("\\t")
        } else {
          sb.write_char(ch)
        }
      None => ()
    }
  }
  sb.to_string()
}
