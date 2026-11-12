///|
fn query_today(ctx : QueryContext) -> QueryValue {
  let n = local_date_number()
  match @ast.Date::new(n / 10000, n / 100 % 100, n % 100) {
    Some(d) => QDate(d)
    None => {
      query_error(ctx, "query.oracle_type_error: system clock unavailable")
      QNull
    }
  }
}

///|
fn query_interval(text : String) -> QueryValue {
  let normalized = String::from_iter(
    text.iter().map(fn(c) { if python_whitespace(c) { ' ' } else { c } }),
  )
  let words = normalized.split(" ").filter(fn(s) { s != "" }).to_array()
  if words.length() != 2 ||
    normalized.has_prefix(" ") ||
    normalized.has_suffix(" ") {
    return QNull
  }
  let unit = words[1].to_owned()
  if !["day", "days", "month", "months", "year", "years"].contains(unit) {
    return QNull
  }
  let raw = words[0].to_owned()
  let digits = if raw.has_prefix("+") || raw.has_prefix("-") {
    raw[1:].to_owned()
  } else {
    raw
  }
  if digits == "" || !digits.iter().all(fn(c) { c.is_ascii_digit() }) {
    return QNull
  }
  let n = @bigint.BigInt::from_string(
    if raw.has_prefix("+") {
      raw[1:].to_owned()
    } else {
      raw
    },
  )
  let zero = @bigint.BigInt::from_int(0)
  if unit.has_prefix("day") {
    QInterval(zero, n)
  } else {
    QInterval(
      if unit.has_prefix("year") {
        n.mul(@bigint.BigInt::from_int(12))
      } else {
        n
      },
      zero,
    )
  }
}

///|
fn interval_repr(months : @bigint.BigInt, days : @bigint.BigInt) -> String {
  let parts : Array[String] = []
  for
    (name, value) in [
      ("years", months.div(@bigint.BigInt::from_int(12))),
      ("months", months % @bigint.BigInt::from_int(12)),
      ("days", days),
    ] {
    if value != @bigint.BigInt::from_int(0) {
      parts.push(
        name +
        "=" +
        (if value > @bigint.BigInt::from_int(0) { "+" } else { "" }) +
        interval_number(value),
      )
    }
  }
  "relativedelta(" + parts.join(", ") + ")"
}

///|
fn floor_div(a : Int32, b : Int32) -> Int32 {
  let q = a / b
  if a % b < 0 {
    q - 1
  } else {
    q
  }
}

///|
fn query_date_bin(
  ctx : QueryContext,
  interval : QueryValue,
  date : @ast.Date,
  origin : @ast.Date,
) -> QueryValue {
  let interval = match interval {
    QText(s) => query_interval(s)
    other => other
  }
  let (months, days) = match interval {
    QInterval(months, days) => (months, days)
    _ => {
      query_error(
        ctx, "query.oracle_type_error: AttributeError invalid interval",
      )
      return QNull
    }
  }
  let zero = @bigint.BigInt::from_int(0)
  if (months == zero && days < zero) || (months < zero && days <= zero) {
    return QNull
  }
  if months == zero && days == zero {
    query_error(
      ctx, "query.oracle_type_error: ZeroDivisionError interval is zero",
    )
    return QNull
  }
  let unit = if months == zero { "days" } else { "months" }
  let amount = if months == zero { days } else { months }
  let n = match query_integer(QInt(amount)) {
    Some(n) => n
    None => {
      if unit == "days" && date.compare(origin) >= 0 {
        return QDate(origin)
      }
      query_error(
        ctx, "query.oracle_type_error: OverflowError interval out of range",
      )
      return QNull
    }
  }
  let result = if unit == "days" {
    ordinal_date(
      ordinal(origin) + floor_div(ordinal(date) - ordinal(origin), n) * n,
    )
  } else {
    let months = n
    if months > 120000 {
      query_error(ctx, "query.oracle_type_error: ValueError date out of range")
      return QNull
    }
    let mut current = origin
    if date.compare(origin) >= 0 {
      while true {
        let next = match
          add_interval_date(
            ctx,
            current,
            QInterval(@bigint.BigInt::from_int(months), days),
            false,
          ) {
          QDate(d) => Some(d)
          _ => None
        }
        match next {
          Some(next) => {
            if next.compare(current) < 0 {
              return QNull
            }
            if next.compare(current) == 0 {
              query_error(
                ctx, "query.oracle_type_error: ZeroDivisionError interval does not advance",
              )
              return QNull
            }
            if next.compare(date) >= 0 {
              break
            }
            current = next
          }
          None => {
            query_error(
              ctx, "query.oracle_type_error: ValueError date out of range",
            )
            return QNull
          }
        }
      }
    } else {
      while current.compare(date) > 0 {
        match
          add_interval_date(
            ctx,
            current,
            QInterval(@bigint.BigInt::from_int(months), days),
            true,
          ) {
          QDate(previous) => {
            if previous.compare(current) >= 0 {
              return QNull
            }
            current = previous
          }
          _ => {
            query_error(
              ctx, "query.oracle_type_error: ValueError date out of range",
            )
            return QNull
          }
        }
      }
    }
    QDate(current)
  }
  if result is QNull {
    query_error(ctx, "query.oracle_type_error: ValueError date out of range")
  }
  result
}

