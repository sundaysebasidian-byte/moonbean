// Text and JSON reports built on the realized ledger.  All reports are
// deterministic and currency-precision preserving: JSON numbers are emitted
// as strings so that exact decimals survive serialization.

///|
pub(all) struct ReportRow {
  label : String
  amount : @ast.Amount
}

///|
pub(all) struct Report {
  title : String
  rows : Array[ReportRow]
  totals : Array[ReportRow]
}

///|
fn pad_right(text : String, width : Int32) -> String {
  let sb = StringBuilder()
  sb.write_string(text)
  let mut i = text.length()
  while i < width {
    sb.write_string(" ")
    i = i + 1
  }
  sb.to_string()
}

///|
fn pad_left(text : String, width : Int32) -> String {
  let sb = StringBuilder()
  let mut i = text.length()
  while i < width {
    sb.write_string(" ")
    i = i + 1
  }
  sb.write_string(text)
  sb.to_string()
}

///|
fn amount_text(amount : @ast.Amount) -> String {
  amount.number.to_string() + " " + amount.currency
}

///|
fn max_label_width(rows : Array[ReportRow], fallback : Int32) -> Int32 {
  let mut width = fallback
  for row in rows {
    if row.label.length() > width {
      width = row.label.length()
    }
  }
  width
}

///|
fn max_amount_width(rows : Array[ReportRow]) -> Int32 {
  let mut width = 1
  for row in rows {
    if amount_text(row.amount).length() > width {
      width = amount_text(row.amount).length()
    }
  }
  width
}

///|
fn render_rows(
  sb : StringBuilder,
  rows : Array[ReportRow],
  label_width : Int32,
  amount_width : Int32,
) -> Unit {
  for row in rows {
    sb.write_string(pad_right(row.label, label_width))
    sb.write_string("  ")
    sb.write_string(pad_left(amount_text(row.amount), amount_width))
    sb.write_string("\n")
  }
}

///|
pub fn Report::to_text(self : Report) -> String {
  let sb = StringBuilder()
  sb.write_string(self.title)
  sb.write_string("\n")
  let label_width = max_label_width(self.rows, 7)
  let amount_width = max_amount_width(self.rows.copy() + self.totals.copy())
  sb.write_string(pad_right("Account", label_width))
  sb.write_string("  ")
  sb.write_string(pad_left("Amount", amount_width))
  sb.write_string("\n")
  render_rows(sb, self.rows, label_width, amount_width)
  if self.totals.length() > 0 {
    sb.write_string("\n")
    render_rows(sb, self.totals, label_width, amount_width)
  }
  sb.to_string()
}

///|
fn amount_json(amount : @ast.Amount) -> String {
  "{\"number\":\"" +
  amount.number.to_string() +
  "\",\"currency\":\"" +
  json_escape(amount.currency) +
  "\"}"
}

///|
fn rows_json(rows : Array[ReportRow]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  let mut first = true
  for row in rows {
    if !first {
      sb.write_string(",")
    }
    sb.write_string("{\"account\":\"")
    sb.write_string(json_escape(row.label))
    sb.write_string("\",\"amount\":")
    sb.write_string(amount_json(row.amount))
    sb.write_string("}")
    first = false
  }
  sb.write_string("]")
  sb.to_string()
}

///|
pub fn Report::to_json(self : Report) -> String {
  "{\"title\":\"" +
  json_escape(self.title) +
  "\",\"rows\":" +
  rows_json(self.rows) +
  ",\"totals\":" +
  rows_json(self.totals) +
  "}"
}

///|
fn add_amount(target : Array[@ast.Amount], amount : @ast.Amount) -> Unit {
  if amount.number.is_zero() {
    return
  }
  for i in 0..<target.length() {
    if target[i].currency == amount.currency {
      target[i] = @ast.Amount::new(
        target[i].number.add(amount.number),
        amount.currency,
      )
      return
    }
  }
  target.push(amount)
}

///|
fn account_amounts(
  realized : RealizedLedger,
  account : String,
  convert : String?,
) -> Array[@ast.Amount] {
  let inventory = realized.inventory(account)
  let amounts = []
  match convert {
    Some(target) =>
      for position in inventory.positions {
        match realized.convert(position.units, target) {
          Some(converted) => add_amount(amounts, converted)
          None =>
            match position.cost {
              Some(cost) =>
                if cost.currency == target {
                  add_amount(
                    amounts,
                    @ast.Amount::new(
                      position.units.number.mul(cost.number),
                      target,
                    ),
                  )
                } else {
                  add_amount(amounts, position.units)
                }
              None => add_amount(amounts, position.units)
            }
        }
      }
    None =>
      for currency in inventory.currencies() {
        let quantity = inventory.quantity(currency)
        if !quantity.is_zero() {
          amounts.push(@ast.Amount::new(quantity, currency))
        }
      }
  }
  amounts
}

///|
fn root_allowed(account : String, roots : Array[String]) -> Bool {
  roots.contains(@ast.account_root(account))
}

