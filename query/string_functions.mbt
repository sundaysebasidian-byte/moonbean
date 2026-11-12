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
  let portable = StringBuilder()
  let chars = pattern.iter().to_array()
  let mut in_class = false
  let mut index = 0
  while index < chars.length() {
    let c = chars[index]
    if c == '\\' {
      index = index + 1
      if index >= chars.length() {
        query_error(
          ctx, "query.oracle_type_error: PatternError trailing escape",
        )
        return None
      }
      let escaped = chars[index]
      if "dDsSwWbBAZ0123456789NxU".contains(escaped.to_string()) {
        query_error(
          ctx, "unsupported query.unsupported.regex: Python Unicode classes or assertions",
        )
        return None
      }
      portable.write_char('\\')
      portable.write_char(escaped)
    } else {
      if c == '[' {
        in_class = true
      }
      if c == ']' {
        in_class = false
      }
      if c == '(' &&
        !in_class &&
        index + 1 < chars.length() &&
        chars[index + 1] == '?' &&
        !((index + 2 < chars.length() && chars[index + 2] == ':') ||
        (
          index + 3 < chars.length() &&
          chars[index + 2] == 'i' &&
          chars[index + 3] == ':'
        )) {
        query_error(
          ctx, "unsupported query.unsupported.regex: Python lookaround, backreferences or flags",
        )
        return None
      }
      if c == '.' && !in_class {
        portable.write_string("[^\n]")
      } else {
        portable.write_char(c)
      }
    }
    index = index + 1
  }
  let pattern = portable.to_string()
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
  let groups = regex_group_count(pattern)
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
  let groups = regex_group_count(pattern)
  regex_replacement(ctx, replacement, groups, None) |> ignore
  if ctx.error is Some(_) {
    return QNull
  }
  match query_regex(ctx, pattern, false) {
    Some(regex) =>
      if (
          pattern.contains("*?") ||
          pattern.contains("+?") ||
          pattern.contains("??") ||
          pattern.contains("}?")
        ) &&
        regex
        .find(text)
        .any(fn(m) { m.content().is_empty() && !m.after().is_empty() }) {
        query_error(
          ctx, "unsupported query.unsupported.regex: adjacent lazy empty and nonempty matches at BQL:1:1",
        )
        QNull
      } else {
        QText(
          regex
          .replace_by(text, fn(m) {
            regex_replacement(ctx, replacement, groups, Some(m))[:]
          })
          .to_owned(),
        )
      }
    None => QNull
  }
}

///|
fn regex_group_count(pattern : String) -> Int32 {
  let chars = pattern.iter().to_array()
  let mut groups = 0
  let mut in_class = false
  let mut escaped = false
  for i in 0..<chars.length() {
    let c = chars[i]
    if escaped {
      escaped = false
      continue
    }
    if c == '\\' {
      escaped = true
      continue
    }
    if c == '[' {
      in_class = true
    }
    if c == ']' {
      in_class = false
    }
    if c == '(' && !in_class && !(i + 1 < chars.length() && chars[i + 1] == '?') {
      groups = groups + 1
    }
  }
  groups
}

///|
fn regex_replacement(
  ctx : QueryContext,
  replacement : String,
  groups : Int32,
  matched : @string.MatchResult?,
) -> String {
  let chars = replacement.iter().to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i = i + 1
    if c != '\\' {
      out.write_char(c)
      continue
    }
    if i == chars.length() {
      query_error(
        ctx, "query.oracle_type_error: PatternError trailing replacement escape",
      )
      return ""
    }
    let c = chars[i]
    i = i + 1
    let mut group = -1
    if c == 'g' && i < chars.length() && chars[i] == '<' {
      i = i + 1
      let name = StringBuilder()
      while i < chars.length() && chars[i] != '>' {
        name.write_char(chars[i])
        i = i + 1
      }
      if i == chars.length() ||
        name.to_string() == "" ||
        !name.to_string().iter().all(fn(c) { c >= '0' && c <= '9' }) {
        query_error(
          ctx, "query.oracle_type_error: PatternError invalid replacement group",
        )
        return ""
      }
      i = i + 1
      group = bql_parse_int(name.to_string())
    } else if c >= '0' && c <= '9' {
      let octal = c == '0' ||
        (
          c <= '7' &&
          i + 1 < chars.length() &&
          chars[i] >= '0' &&
          chars[i] <= '7' &&
          chars[i + 1] >= '0' &&
          chars[i + 1] <= '7'
        )
      let mut value = c.to_int() - 48
      let mut digits = 1
      while i < chars.length() &&
            digits < (if octal { 3 } else { 2 }) &&
            chars[i] >= '0' &&
            chars[i] <= (if octal { '7' } else { '9' }) {
        value = value * (if octal { 8 } else { 10 }) + chars[i].to_int() - 48
        i = i + 1
        digits = digits + 1
      }
      if octal {
        if value > 255 {
          query_error(
            ctx, "query.oracle_type_error: PatternError octal escape out of range",
          )
          return ""
        }
        out.write_char(value.unsafe_to_char())
      } else {
        group = value
      }
    } else {
      match c {
        '\\' => out.write_char('\\')
        'n' => out.write_char('\n')
        'r' => out.write_char('\r')
        't' => out.write_char('\t')
        'a' => out.write_char((7).unsafe_to_char())
        'b' => out.write_char((8).unsafe_to_char())
        'f' => out.write_char((12).unsafe_to_char())
        'v' => out.write_char((11).unsafe_to_char())
        _ => {
          if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
            query_error(
              ctx, "query.oracle_type_error: PatternError bad replacement escape",
            )
            return ""
          }
          out.write_char('\\')
          out.write_char(c)
        }
      }
    }
    if group >= 0 {
      if group > groups {
        query_error(
          ctx, "query.oracle_type_error: PatternError invalid group reference",
        )
        return ""
      }
      if matched is Some(m) {
        out.write_string(
          if group == 0 {
            m.content().to_owned()
          } else {
            m.group(group).map(fn(s) { s.to_owned() }).unwrap_or("")
          },
        )
      }
    }
  }
  out.to_string()
}
