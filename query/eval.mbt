// BQL evaluation over a realized ledger.  The engine works on a flat posting
// table (or an inventory-position table for FROM balances), supports a WHERE
// predicate, grouping with sum()/count(), ordering and LIMIT.

///|
priv struct BqlRow {
  date : @ast.Date
  flag : String
  payee : String
  narration : String
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
        Some(@ast.Total(amount)) => Some(amount)
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
fn posting_rows(realized : @realization.RealizedLedger) -> Array[BqlRow] {
  let rows : Array[BqlRow] = []
  for entry in realized.entries {
    match entry.directive {
      DTransaction(txn) =>
        for posting in txn.postings {
          match posting.units {
            Some(units) => {
              let cost = posting_cost(posting, units)
              rows.push({
                date: entry.date,
                flag: txn.flag,
                payee: match txn.payee {
                  Some(payee) => payee
                  None => ""
                },
                narration: txn.narration,
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
        date,
        flag: "",
        payee: "",
        narration: "",
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
) -> Array[BqlRow] {
  match source {
    SrcPostings => posting_rows(realized)
    SrcBalances => balance_rows(realized)
  }
}

///|
fn eval_column(row : BqlRow, name : String) -> QueryValue {
  match name {
    "date" => QDate(row.date)
    "year" => QNumber(@decimal.Decimal::from_int(row.date.year))
    "month" => QNumber(@decimal.Decimal::from_int(row.date.month))
    "flag" => QText(row.flag)
    "payee" => if row.payee == "" { QNull } else { QText(row.payee) }
    "narration" => QText(row.narration)
    "account" => QText(row.account)
    "root" => QText(@ast.account_root(row.account))
    "parent" => QText(@ast.account_parent(row.account))
    "leaf" => QText(@ast.account_leaf(row.account))
    "units" => QAmount(row.units)
    "currency" => QText(row.units.currency)
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
fn eval_expr(expr : Expr, row : BqlRow) -> QueryValue {
  match expr {
    ECol(name) => eval_column(row, name)
    EStr(text) => QText(text)
    ENum(number) => QNumber(number)
    EDate(date) => QDate(date)
    ENull => QNull
    EStar => QNull
    EBool(value) =>
      if value {
        QNumber(@decimal.Decimal::one())
      } else {
        QNumber(@decimal.Decimal::zero())
      }
    ECall(name, args) =>
      match (name, args) {
        ("year", [arg]) =>
          match eval_expr(arg, row) {
            QDate(date) => QNumber(@decimal.Decimal::from_int(date.year))
            _ => QNull
          }
        ("month", [arg]) =>
          match eval_expr(arg, row) {
            QDate(date) => QNumber(@decimal.Decimal::from_int(date.month))
            _ => QNull
          }
        ("root", [arg]) =>
          match eval_expr(arg, row) {
            QText(account) => QText(@ast.account_root(account))
            _ => QNull
          }
        ("parent", [arg]) =>
          match eval_expr(arg, row) {
            QText(account) => QText(@ast.account_parent(account))
            _ => QNull
          }
        ("leaf", [arg]) =>
          match eval_expr(arg, row) {
            QText(account) => QText(@ast.account_leaf(account))
            _ => QNull
          }
        _ => QNull
      }
  }
}

///|
fn cond_holds(cond : Cond, row : BqlRow) -> Bool {
  match cond {
    CTrue => true
    CNot(inner) => !cond_holds(inner, row)
    CAnd(left, right) => cond_holds(left, row) && cond_holds(right, row)
    COr(left, right) => cond_holds(left, row) || cond_holds(right, row)
    CIsNull(expr, negated) => {
      let is_null = eval_expr(expr, row) is QNull
      if negated {
        !is_null
      } else {
        is_null
      }
    }
    CTruthy(expr) =>
      match eval_expr(expr, row) {
        QNull => false
        QText(text) => text != ""
        QNumber(number) => !number.is_zero()
        QAmount(amount) => !amount.number.is_zero()
        QPosition(position) => !position.units.number.is_zero()
        QInventory(inventory) => !inventory.is_empty()
        QDate(_) => true
      }
    CCmp(left, op, right) => {
      let a = eval_expr(left, row)
      let b = eval_expr(right, row)
      match value_compare(a, b) {
        Some(order) =>
          match op {
            "=" | "==" => order == 0
            "!=" | "<>" => order != 0
            "<" => order < 0
            "<=" => order <= 0
            ">" => order > 0
            ">=" => order >= 0
            _ => false
          }
        None => false
      }
    }
  }
}

///|
fn expr_label(expr : Expr) -> String {
  match expr {
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
    ECall("sum", _) | ECall("count", _) => true
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
fn sum_numbers(values : Array[@decimal.Decimal]) -> QueryValue {
  if values.length() == 0 {
    return QNull
  }
  let mut total = @decimal.Decimal::zero()
  for value in values {
    total = total.add(value)
  }
  QNumber(total)
}

///|
fn eval_aggregate(expr : Expr, rows : Array[BqlRow]) -> QueryValue {
  match expr {
    ECall("count", _) => QNumber(@decimal.Decimal::from_int(rows.length()))
    ECall("sum", [arg]) =>
      match arg {
        ECol("position") => {
          let inventory = @booking.Inventory::new()
          for row in rows {
            inventory.add(row.position)
          }
          QInventory(inventory)
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
          let numbers : Array[@decimal.Decimal] = []
          for row in rows {
            match value_number(eval_expr(arg, row)) {
              Some(number) => numbers.push(number)
              None => ()
            }
          }
          sum_numbers(numbers)
        }
      }
    _ => QNull
  }
}

///|
fn eval_grouped(expr : Expr, rows : Array[BqlRow]) -> QueryValue {
  if contains_sum(expr) {
    eval_aggregate(expr, rows)
  } else if rows.length() > 0 {
    eval_expr(expr, rows[0])
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
fn group_key(exprs : Array[Expr], row : BqlRow) -> String {
  let sb = StringBuilder()
  for expr in exprs {
    sb.write_string(eval_expr(expr, row).to_text())
    sb.write_string("\u{1f}")
  }
  sb.to_string()
}

///|
fn build_output(query : SelectQuery, rows : Array[BqlRow]) -> Array[OutputRow] {
  let outputs : Array[OutputRow] = []
  let any_aggregate = {
    let mut found = false
    for projection in query.projections {
      if contains_sum(projection) {
        found = true
      }
    }
    for order in query.orders {
      if contains_sum(order.expr) {
        found = true
      }
    }
    found
  }
  if query.groups.length() == 0 && !any_aggregate {
    for row in rows {
      let values : Array[QueryValue] = []
      for projection in query.projections {
        values.push(eval_expr(projection, row))
      }
      outputs.push({ values, group: [row], })
    }
    return outputs
  }
  let groups : Map[String, Array[BqlRow]] = Map([])
  let order : Array[String] = []
  if query.groups.length() == 0 {
    order.push("")
    groups.set("", rows)
  } else {
    for row in rows {
      let key = group_key(query.groups, row)
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
      values.push(eval_grouped(projection, bucket))
    }
    outputs.push({ values, group: bucket, })
  }
  outputs
}

///|
fn sort_outputs(outputs : Array[OutputRow], orders : Array[OrderSpec]) -> Unit {
  let mut i = 1
  while i < outputs.length() {
    let current = outputs[i]
    let mut j = i
    while j > 0 {
      let prev = outputs[j - 1]
      let mut before = false
      let mut decided = false
      for spec in orders {
        if !decided {
          let a = eval_grouped(spec.expr, prev.group)
          let b = eval_grouped(spec.expr, current.group)
          let order = match value_compare(a, b) {
            Some(value) => value
            None => 0
          }
          if order != 0 {
            before = if spec.descending { order < 0 } else { order > 0 }
            decided = true
          }
        }
      }
      if before {
        outputs[j - 1] = current
        outputs[j] = prev
        j = j - 1
      } else {
        break
      }
    }
    i = i + 1
  }
}

///|
fn run_select(
  realized : @realization.RealizedLedger,
  query : SelectQuery,
) -> QueryResult {
  let all_rows = source_rows(realized, query.source)
  let rows : Array[BqlRow] = []
  for row in all_rows {
    if cond_holds(query.filter, row) {
      rows.push(row)
    }
  }
  let mut outputs = build_output(query, rows)
  sort_outputs(outputs, query.orders)
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
  let columns : Array[String] = []
  for projection in query.projections {
    columns.push(expr_label(projection))
  }
  let result_rows : Array[Array[QueryValue]] = []
  for output in outputs {
    result_rows.push(output.values)
  }
  { columns, rows: result_rows, error: None, }
}

///|
fn run_balances(realized : @realization.RealizedLedger) -> QueryResult {
  let columns = ["account", "balance"]
  let rows : Array[Array[QueryValue]] = []
  for account in realized.account_names() {
    let inventory = realized.inventory(account)
    if !inventory.is_empty() {
      rows.push([QText(account), QInventory(inventory)])
    }
  }
  { columns, rows, error: None, }
}

///|
fn journal_row(entry : @ast.Entry, posting : @ast.Posting) -> BqlRow? {
  match posting.units {
    Some(units) => {
      let cost = posting_cost(posting, units)
      Some({
        date: entry.date,
        flag: "",
        payee: "",
        narration: "",
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
        for posting in txn.postings {
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
  { columns, rows, error: None, }
}

///|
pub fn run_query(
  realized : @realization.RealizedLedger,
  text : String,
) -> QueryResult {
  match parse_query(text) {
    PqError(message) => { columns: [], rows: [], error: Some(message), }
    PqSelect(query) => run_select(realized, query)
    PqBalances => run_balances(realized)
    PqJournal(account, limit) => run_journal(realized, account, limit)
  }
}
