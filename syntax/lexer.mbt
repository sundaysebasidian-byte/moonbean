// Line lexer for the Beancount textual syntax.  The grammar is line and
// indentation sensitive; the parser supplies complete logical lines.

///|
pub(all) enum TokenKind {
  Word(String)
  Str(String)
  Invalid(String)
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
  c == '|' ||
  c == ',' ||
  c == '#' ||
  c == '^' ||
  c == ';' ||
  c == '"'
}

///|
fn tag_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '-' ||
  c == '_' ||
  c == '/' ||
  c == '.'
}

///|
// Longest slash-prefixed commodity token. A numeric divisor has no letter.
fn futures_end(text : String, start : Int32) -> Int32 {
  let mut i = start + 1
  let mut end = start
  let mut letter = false
  while text.get_char(i) is Some(c) {
    if c >= 'A' && c <= 'Z' {
      letter = true
    } else if !c.is_ascii_digit() &&
      c != '.' &&
      c != '_' &&
      c != '-' &&
      c != '\'' {
      break
    }
    i += 1
    if letter && (c.is_ascii_alphabetic() || c.is_ascii_digit()) {
      end = i
    }
  }
  end
}

///|
fn is_digit(c : Char) -> Bool {
  c.is_ascii_digit()
}

///|
// A ledger date has three digit fields and at least four year digits.
// Keep Date::parse's ISO-only contract for BQL and external callers.
fn date_token(text : String, start : Int32) -> (TokenKind, Int32)? {
  guard text.get_char(start + 3) is Some(fourth) && fourth.is_ascii_digit() else {
    return None
  }
  let mut i = start
  let parts = []
  for field in 0..<3 {
    let begin = i
    let mut value = 0
    while text.get_char(i) is Some(c) && c.is_ascii_digit() {
      // Values over 9999 cannot be valid; saturate instead of overflowing.
      if value <= 9999 {
        value = value * 10 + c.to_int() - '0'.to_int()
      }
      i += 1
    }
    if i == begin || (field == 0 && i - begin < 4) {
      return None
    }
    parts.push(value)
    if field < 2 {
      let sep = text.get_char(i)
      if sep != Some('-') && sep != Some('/') {
        return None
      }
      i += 1
    }
  }
  match @ast.Date::new(parts[0], parts[1], parts[2]) {
    Some(date) => Some((Word(date.to_string()), i))
    None => Some((Invalid(text[start:i].to_owned()), i))
  }
}

///|
fn read_string(text : String, start : Int32) -> (String, Int32, Bool) {
  let sb = StringBuilder()
  let mut i = start + 1
  let len = text.length()
  while i < len {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == '"' {
      return (sb.to_string(), i + 1, true)
    }
    if c == '\\' && i + 1 < len {
      let escaped = match text.get_char(i + 1) {
        Some(c) => c
        None => '\\'
      }
      if escaped == '\n' {
        return (sb.to_string(), i, false)
      }
      match escaped {
        'n' => sb.write_string("\n")
        't' => sb.write_string("\t")
        'r' => sb.write_string("\r")
        'b' => sb.write_char('\u{0008}')
        'f' => sb.write_char('\u{000C}')
        '"' => sb.write_char('"')
        '\\' => sb.write_char('\\')
        _ => sb.write_char(escaped)
      }
      i = i + 1 + (if escaped.to_int() > 0xFFFF { 2 } else { 1 })
    } else {
      sb.write_char(c)
      i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
    }
  }
  (sb.to_string(), len, false)
}

///|
pub fn tokenize(text : String) -> Array[Token] {
  tokenize_guarded(text, None)
}

