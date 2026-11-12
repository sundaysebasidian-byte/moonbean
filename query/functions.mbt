///|
fn query_int(n : Int32) -> QueryValue {
  QInt(@bigint.BigInt::from_int(n))
}

///|
fn query_integer(value : QueryValue) -> Int32? {
  match value {
    QBool(b) => Some(if b { 1 } else { 0 })
    QInt(n) => {
      let d = @decimal.Decimal::new(n, 0)
      if d.less_than(@decimal.Decimal::from_int(-2147483647)) ||
        @decimal.Decimal::from_int(2147483647).less_than(d) {
        None
      } else {
        Some(bql_parse_int(n.to_string()))
      }
    }
    _ => None
  }
}

///|
fn truth(value : QueryValue) -> Bool {
  match value {
    QNull => false
    QBool(b) => b
    QText(s) => s != ""
    QInterval(_, n) => n != @bigint.BigInt::from_int(0)
    QNegativeZero(_) => false
    QNumber(n) => !n.is_zero()
    QInt(n) => n != @bigint.BigInt::from_int(0)
    QDict(v) | QRecord(_, v) => !v.is_empty()
    QList(v) => !v.is_empty()
    QSet(v) | QFrozenSet(v) => !v.is_empty()
    QAmount(a) => !a.number.is_zero()
    QPosition(p) => !p.units.number.is_zero()
    QInventory(v) => !v.is_empty()
    _ => true
  }
}

///|
fn ordinal(d : @ast.Date) -> Int32 {
  let y = d.year - 1
  let mut result = y * 365 + y / 4 - y / 100 + y / 400 + d.day
  for m in 1..<d.month {
    result = result + @ast.Date::days_in_month(d.year, m)
  }
  result
}

///|
fn ordinal_date(n : Int32) -> QueryValue {
  if n < 1 || n > 3652059 {
    return QNull
  }
  let mut lo = 1
  let mut hi = 10000
  while lo + 1 < hi {
    let mid = (lo + hi) / 2
    if ordinal(@ast.Date::new(mid, 1, 1).unwrap()) <= n {
      lo = mid
    } else {
      hi = mid
    }
  }
  let mut day = n - ordinal(@ast.Date::new(lo, 1, 1).unwrap()) + 1
  let mut month = 1
  while day > @ast.Date::days_in_month(lo, month) {
    day = day - @ast.Date::days_in_month(lo, month)
    month = month + 1
  }
  QDate(@ast.Date::new(lo, month, day).unwrap())
}

///|
fn metadata_function(
  ctx : QueryContext,
  name : String,
  values : Array[QueryValue],
  row : BqlRow,
) -> QueryValue {
  let key = match values[0] {
    QText(s) => s
    _ => return QNull
  }
  if name == "any_meta" {
    if row.extra is Some(extra) && extra.cells is Some(cells) {
      if dict_get(cells.get("meta").unwrap_or(QNull), key) is Some(value) {
        return value
      }
      let entry_meta = record_metadata(ctx, cells.get("entry").unwrap_or(QNull))
      return dict_get(entry_meta, key).unwrap_or(QNull)
    }
    if row_posting(row) is Some(p) {
      for (k, v) in source_metadata(p.loc, p.meta) {
        if k == key {
          return v
        }
      }
    }
    return match row_entry(row) {
      Some(e) => dict_get(entry_metadata(e), key).unwrap_or(QNull)
      None => QNull
    }
  }
  let entry = if name == "commodity_meta" || name == "currency_meta" {
    let mut found = None
    for e in ctx.realized.entries {
      if e.directive is DCommodity(c) && c.currency == key {
        found = Some(e)
      }
    }
    found
  } else {
    ensure_account_index(ctx)
    if name == "close_date" {
      ctx.closes.unwrap().get(key)
    } else {
      ctx.opens.unwrap().get(key)
    }
  }
  match entry {
    None => QNull
    Some(e) =>
      if name == "open_date" || name == "close_date" {
        QDate(e.date)
      } else {
        let meta = entry_metadata(e)
        if values.length() == 2 {
          match values[1] {
            QText(k) => dict_get(meta, k).unwrap_or(QNull)
            _ => QNull
          }
        } else {
          meta
        }
      }
  }
}

