// Values produced by BQL expressions and their text/JSON rendering.

///|
pub(all) enum QueryValue {
  QInt(@bigint.BigInt)
  QDict(Array[(String, QueryValue)])
  QList(Array[QueryValue])
  QRecord(String, Array[(String, QueryValue)])
  QEnum(String, String)
  QPythonType(String)
  QText(String)
  QSet(Array[String])
  QFrozenSet(Array[String])
  QNumber(@decimal.Decimal)
  QNegativeZero(Int32)
  QInterval(@bigint.BigInt, @bigint.BigInt)
  QDate(@ast.Date)
  QAmount(@ast.Amount)
  QPosition(@booking.Position)
  QInventory(@booking.Inventory)
  QNull
  QBool(Bool)
}

///|
pub(all) enum StatementResult {
  Table
  DirectiveText(String)
}

///|
pub(all) struct QueryResult {
  kind : StatementResult
  columns : Array[String]
  rows : Array[Array[QueryValue]]
  error : String?
}

///|
pub fn QueryResult::is_ok(self : QueryResult) -> Bool {
  self.error is None
}

///|
fn query_json_escape(text : String) -> String {
  let sb = StringBuilder()
  for i in 0..<text.length() {
    let ch = match text.get_char(i) {
      Some(c) => c
      None => continue
    }
    match ch {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      other =>
        if other.to_int() < 32 {
          sb.write_string("\\u00" + repr_hex(other.to_int(), 2))
        } else {
          sb.write_char(other)
        }
    }
  }
  sb.to_string()
}

///|
pub fn QueryValue::to_text(self : QueryValue) -> String {
  match self {
    QInterval(months, days) => interval_repr(months, days)
    QInt(n) => n.to_string()
    QDict(_) | QList(_) | QRecord(_, _) => python_repr(self)
    QEnum(name, value) => name + "." + value
    QPythonType(name) => "<class '" + name + "'>"
    QFrozenSet(values) =>
      if values.is_empty() {
        "frozenset()"
      } else {
        let sorted = values.copy()
        sorted.sort_by(fn(a, b) { a.lexical_compare(b) })
        "frozenset({" +
        sorted
        .map(fn(s) {
          "'" +
          s.replace_all(old="\\", new="\\\\").replace_all(old="'", new="\\'") +
          "'"
        })
        .join(", ") +
        "})"
      }
    QSet(values) => {
      let sorted = values.copy()
      sorted.sort_by(fn(a, b) { a.lexical_compare(b) })
      sorted.join(",")
    }
    QText(text) => text
    QNegativeZero(scale) =>
      "-" + python_decimal(@decimal.Decimal::zero_scaled(scale))
    QNumber(number) => python_decimal(number)
    QDate(date) => date.to_string()
    QAmount(amount) => python_amount(amount)
    QPosition(position) => python_position(position)
    QInventory(inventory) => {
      let sb = StringBuilder()
      let mut first = true
      for position in inventory.positions {
        if !first {
          sb.write_string(", ")
        }
        sb.write_string(position.to_string())
        first = false
      }
      sb.to_string()
    }
    QBool(b) => if b { "TRUE" } else { "FALSE" }
    QNull => ""
  }
}

///|
fn query_amount_json(amount : @ast.Amount) -> String {
  "{\"number\":\"" +
  python_decimal(amount.number) +
  "\",\"currency\":\"" +
  query_json_escape(amount.currency) +
  "\"}"
}

///|
fn query_cost_json(cost : @ast.Cost?) -> String {
  match cost {
    Some(c) =>
      "{ \"number\": \"" +
      python_decimal(c.number) +
      "\", \"currency\": \"" +
      query_json_escape(c.currency) +
      "\", \"date\":" +
      (match c.date {
        Some(d) => "\"" + d.to_string() + "\""
        None => "null"
      }) +
      ", \"label\":" +
      (match c.label {
        Some(l) => "\"" + query_json_escape(l) + "\""
        None => "null"
      }) +
      " }"
    None => "null"
  }
}

///|
fn query_position_json(position : @booking.Position) -> String {
  "{\"units\":" +
  query_amount_json(position.units) +
  ",\"cost\":" +
  query_cost_json(position.cost) +
  "}"
}

///|
pub fn QueryValue::to_json(self : QueryValue) -> String {
  match self {
    QInterval(_, _) => nested_json(self)
    QInt(n) => n.to_string()
    QDict(_) | QList(_) | QRecord(_, _) | QEnum(_, _) | QPythonType(_) =>
      nested_json(self)
    QSet(values) | QFrozenSet(values) =>
      "[" +
      values.map(fn(s) { "\"" + query_json_escape(s) + "\"" }).join(",") +
      "]"
    QText(text) => "\"" + query_json_escape(text) + "\""
    QNegativeZero(scale) =>
      "-" + python_decimal(@decimal.Decimal::zero_scaled(scale))
    QNumber(number) => python_decimal(number)
    QDate(date) => "\"" + date.to_string() + "\""
    QAmount(amount) => query_amount_json(amount)
    QPosition(position) => query_position_json(position)
    QInventory(inventory) => {
      let sb = StringBuilder()
      sb.write_string("[")
      let mut first = true
      for position in inventory.positions {
        if !first {
          sb.write_string(",")
        }
        sb.write_string(query_position_json(position))
        first = false
      }
      sb.write_string("]")
      sb.to_string()
    }
    QBool(b) => if b { "true" } else { "false" }
    QNull => "null"
  }
}

