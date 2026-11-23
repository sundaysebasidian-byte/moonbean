///|
priv struct QueryExtension {
  name : String
  args : Array[String]
  result : String
  aggregate : Bool
}

///|
let query_extensions : Array[QueryExtension] = [
  {
    name: "sorted_set_json",
    args: ["text_set_or_null"],
    result: "str",
    aggregate: false,
  },
  {
    name: "list_at",
    args: ["list_or_null", "int_or_null"],
    result: "object",
    aggregate: false,
  },
  {
    name: "list_slice",
    args: ["list_or_null", "int_or_null", "int_or_null"],
    result: "list",
    aggregate: false,
  },
  {
    name: "percentile_disc",
    args: ["numeric", "numeric"],
    result: "decimal",
    aggregate: true,
  },
  {
    name: "arg_max",
    args: ["any", "ordered_scalar"],
    result: "first",
    aggregate: true,
  },
  {
    name: "arg_min",
    args: ["any", "ordered_scalar"],
    result: "first",
    aggregate: true,
  },
  {
    name: "add_business_days",
    args: ["date_or_null", "int_or_null"],
    result: "date",
    aggregate: false,
  },
  {
    name: "business_days_between",
    args: ["date_or_null", "date_or_null"],
    result: "int",
    aggregate: false,
  },
  {
    name: "round_increment",
    args: ["numeric", "numeric"],
    result: "decimal",
    aggregate: false,
  },
  { name: "bool_or", args: ["bool_or_null"], result: "bool", aggregate: true, },
  { name: "bool_and", args: ["bool_or_null"], result: "bool", aggregate: true, },
  {
    name: "fiscal_year",
    args: ["date_or_null", "int_or_null"],
    result: "int",
    aggregate: false,
  },
  {
    name: "fiscal_quarter",
    args: ["date_or_null", "int_or_null"],
    result: "int",
    aggregate: false,
  },
  {
    name: "account_in_subtree",
    args: ["str_or_null", "str_or_null"],
    result: "bool",
    aggregate: false,
  },
  {
    name: "weighted_avg",
    args: ["numeric", "numeric"],
    result: "decimal",
    aggregate: true,
  },
  {
    name: "clamp",
    args: ["numeric", "numeric", "numeric"],
    result: "decimal",
    aggregate: false,
  },
  {
    name: "days_in_month",
    args: ["date_or_null"],
    result: "int",
    aggregate: false,
  },
  {
    name: "month_end",
    args: ["date_or_null"],
    result: "date",
    aggregate: false,
  },
  {
    name: "date_format",
    args: ["date_or_null", "str_or_null"],
    result: "str",
    aggregate: false,
  },
  {
    name: "ends_with",
    args: ["str_or_null", "str_or_null"],
    result: "bool",
    aggregate: false,
  },
  {
    name: "starts_with",
    args: ["str_or_null", "str_or_null"],
    result: "bool",
    aggregate: false,
  },
  {
    name: "replace_text",
    args: ["str_or_null", "str_or_null", "str_or_null"],
    result: "str",
    aggregate: false,
  },
  { name: "rtrim", args: ["str_or_null"], result: "str", aggregate: false, },
  { name: "ltrim", args: ["str_or_null"], result: "str", aggregate: false, },
  { name: "trim", args: ["str_or_null"], result: "str", aggregate: false, },
  {
    name: "join_text",
    args: ["list_or_null", "str_or_null"],
    result: "str",
    aggregate: false,
  },
  {
    name: "split_text",
    args: ["str_or_null", "str_or_null"],
    result: "list",
    aggregate: false,
  },
  { name: "last_non_null", args: ["any"], result: "first", aggregate: true, },
  { name: "first_non_null", args: ["any"], result: "first", aggregate: true, },
  { name: "collect", args: ["any"], result: "list", aggregate: true, },
  { name: "median", args: ["numeric"], result: "decimal", aggregate: true, },
  { name: "count_distinct", args: ["scalar"], result: "int", aggregate: true, },
  { name: "avg", args: ["numeric"], result: "decimal", aggregate: true, },
  { name: "nullif", args: ["any", "any"], result: "first", aggregate: false, },
]