///|
fn tokenize_guarded(
  text : String,
  signed_zero : Array[Bool]?,
  words~ : Map[String, String]? = None,
) -> Array[Token] {
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
      let (value, next, closed) = read_string(text, i)
      if !closed {
        tokens.push({ kind: Invalid(text[i:].to_owned()), pos: i, })
        break
      }
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
    if c == '|' {
      tokens.push({ kind: Word("|"), pos: i, })
      i += 1
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
        if !tag_char(d) {
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
      } else if value == "" {
        tokens.push({ kind: Invalid("^"), pos: i, })
      } else {
        tokens.push({ kind: Link(value), pos: i, })
      }
      i = j
      continue
    }
    if c == '-' &&
      tokens.last() is Some(previous) &&
      previous.kind is Word(word) &&
      (
        word == ")" ||
        (
          word.get_char(0) is Some(first) &&
          (first.is_ascii_digit() || first == '-' || first == '+') &&
          @decimal.Decimal::parse(normal_ledger_number(word)) is Some(_)
        )
      ) {
      tokens.push({ kind: Word("-"), pos: i, })
      i += 1
      continue
    }
    if (c == '-' || c == '+') && text.get_char(i + 1) == Some('.') {
      tokens.push({ kind: Word(c.to_string()), pos: i, })
      i += 1
      continue
    }
    if c == '/' {
      let next = futures_end(text, i)
      if next > i {
        tokens.push({ kind: Word(text[i:next].to_owned()), pos: i, })
        i = next
        continue
      }
    }
    if is_digit(c) && date_token(text, i) is Some((kind, next)) {
      tokens.push({ kind, pos: i, })
      i = next
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
        if number_start && double_leading_group(text, start, j) {
          j += 2
          continue
        }
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
      if d == '+' ||
        d == '/' ||
        d == '(' ||
        d == ')' ||
        d == '*' ||
        (
          d == '-' &&
          number_start &&
          j > start &&
          !(text.get_char(start + 4) == Some('-') &&
          text.get_char(start + 7) == Some('-'))
        ) {
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
    let text_word = text.unsafe_substring(start~, end=j)
    // A quote only starts a string after a recognized lexical token. Unknown
    // words consume the entire non-whitespace run, including attached quotes.
    if text.get_char(j) == Some('"') && !quoted_word_prefix(text_word) {
      while j < len && text.get_char(j) is Some(c) && !is_space(c) && c != '\n' {
        j += if c.to_int() > 0xFFFF { 2 } else { 1 }
      }
      tokens.push({ kind: Invalid(text[start:j].to_owned()), pos: start, })
      i = j
      continue
    }
    if (
        c == '.' &&
        text_word.length() > 1 &&
        text_word.get_char(1) is Some(c) &&
        c.is_ascii_digit()
      ) ||
      (
        ((c == '-' || c == '+') && text.get_char(start + 1) == Some('.')) &&
        text_word.length() > 2
      ) {
      tokens.push({ kind: Invalid(text_word), pos: start, })
      i = j
      continue
    }
    if (text_word.length() == 1 && ((c >= 'a' && c <= 'z') || c == '\'')) ||
      (
        c >= 'A' &&
        c <= 'Z' &&
        text_word.length() > 1 &&
        !text_word.contains(":") &&
        text_word != "TRUE" &&
        text_word != "FALSE" &&
        text_word != "NULL" &&
        !ledger_currency(text_word)
      ) {
      tokens.push({ kind: Invalid(text_word), pos: start, })
      i = j
      continue
    }
    let word = match words {
      Some(cache) =>
        match cache.get(text_word) {
          Some(word) => word
          None => {
            if cache.length() < literal_cache_limit {
              cache[text_word] = text_word
            }
            text_word
          }
        }
      None => text_word
    }
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

///|
fn double_leading_group(text : String, start : Int32, comma : Int32) -> Bool {
  let first = if text.get_char(start) == Some('+') ||
    text.get_char(start) == Some('-') {
    start + 1
  } else {
    start
  }
  comma == first + 1 &&
  text.get_char(first) is Some(digit) &&
  digit.is_ascii_digit() &&
  text.get_char(comma) == Some(',') &&
  text.get_char(comma + 1) == Some(',') &&
  text.get_char(comma + 2) is Some(next) &&
  next.is_ascii_digit()
}

///|
fn normal_ledger_number(text : String) -> String {
  let comma = if text.has_prefix("-") || text.has_prefix("+") { 2 } else { 1 }
  if double_leading_group(text, 0, comma) {
    text[:comma].to_owned() + text[comma + 1:].to_owned()
  } else {
    text
  }
}

///|
fn physical_line_end(source : String, start : Int32) -> Int32 {
  let mut i = start
  while i < source.length() {
    guard source.get_char(i) is Some(c) else { break }
    if c == '\n' {
      break
    }
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
  }
  i
}

///|
// Search without consuming the iterator. Only actual string openings extend
// the logical line; invalid word/quote runs end at their physical newline.
fn multiline_line_end(
  source : String,
  opening : Int32,
  initial_end : Int32,
) -> Int32 {
  let mut quote = opening
  let mut end = initial_end
  while quote < source.length() {
    let mut i = quote + 1
    let mut closed = false
    while i < source.length() {
      guard source.get_char(i) is Some(c) else { break }
      if c == '"' {
        closed = true
        i = i + 1
        break
      }
      if c == '\\' {
        i = i + 1
        if source.get_char(i) == Some('\n') {
          return end
        }
        if source.get_char(i) is Some(escaped) {
          i = i + (if escaped.to_int() > 0xFFFF { 2 } else { 1 })
        }
      } else {
        i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
      }
    }
    if !closed {
      return end
    }
    end = physical_line_end(source, i)
    let tail = tokenize(source[i:end].to_owned())
    if tail.length() < 2 {
      return end
    }
    match tail[tail.length() - 2].kind {
      Invalid(raw) if raw.has_prefix("\"") =>
        quote = i + tail[tail.length() - 2].pos
      _ => return end
    }
  }
  end
}

///|
/// Return the physical newline boundary that ends a logical source line.
pub fn logical_line_end(source : String, start~ : Int32 = 0) -> Int32 {
  let end = physical_line_end(source, start)
  if ignored_heading(source[start:end].to_owned()) {
    return end
  }
  let tokens = tokenize(source[start:end].to_owned())
  if tokens.length() > 1 &&
    tokens[tokens.length() - 2].kind is Invalid(raw) &&
    raw.has_prefix("\"") {
    multiline_line_end(source, start + tokens[tokens.length() - 2].pos, end)
  } else {
    end
  }
}

///|
fn ignored_heading(line : String) -> Bool {
  guard line.get_char(0) is Some(first) && line.get_char(1) is Some(next) else {
    return false
  }
  match first {
    '*' | ':' | '!' | '&' | '?' | '%' => true
    '#' => !tag_char(next)
    _ => false
  }
}

///|
fn quoted_word_prefix(word : String) -> Bool {
  lexical_account(word) ||
  (is_valid_currency(word) && word.length() > 1) ||
  @ast.Date::parse(word) is Some(_) ||
  (
    word.get_char(0) is Some(c) &&
    (c.is_ascii_digit() || c == '-' || c == '+') &&
    @decimal.Decimal::parse(word) is Some(_)
  ) ||
  meta_key_from_word(word) is Some(_) ||
  [
    "option", "plugin", "include", "pushtag", "poptag", "pushmeta", "popmeta", "open",
    "close", "commodity", "pad", "balance", "price", "event", "query", "note", "document",
    "custom", "txn", "TRUE", "FALSE", "NULL",
  ].contains(word)
}

///|
fn is_flag_word(word : String) -> Bool {
  word.length() == 1 &&
  word.get_char(0) is Some(c) &&
  ((c >= 'A' && c <= 'Z') || "!%&?".contains(word))
}