///|
fn interval_number(value : @bigint.BigInt) -> String {
  let raw = value.to_string()
  let negative = raw.has_prefix("-")
  let digits = if negative { raw[1:].to_owned() } else { raw }
  if digits.length() <= 6 {
    return raw
  }
  let rounded = @decimal.Decimal::new(
    if negative {
      value.neg()
    } else {
      value
    },
    0,
  ).round_to_significant(6)
  let text = rounded.to_string()
  let exponent = text.length() - 1
  let significant = text.trim_end(chars="0").to_owned()
  let fraction = if significant.length() > 1 {
    "." + significant[1:].to_owned()
  } else {
    ""
  }
  (if negative { "-" } else { "" }) +
  significant[:1].to_owned() +
  fraction +
  "e+" +
  (if exponent < 10 { "0" } else { "" }) +
  exponent.to_string()
}

///|
fn add_interval_date(
  ctx : QueryContext,
  date : @ast.Date,
  interval : QueryValue,
  subtract : Bool,
) -> QueryValue {
  guard interval is QInterval(months, days) else { return QNull }
  let months = if subtract { months.neg() } else { months }
  let days = if subtract { days.neg() } else { days }
  let m = match query_integer(QInt(months)) {
    Some(n) => n
    None => {
      query_error(ctx, "query.oracle_type_error: OverflowError interval months")
      return QNull
    }
  }
  if m > 120000 || m < -120000 {
    query_error(
      ctx, "query.oracle_type_error: ValueError interval year out of range",
    )
    return QNull
  }
  let total = date.year * 12 + date.month - 1 + m
  let year = floor_div(total, 12)
  let month = total - year * 12 + 1
  let shifted = @ast.Date::new(
    year,
    month,
    date.day.min(@ast.Date::days_in_month(year, month)),
  )
  guard shifted is Some(shifted) else {
    query_error(
      ctx, "query.oracle_type_error: ValueError interval year out of range",
    )
    return QNull
  }
  add_date_days(ctx, shifted, days)
}

///|
fn add_date_days(
  ctx : QueryContext,
  date : @ast.Date,
  days : @bigint.BigInt,
) -> QueryValue {
  let ordinal = @bigint.BigInt::from_int(ordinal(date)).add(days)
  if ordinal < @bigint.BigInt::from_int(1) ||
    ordinal > @bigint.BigInt::from_int(3652059) {
    query_error(ctx, "query.oracle_type_error: OverflowError date out of range")
    return QNull
  }
  ordinal_date(query_integer(QInt(ordinal)).unwrap())
}