///|
fn extension_numeric_values(
  ctx : QueryContext,
  arg : Expr,
  rows : Array[BqlRow],
) -> Array[@decimal.Decimal] {
  let values = []
  for row in rows {
    if value_number(eval_expr(ctx, arg, row)) is Some(n) {
      values.push(n)
    }
  }
  values
}

///|
fn extension_sum_exact(values : Array[@decimal.Decimal]) -> @decimal.Decimal {
  let mut scale = 0
  for n in values {
    if n.scale() > scale {
      scale = n.scale()
    }
  }
  let mut coeff = @bigint.BigInt::from_int(0)
  let ten = @bigint.BigInt::from_int(10)
  for n in values {
    let adjust = scale - n.scale()
    coeff = coeff +
      (if adjust == 0 {
        n.mantissa()
      } else {
        n.mantissa() * ten.pow(@bigint.BigInt::from_int(adjust))
      })
  }
  @decimal.Decimal::new(coeff, scale)
}

///|
fn extension_mean(values : Array[@decimal.Decimal]) -> QueryValue {
  if values.is_empty() {
    return QNull
  }
  QNumber(
    extension_sum_exact(values)
    .div(@decimal.Decimal::from_int(values.length()))
    .unwrap(),
  )
}

///|
fn extension_weighted_mean(
  ctx : QueryContext,
  value : Expr,
  weight : Expr,
  rows : Array[BqlRow],
) -> QueryValue {
  let products = []
  let weights = []
  for row in rows {
    let v = value_number(eval_expr(ctx, value, row))
    let w = value_number(eval_expr(ctx, weight, row))
    if v is Some(v) && w is Some(w) {
      products.push(
        @decimal.Decimal::new(
          v.mantissa() * w.mantissa(),
          v.scale() + w.scale(),
        ),
      )
      weights.push(w)
    }
  }
  match extension_sum_exact(products).div(extension_sum_exact(weights)) {
    Some(mean) => QNumber(mean)
    None => QNull
  }
}

///|
fn extension_trim(s : String, left : Bool, right : Bool) -> QueryValue {
  let chars = s.to_array()
  let mut start = 0
  let mut end = chars.length()
  while left && start < end && python_whitespace(chars[start]) {
    start += 1
  }
  while right && end > start && python_whitespace(chars[end - 1]) {
    end -= 1
  }
  QText(String::from_array(chars[start:end].to_owned()))
}

///|
fn extension_date_format(
  ctx : QueryContext,
  d : @ast.Date,
  pattern : String,
) -> QueryValue {
  let chars = pattern.to_array()
  let iso = d.to_string()
  let output = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '%' {
      output.write_char(c)
      i += 1
      continue
    }
    i += 1
    if i >= chars.length() {
      query_error(ctx, "evaluation query.date_format: trailing %")
      return QNull
    }
    match chars[i] {
      '%' => output.write_char('%')
      'Y' => output.write_string(iso[:4].to_owned())
      'm' => output.write_string(iso[5:7].to_owned())
      'd' => output.write_string(iso[8:10].to_owned())
      'F' => output.write_string(iso)
      'j' => {
        let day = d.day_of_year().to_string()
        output.write_string("0".repeat(3 - day.length()) + day)
      }
      invalid => {
        query_error(
          ctx,
          "evaluation query.date_format: unsupported directive %" +
          invalid.to_string(),
        )
        return QNull
      }
    }
    i += 1
  }
  QText(output.to_string())
}

///|
fn list_coordinate(n : @bigint.BigInt, count : Int32) -> Int32 {
  let width = @bigint.BigInt::from_int(count)
  let adjusted = if n.compare_int(0) < 0 { width + n } else { n }
  if adjusted.compare_int(0) < 0 {
    0
  } else if adjusted >= width {
    count
  } else {
    query_integer(QInt(adjusted)).unwrap()
  }
}

