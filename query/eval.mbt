// BQL evaluation over a realized ledger.  The engine works on a flat posting
// table (or an inventory-position table for FROM balances), supports a WHERE
// predicate, grouping with sum()/count(), ordering and LIMIT.

///|
priv struct BqlRow {
  date : @ast.Date
  mut extra : RowExtra?
  flag : String
  payee : String?
  narration : String
  tags : Array[String]
  links : Array[String]
  meta : @ast.Meta
  entry_meta : @ast.Meta
  accounts : Array[@ast.Posting]
  account : String
  units : @ast.Amount
  cost : @ast.Cost?
  value : @ast.Amount?
  position : @booking.Position
}

///|
fn posting_cost(posting : @ast.Posting, units : @ast.Amount) -> @ast.Cost? {
  match posting.cost {
    Some(spec) => {
      let currency = match spec.currency {
        Some(name) => name
        None => units.currency
      }
      let number = match spec.number_per {
        Some(per) => Some(per)
        None =>
          match spec.number_total {
            Some(total) =>
              if units.number.is_zero() {
                None
              } else {
                total.div(units.number)
              }
            None => None
          }
      }
      match number {
        Some(value) =>
          Some(@ast.Cost::new(value, currency, spec.date, spec.label))
        None => None
      }
    }
    None => None
  }
}

///|
fn posting_value(
  units : @ast.Amount,
  cost : @ast.Cost?,
  price : @ast.PriceAnno?,
) -> @ast.Amount? {
  match cost {
    Some(c) => Some(@ast.Amount::new(units.number.mul(c.number), c.currency))
    None =>
      match price {
        Some(@ast.PerUnit(amount)) =>
          Some(
            @ast.Amount::new(units.number.mul(amount.number), amount.currency),
          )
        Some(@ast.Total(amount)) =>
          Some(
            @ast.Amount::new(
              if units.number.is_negative() {
                amount.number.abs().neg()
              } else {
                amount.number.abs()
              },
              amount.currency,
            ),
          )
        None => None
      }
  }
}

///|
fn last_entry_date(realized : @realization.RealizedLedger) -> @ast.Date? {
  let mut latest : @ast.Date? = None
  for entry in realized.entries {
    latest = match latest {
      Some(date) =>
        if date.less_than(entry.date) {
          Some(entry.date)
        } else {
          Some(date)
        }
      None => Some(entry.date)
    }
  }
  latest
}

///|
fn posting_rows(
  realized : @realization.RealizedLedger,
  origin : Bool,
) -> Array[BqlRow] {
  let rows : Array[BqlRow] = []
  for entry in realized.entries {
    match entry.directive {
      DTransaction(txn) =>
        for posting in booked_postings(txn.postings) {
          match posting.units {
            Some(units) => {
              let cost = posting_cost(posting, units)
              rows.push({
                extra: if origin {
                  Some(new_row_extra(Some(entry), None, Some(posting)))
                } else {
                  None
                },
                date: entry.date,
                flag: txn.flag,
                payee: txn.payee,
                narration: txn.narration,
                tags: txn.tags,
                links: txn.links,
                meta: posting.meta,
                entry_meta: entry.meta,
                accounts: txn.postings,
                account: posting.account,
                units,
                cost,
                value: posting_value(units, cost, posting.price),
                position: @booking.Position::new(units, cost),
              })
            }
            None => ()
          }
        }
      _ => ()
    }
  }
  rows
}

///|
fn balance_rows(realized : @realization.RealizedLedger) -> Array[BqlRow] {
  let rows : Array[BqlRow] = []
  let date = match realized.at {
    Some(at) => at
    None =>
      match last_entry_date(realized) {
        Some(latest) => latest
        None => @ast.Date::new(1970, 1, 1).unwrap()
      }
  }
  for account in realized.account_names() {
    for position in realized.inventory(account).positions {
      rows.push({
        extra: None,
        date,
        flag: "",
        payee: None,
        narration: "",
        tags: [],
        links: [],
        meta: @ast.Meta::new(),
        entry_meta: @ast.Meta::new(),
        accounts: [],
        account,
        units: position.units,
        cost: position.cost,
        value: posting_value(position.units, position.cost, None),
        position,
      })
    }
  }
  rows
}

///|
fn source_rows(
  realized : @realization.RealizedLedger,
  source : QuerySource,
  origin : Bool,
) -> Array[BqlRow] {
  match source {
    SrcPostings | SrcFrom(_, _, _, _, _) => posting_rows(realized, origin)
    SrcTransactions => transaction_rows(realized, origin)
    SrcBalances => balance_rows(realized)
    SrcDirectives(table) => directive_rows(realized, table)
    SrcOpen(start, close) => opening_rows(realized, start, close)
    SrcClose(date) =>
      posting_rows(realized, origin).filter(fn(row) { row.date.less_than(date) })
    SrcRelation(_) => [] // Materialized by run_select, with error propagation.
  }
}

