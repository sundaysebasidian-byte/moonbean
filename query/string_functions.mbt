///|
fn python_whitespace(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 9 && n <= 13) || (n >= 28 && n <= 32) || n == 0x85 || n == 0xA0 ||
  n == 0x1680 || (n >= 0x2000 && n <= 0x200A) || n == 0x2028 || n == 0x2029 ||
  n == 0x202F || n == 0x205F || n == 0x3000
}

///|
fn query_maxwidth(ctx : QueryContext, text : String, width : QueryValue) -> QueryValue {
  if text.contains("-") {
    query_error(ctx, "unsupported query.unsupported.maxwidth: Python hyphen wrapping")
    return QNull
  }
  let n = match query_integer(width) {
    Some(n) => n
    None => {
      // An enormous positive integer cannot shorten an in-memory string.
      if width.to_text().has_prefix("-") { query_error(ctx, "query.oracle_type_error: ValueError invalid width"); return QNull }
      2147483647
    }
  }
  if n < 5 { query_error(ctx, "query.oracle_type_error: ValueError invalid width or placeholder too large"); return QNull }
  let words : Array[String] = []
  let mut word = StringBuilder()
  for c in text.iter() {
    if python_whitespace(c) {
      if word.to_string() != "" { words.push(word.to_string()); word = StringBuilder() }
    } else { word.write_char(c) }
  }
  if word.to_string() != "" { words.push(word.to_string()) }
  let collapsed = words.join(" ")
  if collapsed.iter().count() <= n { return QText(collapsed) }
  let kept : Array[String] = []
  let mut used = 0
  for word in words {
    let size = word.iter().count()
    let next = used + size + (if used > 0 { 1 } else { 0 })
    if next > n - 6 { break }
    kept.push(word)
    used = next
  }
  QText(if kept.is_empty() { "[...]" } else { kept.join(" ") + " [...]" })
}

///|
fn query_regex(ctx : QueryContext, pattern : String, insensitive : Bool) -> @string.Regex? {
  // Do not silently reinterpret Python-only constructs in the portable engine.
  if pattern.contains("(?") || pattern.contains("\\") || pattern.contains("{") || pattern.contains("}") {
    query_error(ctx, "unsupported query.unsupported.regex: Python regex dialect at BQL:1:1")
    return None
  }
  try {
    Some(@string.Regex(if insensitive { "(?i:" + pattern + ")" } else { pattern }))
  } catch {
    _ => { query_error(ctx, "query.oracle_type_error: PatternError invalid regex at BQL:1:1"); None }
  }
}

///|
fn regex_function(ctx : QueryContext, name : String, values : Array[QueryValue], row : BqlRow) -> QueryValue {
  let pattern = match values[0] { QText(s) => s; _ => return QNull }
  let regex = match query_regex(ctx, pattern, name == "has_account") { Some(r) => r; None => return QNull }
  if name == "has_account" {
    let accounts = if row.extra is Some(extra) && extra.cells is Some(cells) {
      match dict_get(cells.get("entry").unwrap_or(QNull), "postings") {
        Some(QList(postings)) => postings.map(fn(p) { dict_get(p, "account").unwrap_or(QNull).to_text() })
        _ => []
      }
    } else { transaction_accounts(row.accounts) }
    return QBool(accounts.any(fn(a) { regex.execute(a) is Some(_) }))
  }
  if name == "findfirst" {
    let items = match values[1] { QSet(s) | QFrozenSet(s) => s; _ => return QNull }
    let found = items.filter(fn(s) { regex.execute(s) is Some(_) })
    if found.length() > 1 {
      query_error(ctx, "unsupported query.unsupported.set_representation: findfirst depends on CPython hash seed at BQL:1:1")
      return QNull
    }
    return if found.is_empty() { QNull } else { QText(found[0]) }
  }
  let text = match values[1] { QText(s) => s; _ => return QNull }
  let matched = match regex.execute(text) { Some(m) => m; None => return QNull }
  if name == "grep" { return QText(matched.content().to_owned()) }
  let index = query_integer(values[2]).unwrap_or(-1)
  // Count capturing parentheses in the accepted dialect, ignoring character classes.
  let mut groups = 0
  let mut in_class = false
  for c in pattern.iter() {
    if c == '[' { in_class = true }
    if c == ']' { in_class = false }
    if c == '(' && !in_class { groups = groups + 1 }
  }
  if index < 0 || index > groups {
    query_error(ctx, "query.oracle_type_error: IndexError no such group at BQL:1:1")
    QNull
  } else if index == 0 { QText(matched.content().to_owned()) }
  else { matched.group(index).map(fn(s) { QText(s.to_owned()) }).unwrap_or(QNull) }
}