///|
fn value_number(value : QueryValue) -> @decimal.Decimal? {
  match value {
    QBool(b) => Some(@decimal.Decimal::from_int(if b { 1 } else { 0 }))
    QInt(n) => Some(@decimal.Decimal::new(n, 0))
    QNegativeZero(scale) => Some(@decimal.Decimal::zero_scaled(scale))
    QNumber(number) => Some(number)
    QAmount(amount) => Some(amount.number)
    QPosition(position) => Some(position.units.number)
    _ => None
  }
}

///|
fn value_compare(a : QueryValue, b : QueryValue) -> Int32? {
  match (a, b) {
    (QNull, QNull) => Some(0)
    (QNull, _) => None
    (_, QNull) => None
    (QDate(da), QDate(db)) => Some(da.compare(db))
    (QText(ta), QText(tb)) => Some(python_text_compare(ta, tb))
    (QAmount(aa), QAmount(ab)) =>
      if aa.currency == ab.currency {
        Some(aa.number.compare(ab.number))
      } else {
        None
      }
    (QPosition(pa), QPosition(pb)) =>
      value_compare(QAmount(pa.units), QAmount(pb.units))
    (QInventory(_), _) => None
    (_, QInventory(_)) => None
    _ =>
      match (value_number(a), value_number(b)) {
        (Some(na), Some(nb)) => Some(na.compare(nb))
        _ => None
      }
  }
}

///|
pub fn QueryResult::to_text(self : QueryResult) -> String {
  let sb = StringBuilder()
  match self.error {
    Some(message) => {
      sb.write_string("ERROR: ")
      sb.write_string(message)
      sb.write_string("\n")
      return sb.to_string()
    }
    None => ()
  }
  if self.kind is DirectiveText(text) {
    return text
  }
  let widths : Array[Int32] = []
  for column in self.columns {
    widths.push(column.length())
  }
  let rendered : Array[Array[String]] = []
  for row in self.rows {
    let cells : Array[String] = []
    for i in 0..<self.columns.length() {
      let text = if i < row.length() { row[i].to_text() } else { "" }
      if text.length() > widths[i] {
        widths[i] = text.length()
      }
      cells.push(text)
    }
    rendered.push(cells)
  }
  for i in 0..<self.columns.length() {
    if i > 0 {
      sb.write_string("  ")
    }
    sb.write_string(pad_right(self.columns[i], widths[i]))
  }
  sb.write_string("\n")
  for i in 0..<self.columns.length() {
    if i > 0 {
      sb.write_string("  ")
    }
    let mut dashes = 0
    while dashes < widths[i] {
      sb.write_string("-")
      dashes = dashes + 1
    }
  }
  sb.write_string("\n")
  for cells in rendered {
    for i in 0..<self.columns.length() {
      if i > 0 {
        sb.write_string("  ")
      }
      sb.write_string(pad_right(cells[i], widths[i]))
    }
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
fn pad_right(text : String, width : Int32) -> String {
  if text.length() >= width {
    return text
  }
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
pub fn QueryResult::to_json(self : QueryResult) -> String {
  let sb = StringBuilder()
  match self.error {
    Some(message) => return "{\"error\":\"" + query_json_escape(message) + "\"}"
    None => ()
  }
  if self.kind is DirectiveText(text) {
    sb.write_string(
      "{\"kind\":\"print\",\"text\":" + QText(text).to_json() + ",",
    )
  } else {
    sb.write_char('{')
  }
  sb.write_string("\"columns\":[")
  for i in 0..<self.columns.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("\"")
    sb.write_string(query_json_escape(self.columns[i]))
    sb.write_string("\"")
  }
  sb.write_string("],\"rows\":[")
  for r in 0..<self.rows.length() {
    if r > 0 {
      sb.write_string(",")
    }
    sb.write_string("[")
    let row = self.rows[r]
    for i in 0..<row.length() {
      if i > 0 {
        sb.write_string(",")
      }
      sb.write_string(row[i].to_json())
    }
    sb.write_string("]")
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
/// Matchable query failure; the original message remains available in each case.
pub(all) enum QueryError {
  Syntax(String)
  Compilation(String)
  Evaluation(String)
  Unsupported(String)
}

///|
/// Classifies parser failures without requiring hosts to match message text.
/// The legacy `error` field retains its original text for existing callers.
pub fn QueryResult::failure(self : QueryResult) -> QueryError? {
  match self.error {
    None => None
    Some(message) =>
      if message.has_prefix("compilation ") {
        Some(Compilation(message))
      } else if message.has_prefix("query.oracle_type_error") {
        Some(Evaluation(message))
      } else if message.has_prefix("unsupported ") ||
        message.has_prefix("unknown function ") ||
        message.has_prefix("unknown FROM source ") ||
        message.has_prefix("BALANCES AT supports ") {
        Some(Unsupported(message))
      } else {
        Some(Syntax(message))
      }
  }
}