///|
fn eval_column(ctx : QueryContext, row : BqlRow, name : String) -> QueryValue {
  if row.extra is Some(extra) && extra.cells is Some(cells) {
    return cells.get(name).unwrap_or(QNull)
  }
  if row.extra is Some(extra) &&
    extra.entry is Some(entry) &&
    extra.source is Some(table) {
    return directive_column(ctx, entry, name, table)
  }
  match name {
    "balance" => running_balance(ctx, row)
    "entry" | "id" =>
      match row_entry(row) {
        Some(entry) => {
          let value = directive_value(entry)
          if name == "id" {
            QText(directive_identity(value))
          } else {
            value
          }
        }
        None => {
          query_error(ctx, "unsupported query.unsupported.synthetic_origin")
          QNull
        }
      }
    "meta" =>
      if row_posting(row) is Some(p) {
        posting_metadata(p)
      } else {
        match row_entry(row) {
          Some(entry) => entry_metadata(entry)
          None => {
            query_error(ctx, "unsupported query.unsupported.synthetic_metadata")
            QNull
          }
        }
      }
    "type" => QText("transaction")
    "filename" | "lineno" | "location" =>
      match row_entry(row) {
        Some(e) =>
          if row_posting(row) is Some(p) && p.loc.file == "" && p.loc.line == 0 {
            QNull
          } else if name == "filename" {
            QText(
              row_posting(row)
              .map(fn(p) { p.loc.file })
              .unwrap_or(query_location(e).file),
            )
          } else if name == "lineno" {
            QInt(
              @bigint.BigInt::from_int(
                row_posting(row)
                .map(fn(p) { p.loc.line })
                .unwrap_or(query_location(e).line),
              ),
            )
          } else {
            QText(
              row_posting(row)
              .map(fn(p) { p.loc.file + ":" + p.loc.line.to_string() + ":" })
              .unwrap_or(
                query_location(e).file +
                ":" +
                query_location(e).line.to_string() +
                ":",
              ),
            )
          }
        None => {
          query_error(ctx, "unsupported query.unsupported.synthetic_origin")
          QNull
        }
      }
    "posting_flag" =>
      match row_posting(row) {
        Some(p) =>
          match p.flag {
            Some(s) => QText(s)
            None => QNull
          }
        None => QNull
      }
    "other_accounts" =>
      QSet(
        transaction_accounts(row.accounts).filter(fn(a) { a != row.account }),
      )
    "number" => QNumber(row.units.number)
    "cost_number" =>
      match row.cost {
        Some(c) => QNumber(c.number)
        None => QNull
      }
    "cost_currency" =>
      match row.cost {
        Some(c) => QText(c.currency)
        None => QNull
      }
    "cost_date" =>
      match row.cost {
        Some(c) =>
          match c.date {
            Some(d) => QDate(d)
            None => QNull
          }
        None => QNull
      }
    "cost_label" =>
      QText(row.cost.map(fn(c) { c.label.unwrap_or("") }).unwrap_or(""))
    "price" =>
      match row_posting(row) {
        Some(p) => posting_price(p)
        None => QNull
      }
    "date" => QDate(row.date)
    "year" => query_int(row.date.year)
    "month" => query_int(row.date.month)
    "day" => query_int(row.date.day)
    "flag" => QText(row.flag)
    "payee" =>
      match row.payee {
        Some(s) => QText(s)
        None => QNull
      }
    "description" =>
      QText(
        match row.payee {
          Some(p) =>
            if p == "" {
              row.narration
            } else {
              p + " | " + row.narration
            }
          None => row.narration
        },
      )
    "narration" => QText(row.narration)
    "tags" => QSet(row.tags)
    "links" => QSet(row.links)
    "accounts" => QSet(transaction_accounts(row.accounts))
    "account" => QText(row.account)
    "root" => QText(@ast.account_root(row.account))
    "parent" => QText(@ast.account_parent(row.account))
    "leaf" => QText(@ast.account_leaf(row.account))
    "units" => QAmount(row.units)
    "currency" => QText(row.units.currency)
    "weight" => QAmount(row.value.unwrap_or(row.units))
    "cost" =>
      match row.cost {
        Some(cost) => QAmount(@ast.Amount::new(cost.number, cost.currency))
        None => QNull
      }
    "value" =>
      match row.value {
        Some(amount) => QAmount(amount)
        None => QNull
      }
    "position" => QPosition(row.position)
    _ => QNull
  }
}

///|
fn eval_expr(ctx : QueryContext, expr : Expr, row : BqlRow) -> QueryValue {
  match expr {
    EPredicate(cond) =>
      eval_predicate(ctx, cond, fn(e) { eval_expr(ctx, e, row) })
    EValue(value) => value
    EBinary(left, op, right) =>
      arithmetic(ctx, eval_expr(ctx, left, row), op, eval_expr(ctx, right, row))
    ECol(name) => eval_column(ctx, row, name)
    EStr(text) => QText(text)
    ENum(number) =>
      if number.scale() == 0 {
        QInt(number.mantissa())
      } else {
        QNumber(number)
      }
    EDate(date) => QDate(date)
    ENull => QNull
    EStar => QNull
    EBool(value) => QBool(value)
    ECall(name, args) =>
      match (name, args) {
        ("meta" | "entry_meta", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QText(key) => {
              if row.extra is Some(extra) && extra.cells is Some(cells) {
                let metadata = if name == "meta" {
                  cells.get("meta").unwrap_or(QNull)
                } else {
                  record_metadata(ctx, cells.get("entry").unwrap_or(QNull))
                }
                return dict_get(metadata, key).unwrap_or(QNull)
              }
              let metadata = if name == "meta" && row_posting(row) is Some(p) {
                QDict(source_metadata(p.loc, p.meta))
              } else {
                match row_entry(row) {
                  Some(e) => entry_metadata(e)
                  None =>
                    QDict(
                      (if name == "entry_meta" {
                        row.entry_meta
                      } else {
                        row.meta
                      }).entries.map(fn(p) { (p.0, meta_value(p.1)) }),
                    )
                }
              }
              dict_get(metadata, key).unwrap_or(QNull)
            }
            _ => QNull
          }
        ("getitem", [dict, key]) | ("getitem", [dict, key, _]) =>
          match (eval_expr(ctx, dict, row), eval_expr(ctx, key, row)) {
            (value, QText(k)) =>
              match dict_get(value, k) {
                Some(v) => v
                None =>
                  if args.length() == 3 {
                    eval_expr(ctx, args[2], row)
                  } else {
                    QNull
                  }
              }
            _ => QNull
          }
        ("upper" | "lower", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QText(s) => QText(unicode_case(s, name == "upper"))
            _ => QNull
          }
        ("length", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QSet(v) | QFrozenSet(v) => query_int(v.length())
            QList(v) => query_int(v.length())
            QText(s) => query_int(s.iter().count())
            _ => QNull
          }
        ("substr", [arg, start, end]) =>
          match eval_expr(ctx, arg, row) {
            QText(s) => {
              let chars = s.iter().to_array()
              let size = chars.length()
              let a = slice_index(ctx, start, row, size)
              let b = slice_index(ctx, end, row, size)
              let sb = StringBuilder()
              for i in a..<b {
                sb.write_char(chars[i])
              }
              QText(sb.to_string())
            }
            _ => QNull
          }
        ("year", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QDate(date) => query_int(date.year)
            _ => QNull
          }
        ("month", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QDate(date) => query_int(date.month)
            _ => QNull
          }
        ("root", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QText(account) => QText(@ast.account_root(account))
            _ => QNull
          }
        ("parent", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QText(account) => QText(@ast.account_parent(account))
            _ => QNull
          }
        ("leaf", [arg]) =>
          match eval_expr(ctx, arg, row) {
            QText(account) => QText(@ast.account_leaf(account))
            _ => QNull
          }
        _ =>
          eval_function(
            ctx,
            name,
            args.map(fn(arg) { eval_expr(ctx, arg, row) }),
            row,
          )
      }
  }
}

