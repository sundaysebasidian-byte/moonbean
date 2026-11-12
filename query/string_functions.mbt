///|
fn python_whitespace(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 9 && n <= 13) ||
  (n >= 28 && n <= 32) ||
  n == 0x85 ||
  n == 0xA0 ||
  n == 0x1680 ||
  (n >= 0x2000 && n <= 0x200A) ||
  n == 0x2028 ||
  n == 0x2029 ||
  n == 0x202F ||
  n == 0x205F ||
  n == 0x3000
}

///|
fn query_maxwidth(
  ctx : QueryContext,
  text : String,
  width : QueryValue,
) -> QueryValue {
  let n = match query_integer(width) {
    Some(n) => n
    None => {
      // An enormous positive integer cannot shorten an in-memory string.
      if width.to_text().has_prefix("-") {
        query_error(ctx, "query.oracle_type_error: ValueError invalid width")
        return QNull
      }
      2147483647
    }
  }
  if n < 5 {
    query_error(
      ctx, "query.oracle_type_error: ValueError invalid width or placeholder too large",
    )
    return QNull
  }
  let words : Array[String] = []
  let mut word = StringBuilder()
  for c in text.iter() {
    if python_whitespace(c) {
      if word.to_string() != "" {
        words.push(word.to_string())
        word = StringBuilder()
      }
    } else {
      word.write_char(c)
    }
  }
  if word.to_string() != "" {
    words.push(word.to_string())
  }
  let collapsed = words.join(" ")
  if collapsed.iter().count() <= n {
    return QText(collapsed)
  }
  let chunks : Array[String] = []
  for word in words {
    if !chunks.is_empty() {
      chunks.push(" ")
    }
    let chars = word.iter().to_array()
    let word_char = fn(i : Int32) {
      i >= 0 &&
      i < chars.length() &&
      (
        (chars[i].is_ascii_alphabetic() || chars[i].is_ascii_digit()) ||
        chars[i] == '_' ||
        chars[i].to_int() >= 128
      )
    }
    let mut start = 0
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '-' {
        let mut end = i + 1
        while end < chars.length() && chars[end] == '-' {
          end = end + 1
        }
        if end - i >= 2 && word_char(i - 1) && word_char(end) {
          if i > start {
            chunks.push(String::from_iter(chars[start:i].iter()))
          }
          chunks.push(String::from_iter(chars[i:end].iter()))
          start = end
        } else if end == i + 1 &&
          word_char(i - 1) &&
          word_char(end) &&
          (
            word_char(i - 2) ||
            (i >= 3 && chars[i - 2] == '-' && word_char(i - 3))
          ) &&
          (
            word_char(end + 1) ||
            (
              end + 2 < chars.length() &&
              chars[end + 1] == '-' &&
              word_char(end + 2)
            )
          ) {
          chunks.push(String::from_iter(chars[start:end].iter()))
          start = end
        }
        i = end
      } else {
        i = i + 1
      }
    }
    if start < chars.length() {
      chunks.push(String::from_iter(chars[start:].iter()))
    }
  }
  let kept = StringBuilder()
  let mut used = 0
  for chunk in chunks {
    let size = chunk.iter().count()
    if used + size > n - 6 {
      break
    }
    kept.write_string(chunk)
    used = used + size
  }
  let prefix = kept.to_string().trim_end().to_owned()
  QText(if prefix == "" { "[...]" } else { prefix + " [...]" })
}

///|
fn query_regex(
  ctx : QueryContext,
  pattern : String,
  insensitive : Bool,
) -> @string.Regex? {
  // Do not silently reinterpret Python-only constructs in the portable engine.
  if pattern.contains("(?") ||
    pattern.contains("\\") ||
    pattern.contains("{") ||
    pattern.contains("}") {
    query_error(
      ctx, "unsupported query.unsupported.regex: Python regex dialect at BQL:1:1",
    )
    return None
  }
  Some(
    @string.Regex(if insensitive { "(?i:" + pattern + ")" } else { pattern }),
  ) catch {
    _ => {
      query_error(
        ctx, "query.oracle_type_error: PatternError invalid regex at BQL:1:1",
      )
      None
    }
  }
}

///|
fn regex_function(
  ctx : QueryContext,
  name : String,
  values : Array[QueryValue],
  row : BqlRow,
) -> QueryValue {
  let pattern = match values[0] {
    QText(s) => s
    _ => return QNull
  }
  let regex = match query_regex(ctx, pattern, name == "has_account") {
    Some(r) => r
    None => return QNull
  }
  if name == "has_account" {
    let accounts = match eval_column(ctx, row, "accounts") {
      QSet(s) | QFrozenSet(s) => s
      _ => []
    }
    return QBool(accounts.any(fn(a) { regex.execute(a) is Some(_) }))
  }
  if name == "findfirst" {
    let items = match values[1] {
      QSet(s) | QFrozenSet(s) => s
      _ => return QNull
    }
    let found = items.filter(fn(s) { regex.execute(s) is Some(_) })
    if found.length() > 1 {
      query_error(
        ctx, "unsupported query.unsupported.set_representation: findfirst depends on CPython hash seed at BQL:1:1",
      )
      return QNull
    }
    return if found.is_empty() { QNull } else { QText(found[0]) }
  }
  let text = match values[1] {
    QText(s) => s
    _ => return QNull
  }
  let matched = match regex.execute(text) {
    Some(m) => m
    None => return QNull
  }
  if name == "grep" {
    return QText(matched.content().to_owned())
  }
  let index = query_integer(values[2]).unwrap_or(-1)
  // Count capturing parentheses in the accepted dialect, ignoring character classes.
  let mut groups = 0
  let mut in_class = false
  for c in pattern.iter() {
    if c == '[' {
      in_class = true
    }
    if c == ']' {
      in_class = false
    }
    if c == '(' && !in_class {
      groups = groups + 1
    }
  }
  if index < 0 || index > groups {
    query_error(
      ctx, "query.oracle_type_error: IndexError no such group at BQL:1:1",
    )
    QNull
  } else if index == 0 {
    QText(matched.content().to_owned())
  } else {
    matched.group(index).map(fn(s) { QText(s.to_owned()) }).unwrap_or(QNull)
  }
}

///|
fn query_substitute(
  ctx : QueryContext,
  pattern : String,
  replacement : String,
  text : String,
) -> QueryValue {
  if replacement.contains("\\") {
    query_error(
      ctx, "unsupported query.unsupported.regex: Python replacement escapes at BQL:1:1",
    )
    return QNull
  }
  match query_regex(ctx, pattern, false) {
    Some(regex) =>
      if pattern.contains("*?") ||
        pattern.contains("+?") ||
        pattern.contains("??") {
        query_error(
          ctx, "unsupported query.unsupported.regex: adjacent lazy empty and nonempty matches at BQL:1:1",
        )
        QNull
      } else {
        QText(regex.replace_by(text, fn(_) { replacement[:] }).to_owned())
      }
    None => QNull
  }
}
