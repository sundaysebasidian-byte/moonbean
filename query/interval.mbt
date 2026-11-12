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
  QInterval(
    if unit.has_prefix("day") {
      "days"
    } else if unit.has_prefix("month") {
      "months"
    } else {
      "years"
    },
    n,
  )
}

///|
fn interval_repr(unit : String, n : @bigint.BigInt) -> String {
  let parts : Array[String] = []
  let values = if unit == "months" {
    [
      ("years", n.div(@bigint.BigInt::from_int(12))),
      ("months", n % @bigint.BigInt::from_int(12)),
    ]
  } else {
    [(unit, n)]
  }
  for (name, value) in values {
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
  let (unit, amount) = match interval {
    QInterval(unit, n) => (unit, n)
    _ => {
      query_error(
        ctx, "query.oracle_type_error: AttributeError invalid interval",
      )
      return QNull
    }
  }
  if amount < @bigint.BigInt::from_int(0) {
    return QNull
  }
  if amount == @bigint.BigInt::from_int(0) {
    query_error(
      ctx, "query.oracle_type_error: ZeroDivisionError interval is zero",
    )
    return QNull
  }
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
    let months = if unit == "years" {
      if n > 178956970 {
        query_error(
          ctx, "query.oracle_type_error: OverflowError interval out of range",
        )
        return QNull
      }
      n * 12
    } else {
      n
    }
    if months > 120000 {
      query_error(ctx, "query.oracle_type_error: ValueError date out of range")
      return QNull
    }
    let mut current = origin
    if date.compare(origin) >= 0 {
      while true {
        let total = current.year * 12 + current.month - 1 + months
        let y = total / 12
        let m = total % 12 + 1
        let next = @ast.Date::new(
          y,
          m,
          current.day.min(@ast.Date::days_in_month(y, m)),
        )
        match next {
          Some(next) => {
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
        let total = current.year * 12 + current.month - 1 - months
        let y = floor_div(total, 12)
        let m = total - y * 12 + 1
        match
          @ast.Date::new(y, m, current.day.min(@ast.Date::days_in_month(y, m))) {
          Some(previous) => current = previous
          None => {
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
