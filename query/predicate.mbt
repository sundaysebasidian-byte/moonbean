///|
fn eval_predicate(
  ctx : QueryContext,
  cond : Cond,
  evaluate : (Expr) -> QueryValue,
) -> QueryValue {
  match cond {
    CTrue => QBool(true)
    CTruthy(e) => {
      let v = evaluate(e)
      if v is QInventory(_) {
        query_error(
          ctx, "query.oracle_type_error: NotImplementedError inventory truth",
        )
        return QNull
      }
      if v is QNull {
        QNull
      } else {
        QBool(truth(v))
      }
    }
    CNot(c) => QBool(!truth(eval_predicate(ctx, c, evaluate)))
    CAnd(a, b) => {
      let x = eval_predicate(ctx, a, evaluate)
      if !truth(x) {
        x
      } else {
        eval_predicate(ctx, b, evaluate)
      }
    }
    COr(a, b) => {
      let x = eval_predicate(ctx, a, evaluate)
      if truth(x) {
        x
      } else {
        eval_predicate(ctx, b, evaluate)
      }
    }
    CIsNull(e, negated) => QBool((evaluate(e) is QNull) != negated)
    CRegex(e, _, regex) =>
      match evaluate(e) {
        QNull => QNull
        QText(s) => QBool(regex.execute(s) is Some(_))
        _ => {
          query_error(
            ctx, "query.oracle_type_error: TypeError regex requires string",
          )
          QNull
        }
      }
    CCmp(a, op, b) => query_comparison(ctx, evaluate(a), op, evaluate(b))
  }
}

///|
fn projection_condition_types(
  cond : Cond,
  source : QuerySource,
  errors : Array[String],
) -> Unit {
  match cond {
    CTrue => ()
    CNot(c) => projection_condition_types(c, source, errors)
    CAnd(a, b) | COr(a, b) => {
      projection_condition_types(a, source, errors)
      projection_condition_types(b, source, errors)
    }
    CIsNull(e, _) | CTruthy(e) => expression_type(e, source, errors) |> ignore
    CRegex(e, _, _) => {
      let t = expression_type(e, source, errors)
      if t != "str" && t != "object" {
        errors.push("compilation query.invalid_signature: regex " + t)
      }
    }
    CCmp(a, _, b) => {
      let ta = expression_type(a, source, errors)
      let tb = expression_type(b, source, errors)
      let primitive = fn(t) { ["int", "decimal", "str", "date"].contains(t) }
      if !((ta == tb && primitive(ta)) ||
        (["int", "decimal"].contains(ta) && ["int", "decimal"].contains(tb)) ||
        (ta == "object" && primitive(tb)) ||
        (tb == "object" && primitive(ta))) {
        errors.push(
          "compilation query.invalid_signature: comparison " + ta + " " + tb,
        )
      }
    }
  }
}

///|
fn condition_label(cond : Cond) -> String {
  match cond {
    CTrue => "true"
    CTruthy(e) => oracle_expr_label(e)
    CNot(c) => "NOT " + condition_label(c)
    CAnd(a, b) => condition_label(a) + " AND " + condition_label(b)
    COr(a, b) => condition_label(a) + " OR " + condition_label(b)
    CCmp(a, op, b) => oracle_expr_label(a) + op + oracle_expr_label(b)
    CIsNull(e, n) =>
      oracle_expr_label(e) + (if n { " IS NOT NULL" } else { " IS NULL" })
    CRegex(e, p, _) => oracle_expr_label(e) + "~'" + p + "'"
  }
}

///|
fn same_condition(a : Cond, b : Cond) -> Bool {
  match (a, b) {
    (CTrue, CTrue) => true
    (CTruthy(a), CTruthy(b)) => same_expr(a, b)
    (CNot(a), CNot(b)) => same_condition(a, b)
    (CAnd(a, b), CAnd(c, d)) | (COr(a, b), COr(c, d)) =>
      same_condition(a, c) && same_condition(b, d)
    (CCmp(a, op, b), CCmp(c, p, d)) =>
      op == p && same_expr(a, c) && same_expr(b, d)
    (CIsNull(a, n), CIsNull(b, m)) => n == m && same_expr(a, b)
    (CRegex(a, p, _), CRegex(b, q, _)) => p == q && same_expr(a, b)
    _ => false
  }
}
