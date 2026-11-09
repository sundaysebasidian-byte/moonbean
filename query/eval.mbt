// BQL evaluation over a realized ledger.  The engine works on a flat posting
// table (or an inventory-position table for FROM balances), supports a WHERE
// predicate, grouping with sum()/count(), ordering and LIMIT.

///|
priv struct BqlRow {
  date : @ast.Date
  entry : @ast.Entry?
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
                entry: None,
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
        entry: None,
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
) -> Array[BqlRow] {
  match source {
    SrcPostings => posting_rows(realized)
    SrcTransactions => transaction_rows(realized)
    SrcBalances => balance_rows(realized)
    SrcDirectives(table) => directive_rows(realized, table)
    SrcOpen(start, close) => opening_rows(realized, start, close)
    SrcClose(date) =>
      posting_rows(realized).filter(fn(row) { row.date.less_than(date) })
  }
}

///|
fn eval_column(row : BqlRow, name : String) -> QueryValue {
  if row.entry is Some(entry) {
    return directive_column(entry, name, row.flag)
  }
  match name {
    "date" => QDate(row.date)
    "year" => QNumber(@decimal.Decimal::from_int(row.date.year))
    "month" => QNumber(@decimal.Decimal::from_int(row.date.month))
    "day" => QNumber(@decimal.Decimal::from_int(row.date.day))
    "flag" => QText(row.flag)
    "payee" =>
      match row.payee {
        Some(s) => QText(s)
        None => QNull
      }
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
    "weight" =>
      match row.cost {
        Some(cost) =>
          QAmount(
            @ast.Amount::new(row.units.number.mul(cost.number), cost.currency),
          )
        None => QAmount(row.units)
      }
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
    EValue(value) => value
    EBinary(left, op, right) =>
      arithmetic(eval_expr(left, row), op, eval_expr(right, row))
    ECol(name) => eval_column(row, name)
    EStr(text) => QText(text)
    ENum(number) => QNumber(number)
    EDate(date) => QDate(date)
    ENull => QNull
    EStar => QNull
    EBool(value) => QBool(value)
    ECall(name, args) =>
      match (name, args) {
        ("meta" | "entry_meta", [EStr(key)]) =>
          match
            (match (row.entry, key) {
              (Some(entry), "filename") => Some(@ast.MString(entry.loc.file))
              (Some(entry), "lineno") =>
                Some(@ast.MNumber(@decimal.Decimal::from_int(entry.loc.line)))
              _ =>
                (if name == "entry_meta" { row.entry_meta } else { row.meta }).get(
                  key,
                )
            }) {
            Some(@ast.MString(s))
            | Some(@ast.MAccount(s))
            | Some(@ast.MCurrency(s))
            | Some(@ast.MTag(s)) => QText(s)
            Some(@ast.MNumber(n)) => QNumber(n)
            Some(@ast.MDate(d)) => QDate(d)
            Some(@ast.MBool(b)) => QBool(b)
            None => QNull
          }
        ("upper" | "lower", [arg]) =>
          match eval_expr(arg, row) {
            QText(s) => QText(unicode_case(s, name == "upper"))
            _ => QNull
          }
        ("length", [arg]) =>
          match eval_expr(arg, row) {
            QText(s) => QNumber(@decimal.Decimal::from_int(s.iter().count()))
            _ => QNull
          }
        ("substr", [arg, start, end]) =>
          match eval_expr(arg, row) {
            QText(s) => {
              let chars = s.iter().to_array()
              let size = chars.length()
              let a = slice_index(start, row, size)
              let b = slice_index(end, row, size)
              let sb = StringBuilder()
              for i in a..<b {
                sb.write_char(chars[i])
              }
              QText(sb.to_string())
            }
            _ => QNull
          }
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
    CRegex(e, regex) =>
      match eval_expr(e, row) {
        QText(s) => regex.execute(s) is Some(_)
        _ => false
      }
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
        QSet(values) | QFrozenSet(values) => values.length() > 0
        QNull => false
        QText(text) => text != ""
        QNumber(number) => !number.is_zero()
        QAmount(amount) => !amount.number.is_zero()
        QPosition(position) => !position.units.number.is_zero()
        QInventory(inventory) => !inventory.is_empty()
        QBool(b) => b
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
fn sum_numbers(values : Array[@decimal.Decimal]) -> QueryValue {
  if values.length() == 0 {
    return QNumber(@decimal.Decimal::zero())
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
    ECall("first" | "last" | "min" | "max", [arg]) => {
      let mut result = QNull
      for row in rows {
        let value = eval_expr(arg, row)
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
          ECall("last", _) => result = value
          ECall("min" | "max", _) => {
            let order = value_compare(value, result)
            if (expr is ECall("min", _) && order is Some(n) && n < 0) ||
              (expr is ECall("max", _) && order is Some(n) && n > 0) {
              result = value
            }
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
        rows.filter(fn(row) { !(eval_expr(arg, row) is QNull) }).length()
      } else {
        0
      }
      QNumber(@decimal.Decimal::from_int(count))
    }
    ECall("sum", [arg]) =>
      match arg {
        ECol("amount") => {
          let inventory = @booking.Inventory::new()
          for row in rows {
            if eval_expr(arg, row) is QAmount(amount) {
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
            if eval_column(row, "weight") is QAmount(a) {
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
  if expr is EBinary(left, op, right) {
    arithmetic(eval_grouped(left, rows), op, eval_grouped(right, rows))
  } else if expr is ECall(name, args) && contains_sum(expr) {
    if ["sum", "count", "first", "last", "min", "max"].contains(name) {
      eval_aggregate(expr, rows)
    } else if !rows.is_empty() {
      eval_expr(
        ECall(
          name,
          args.map(fn(arg) {
            if contains_sum(arg) {
              EValue(eval_grouped(arg, rows))
            } else {
              arg
            }
          }),
        ),
        rows[0],
      )
    } else {
      QNull
    }
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
    let value = eval_expr(expr, row)
    sb.write_string(
      match value {
        QBool(b) => if b { "1" } else { "0" }
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
          let order = match (a, b) {
            (QNull, QNull) => 0
            (QNull, _) => -1
            (_, QNull) => 1
            _ =>
              match value_compare(a, b) {
                Some(value) => value
                None => 0
              }
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
  let mut outputs = build_output(query, rows).filter(fn(output) {
    grouped_cond(query.having, output.group)
  })
  sort_outputs(outputs, query.orders)
  if query.distinct {
    let unique : Array[OutputRow] = []
    for output in outputs {
      if !unique.any(fn(prev) {
          prev.values.length() == output.values.length() &&
          prev.values
          .iter()
          .zip(output.values.iter())
          .all(fn(pair) { distinct_equal(pair.0, pair.1) })
        }) {
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
        entry: None,
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

///|
fn arithmetic(a : QueryValue, op : String, b : QueryValue) -> QueryValue {
  match (a, b) {
    (QNumber(x), QNumber(y)) =>
      match op {
        "+" => QNumber(x.add(y))
        "-" => QNumber(x.sub(y))
        "*" => QNumber(x.mul(y))
        "/" =>
          match x.div(y) {
            Some(n) => QNumber(n)
            None => QNull
          }
        _ => QNull
      }
    _ => QNull
  }
}

///|
fn grouped_cond(cond : Cond, rows : Array[BqlRow]) -> Bool {
  match cond {
    CRegex(e, regex) =>
      match eval_grouped(e, rows) {
        QText(s) => regex.execute(s) is Some(_)
        _ => false
      }
    CTrue => true
    CNot(c) => !grouped_cond(c, rows)
    CAnd(a, b) => grouped_cond(a, rows) && grouped_cond(b, rows)
    COr(a, b) => grouped_cond(a, rows) || grouped_cond(b, rows)
    CIsNull(e, negated) => (eval_grouped(e, rows) is QNull) != negated
    CTruthy(e) =>
      match eval_grouped(e, rows) {
        QBool(b) => b
        QNumber(n) => !n.is_zero()
        QNull => false
        _ => true
      }
    CCmp(a, op, b) =>
      match value_compare(eval_grouped(a, rows), eval_grouped(b, rows)) {
        Some(n) =>
          match op {
            "=" | "==" => n == 0
            "!=" | "<>" => n != 0
            "<" => n < 0
            "<=" => n <= 0
            ">" => n > 0
            ">=" => n >= 0
            _ => false
          }
        None => false
      }
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
  for row in posting_rows(realized) {
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
        entry: None,
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
fn slice_index(expr : Expr, row : BqlRow, size : Int32) -> Int32 {
  let raw = eval_expr(expr, row).to_text()
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
fn transaction_rows(realized : @realization.RealizedLedger) -> Array[BqlRow] {
  let rows : Array[BqlRow] = []
  for entry in realized.entries {
    if entry.directive is DTransaction(txn) {
      // Posting-only columns are rejected before evaluation for this source.
      let units = @ast.Amount::new(@decimal.Decimal::zero(), "")
      rows.push({
        entry: None,
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
fn distinct_equal(a : QueryValue, b : QueryValue) -> Bool {
  match (a, b) {
    (QSet(a) | QFrozenSet(a), QSet(b) | QFrozenSet(b)) =>
      a.length() == b.length() && a.all(fn(s) { b.contains(s) })
    _ => value_compare(a, b) == Some(0)
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
      entry: Some(entry),
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
  entry : @ast.Entry,
  name : String,
  table : String,
) -> QueryValue {
  match name {
    "date" => return QDate(entry.date)
    "year" => return QNumber(@decimal.Decimal::from_int(entry.date.year))
    "month" => return QNumber(@decimal.Decimal::from_int(entry.date.month))
    "day" => return QNumber(@decimal.Decimal::from_int(entry.date.day))
    "lineno" => return QNumber(@decimal.Decimal::from_int(entry.loc.line))
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
            return QText(entry.loc.file)
          }
        _ => return QText(entry.loc.file)
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
        "tags" | "links" =>
          if table == "notes" {
            QFrozenSet([])
          } else {
            QSet([])
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
