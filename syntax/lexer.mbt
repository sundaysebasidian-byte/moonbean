// Line lexer for the Beancount textual syntax.  The grammar is line and
// indentation sensitive, so tokens never cross a physical line.

///|
pub(all) enum TokenKind {
  Word(String)
  Str(String)
  LBrace
  RBrace
  LDoubleBrace
  RDoubleBrace
  At
  AtAt
  Tilde
  Comma
  Star
  Tag(String)
  Link(String)
  Eof
}

///|
pub(all) struct Token {
  kind : TokenKind
  pos : Int32
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
fn is_delimiter(c : Char) -> Bool {
  is_space(c) ||
  c == '{' ||
  c == '}' ||
  c == '@' ||
  c == '~' ||
  c == ',' ||
  c == '#' ||
  c == '^' ||
  c == ';' ||
  c == '"'
}

///|
fn is_digit(c : Char) -> Bool {
  c.is_ascii_digit()
}

///|
fn read_string(text : String, start : Int32) -> (String, Int32) {
  let sb = StringBuilder()
  let mut i = start + 1
  let len = text.length()
  while i < len {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == '"' {
      return (sb.to_string(), i + 1)
    }
    if c == '\\' && i + 1 < len {
      let escaped = match text.get_char(i + 1) {
        Some(c) => c
        None => '\\'
      }
      match escaped {
        'n' => sb.write_string("\n")
        't' => sb.write_string("\t")
        'r' => sb.write_string("\r")
        '"' => sb.write_char('"')
        '\\' => sb.write_char('\\')
        _ => {
          sb.write_char('\\')
          sb.write_char(escaped)
        }
      }
      i = i + 1 + (if escaped.to_int() > 0xFFFF { 2 } else { 1 })
    } else {
      sb.write_char(c)
      i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
    }
  }
  (sb.to_string(), len)
}

///|
pub fn tokenize(text : String) -> Array[Token] {
  tokenize_guarded(text, None)
}

///|
fn tokenize_guarded(text : String, signed_zero : Array[Bool]?) -> Array[Token] {
  let tokens = []
  let len = text.length()
  let mut i = 0
  while i < len {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if is_space(c) {
      i = i + 1
      continue
    }
    if c == ';' {
      break
    }
    if c == '"' {
      let (value, next) = read_string(text, i)
      tokens.push({ kind: Str(value), pos: i, })
      i = next
      continue
    }
    if c == '{' {
      if i + 1 < len && text.get_char(i + 1) == Some('{') {
        tokens.push({ kind: LDoubleBrace, pos: i, })
        i = i + 2
      } else {
        tokens.push({ kind: LBrace, pos: i, })
        i = i + 1
      }
      continue
    }
    if c == '}' {
      if i + 1 < len && text.get_char(i + 1) == Some('}') {
        tokens.push({ kind: RDoubleBrace, pos: i, })
        i = i + 2
      } else {
        tokens.push({ kind: RBrace, pos: i, })
        i = i + 1
      }
      continue
    }
    if c == '@' {
      if i + 1 < len && text.get_char(i + 1) == Some('@') {
        tokens.push({ kind: AtAt, pos: i, })
        i = i + 2
      } else {
        tokens.push({ kind: At, pos: i, })
        i = i + 1
      }
      continue
    }
    if c == '~' {
      tokens.push({ kind: Tilde, pos: i, })
      i = i + 1
      continue
    }
    if c == ',' {
      tokens.push({ kind: Comma, pos: i, })
      i = i + 1
      continue
    }
    if c == '*' {
      tokens.push({ kind: Star, pos: i, })
      i = i + 1
      continue
    }
    if c == '#' || c == '^' {
      let start = i + 1
      let mut j = start
      while j < len {
        let d = match text.get_char(j) {
          Some(d) => d
          None => break
        }
        if is_delimiter(d) {
          break
        }
        j = j + (if d.to_int() > 0xFFFF { 2 } else { 1 })
      }
      let value = if start < j {
        text.unsafe_substring(start~, end=j)
      } else {
        ""
      }
      if c == '#' {
        tokens.push({ kind: Tag(value), pos: i, })
      } else {
        tokens.push({ kind: Link(value), pos: i, })
      }
      i = j
      continue
    }
    let number_start = if is_digit(c) {
      true
    } else if c == '-' || c == '+' || c == '.' {
      if i + 1 < len {
        match text.get_char(i + 1) {
          Some(d) => is_digit(d)
          None => false
        }
      } else {
        false
      }
    } else {
      false
    }
    let start = i
    let mut j = i
    while j < len {
      let d = match text.get_char(j) {
        Some(d) => d
        None => break
      }
      if d == ',' {
        let mut join = false
        if number_start && j + 1 < len {
          match text.get_char(j + 1) {
            Some(e) => if is_digit(e) { join = true }
            None => ()
          }
        }
        if join {
          j = j + 1
          continue
        }
        break
      }
      if d == '+' || d == '/' || d == '(' || d == ')' {
        break
      }
      if is_delimiter(d) {
        break
      }
      j = j + (if d.to_int() > 0xFFFF { 2 } else { 1 })
    }
    if j == start {
      // Unknown punctuation: consume it as a one character word so that the
      // parser can report a precise error instead of looping forever.
      j = j + (if c.to_int() > 0xFFFF { 2 } else { 1 })
    }
    let word = text.unsafe_substring(start~, end=j)
    if signed_zero is Some(flag) &&
      !flag[0] &&
      word.has_prefix("-0") &&
      word[1:].iter().all(fn(c) { c == '0' || c == '.' || c == ',' }) {
      flag[0] = true
    }
    tokens.push({ kind: Word(word), pos: start, })
    i = j
  }
  tokens.push({ kind: Eof, pos: len, })
  tokens
}
