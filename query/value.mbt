// Values produced by BQL expressions and their text/JSON rendering.

///|
pub(all) enum QueryValue {
  QText(String)
  QSet(Array[String])
  QNumber(@decimal.Decimal)
  QDate(@ast.Date)
  QAmount(@ast.Amount)
  QPosition(@booking.Position)
  QInventory(@booking.Inventory)
  QNull
}

///|
pub(all) struct QueryResult {
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
      other => sb.write_char(other)
    }
  }
  sb.to_string()
}

///|
pub fn QueryValue::to_text(self : QueryValue) -> String {
  match self {
    QSet(values) => values.join(",")
    QText(text) => text
    QNumber(number) => number.to_string()
    QDate(date) => date.to_string()
    QAmount(amount) => amount.to_string()
    QPosition(position) => position.to_string()
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
    QNull => ""
  }
}

///|
fn query_amount_json(amount : @ast.Amount) -> String {
  "{\"number\":\"" +
  amount.number.to_string() +
  "\",\"currency\":\"" +
  query_json_escape(amount.currency) +
  "\"}"
}

///|
fn query_cost_json(cost : @ast.Cost?) -> String {
  match cost {
    Some(c) =>
      "{ \"number\": \"" +
      c.number.to_string() +
      "\", \"currency\": \"" +
      query_json_escape(c.currency) +
      "\" }"
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
    QSet(values) =>
      "[" +
      values.map(fn(s) { "\"" + query_json_escape(s) + "\"" }).join(",") +
      "]"
    QText(text) => "\"" + query_json_escape(text) + "\""
    QNumber(number) => number.to_string()
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
    QNull => "null"
  }
}

///|
fn value_number(value : QueryValue) -> @decimal.Decimal? {
  match value {
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
    (QText(ta), QText(tb)) => Some(ta.lexical_compare(tb))
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
  sb.write_string("{\"columns\":[")
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
