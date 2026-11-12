///|
fn literal_value(expr : Expr) -> QueryValue? {
  match expr {
    EStr(s) => Some(QText(s))
    EDate(d) => Some(QDate(d))
    EBool(b) => Some(QBool(b))
    ENull => Some(QNull)
    ENum(n) =>
      Some(if n.scale() == 0 { QInt(n.mantissa()) } else { QNumber(n) })
    _ => None
  }
}

///|
fn membership_equal(a : QueryValue, b : QueryValue) -> Bool {
  match (a, b) {
    (QNull, QNull) => true
    (QSet(a) | QFrozenSet(a), QSet(b) | QFrozenSet(b)) =>
      a.length() == b.length() && a.all(fn(s) { b.contains(s) })
    (QList(a), QList(b)) =>
      a.length() == b.length() &&
      a.iter().zip(b.iter()).all(fn(p) { membership_equal(p.0, p.1) })
    (QDict(a), QDict(b)) =>
      a.length() == b.length() &&
      a.all(fn(p) { b.any(fn(q) { p.0 == q.0 && membership_equal(p.1, q.1) }) })
    (QRecord(_, a), QRecord(_, b)) =>
      a.length() == b.length() &&
      a.iter().zip(b.iter()).all(fn(p) { membership_equal(p.0.1, p.1.1) })
    (QEnum(a, x), QEnum(b, y)) => a == b && x == y
    (QPythonType(a), QPythonType(b)) => a == b
    (QAmount(a), QAmount(b)) =>
      a.currency == b.currency && a.number.compare(b.number) == 0
    (QPosition(a), QPosition(b)) =>
      membership_equal(QAmount(a.units), QAmount(b.units)) &&
      (match (a.cost, b.cost) {
        (None, None) => true
        (Some(a), Some(b)) =>
          a.number.compare(b.number) == 0 &&
          a.currency == b.currency &&
          a.date.map(fn(d) { d.to_string() }) ==
          b.date.map(fn(d) { d.to_string() }) &&
          a.label == b.label
        _ => false
      })
    (QInventory(a), QInventory(b)) =>
      a.positions.length() == b.positions.length() &&
      a.positions.all(fn(p) {
        b.positions.any(fn(q) { membership_equal(QPosition(p), QPosition(q)) })
      })
    _ => value_compare(a, b) is Some(0)
  }
}

///|
fn query_comparison(
  ctx : QueryContext,
  a : QueryValue,
  op : String,
  b : QueryValue,
) -> QueryValue {
  if a is QNull || b is QNull {
    return QNull
  }
  if a is QInterval(am, ad) && b is QInterval(bm, bd) {
    if ["=", "==", "!=", "<>"].contains(op) {
      let equal = am == bm && ad == bd
      return QBool(if op == "!=" || op == "<>" { !equal } else { equal })
    }
    query_error(ctx, "query.oracle_type_error: TypeError interval ordering")
    return QNull
  }

  if ["=", "==", "!=", "<>"].contains(op) &&
    (
      structural_value(a) ||
      structural_value(b) ||
      a is QInventory(_) ||
      b is QInventory(_)
    ) {
    let equal = membership_equal(a, b)
    return QBool(if op == "!=" || op == "<>" { !equal } else { equal })
  }
  match (a, b) {
    (QSet(x) | QFrozenSet(x), QSet(y) | QFrozenSet(y)) => {
      let subset = x.all(fn(s) { y.contains(s) })
      let superset = y.all(fn(s) { x.contains(s) })
      return QBool(
        match op {
          "=" | "==" => subset && superset
          "!=" | "<>" => !(subset && superset)
          "<" => subset && !superset
          "<=" => subset
          ">" => superset && !subset
          ">=" => superset
          _ => false
        },
      )
    }
    _ => ()
  }
  match typed_compare(ctx, a, b) {
    None => QNull
    Some(n) =>
      QBool(
        match op {
          "=" | "==" => n == 0
          "!=" | "<>" => n != 0
          "<" => n < 0
          "<=" => n <= 0
          ">" => n > 0
          ">=" => n >= 0
          _ => false
        },
      )
  }
}

///|
fn membership(
  ctx : QueryContext,
  item : QueryValue,
  container : QueryValue,
) -> QueryValue {
  let found = match container {
    QList(values) => values.any(fn(v) { membership_equal(item, v) })
    QSet(values) | QFrozenSet(values) =>
      match item {
        QText(s) => values.contains(s)
        _ => false
      }
    QDict(values) =>
      match item {
        QText(s) => values.any(fn(p) { p.0 == s })
        _ => false
      }
    QText(text) =>
      match item {
        QText(s) => text.contains(s)
        _ => {
          query_error(
            ctx, "query.oracle_type_error: TypeError string membership requires string",
          )
          return QNull
        }
      }
    QAmount(a) =>
      membership_equal(item, QNumber(a.number)) ||
      membership_equal(item, QText(a.currency))
    QRecord(_, fields) => fields.any(fn(p) { membership_equal(item, p.1) })
    QInventory(_) => {
      if item is QList(_) || item is QDict(_) || item is QInventory(_) {
        query_error(
          ctx, "query.oracle_type_error: TypeError unhashable inventory key",
        )
        return QNull
      }
      false
    }
    QPosition(p) =>
      match item {
        QAmount(a) =>
          a.currency == p.units.currency && a.number.equal(p.units.number)
        _ => {
          query_error(
            ctx, "query.oracle_type_error: AttributeError position membership requires amount",
          )
          return QNull
        }
      }
    _ => {
      query_error(
        ctx, "query.oracle_type_error: TypeError value is not iterable",
      )
      return QNull
    }
  }
  QBool(found)
}

///|
fn decimal_modulo(
  ctx : QueryContext,
  a : @decimal.Decimal,
  b : @decimal.Decimal,
) -> @decimal.Decimal? {
  if b.is_zero() {
    return None
  }
  let scale = a.scale().max(b.scale())
  let x = a.shift_scale(scale - a.scale()).mantissa()
  let y = b.shift_scale(scale - b.scale()).mantissa()
  let quotient = x.div(y).to_string().replace_all(old="-", new="")
  if quotient.length() > 28 {
    query_error(
      ctx, "query.oracle_type_error: InvalidOperation DivisionImpossible",
    )
    return None
  }
  Some(@decimal.Decimal::new(x % y, scale).round_to_significant(28))
}