///|
fn cond_holds(ctx : QueryContext, cond : Cond, row : BqlRow) -> Bool {
  match cond {
    CRegex(e, _, regex) =>
      match eval_expr(ctx, e, row) {
        QText(s) => regex.execute(s) is Some(_)
        _ => false
      }
    CTrue => true
    CNot(inner) => !cond_holds(ctx, inner, row)
    CAnd(left, right) =>
      cond_holds(ctx, left, row) && cond_holds(ctx, right, row)
    COr(left, right) =>
      cond_holds(ctx, left, row) || cond_holds(ctx, right, row)
    CIsNull(expr, negated) => {
      let is_null = eval_expr(ctx, expr, row) is QNull
      if negated {
        !is_null
      } else {
        is_null
      }
    }
    CTruthy(expr) =>
      match eval_expr(ctx, expr, row) {
        QSet(values) | QFrozenSet(values) => values.length() > 0
        QNull => false
        QText(text) => text != ""
        QNegativeZero(_) => false
        QNumber(number) => !number.is_zero()
        QAmount(amount) => !amount.number.is_zero()
        QPosition(position) => !position.units.number.is_zero()
        QInventory(inventory) => !inventory.is_empty()
        QBool(b) => b
        QInt(n) => n.to_string() != "0"
        QDict(v) | QRecord(_, v) => !v.is_empty()
        QList(v) => !v.is_empty()
        QEnum(_, _) | QPythonType(_) => true
        QInterval(_, n) => n != @bigint.BigInt::from_int(0)
        QDate(_) => true
      }
    CCmp(left, op, right) =>
      truth(
        query_comparison(
          ctx,
          eval_expr(ctx, left, row),
          op,
          eval_expr(ctx, right, row),
        ),
      )
  }
}

///|
fn expr_label(expr : Expr) -> String {
  match expr {
    EPredicate(c) => condition_label(c)
    EValue(value) => value.to_text()
    EBinary(left, op, right) => expr_label(left) + op + expr_label(right)
    ECol(name) => name
    EStr(text) => "\"" + text + "\""
    ENum(number) => number.to_string()
    EDate(date) => date.to_string()
    ENull => "null"
    EStar => "*"
    EBool(value) => if value { "true" } else { "false" }
    ECall(name, args) => {
      let sb = StringBuilder()
      sb.write_string(name)
      for i in 0..<args.length() {
        sb.write_string("_")
        sb.write_string(expr_label(args[i]))
      }
      sb.to_string()
    }
  }
}

