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
        sb.write_char(quote)
        i = i + 2
        continue
      }
      return (sb.to_string(), i + 1)
    }
    sb.write_char(c)
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
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
    if c.is_ascii_digit() ||
      c == '.' ||
      (
        c == '-' &&
        i - start < 10 &&
        text.length() >= start + 10 &&
        bql_char(text, start + 4) == Some('-') &&
        bql_char(text, start + 7) == Some('-')
      ) {
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
      if bql_has_dot(raw) ||
        number.compare(@decimal.Decimal::from_int(2147483647)) > 0 {
        BNum(number)
      } else {
        BInt(bql_parse_int(raw))
      }
    None => BWord(raw)
  }
}

///|
fn lex_bql(
  text : String,
  unsupported~ : Array[String] = [],
  positions~ : Array[Int32] = [],
) -> Array[BTok] {
  let mut selects = 0
  let tokens : Array[BTok] = []
  let mut i = 0
  let len = text.length()
  while i < len {
    let c = match bql_char(text, i) {
      Some(c) => c
      None => {
        unsupported.push(bql_lex_error(text, i))
        break
      }
    }
    if c.to_int() > 0xFFFF {
      unsupported.push(bql_lex_error(text, i))
      i = i + 2
      continue
    }
    if c.is_ascii_whitespace() {
      i = i + 1
      continue
    }
    positions.push(i)
    if c == '"' || c == '\'' {
      let (value, next) = bql_read_string(text, i)
      tokens.push(BStr(value))
      i = next
      continue
    }
    if c.is_ascii_digit() {
      let (raw, next) = bql_read_number(text, i)
      tokens.push(bql_number_token(raw))
      i = next
      continue
    }
    if bql_is_word_start(c) {
      let start = i
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
      let word = sb.to_string()
      let kind = match word.to_lower() {
        "select" => {
          selects = selects + 1
          if selects > 1 {
            "subquery"
          } else {
            ""
          }
        }
        "like" => "like"
        "join" => "join"
        "pivot" => "pivot"
        _ => ""
      }
      if kind != "" {
        let mut line = 1
        let mut column = 1
        for offset in 0..<start {
          if bql_char(text, offset) == Some('\n') {
            line = line + 1
            column = 1
          } else {
            column = column + 1
          }
        }
        unsupported.push(
          "unsupported query.unsupported." +
          kind +
          " at BQL:" +
          line.to_string() +
          ":" +
          column.to_string(),
        )
      }
      tokens.push(BWord(word))
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
  positions.push(len)
  tokens.push(BEof)
  tokens
}

///|
fn bql_lex_error(text : String, index : Int32) -> String {
  let mut line = 1
  let mut column = 1
  for offset in 0..<index {
    if bql_char(text, offset) == Some('\n') {
      line += 1
      column = 1
    } else {
      column += 1
    }
  }
  "lexical query.invalid_character at BQL:" +
  line.to_string() +
  ":" +
  column.to_string()
}