///|
fn sorted_report_rows(rows : Array[ReportRow]) -> Array[ReportRow] {
  let result = rows.copy()
  let mut i = 1
  while i < result.length() {
    let current = result[i]
    let mut j = i
    while j > 0 {
      let prev = result[j - 1]
      let key_cmp = prev.label.lexical_compare(current.label)
      let ccy_cmp = prev.amount.currency.lexical_compare(
        current.amount.currency,
      )
      let after = key_cmp > 0 || (key_cmp == 0 && ccy_cmp > 0)
      if after {
        result[j - 1] = current
        result[j] = prev
        j = j - 1
      } else {
        break
      }
    }
    i = i + 1
  }
  result
}

///|
fn built_rows(
  realized : RealizedLedger,
  roots : Array[String],
  convert : String?,
) -> Array[ReportRow] {
  let rows : Array[ReportRow] = []
  for account in realized.account_names() {
    if root_allowed(account, roots) {
      for amount in account_amounts(realized, account, convert) {
        rows.push({ label: account, amount, })
      }
    }
  }
  sorted_report_rows(rows)
}

///|
fn sum_rows(rows : Array[ReportRow]) -> @ast.Amount? {
  if rows.length() == 0 {
    return None
  }
  let currency = rows[0].amount.currency
  let mut total = @decimal.Decimal::zero()
  for row in rows {
    if row.amount.currency != currency {
      return None
    }
    total = total.add(row.amount.number)
  }
  Some(@ast.Amount::new(total, currency))
}

///|
fn total_row(label : String, rows : Array[ReportRow]) -> Array[ReportRow] {
  match sum_rows(rows) {
    Some(amount) => [{ label, amount, }]
    None => []
  }
}

///|
fn rows_with_root(rows : Array[ReportRow], root : String) -> Array[ReportRow] {
  let result = []
  for row in rows {
    if @ast.account_root(row.label) == root {
      result.push(row)
    }
  }
  result
}

///|
pub fn trial_balance(
  realized : RealizedLedger,
  convert~ : String? = None,
) -> Report {
  let all_roots = ["Assets", "Liabilities", "Equity", "Income", "Expenses"]
  let rows = built_rows(realized, all_roots, convert)
  let totals = total_row("Total", rows)
  { title: "Trial Balance", rows, totals, }
}

///|
pub fn balance_sheet(
  realized : RealizedLedger,
  convert~ : String? = None,
) -> Report {
  let rows = built_rows(realized, ["Assets", "Liabilities", "Equity"], convert)
  let totals = []
  for root in ["Assets", "Liabilities", "Equity"] {
    for row in total_row("Total " + root, rows_with_root(rows, root)) {
      totals.push(row)
    }
  }
  { title: "Balance Sheet", rows, totals, }
}

///|
fn income_rows(
  realized : RealizedLedger,
  start : @ast.Date?,
  convert : String?,
) -> Array[ReportRow] {
  let rows : Array[ReportRow] = []
  for entry in realized.entries {
    let in_period = match start {
      Some(date) => date.less_equal(entry.date)
      None => true
    }
    if in_period {
      match entry.directive {
        DTransaction(txn) =>
          for posting in txn.postings {
            if root_allowed(posting.account, ["Income", "Expenses"]) {
              match posting.units {
                Some(units) => {
                  let amount = match convert {
                    Some(target) =>
                      match realized.convert(units, target) {
                        Some(converted) => converted
                        None => units
                      }
                    None => units
                  }
                  let mut found = false
                  for i in 0..<rows.length() {
                    if rows[i].label == posting.account &&
                      rows[i].amount.currency == amount.currency {
                      rows[i] = {
                        label: posting.account,
                        amount: @ast.Amount::new(
                          rows[i].amount.number.add(amount.number),
                          amount.currency,
                        ),
                      }
                      found = true
                    }
                  }
                  if !found {
                    rows.push({ label: posting.account, amount, })
                  }
                }
                None => ()
              }
            }
          }
        _ => ()
      }
    }
  }
  sorted_report_rows(rows)
}

///|
pub fn income_statement(
  realized : RealizedLedger,
  start~ : @ast.Date? = None,
  convert~ : String? = None,
) -> Report {
  let rows = income_rows(realized, start, convert)
  let income = rows_with_root(rows, "Income")
  let expenses = rows_with_root(rows, "Expenses")
  let totals = []
  for row in total_row("Total Income", income) {
    totals.push(row)
  }
  for row in total_row("Total Expenses", expenses) {
    totals.push(row)
  }
  let combined = income.copy() + expenses.copy()
  match sum_rows(combined) {
    Some(amount) =>
      totals.push({
        label: "Net Income",
        amount: @ast.Amount::new(amount.number.neg(), amount.currency),
      })
    None => ()
  }
  { title: "Income Statement", rows, totals, }
}

///|
pub(all) struct InventoryReportRow {
  account : String
  units : @ast.Amount
  cost : String?
  value : @ast.Amount?
}

