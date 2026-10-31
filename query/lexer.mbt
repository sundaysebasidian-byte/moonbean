// A small BQL tokenizer.  It is intentionally independent from the ledger
// lexer: BQL has operators, quoted strings and expressions on one line.

///|
priv enum BTok {
  BWord(String)
  BStr(String)
  BInt(Int32)
  BNum(@decimal.Decimal)
  BDate(@ast.Date)
  BSym(String)
  BEof
}

///|
fn bql_char(text : String, index : Int32) -> Char? {
  text.get_char(index)
}

///|
fn bql_is_word_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_'
}

///|
fn bql_is_word_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '_' ||
  c == ':' ||
  c == '.' ||
  c == '-'
}

///|
fn bql_read_string(text : String, start : Int32) -> (String, Int32) {
  let quote = match bql_char(text, start) {
    Some(c) => c
    None => '"'
  }
  let sb = StringBuilder()
  let mut i = start + 1
  let len = text.length()
  while i < len {
    let c = match bql_char(text, i) {
      Some(c) => c
      None => break
    }
    if c == quote {
      if i + 1 < len && bql_char(text, i + 1) == Some(quote) {
        sb.write_char(quote)
        i = i + 2
        continue
      }
      return (sb.to_string(), i + 1)
    }
    if c == '\\' && i + 1 < len {
      let escaped = match bql_char(text, i + 1) {
        Some(c) => c
        None => '\\'
      }
      let decoded = match escaped {
        'n' => '\n'
        't' => '\t'
        'r' => '\r'
        other => other
      }
      sb.write_char(decoded)
      i = i + 2
      continue
    }
    sb.write_char(c)
    i = i + 1
  }
  (sb.to_string(), i)
}

///|
fn bql_read_number(text : String, start : Int32) -> (String, Int32) {
  let sb = StringBuilder()
  let mut i = start
  let len = text.length()
  while i < len {
    let c = match bql_char(text, i) {
      Some(c) => c
      None => break
    }
    if c.is_ascii_digit() || c == '-' || c == '.' {
      sb.write_char(c)
      i = i + 1
    } else {
      break
    }
  }
  (sb.to_string(), i)
}

///|
fn bql_parse_int(raw : String) -> Int32 {
  let mut value = 0
  let mut i = 0
  let mut negative = false
  if raw.length() > 0 && bql_char(raw, 0) == Some('-') {
    negative = true
    i = 1
  }
  while i < raw.length() {
    let c = match bql_char(raw, i) {
      Some(c) => c
      None => break
    }
    let digit = c.to_int() - 48
    value = value * 10 + digit
    i = i + 1
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
fn bql_has_dot(raw : String) -> Bool {
  for i in 0..<raw.length() {
    if bql_char(raw, i) == Some('.') {
      return true
    }
  }
  false
}

///|
fn bql_number_token(raw : String) -> BTok {
  if raw.length() == 10 &&
    bql_char(raw, 4) == Some('-') &&
    bql_char(raw, 7) == Some('-') {
    match @ast.Date::parse(raw) {
      Some(date) => return BDate(date)
      None => ()
    }
  }
  match @decimal.Decimal::parse(raw) {
    Some(number) =>
      if bql_has_dot(raw) {
        BNum(number)
      } else {
        BInt(bql_parse_int(raw))
      }
    None => BWord(raw)
  }
}

///|
fn bql_starts_signed_number(text : String, index : Int32) -> Bool {
  if bql_char(text, index) != Some('-') {
    return false
  }
  match bql_char(text, index + 1) {
    Some(d) => d.is_ascii_digit()
    None => false
  }
}

///|
fn lex_bql(text : String) -> Array[BTok] {
  let tokens : Array[BTok] = []
  let mut i = 0
  let len = text.length()
  while i < len {
    let c = match bql_char(text, i) {
      Some(c) => c
      None => break
    }
    if c.is_ascii_whitespace() {
      i = i + 1
      continue
    }
    if c == '"' || c == '\'' {
      let (value, next) = bql_read_string(text, i)
      tokens.push(BStr(value))
      i = next
      continue
    }
    if c.is_ascii_digit() || bql_starts_signed_number(text, i) {
      let (raw, next) = bql_read_number(text, i)
      tokens.push(bql_number_token(raw))
      i = next
      continue
    }
    if bql_is_word_start(c) {
      let sb = StringBuilder()
      while i < len {
        let ch = match bql_char(text, i) {
          Some(ch) => ch
          None => break
        }
        if bql_is_word_char(ch) {
          sb.write_char(ch)
          i = i + 1
        } else {
          break
        }
      }
      tokens.push(BWord(sb.to_string()))
      continue
    }
    let next = if i + 1 < len { bql_char(text, i + 1) } else { None }
    let two = match next {
      Some(n) => {
        let pair = StringBuilder()
        pair.write_char(c)
        pair.write_char(n)
        pair.to_string()
      }
      None => ""
    }
    if two == "<=" || two == ">=" || two == "!=" || two == "<>" || two == "==" {
      tokens.push(BSym(two))
      i = i + 2
    } else {
      let sym = StringBuilder()
      sym.write_char(c)
      tokens.push(BSym(sym.to_string()))
      i = i + 1
    }
  }
  tokens.push(BEof)
  tokens
}
