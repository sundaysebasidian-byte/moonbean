///|
fn python_number_string(
  ctx : QueryContext,
  input : String,
  integer : Bool,
) -> QueryValue {
  let raw = normalize_python_digits(input.trim().to_owned())
  let plain = raw.replace_all(old="_", new="").to_lower()
  let word = if plain.has_prefix("+") || plain.has_prefix("-") {
    plain[1:].to_owned()
  } else {
    plain
  }
  if !integer &&
    (
      word == "infinity" ||
      word == "inf" ||
      word.has_prefix("nan") ||
      word.has_prefix("snan")
    ) {
    let tail = if word.has_prefix("snan") {
      word[4:].to_owned()
    } else if word.has_prefix("nan") {
      word[3:].to_owned()
    } else {
      ""
    }
    if tail.iter().all(fn(c) { c.is_ascii_digit() }) {
      query_error(
        ctx, "unsupported query.unsupported.decimal_representation: nonfinite strings",
      )
      return QNull
    }
  }
  if !integer && plain.contains("e") {
    let parts = plain.split("e").to_array()
    if parts.length() != 2 {
      return QNull
    }
    let base = python_number_string(ctx, parts[0].to_owned(), false)
    let exp = python_number_string(ctx, parts[1].to_owned(), true)
    match (base, exp) {
      (QNumber(base), QInt(_)) =>
        match query_integer(exp) {
          Some(e) =>
            if e > 1000000 || e < -1000000 {
              query_error(
                ctx, "unsupported query.unsupported.decimal_representation: exponent resource bound",
              )
              QNull
            } else {
              QNumber(@decimal.Decimal::new(base.mantissa(), base.scale() - e))
            }
          None => {
            query_error(
              ctx, "unsupported query.unsupported.decimal_representation: exponent resource bound",
            )
            QNull
          }
        }
      _ => QNull
    }
  } else {
    let out = StringBuilder()
    let chars = raw.iter().to_array()
    for i in 0..<chars.length() {
      let c = chars[i]
      if c == '_' {
        if integer &&
          (
            i == 0 ||
            i == chars.length() - 1 ||
            chars[i - 1] == '_' ||
            chars[i + 1] == '_' ||
            chars[i - 1] == '+' ||
            chars[i - 1] == '-'
          ) {
          return QNull
        }
        continue
      }
      let n = c.to_int()
      if c.is_ascii_digit() || c == '+' || c == '-' || (!integer && c == '.') {
        out.write_char(c)
      } else {
        let mut digit = -1
        for start in unicode_decimal_starts {
          if n >= start && n < start + 10 {
            digit = n - start
            break
          }
        }
        if digit >= 0 {
          out.write_string(digit.to_string())
        } else {
          return QNull
        }
      }
    }
    match @decimal.Decimal::parse(out.to_string()) {
      Some(n) =>
        if integer {
          QInt(n.mantissa())
        } else if n.is_zero() && out.to_string().has_prefix("-") {
          query_error(
            ctx, "unsupported query.unsupported.decimal_representation: signed zero",
          )
          QNull
        } else {
          QNumber(n)
        }
      None => QNull
    }
  }
}

///|
fn normalize_python_digits(input : String) -> String {
  let out = StringBuilder()
  for c in input.iter() {
    let mut mapped = c
    for start in unicode_decimal_starts {
      if c.to_int() >= start && c.to_int() < start + 10 {
        mapped = (48 + c.to_int() - start).unsafe_to_char()
        break
      }
    }
    out.write_char(mapped)
  }
  out.to_string()
}
