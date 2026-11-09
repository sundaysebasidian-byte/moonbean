///|
fn repr_hex(number : Int32, width : Int32) -> String {
  let digits = "0123456789abcdef"
  let result : Array[Char] = []
  let mut n = number
  for _ in 0..<width {
    result.push(digits.get_char(n % 16).unwrap())
    n = n / 16
  }
  let out = StringBuilder()
  for i in 0..<width {
    out.write_char(result[width - 1 - i])
  }
  out.to_string()
}

///|
fn python_string(text : String) -> String {
  let quote = if text.contains("'") && !text.contains("\"") {
    '"'
  } else {
    '\''
  }
  let out = StringBuilder()
  out.write_char(quote)
  for c in text.iter() {
    if c == quote || c == '\\' {
      out.write_char('\\')
      out.write_char(c)
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c == '\t' {
      out.write_string("\\t")
    } else if !unicode_in_ranges(c, unicode_printable_ranges) {
      let n = c.to_int()
      out.write_string(
        if n <= 255 {
          "\\x" + repr_hex(n, 2)
        } else if n <= 65535 {
          "\\u" + repr_hex(n, 4)
        } else {
          "\\U" + repr_hex(n, 8)
        },
      )
    } else {
      out.write_char(c)
    }
  }
  out.write_char(quote)
  out.to_string()
}

///|
fn python_repr(value : QueryValue) -> String {
  match value {
    QText(s) => python_string(s)
    QNumber(n) => "Decimal(" + python_string(n.to_string()) + ")"
    QInt(n) => n.to_string()
    QDate(d) =>
      "datetime.date(" +
      d.year.to_string() +
      ", " +
      d.month.to_string() +
      ", " +
      d.day.to_string() +
      ")"
    QBool(b) => if b { "True" } else { "False" }
    QNull => "None"
    QDict(items) =>
      "{" +
      items
      .map(fn(p) { python_string(p.0) + ": " + python_repr(p.1) })
      .join(", ") +
      "}"
    QList(items) => "[" + items.map(python_repr).join(", ") + "]"
    QRecord(name, items) =>
      name +
      "(" +
      items.map(fn(p) { p.0 + "=" + python_repr(p.1) }).join(", ") +
      ")"
    QPythonType(name) => "<class '" + name + "'>"
    QEnum(name, v) => "<" + name + "." + v + ": " + python_string(v) + ">"
    QFrozenSet(items) | QSet(items) =>
      if items.is_empty() {
        "frozenset()"
      } else {
        let sorted = items.copy()
        sorted.sort_by(fn(a, b) { a.lexical_compare(b) })
        "frozenset({" + sorted.map(python_string).join(", ") + "})"
      }
    _ => value.to_text()
  }
}

///|
fn nested_json(value : QueryValue) -> String {
  match value {
    QSet(items) | QFrozenSet(items) => {
      let sorted = items.copy()
      sorted.sort_by(fn(a, b) { a.lexical_compare(b) })
      "[" + sorted.map(fn(s) { QText(s).to_json() }).join(",") + "]"
    }
    QDict(items) =>
      "{" +
      items
      .map(fn(p) { QText(p.0).to_json() + ":" + nested_json(p.1) })
      .join(",") +
      "}"
    QList(items) => "[" + items.map(nested_json).join(",") + "]"
    QRecord(name, items) =>
      "{\"_type\":" +
      QText(name).to_json() +
      (if items.is_empty() { "" } else { "," }) +
      items
      .map(fn(p) { QText(p.0).to_json() + ":" + nested_json(p.1) })
      .join(",") +
      "}"
    QPythonType(name) => "{\"_python_type\":" + QText(name).to_json() + "}"
    QEnum(name, v) =>
      "{\"_enum\":" +
      QText(name).to_json() +
      ",\"value\":" +
      QText(v).to_json() +
      "}"
    QNumber(n) => "{\"_decimal\":" + QText(n.to_string()).to_json() + "}"
    QDate(d) => "{\"_date\":" + QText(d.to_string()).to_json() + "}"
    _ => value.to_json()
  }
}

///|
fn meta_value(value : @ast.MetaValue) -> QueryValue {
  match value {
    MString(s) | MAccount(s) | MCurrency(s) | MTag(s) => QText(s)
    MNumber(n) => QNumber(n)
    MDate(d) => QDate(d)
    MBool(b) => QBool(b)
  }
}

///|
fn source_metadata(
  loc : @ast.Loc,
  meta : @ast.Meta,
) -> Array[(String, QueryValue)] {
  let result = [
    ("filename", QText(loc.file)),
    ("lineno", QInt(@bigint.BigInt::from_int(loc.line))),
  ]
  for (key, value) in meta.entries {
    if key != "filename" && key != "lineno" {
      result.push((key, meta_value(value)))
    }
  }
  result
}