///|
fn contains_sum(expr : Expr) -> Bool {
  match expr {
    EPredicate(c) => !aggregate_free_cond(c)
    EBinary(left, _, right) => contains_sum(left) || contains_sum(right)
    ECall("sum" | "count" | "first" | "last" | "min" | "max", _) => true
    ECall(_, args) => {
      for arg in args {
        if contains_sum(arg) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn sum_amounts(values : Array[@ast.Amount]) -> QueryValue {
  if values.length() == 0 {
    return QNull
  }
  let sums : Array[@ast.Amount] = []
  for value in values {
    let mut found = false
    for i in 0..<sums.length() {
      if sums[i].currency == value.currency {
        sums[i] = @ast.Amount::new(
          sums[i].number.add(value.number),
          value.currency,
        )
        found = true
      }
    }
    if !found {
      sums.push(value)
    }
  }
  if sums.length() == 1 {
    QAmount(sums[0])
  } else {
    let inventory = @booking.Inventory::new()
    for amount in sums {
      inventory.add_amount(amount)
    }
    QInventory(inventory)
  }
}

///|
fn eval_aggregate(
  ctx : QueryContext,
  expr : Expr,
  rows : Array[BqlRow],
) -> QueryValue {
  match expr {
    ECall("first" | "last" | "min" | "max", [arg]) => {
      let mut result = QNull
      for row in rows {
        let value = eval_expr(ctx, arg, row)
        if expr is ECall("last", _) {
          result = value
          continue
        }
        if value is QNull {
          continue
        }
        if result is QNull {
          result = value
          continue
        }
        match expr {
          ECall("min" | "max", _) =>
            if aggregate_precedes(ctx, value, result, expr is ECall("max", _)) {
              result = value
            }
          _ => ()
        }
      }
      result
    }
    ECall("count", args) => {
      let count = if args is [EStar] {
        rows.length()
      } else if args is [arg] {
        rows.filter(fn(row) { !(eval_expr(ctx, arg, row) is QNull) }).length()
      } else {
        0
      }
      query_int(count)
    }
    ECall("sum", [arg]) =>
      match arg {
        ECol("amount") => {
          let inventory = @booking.Inventory::new()
          for row in rows {
            if eval_expr(ctx, arg, row) is QAmount(amount) {
              inventory.add_amount(amount)
            }
          }
          QInventory(inventory)
        }
        ECol("position") => {
          let inventory = @booking.Inventory::new()
          for row in rows {
            inventory.add(row.position)
          }
          QInventory(inventory)
        }
        ECol("weight") => {
          let values : Array[@ast.Amount] = []
          for row in rows {
            if eval_column(ctx, row, "weight") is QAmount(a) {
              values.push(a)
            }
          }
          sum_amounts(values)
        }
        ECol("units") => {
          let values : Array[@ast.Amount] = []
          for row in rows {
            values.push(row.units)
          }
          sum_amounts(values)
        }
        ECol("cost") => {
          let values : Array[@ast.Amount] = []
          for row in rows {
            match row.cost {
              Some(cost) =>
                values.push(@ast.Amount::new(cost.number, cost.currency))
              None => ()
            }
          }
          sum_amounts(values)
        }
        ECol("value") => {
          let values : Array[@ast.Amount] = []
          for row in rows {
            match row.value {
              Some(amount) => values.push(amount)
              None => ()
            }
          }
          sum_amounts(values)
        }
        _ => {
          let kind = expression_type(arg, ctx.source, [])
          let inventory = @booking.Inventory::new()
          let mut total = @decimal.Decimal::zero()
          let mut integer_total = @bigint.BigInt::from_int(0)
          for row in rows {
            match eval_expr(ctx, arg, row) {
              QAmount(a) => inventory.add_amount(a)
              QPosition(p) => inventory.add(p)
              QInventory(i) =>
                for p in i.positions {
                  inventory.add(p)
                }
              QInt(n) => integer_total = integer_total.add(n)
              QNegativeZero(scale) =>
                total = total.add(@decimal.Decimal::zero_scaled(scale))
              QNumber(n) => total = total.add(n)
              QBool(b) =>
                if b {
                  integer_total = integer_total.add(@bigint.BigInt::from_int(1))
                }
              _ => ()
            }
          }
          if ["amount", "position", "inventory"].contains(kind) {
            QInventory(inventory)
          } else if kind == "int" || kind == "bool" {
            QInt(integer_total)
          } else {
            QNumber(total)
          }
        }
      }
    _ => QNull
  }
}

///|
fn eval_grouped(
  ctx : QueryContext,
  expr : Expr,
  rows : Array[BqlRow],
) -> QueryValue {
  if expr is EPredicate(cond) {
    eval_predicate(ctx, cond, fn(e) { eval_grouped(ctx, e, rows) })
  } else if expr is EBinary(left, op, right) {
    arithmetic(
      ctx,
      eval_grouped(ctx, left, rows),
      op,
      eval_grouped(ctx, right, rows),
    )
  } else if expr is ECall(name, args) && contains_sum(expr) {
    if ["sum", "count", "first", "last", "min", "max"].contains(name) {
      eval_aggregate(ctx, expr, rows)
    } else if !rows.is_empty() {
      eval_expr(
        ctx,
        ECall(
          name,
          args.map(fn(arg) {
            if contains_sum(arg) {
              EValue(eval_grouped(ctx, arg, rows))
            } else {
              arg
            }
          }),
        ),
        ctx.aggregate_row.unwrap_or_else(fn() { rows[0] }),
      )
    } else {
      QNull
    }
  } else if rows.length() > 0 {
    eval_expr(ctx, expr, ctx.aggregate_row.unwrap_or_else(fn() { rows[0] }))
  } else {
    QNull
  }
}

///|
priv struct OutputRow {
  values : Array[QueryValue]
  group : Array[BqlRow]
}

///|
fn group_key(ctx : QueryContext, exprs : Array[Expr], row : BqlRow) -> String {
  let sb = StringBuilder()
  for expr in exprs {
    let value = eval_expr(ctx, expr, row)
    sb.write_string(
      match value {
        QBool(b) => if b { "1" } else { "0" }
        QText(text) => "s" + text.length().to_string() + ":" + text
        QSet(_) | QFrozenSet(_) => distinct_key(value)
        QPosition(p) => position_group_key(p)
        QDict(_)
        | QRecord(_, _)
        | QList(_)
        | QInventory(_)
        | QEnum(_, _)
        | QPythonType(_) => {
          query_error(
            ctx, "query.oracle_type_error: TypeError unhashable structural value",
          )
          ""
        }
        QNegativeZero(scale) =>
          decimal_group_key(@decimal.Decimal::zero_scaled(scale))
        QNumber(n) => decimal_group_key(n)
        QAmount(a) => "amount:" + a.currency + ":" + decimal_group_key(a.number)
        _ => value.to_json()
      },
    )
    sb.write_string("\u{1f}")
  }
  sb.to_string()
}

///|
fn build_output(
  ctx : QueryContext,
  query : SelectQuery,
  rows : Array[BqlRow],
) -> Array[OutputRow] {
  let outputs : Array[OutputRow] = []
  let any_aggregate = {
    let mut found = false
    for projection in query.projections {
      if contains_sum(projection) {
        found = true
      }
    }
    found
  }
  if query.groups.length() == 0 && !any_aggregate {
    for row in rows {
      let values : Array[QueryValue] = []
      for projection in query.projections {
        values.push(eval_expr(ctx, projection, row))
      }
      outputs.push({ values, group: [row], })
    }
    return outputs
  }
  if rows.is_empty() {
    return outputs
  }
  let groups : Map[String, Array[BqlRow]] = Map([])
  let order : Array[String] = []
  if query.groups.length() == 0 {
    order.push("")
    groups.set("", rows)
  } else {
    for row in rows {
      let key = group_key(ctx, query.groups, row)
      match groups.get(key) {
        Some(bucket) => bucket.push(row)
        None => {
          groups.set(key, [row])
          order.push(key)
        }
      }
    }
  }
  for key in order {
    let bucket = match groups.get(key) {
      Some(found) => found
      None => []
    }
    let values : Array[QueryValue] = []
    for projection in query.projections {
      values.push(eval_grouped(ctx, projection, bucket))
    }
    outputs.push({ values, group: bucket, })
  }
  outputs
}

///|
fn sort_outputs(
  ctx : QueryContext,
  outputs : Array[OutputRow],
  orders : Array[OrderSpec],
  projections : Array[Expr],
) -> Unit {
  if orders.is_empty() || outputs.is_empty() {
    return
  }
  let projected = orders.map(fn(spec) {
    if spec.expr is ECol(name) {
      for i in 0..<projections.length() {
        if projections[i] is ECol(other) && name == other {
          return i
        }
      }
    }
    -1
  })
  let reuse = projected.all(fn(i) { i >= 0 })
  let keys = outputs.map(fn(output) {
    if reuse {
      output.values
    } else {
      let values : Array[QueryValue] = []
      for i in 0..<orders.length() {
        values.push(
          if projected[i] >= 0 {
            output.values[projected[i]]
          } else {
            let saved = ctx.aggregate_row
            if !contains_sum(orders[i].expr) {
              ctx.aggregate_row = None
            }
            let value = eval_grouped(ctx, orders[i].expr, output.group)
            ctx.aggregate_row = saved
            value
          },
        )
      }
      values
    }
  })
  if outputs.length() < 2 || ctx.error is Some(_) {
    return
  }
  let indices : Array[Int32] = []
  for i in 0..<outputs.length() {
    indices.push(i)
  }
  indices.sort_by(fn(a, b) {
    for i in 0..<orders.length() {
      let slot = if reuse { projected[i] } else { i }
      let order = sort_value_compare(ctx, keys[a][slot], keys[b][slot])
      if order != 0 {
        return if orders[i].descending { -order } else { order }
      }
    }
    a.compare(b)
  })
  let original = outputs.copy()
  for i in 0..<indices.length() {
    outputs[i] = original[indices[i]]
  }
}

///|
fn sort_value_compare(
  ctx : QueryContext,
  a : QueryValue,
  b : QueryValue,
) -> Int32 {
  match (a, b) {
    (QNull, QNull) => 0
    (QNull, _) => -1
    (_, QNull) => 1
    (QAmount(a), QAmount(b)) => {
      let currency = a.currency.lexical_compare(b.currency)
      if currency == 0 {
        a.number.compare(b.number)
      } else {
        currency
      }
    }
    (QPosition(a), QPosition(b)) => position_sort_compare(a, b)
    (QSet(_) | QFrozenSet(_), _) | (_, QSet(_) | QFrozenSet(_)) => {
      query_error(
        ctx, "unsupported query.unsupported.set_order: partial set ordering",
      )
      0
    }
    _ =>
      match typed_compare(ctx, a, b) {
        Some(order) => order
        None => {
          if ctx.error is None {
            query_error(
              ctx, "query.oracle_type_error: TypeError incomparable sort keys",
            )
          }
          0
        }
      }
  }
}

///|
fn run_select(
  realized : @realization.RealizedLedger,
  query : SelectQuery,
  diagnostics : Array[@ast.Diagnostic],
) -> QueryResult {
  if (query.distinct || query_any(query, representation_expr)) &&
    realized.entries.any(fn(e) { !e.query_exact_decimal }) {
    return {
      kind: Table,
      columns: [],
      rows: [],
      error: Some(
        "unsupported query.unsupported.decimal_representation: source contains signed zero; exact metadata/fingerprint representation unavailable",
      ),
    }
  }
  let ctx = QueryContext::new(realized, query.source)
  let from_filter = match query.source {
    SrcFrom(c, _, _, _, _) => c
    _ => CTrue
  }
  let origin = query_any(query, origin_expr) ||
    cond_any(from_filter, origin_expr)
  let source_realized = if query.source is SrcFrom(_, _, _, _, _) {
    {
      ..realized,
      entries: print_period(
        realized,
        print_recovered_entries(realized.entries, diagnostics),
        query.source,
      ),
    }
  } else {
    realized
  }
  let running = query_any(query, fn(e) { e is ECol("balance") })
  let all_rows = if query.source is SrcRelation(inner) {
    if inner.pivot is Some(_) {
      return {
        kind: Table,
        columns: [],
        rows: [],
        error: Some(
          "query.oracle_type_error: AttributeError pivot relation schema at BQL:1:1",
        ),
      }
    }
    let relation = run_select(realized, inner, diagnostics)
    if relation.error is Some(_) {
      return relation
    }
    relation_rows(inner.names, relation.rows)
  } else {
    source_rows(source_realized, query.source, origin)
  }
  let rows : Array[BqlRow] = []
  for row in all_rows {
    if cond_holds(ctx, from_filter, row) && cond_holds(ctx, query.filter, row) {
      if running {
        running_balance(ctx, row) |> ignore
      }
      rows.push(row)
    }
  }
  let built = build_output(ctx, query, rows)
  ctx.aggregate_row = all_rows.last()
  let mut outputs = built.filter(fn(output) {
    grouped_cond(ctx, query.having, output.group)
  })
  sort_outputs(ctx, outputs, query.orders, query.projections)
  if query.distinct {
    let unique : Array[OutputRow] = []
    let seen : Map[String, Bool] = Map([])
    for output in outputs {
      let key = output.values
        .map(distinct_key)
        .map(fn(s) { s.length().to_string() + ":" + s })
        .join("")
      if !seen.contains(key) {
        seen.set(key, true)
        unique.push(output)
      }
    }
    outputs = unique
  }
  match query.limit {
    Some(limit) =>
      if outputs.length() > limit {
        let truncated : Array[OutputRow] = []
        for i in 0..<limit {
          truncated.push(outputs[i])
        }
        outputs = truncated
      }
    None => ()
  }
  let columns = query.labels
  let result_rows : Array[Array[QueryValue]] = []
  for output in outputs {
    result_rows.push(output.values)
  }
  let result = { kind: Table, columns, rows: result_rows, error: ctx.error, }
  if query.pivot is Some((row, column)) && ctx.error is None {
    pivot_result(ctx, query, result_rows, row, column)
  } else {
    result
  }
}

///|
fn journal_row(entry : @ast.Entry, posting : @ast.Posting) -> BqlRow? {
  match posting.units {
    Some(units) => {
      let cost = posting_cost(posting, units)
      Some({
        extra: None,
        date: entry.date,
        flag: "",
        payee: None,
        narration: "",
        tags: [],
        links: [],
        meta: @ast.Meta::new(),
        entry_meta: @ast.Meta::new(),
        accounts: [],
        account: posting.account,
        units,
        cost,
        value: posting_value(units, cost, posting.price),
        position: @booking.Position::new(units, cost),
      })
    }
    None => None
  }
}

///|
fn run_journal(
  realized : @realization.RealizedLedger,
  account : String,
  limit : Int32?,
) -> QueryResult {
  let columns = ["date", "flag", "payee", "narration", "account", "position"]
  let rows : Array[Array[QueryValue]] = []
  for entry in realized.entries {
    match entry.directive {
      DTransaction(txn) =>
        for posting in booked_postings(txn.postings) {
          if posting.account == account ||
            @realization.is_subaccount(posting.account, account) {
            match journal_row(entry, posting) {
              Some(row) => {
                let done = match limit {
                  Some(max) => rows.length() >= max
                  None => false
                }
                if done {
                  break
                }
                rows.push([
                  QDate(entry.date),
                  QText(txn.flag),
                  match txn.payee {
                    Some(payee) => QText(payee)
                    None => QNull
                  },
                  QText(txn.narration),
                  QText(posting.account),
                  QPosition(row.position),
                ])
              }
              None => ()
            }
          }
        }
      _ => ()
    }
  }
  { kind: Table, columns, rows, error: None, }
}

///|
pub fn run_query(
  realized : @realization.RealizedLedger,
  text : String,
  diagnostics~ : Array[@ast.Diagnostic] = [],
) -> QueryResult {
  match parse_query(text) {
    PqError(message) =>
      { kind: Table, columns: [], rows: [], error: Some(message), }
    PqSelect(query) => run_select(realized, query, diagnostics)
    PqPrint(filter, period) => run_print(realized, filter, period, diagnostics)
    PqJournal(account, limit) => run_journal(realized, account, limit)
  }
}

///|
fn arithmetic(
  ctx : QueryContext,
  a : QueryValue,
  op : String,
  b : QueryValue,
) -> QueryValue {
  if a is QInt(x) && b is QInt(y) {
    match op {
      "+" => return QInt(x.add(y))
      "-" => return QInt(x.sub(y))
      "*" => return QInt(x.mul(y))
      "%" => {
        if y == @bigint.BigInt::from_int(0) {
          return QNull
        }
        let remainder = x % y
        return QInt(
          if remainder != @bigint.BigInt::from_int(0) &&
            (x < @bigint.BigInt::from_int(0)) !=
            (y < @bigint.BigInt::from_int(0)) {
            remainder.add(y)
          } else {
            remainder
          },
        )
      }
      _ => ()
    }
  }
  match (value_number(a), value_number(b)) {
    (Some(x), Some(y)) => {
      let result = match op {
        "+" => Some(x.add(y))
        "-" => Some(x.sub(y))
        "*" => Some(x.mul(y))
        "/" =>
          if x.is_zero() && !y.is_zero() {
            Some(@decimal.Decimal::zero_scaled(x.scale() - y.scale()))
          } else {
            x.div(y)
          }
        "%" => decimal_modulo(ctx, x, y)
        _ => None
      }
      match result {
        Some(n) =>
          if n.is_zero() && (a is QNegativeZero(_) || b is QNegativeZero(_)) {
            let negative_a = a is QNegativeZero(_) || x.is_negative()
            let negative_b = b is QNegativeZero(_) || y.is_negative()
            let negative = match op {
              "*" | "/" => negative_a != negative_b
              "+" => negative_a && negative_b
              "-" => negative_a && !negative_b
              "%" => negative_a
              _ => false
            }
            if negative {
              QNegativeZero(n.scale())
            } else {
              QNumber(n)
            }
          } else if n.is_zero() && op == "%" && x.is_negative() {
            QNegativeZero(n.scale())
          } else if n.is_zero() &&
            (op == "*" || op == "/") &&
            x.is_negative() != y.is_negative() &&
            !(a is QInt(_) && b is QInt(_) && op != "/") {
            QNegativeZero(n.scale())
          } else if a is QInt(_) && b is QInt(_) && op != "/" {
            QInt(n.mantissa())
          } else {
            QNumber(n)
          }
        None => QNull
      }
    }
    _ => QNull
  }
}

///|
fn grouped_cond(ctx : QueryContext, cond : Cond, rows : Array[BqlRow]) -> Bool {
  match cond {
    CRegex(e, _, regex) =>
      match eval_grouped(ctx, e, rows) {
        QText(s) => regex.execute(s) is Some(_)
        _ => false
      }
    CTrue => true
    CNot(c) => !grouped_cond(ctx, c, rows)
    CAnd(a, b) => grouped_cond(ctx, a, rows) && grouped_cond(ctx, b, rows)
    COr(a, b) => grouped_cond(ctx, a, rows) || grouped_cond(ctx, b, rows)
    CIsNull(e, negated) => (eval_grouped(ctx, e, rows) is QNull) != negated
    CTruthy(e) =>
      match eval_grouped(ctx, e, rows) {
        QBool(b) => b
        QNegativeZero(_) => false
        QNumber(n) => !n.is_zero()
        QNull => false
        _ => true
      }
    CCmp(a, op, b) =>
      truth(
        query_comparison(
          ctx,
          eval_grouped(ctx, a, rows),
          op,
          eval_grouped(ctx, b, rows),
        ),
      )
  }
}

///|
fn opening_rows(
  realized : @realization.RealizedLedger,
  start : @ast.Date,
  close : @ast.Date?,
) -> Array[BqlRow] {
  let inventories : Map[String, @booking.Inventory] = Map([])
  let names : Array[String] = []
  let rows : Array[BqlRow] = []
  for row in posting_rows(realized, false) {
    if row.date.less_than(start) {
      let root = @ast.account_root(row.account)
      let account = if root == "Income" || root == "Expenses" {
        realized.options.equity_account(
          "account_previous_earnings", "Earnings:Previous",
        )
      } else {
        row.account
      }
      let inventory = match inventories.get(account) {
        Some(i) => i
        None => {
          let i = @booking.Inventory::new()
          inventories.set(account, i)
          names.push(account)
          i
        }
      }
      inventory.add(row.position)
    } else {
      let in_period = match close {
        Some(date) => row.date.less_than(date)
        None => true
      }
      if in_period {
        rows.push(row)
      }
    }
  }
  let date = if start.day > 1 {
    @ast.Date::new(start.year, start.month, start.day - 1).unwrap()
  } else {
    let year = if start.month == 1 { start.year - 1 } else { start.year }
    let month = if start.month == 1 { 12 } else { start.month - 1 }
    @ast.Date::new(year, month, @ast.Date::days_in_month(year, month)).unwrap()
  }
  let summaries : Array[BqlRow] = []
  names.sort()
  for account in names {
    let inventory = inventories.get(account).unwrap()
    for position in inventory.positions {
      let narration = "Opening balance for '" + account + "' (Summarization)"
      let row : BqlRow = {
        extra: None,
        date,
        flag: "S",
        payee: None,
        narration,
        tags: [],
        links: [],
        meta: @ast.Meta::new(),
        entry_meta: @ast.Meta::new(),
        accounts: [],
        account,
        units: position.units,
        cost: position.cost,
        value: posting_value(position.units, position.cost, None),
        position,
      }
      summaries.push(row)
      let amount = match position.cost {
        Some(c) =>
          @ast.Amount::new(
            position.units.number.mul(c.number).neg(),
            c.currency,
          )
        None =>
          @ast.Amount::new(position.units.number.neg(), position.units.currency)
      }
      summaries.push({
        ..row,
        account: realized.options.equity_account(
          "account_previous_balances", "Opening-Balances",
        ),
        units: amount,
        cost: None,
        value: None,
        position: @booking.Position::new(amount, None),
      })
    }
  }
  summaries + rows
}

///|
fn slice_index(
  ctx : QueryContext,
  expr : Expr,
  row : BqlRow,
  size : Int32,
) -> Int32 {
  let value = eval_expr(ctx, expr, row)
  let raw = match value {
    QBool(b) => if b { "1" } else { "0" }
    _ => value.to_text()
  }
  // Clamp before conversion, avoiding overflow for arbitrarily large indices.
  let number = @decimal.Decimal::parse(raw).unwrap()
  let bound = @decimal.Decimal::from_int(size)
  if number.compare(bound) >= 0 {
    return size
  }
  if number.compare(bound.neg()) <= 0 {
    return 0
  }
  let negative = raw.has_prefix("-")
  let mut index = 0
  for c in raw.iter() {
    if c.is_ascii_digit() {
      index = index * 10 + c.to_int() - 48
    }
  }
  if negative {
    size - index
  } else {
    index
  }
}

///|
fn transaction_rows(
  realized : @realization.RealizedLedger,
  origin : Bool,
) -> Array[BqlRow] {
  let rows : Array[BqlRow] = []
  for entry in realized.entries {
    if entry.directive is DTransaction(txn) {
      // Posting-only columns are rejected before evaluation for this source.
      let units = @ast.Amount::new(@decimal.Decimal::zero(), "")
      rows.push({
        extra: if origin {
          Some(new_row_extra(Some(entry), None, None))
        } else {
          None
        },
        date: entry.date,
        flag: txn.flag,
        payee: txn.payee,
        narration: txn.narration,
        tags: txn.tags,
        links: txn.links,
        meta: entry.meta,
        entry_meta: entry.meta,
        accounts: txn.postings,
        account: "",
        units,
        cost: None,
        value: None,
        position: @booking.Position::new(units, None),
      })
    }
  }
  rows
}

///|
fn transaction_accounts(postings : Array[@ast.Posting]) -> Array[String] {
  let accounts : Array[String] = []
  for posting in postings {
    if !accounts.contains(posting.account) {
      accounts.push(posting.account)
    }
  }
  accounts
}

///|
fn distinct_key(value : QueryValue) -> String {
  match value {
    QInt(n) => "n:" + n.to_string()
    QNegativeZero(scale) =>
      "n:" + decimal_group_key(@decimal.Decimal::zero_scaled(scale))
    QNumber(n) => "n:" + decimal_group_key(n)
    QBool(b) => if b { "n:1" } else { "n:0" }
    QSet(s) | QFrozenSet(s) => {
      let sorted = s.copy()
      sorted.sort_by(fn(a, b) { a.lexical_compare(b) })
      "set:" + sorted.map(fn(s) { s.length().to_string() + ":" + s }).join("")
    }
    QPosition(_) | QAmount(_) => "repr:" + value.to_text()
    _ => value.to_json()
  }
}

///|
fn directive_type(entry : @ast.Entry) -> String {
  match entry.directive {
    DOpen(_) => "open"
    DClose(_) => "close"
    DCommodity(_) => "commodity"
    DBalance(_) => "balance"
    DPad(_) => "pad"
    DPrice(_) => "price"
    DTransaction(_) => "transaction"
    DNote(_) => "note"
    DDocument(_) => "document"
    DEvent(_) => "event"
    DQuery(_) => "query"
    DCustom(_) => "custom"
  }
}

///|
fn directive_rows(
  realized : @realization.RealizedLedger,
  table : String,
) -> Array[BqlRow] {
  let result : Array[BqlRow] = []
  let seen : Map[String, Bool] = Map([])
  for entry in realized.entries {
    let kind = directive_type(entry)
    let selected = if table == "accounts" {
      kind == "open"
    } else {
      table == "entries" ||
      table == kind + "s" ||
      (table == "commodities" && kind == "commodity")
    }
    if !selected {
      continue
    }
    if table == "accounts" && entry.directive is DOpen(open) {
      if seen.contains(open.account) {
        continue
      }
      seen.set(open.account, true)
    }
    let units = @ast.Amount::new(@decimal.Decimal::zero(), "")
    result.push({
      extra: Some(new_row_extra(Some(entry), Some(table), None)),
      date: entry.date,
      flag: table,
      payee: None,
      narration: "",
      tags: [],
      links: [],
      meta: entry.meta,
      entry_meta: entry.meta,
      accounts: [],
      account: "",
      units,
      cost: None,
      value: None,
      position: @booking.Position::new(units, None),
    })
  }
  result
}

///|
fn directive_column(
  ctx : QueryContext,
  entry : @ast.Entry,
  name : String,
  table : String,
) -> QueryValue {
  match name {
    "discrepancy" =>
      return match entry.balance_discrepancy {
        Some(a) => QAmount(a)
        None => QNull
      }
    "id" => return QText(directive_identity(directive_value(entry)))
    "meta" => return entry_metadata(entry)
    "open" | "close" => {
      ensure_account_index(ctx)
      let account = match entry.directive {
        DOpen(o) => o.account
        _ => ""
      }
      let found = (if name == "open" { ctx.opens } else { ctx.closes })
        .unwrap()
        .get(account)
      return match found {
        Some(e) => directive_value(e)
        None => QNull
      }
    }
    "date" => return QDate(entry.date)
    "year" => return query_int(entry.date.year)
    "month" => return query_int(entry.date.month)
    "day" => return query_int(entry.date.day)
    "lineno" => return query_int(query_location(entry).line)
    "filename" =>
      match entry.directive {
        DDocument(document) =>
          if table == "documents" {
            let file = @path.Path(document.filename)
            return QText(
              if file.is_absolute() {
                file.normalize().to_string()
              } else {
                @path.Path(entry.loc.file)
                .dirname()
                .join(file)
                .normalize()
                .to_string()
              },
            )
          } else {
            return QText(query_location(entry).file)
          }
        _ => return QText(query_location(entry).file)
      }
    "type" =>
      return QText(
        match entry.directive {
          DEvent(e) => if table == "events" { e.event_type } else { "event" }
          _ => directive_type(entry)
        },
      )
    "accounts" => {
      let accounts = match entry.directive {
        DTransaction(txn) => transaction_accounts(txn.postings)
        DOpen(e) => [e.account]
        DClose(e) => [e.account]
        DBalance(e) => [e.account]
        DPad(e) => [e.account, e.source_account]
        DNote(e) => [e.account]
        DDocument(e) => [e.account]
        DCustom(_) => []
        _ => []
      }
      return QSet(accounts)
    }
    _ => ()
  }
  match entry.directive {
    DTransaction(txn) =>
      match name {
        "flag" => QText(txn.flag)
        "payee" =>
          match txn.payee {
            Some(p) => QText(p)
            None => QNull
          }
        "narration" => QText(txn.narration)
        "description" =>
          QText(
            match txn.payee {
              Some(p) =>
                if p == "" {
                  txn.narration
                } else {
                  p + " | " + txn.narration
                }
              None => txn.narration
            },
          )
        "tags" => QSet(txn.tags)
        "links" => QSet(txn.links)
        _ => QNull
      }
    DOpen(e) => if name == "account" { QText(e.account) } else { QNull }
    DClose(e) => if name == "account" { QText(e.account) } else { QNull }
    DCommodity(e) => if name == "name" { QText(e.currency) } else { QNull }
    DPrice(e) =>
      match name {
        "currency" => QText(e.currency)
        "amount" => QAmount(e.amount)
        _ => QNull
      }
    DBalance(e) =>
      match name {
        "account" => QText(e.account)
        "amount" => QAmount(e.amount)
        "tolerance" =>
          match e.tolerance {
            Some(n) => QNumber(n)
            None => QNull
          }
        _ => QNull
      }
    DEvent(e) =>
      if name == "description" && table == "events" {
        QText(e.description)
      } else {
        QNull
      }
    DNote(e) =>
      match name {
        "account" => QText(e.account)
        "comment" => QText(e.comment)
        "tags" =>
          if table == "notes" {
            QFrozenSet(e.tags)
          } else {
            QSet(e.tags)
          }
        "links" =>
          if table == "notes" {
            QFrozenSet(e.links)
          } else {
            QSet(e.links)
          }
        _ => QNull
      }
    DDocument(e) =>
      match name {
        "account" => QText(e.account)
        "tags" =>
          if table == "documents" {
            QFrozenSet(e.tags)
          } else {
            QSet(e.tags)
          }
        "links" =>
          if table == "documents" {
            QFrozenSet(e.links)
          } else {
            QSet(e.links)
          }
        _ => QNull
      }
    _ => QNull
  }
}

///|
fn decimal_group_key(number : @decimal.Decimal) -> String {
  let text = number.to_string()
  if !text.contains(".") {
    return text
  }
  let mut end = text.length()
  while end > 0 && text.get_char(end - 1) is Some('0') {
    end = end - 1
  }
  if end > 0 && text.get_char(end - 1) is Some('.') {
    end = end - 1
  }
  String::from_iter(text[:end].iter())
}
