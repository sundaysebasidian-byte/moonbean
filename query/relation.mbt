///|
fn oracle_expr_label(expr : Expr) -> String {
  match expr {
    ECall(name, args) =>
      name + "(" + args.map(oracle_expr_label).join(", ") + ")"
    EBinary(a, op, b) => oracle_expr_label(a) + op + oracle_expr_label(b)
    EStr(s) => "'" + s + "'"
    ENull => "NULL"
    _ => expr_label(expr)
  }
}

///|
fn resolve_reference(
  parser : QueryParser,
  expr : Expr,
  projections : Array[Expr],
  names : Array[String],
  clause : String,
) -> Expr {
  if expr is ENum(n) {
    if n.scale() != 0 {
      parser.fail("expected an integer column reference")
      return expr
    }
    let index = bql_parse_int(n.to_string())
    if index < 1 || index > projections.length() {
      parser.fail(
        "compilation query.invalid_reference: invalid " +
        clause +
        " column index " +
        n.to_string(),
      )
      return expr
    }
    return projections[index - 1]
  }
  if expr is ECol(name) {
    for i = names.length() - 1; i >= 0; i = i - 1 {
      if names[i] == name {
        return projections[i]
      }
    }
  }
  expr
}

///|
fn relation_rows(
  names : Array[String],
  values : Array[Array[QueryValue]],
) -> Array[BqlRow] {
  values.map(fn(values) {
    let cells : Map[String, QueryValue] = Map([])
    for i in 0..<names.length() {
      cells.set(names[i], values[i])
    }
    let extra = new_row_extra(None, None, None)
    extra.cells = Some(cells)
    let units = @ast.Amount::new(@decimal.Decimal::zero(), "")
    {
      extra: Some(extra),
      date: @ast.Date::new(1, 1, 1).unwrap(),
      flag: "",
      payee: None,
      narration: "",
      tags: [],
      links: [],
      meta: @ast.Meta::new(),
      entry_meta: @ast.Meta::new(),
      accounts: [],
      account: "",
      units,
      cost: None,
      value: None,
      position: @booking.Position::new(units, None),
    }
  })
}

///|
fn parse_pivot_reference(
  parser : QueryParser,
  projections : Array[Expr],
  names : Array[String],
) -> Int32 {
  let expr = match parse_expr(parser) {
    Some(e) => e
    None => return 0
  }
  if expr is ENum(n) && n.scale() == 0 {
    let index = bql_parse_int(n.to_string())
    if index >= 1 && index <= projections.length() {
      return index - 1
    }
  } else if expr is ECol(name) {
    for i = names.length() - 1; i >= 0; i = i - 1 {
      if names[i] == name {
        return i
      }
    }
  }
  parser.fail("compilation query.invalid_reference: invalid PIVOT BY column")
  0
}

///|
fn pivot_result(
  ctx : QueryContext,
  query : SelectQuery,
  values : Array[Array[QueryValue]],
  row : Int32,
  column : Int32,
) -> QueryResult {
  if query.groups.is_empty() && !query.projections.any(contains_sum) {
    return {
      kind: Table,
      columns: [],
      rows: [],
      error: Some(
        "query.oracle_type_error: TypeError pivot requires grouping at BQL:1:1",
      ),
    }
  }
  let measures : Array[Int32] = []
  for i in 0..<query.names.length() {
    if i != row && i != column {
      measures.push(i)
    }
  }
  let row_keys : Map[String, QueryValue] = Map([])
  let column_keys : Map[String, QueryValue] = Map([])
  let cells : Map[String, Array[QueryValue]] = Map([])
  for cells_row in values {
    let r = distinct_key(cells_row[row])
    let c = distinct_key(cells_row[column])
    if !row_keys.contains(r) {
      row_keys.set(r, cells_row[row])
    }
    if !column_keys.contains(c) {
      column_keys.set(c, cells_row[column])
    }
    cells.set(r.length().to_string() + ":" + r + c, cells_row)
  }
  let rs = row_keys.keys().to_array()
  let cs = column_keys.keys().to_array()
  let compare = fn(keys : Map[String, QueryValue], a : String, b : String) {
    let x = keys.get(a).unwrap()
    let y = keys.get(b).unwrap()
    if (x is QNull) != (y is QNull) {
      query_error(
        ctx, "query.oracle_type_error: TypeError incomparable pivot keys at BQL:1:1",
      )
      0
    } else {
      typed_compare(ctx, x, y).unwrap_or(0)
    }
  }
  rs.sort_by(fn(a, b) { compare(row_keys, a, b) })
  cs.sort_by(fn(a, b) { compare(column_keys, a, b) })
  let columns = [query.names[row] + "/" + query.names[column]]
  for c in cs {
    let v = column_keys.get(c).unwrap()
    let label = match v {
      QNull => "None"
      QBool(b) => if b { "True" } else { "False" }
      _ => v.to_text()
    }
    for measure in measures {
      columns.push(
        label +
        (if measures.length() > 1 { "/" + query.names[measure] } else { "" }),
      )
    }
  }
  let rows : Array[Array[QueryValue]] = []
  for r in rs {
    let result = [row_keys.get(r).unwrap()]
    for c in cs {
      let found = cells.get(r.length().to_string() + ":" + r + c)
      for measure in measures {
        result.push(
          match found {
            Some(v) => v[measure]
            None => QNull
          },
        )
      }
    }
    rows.push(result)
  }
  { kind: Table, columns, rows, error: ctx.error, }
}

///|
fn resolve_quoted(expr : Expr, source : QuerySource) -> Expr {
  match expr {
    ECall("__quoted", [EStr(name)]) =>
      if column_type(source, name) != "unknown" {
        ECol(name)
      } else {
        EStr(name)
      }
    ECall(name, args) =>
      ECall(name, args.map(fn(e) { resolve_quoted(e, source) }))
    EBinary(a, op, b) =>
      EBinary(resolve_quoted(a, source), op, resolve_quoted(b, source))
    EPredicate(c) => EPredicate(resolve_quoted_condition(c, source))
    _ => expr
  }
}

///|
fn resolve_quoted_condition(cond : Cond, source : QuerySource) -> Cond {
  match cond {
    CTrue => CTrue
    CNot(c) => CNot(resolve_quoted_condition(c, source))
    CAnd(a, b) =>
      CAnd(
        resolve_quoted_condition(a, source),
        resolve_quoted_condition(b, source),
      )
    COr(a, b) =>
      COr(
        resolve_quoted_condition(a, source),
        resolve_quoted_condition(b, source),
      )
    CCmp(a, op, b) => {
      let a = resolve_quoted(a, source)
      let b = resolve_quoted(b, source)
      let ta = expression_type(a, source, [])
      let tb = expression_type(b, source, [])
      // The compiler casts dynamic metadata to the other operand's scalar type.
      CCmp(
        if ta == "object" && ["int", "decimal", "str", "date"].contains(tb) {
          ECall(tb, [a])
        } else {
          a
        },
        op,
        if tb == "object" && ["int", "decimal", "str", "date"].contains(ta) {
          ECall(ta, [b])
        } else {
          b
        },
      )
    }
    CIsNull(e, negated) => CIsNull(resolve_quoted(e, source), negated)
    CTruthy(e) => CTruthy(resolve_quoted(e, source))
    CRegex(e, pattern, regex) =>
      CRegex(resolve_quoted(e, source), pattern, regex)
  }
}