///|
fn working_day(n : Int32) -> Bool {
  (n - 1) % 7 < 5
}

///|
fn business_day_count(start : Int32, end : Int32) -> Int32 {
  let lo = start.min(end)
  let hi = start.max(end)
  let weeks = (hi - lo) / 7
  let mut n = weeks * 5
  for day in (lo + weeks * 7)..<hi {
    if working_day(day) {
      n += 1
    }
  }
  if end < start {
    -n
  } else {
    n
  }
}

///|
fn business_day_add(
  ctx : QueryContext,
  date : @ast.Date,
  offset : QueryValue,
) -> QueryValue {
  guard query_integer(offset) is Some(n) && n >= -3652059 && n <= 3652059 else {
    query_error(
      ctx, "evaluation query.business_calendar: date or offset out of range",
    )
    return QNull
  }
  if n == 0 {
    return QDate(date)
  }
  let direction = if n < 0 { -1 } else { 1 }
  let mut left = if n < 0 { -n } else { n }
  let mut day = ordinal(date)
  if !working_day(day) {
    while !working_day(day) {
      day += direction
    }
    left -= 1
  }
  day += left / 5 * 7 * direction
  left %= 5
  while left > 0 {
    day += direction
    if working_day(day) {
      left -= 1
    }
  }
  let result = ordinal_date(day)
  if result is QNull {
    query_error(
      ctx, "evaluation query.business_calendar: date or offset out of range",
    )
  }
  result
}

///|
fn extension_round_increment(
  ctx : QueryContext,
  input : QueryValue,
  increment : QueryValue,
) -> QueryValue {
  guard value_number(input) is Some(value) &&
    value_number(increment) is Some(step) &&
    step.is_positive() else {
    query_error(
      ctx, "evaluation query.round_increment: increment must be positive",
    )
    return QNull
  }
  let offset = value.scale() - step.scale()
  let ten = @bigint.BigInt::from_int(10)
  let one = @bigint.BigInt::from_int(1)
  let two = @bigint.BigInt::from_int(2)
  let negative = value.is_negative() || input is QNegativeZero(_)
  let magnitude = if value.is_negative() {
    value.mantissa().neg()
  } else {
    value.mantissa()
  }
  let a = if offset < 0 {
    magnitude * ten.pow(@bigint.BigInt::from_int(-offset))
  } else {
    magnitude
  }
  let b = if offset > 0 {
    step.mantissa() * ten.pow(@bigint.BigInt::from_int(offset))
  } else {
    step.mantissa()
  }
  let quotient = a / b
  let remainder = a.mod(b) * two
  let rounded = if remainder > b || (remainder == b && quotient.mod(two) == one) {
    quotient + one
  } else {
    quotient
  }
  if rounded.is_zero() && negative {
    return QNegativeZero(step.scale())
  }
  let result = rounded * step.mantissa()
  QNumber(
    @decimal.Decimal::new(
      if negative {
        result.neg()
      } else {
        result
      },
      step.scale(),
    ),
  )
}

///|
fn eval_case(args : Array[Expr], evaluate : (Expr) -> QueryValue) -> QueryValue {
  let fallback = args.length() - 1
  for i = 0; i < fallback; i = i + 2 {
    if truth(evaluate(args[i])) {
      return evaluate(args[i + 1])
    }
  }
  evaluate(args[fallback])
}

///|
fn extension_name(name : String) -> Bool {
  query_extensions.any(fn(s) { s.name == name })
}

///|
fn aggregate_name(name : String) -> Bool {
  ["__filter_aggregate", "sum", "count", "first", "last", "min", "max"].contains(
    name,
  ) ||
  query_extensions.any(fn(s) { s.name == name && s.aggregate })
}

///|
fn extension_type(name : String, args : Array[String]) -> String? {
  for s in query_extensions {
    if s.name == name &&
      s.args.length() == args.length() &&
      s.args.iter().zip(args.iter()).all(fn(p) { type_argument(p.1, p.0) }) {
      return Some(if s.result == "first" { args[0] } else { s.result })
    }
  }
  None
}