///|
fn map_positions(
  value : QueryValue,
  transform : (@booking.Position) -> @booking.Position?,
) -> QueryValue {
  match value {
    QPosition(p) =>
      match transform(p) {
        Some(p) => QPosition(p)
        None => QNull
      }
    QInventory(inv) => {
      let result = @booking.Inventory::new()
      for p in inv.positions {
        if transform(p) is Some(p) {
          result.add(p)
        }
      }
      QInventory(result)
    }
    _ => QNull
  }
}

///|
fn eval_function(
  ctx : QueryContext,
  name : String,
  values : Array[QueryValue],
  row : BqlRow,
) -> QueryValue {
  if values.any(fn(v) { v is QNull }) {
    return QNull
  }
  if [
      "any_meta", "open_meta", "open_date", "close_date", "commodity_meta", "currency_meta",
    ].contains(name) {
    return metadata_function(ctx, name, values, row)
  }
  if (name == "str" || name == "repr") && !values.all(portable_repr) {
    query_error(
      ctx, "unsupported query.unsupported.set_representation: CPython hash-seed iteration order",
    )
    return QNull
  }
  match (name, values) {
    ("parse_date", [QText(text)]) => flexible_date(ctx, text)
    ("parse_date", [QText(text), QText(format)]) =>
      strptime_date(ctx, text, format)
    ("today", []) => query_today(ctx)
    ("interval", [QText(s)]) => query_interval(s)
    ("date_bin", [interval, QDate(date), QDate(origin)]) =>
      query_date_bin(ctx, interval, date, origin)
    ("subst", [QText(pattern), QText(replacement), QText(text)]) =>
      query_substitute(ctx, pattern, replacement, text)
    ("grep" | "grepn" | "findfirst" | "has_account", _) =>
      regex_function(ctx, name, values, row)
    ("date_part" | "date_trunc", [QText(part), QDate(date)]) =>
      calendar_function(ctx, name, part, date)
    ("joinstr", [QSet(items)]) | ("joinstr", [QFrozenSet(items)]) =>
      if items.length() > 1 {
        query_error(
          ctx, "unsupported query.unsupported.set_representation: joinstr depends on CPython hash seed",
        )
        QNull
      } else {
        QText(items.join(","))
      }
    ("maxwidth", [QText(text), width]) => query_maxwidth(ctx, text, width)
    ("getprice", [QText(base), QText(quote)])
    | ("getprice", [QText(base), QText(quote), _]) =>
      match
        query_price(
          ctx,
          base,
          quote,
          if values.length() == 3 && values[2] is QDate(d) {
            Some(d)
          } else {
            None
          },
        ) {
        Some(n) => QNumber(n)
        None => QNull
      }
    ("convert", [value, QText(target)])
    | ("convert", [value, QText(target), _]) =>
      query_conversion(
        ctx,
        value,
        Some(target),
        if values.length() == 3 && values[2] is QDate(d) {
          Some(d)
        } else {
          None
        },
      )
    ("value", [value]) | ("value", [value, _]) =>
      query_conversion(
        ctx,
        value,
        None,
        if values.length() == 2 && values[1] is QDate(d) {
          Some(d)
        } else {
          None
        },
      )
    ("possign", [value, QText(account)]) => {
      let root = @ast.account_root(account)
      if root == "Assets" || root == "Expenses" {
        value
      } else {
        match value {
          QAmount(a) =>
            QAmount(
              @ast.Amount::new(
                a.number.neg().round_to_significant(28),
                a.currency,
              ),
            )
          _ => eval_function(ctx, "neg", [value], row)
        }
      }
    }
    ("account_sortkey", [QText(account)]) => {
      let root = @ast.account_root(account)
      let defaults = ["Assets", "Liabilities", "Equity", "Income", "Expenses"]
      let names = [
        "name_assets", "name_liabilities", "name_equity", "name_income", "name_expenses",
      ]
      for i in 0..<defaults.length() {
        let mut name = defaults[i]
        for (key, value) in ctx.realized.options.raw {
          if key == names[i] {
            name = value
          }
        }
        if root == name {
          return QText(i.to_string() + "-" + account)
        }
      }
      query_error(
        ctx, "query.oracle_type_error: ValueError unknown account root",
      )
      QNull
    }
    ("splitcomp", [QText(s), QText(separator), index]) => {
      if separator == "" {
        query_error(ctx, "query.oracle_type_error: ValueError empty separator")
        return QNull
      }
      let parts = s.split(separator).to_array()
      match query_integer(index) {
        Some(i) => {
          let n = if i < 0 { parts.length() + i } else { i }
          if n < 0 || n >= parts.length() {
            query_error(
              ctx, "query.oracle_type_error: IndexError split component",
            )
            QNull
          } else {
            QText(parts[n].to_owned())
          }
        }
        None => {
          query_error(
            ctx, "query.oracle_type_error: IndexError split component",
          )
          QNull
        }
      }
    }
    ("round", [v]) | ("round", [v, _]) => {
      let digits = if values.length() == 1 {
        Some(0)
      } else {
        query_integer(values[1])
      }
      match (value_number(v), digits) {
        (Some(n), Some(digits)) => {
          if (v is QInt(_) || v is QBool(_)) && digits >= 0 {
            return QInt(n.mantissa())
          }
          if digits > 1000000 || digits < -999999 {
            query_error(
              ctx, "unsupported query.unsupported.decimal_representation: rounding resource bound",
            )
            return QNull
          }
          let magnitude = n
            .mantissa()
            .to_string()
            .replace_all(old="-", new="")
            .length()
          if v is QNumber(_) &&
            !n.is_zero() &&
            magnitude + digits - n.scale() > 28 {
            query_error(
              ctx, "query.oracle_type_error: InvalidOperation decimal precision",
            )
            return QNull
          }
          let rounded = if n.is_zero() || n.scale() - digits > magnitude + 1 {
            @decimal.Decimal::zero_scaled(digits)
          } else {
            n.quantize(digits)
          }
          if (v is QNumber(_) || v is QNegativeZero(_)) &&
            rounded.is_zero() &&
            (n.is_negative() || v is QNegativeZero(_)) {
            QNegativeZero(digits)
          } else if v is QInt(_) || v is QBool(_) {
            QInt(
              @decimal.Decimal::parse(rounded.to_string()).unwrap().mantissa(),
            )
          } else {
            QNumber(rounded)
          }
        }
        _ => {
          query_error(
            ctx, "unsupported query.unsupported.decimal_representation: rounding resource bound",
          )
          QNull
        }
      }
    }
    ("str", [v]) =>
      QText(
        if v is QInventory(_) || v is QSet(_) {
          python_repr(v)
        } else {
          v.to_text()
        },
      )
    ("repr", [v]) => QText(python_repr(v))
    ("bool", [QInventory(_)]) => {
      query_error(
        ctx, "query.oracle_type_error: NotImplementedError inventory truth",
      )
      QNull
    }
    ("bool", [v]) => QBool(truth(v))
    ("int" | "decimal", [QText(s)]) =>
      python_number_string(ctx, s, name == "int")
    ("int" | "decimal", [v]) => {
      let n = match v {
        QInt(n) => Some(@decimal.Decimal::new(n, 0))
        QNegativeZero(scale) => Some(@decimal.Decimal::zero_scaled(scale))
        QNumber(n) => Some(n)
        QBool(b) => Some(@decimal.Decimal::from_int(if b { 1 } else { 0 }))
        _ => None
      }
      match n {
        Some(n) =>
          if name == "decimal" {
            if v is QNegativeZero(scale) {
              QNegativeZero(scale)
            } else {
              QNumber(n)
            }
          } else {
            QInt(
              @decimal.Decimal::parse(
                n.to_string().split(".").to_array()[0].to_owned(),
              )
              .unwrap()
              .mantissa(),
            )
          }
        None => QNull
      }
    }
    ("date", [QDate(d)]) => QDate(d)
    ("date", [QText(s)]) =>
      match @ast.Date::parse(s) {
        Some(d) => QDate(d)
        None => QNull
      }
    ("date", [v]) =>
      match v {
        QDate(d) => QDate(d)
        QText(s) =>
          match @ast.Date::parse(s) {
            Some(d) => QDate(d)
            None => QNull
          }
        _ => QNull
      }
    ("date", [y, m, d]) =>
      match (query_integer(y), query_integer(m), query_integer(d)) {
        (Some(y), Some(m), Some(d)) =>
          match @ast.Date::new(y, m, d) {
            Some(d) => QDate(d)
            None => QNull
          }
        _ => QNull
      }
    ("day", [QDate(d)]) => query_int(d.day)
    ("quarter", [QDate(d)]) =>
      QText(
        d.to_string()[:4].to_owned() +
        "-Q" +
        ((d.month - 1) / 3 + 1).to_string(),
      )
    ("weekday", [QDate(d)]) =>
      QText(
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][(ordinal(d) - 1) % 7],
      )
    ("yearmonth", [QDate(d)]) =>
      QDate(@ast.Date::new(d.year, d.month, 1).unwrap())
    ("date_add", [QDate(d), v]) =>
      match query_integer(v) {
        Some(n) =>
          if n > 3652059 || n < -3652059 {
            query_error(
              ctx, "query.oracle_type_error: OverflowError date value out of range",
            )
            QNull
          } else if ordinal(d) + n < 1 || ordinal(d) + n > 3652059 {
            query_error(
              ctx, "query.oracle_type_error: OverflowError date value out of range",
            )
            QNull
          } else {
            ordinal_date(ordinal(d) + n)
          }
        None => {
          query_error(
            ctx, "query.oracle_type_error: OverflowError date value out of range",
          )
          QNull
        }
      }
    ("date_diff", [QDate(a), QDate(b)]) => query_int(ordinal(a) - ordinal(b))
    ("root", [QText(s), v]) =>
      match query_integer(v) {
        Some(n) => {
          let parts = s.split(":").to_array()
          let end = if n < 0 {
            (parts.length() + n).max(0)
          } else {
            n.min(parts.length())
          }
          QText(parts[:end].to_owned().map(fn(s) { s.to_owned() }).join(":"))
        }
        None =>
          match v {
            QInt(n) => QText(if n.compare_int(0) > 0 { s } else { "" })
            _ => QNull
          }
      }
    ("number", [QAmount(a)]) => QNumber(a.number)
    ("currency" | "commodity", [QAmount(a)]) => QText(a.currency)
    ("empty", [QInventory(i)]) => QBool(i.is_empty())
    ("only", [QText(currency), QInventory(i)]) =>
      QAmount(@ast.Amount::new(i.quantity(currency), currency))
    ("filter_currency", [v, QText(currency)]) =>
      map_positions(v, fn(p) {
        if p.units.currency == currency {
          Some(p)
        } else {
          None
        }
      })
    ("units" | "cost", [v]) =>
      match v {
        QPosition(p) =>
          QAmount(
            if name == "cost" && p.cost is Some(c) {
              @ast.Amount::new(p.units.number.mul(c.number), c.currency)
            } else {
              p.units
            },
          )
        QInventory(_) =>
          map_positions(v, fn(p) {
            Some(
              @booking.Position::new(
                if name == "cost" && p.cost is Some(c) {
                  @ast.Amount::new(p.units.number.mul(c.number), c.currency)
                } else {
                  p.units
                },
                None,
              ),
            )
          })
        _ => QNull
      }
    ("neg", [QAmount(a)]) =>
      QAmount(
        @ast.Amount::new(a.number.neg().round_to_significant(28), a.currency),
      )
    ("neg" | "abs", [QNegativeZero(scale)]) =>
      QNumber(@decimal.Decimal::zero_scaled(scale))
    ("neg" | "abs", [QNumber(n)]) =>
      QNumber(
        (if name == "neg" { n.neg() } else { n.abs() }).round_to_significant(28),
      )
    ("neg" | "abs", [v]) =>
      map_positions(v, fn(p) {
        Some(
          @booking.Position::new(
            @ast.Amount::new(
              if name == "neg" {
                p.units.number.neg().round_to_significant(28)
              } else {
                p.units.number.abs().round_to_significant(28)
              },
              p.units.currency,
            ),
            p.cost,
          ),
        )
      })
    ("safediv", [a, b]) =>
      match (value_number(a), value_number(b)) {
        (Some(a), Some(b)) =>
          if b.is_zero() {
            QNumber(@decimal.Decimal::zero())
          } else if a.is_zero() && b.is_negative() {
            query_error(
              ctx, "unsupported query.unsupported.decimal_representation: signed-zero safediv",
            )
            QNull
          } else {
            QNumber(a.div(b).unwrap())
          }
        _ => QNull
      }
    _ => {
      query_error(ctx, "unsupported query.unsupported.function `" + name + "`")
      QNull
    }
  }
}