///|
pub fn inventory_rows(
  realized : RealizedLedger,
  convert~ : String? = None,
) -> Array[InventoryReportRow] {
  let rows = []
  for account in realized.account_names() {
    for position in realized.inventory(account).positions {
      let value = match convert {
        Some(target) =>
          match realized.convert(position.units, target) {
            Some(converted) => Some(converted)
            None =>
              match position.cost {
                Some(cost) =>
                  if cost.currency == target {
                    Some(
                      @ast.Amount::new(
                        position.units.number.mul(cost.number),
                        target,
                      ),
                    )
                  } else {
                    None
                  }
                None => None
              }
          }
        None => None
      }
      rows.push({
        account,
        units: position.units,
        cost: match position.cost {
          Some(cost) => Some(cost.to_string())
          None => None
        },
        value,
      })
    }
  }
  rows
}

///|
pub fn inventory_to_text(rows : Array[InventoryReportRow]) -> String {
  let sb = StringBuilder()
  sb.write_string("Inventory\n")
  sb.write_string("Account  Units  Cost  Value\n")
  for row in rows {
    sb.write_string(row.account)
    sb.write_string("  ")
    sb.write_string(amount_text(row.units))
    match row.cost {
      Some(cost) => {
        sb.write_string("  ")
        sb.write_string(cost)
      }
      None => ()
    }
    match row.value {
      Some(value) => {
        sb.write_string("  ")
        sb.write_string(amount_text(value))
      }
      None => ()
    }
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
pub fn inventory_to_json(rows : Array[InventoryReportRow]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  let mut first = true
  for row in rows {
    if !first {
      sb.write_string(",")
    }
    sb.write_string("{\"account\":\"")
    sb.write_string(json_escape(row.account))
    sb.write_string("\",\"units\":")
    sb.write_string(amount_json(row.units))
    sb.write_string(",\"cost\":")
    match row.cost {
      Some(cost) => {
        sb.write_string("\"")
        sb.write_string(json_escape(cost))
        sb.write_string("\"")
      }
      None => sb.write_string("null")
    }
    sb.write_string(",\"value\":")
    match row.value {
      Some(value) => sb.write_string(amount_json(value))
      None => sb.write_string("null")
    }
    sb.write_string("}")
    first = false
  }
  sb.write_string("]")
  sb.to_string()
}

///|
pub(all) struct RegisterRow {
  date : @ast.Date
  flag : String
  payee : String
  narration : String
  account : String
  amount : @ast.Amount
  running : @ast.Amount
}

///|
pub fn register_rows(
  realized : RealizedLedger,
  account : String,
  subtree~ : Bool = false,
) -> Array[RegisterRow] {
  let rows = []
  let running : Map[String, @decimal.Decimal] = Map([])
  for entry in realized.entries {
    match entry.directive {
      DTransaction(txn) =>
        for posting in txn.postings {
          if posting.account == account ||
            (subtree && is_subaccount(posting.account, account)) {
            match posting.units {
              Some(units) => {
                let previous = match running.get(units.currency) {
                  Some(value) => value
                  None => @decimal.Decimal::zero()
                }
                let next = previous.add(units.number)
                running.set(units.currency, next)
                rows.push({
                  date: entry.date,
                  flag: txn.flag,
                  payee: match txn.payee {
                    Some(payee) => payee
                    None => ""
                  },
                  narration: txn.narration,
                  account: posting.account,
                  amount: units,
                  running: @ast.Amount::new(next, units.currency),
                })
              }
              None => ()
            }
          }
        }
      _ => ()
    }
  }
  rows
}

///|
fn register_description(row : RegisterRow) -> String {
  if row.payee == "" {
    row.narration
  } else {
    row.payee + " | " + row.narration
  }
}

///|
pub fn register_to_text(rows : Array[RegisterRow]) -> String {
  let sb = StringBuilder()
  sb.write_string("Register\n")
  for row in rows {
    sb.write_string(row.date.to_string())
    sb.write_string("  ")
    sb.write_string(row.flag)
    sb.write_string("  ")
    sb.write_string(pad_right(amount_text(row.amount), 18))
    sb.write_string("  ")
    sb.write_string(pad_right(amount_text(row.running), 18))
    sb.write_string("  ")
    sb.write_string(register_description(row))
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
pub fn register_to_json(rows : Array[RegisterRow]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  let mut first = true
  for row in rows {
    if !first {
      sb.write_string(",")
    }
    sb.write_string("{\"date\":\"")
    sb.write_string(row.date.to_string())
    sb.write_string("\",\"flag\":\"")
    sb.write_string(json_escape(row.flag))
    sb.write_string("\",\"payee\":\"")
    sb.write_string(json_escape(row.payee))
    sb.write_string("\",\"narration\":\"")
    sb.write_string(json_escape(row.narration))
    sb.write_string("\",\"account\":\"")
    sb.write_string(json_escape(row.account))
    sb.write_string("\",\"amount\":")
    sb.write_string(amount_json(row.amount))
    sb.write_string(",\"running\":")
    sb.write_string(amount_json(row.running))
    sb.write_string("}")
    first = false
  }
  sb.write_string("]")
  sb.to_string()
}
