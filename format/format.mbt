// Source formatter.  It keeps directives verbatim (minus trailing spaces) and
// canonicalizes transaction blocks: postings are indented by two spaces and
// their amounts are aligned in one column per transaction.

///|
fn format_view(view : StringView) -> String {
  String::from_iter(view.iter())
}

///|
fn format_trimmed(text : String) -> String {
  format_view(text.trim())
}

///|
fn format_trim_end(text : String) -> String {
  format_view(text.trim_end())
}

///|
fn format_starts_indented(text : String) -> Bool {
  match text.get_char(0) {
    Some(' ') => true
    Some('\t') => true
    _ => false
  }
}

///|
fn format_is_ascii_digit_at(text : String, index : Int32) -> Bool {
  match text.get_char(index) {
    Some(c) => c.is_ascii_digit()
    None => false
  }
}

///|
fn format_is_date_prefix(text : String) -> Bool {
  text.length() >= 10 &&
  format_is_ascii_digit_at(text, 0) &&
  format_is_ascii_digit_at(text, 1) &&
  format_is_ascii_digit_at(text, 2) &&
  format_is_ascii_digit_at(text, 3) &&
  text.get_char(4) == Some('-') &&
  format_is_ascii_digit_at(text, 5) &&
  format_is_ascii_digit_at(text, 6) &&
  text.get_char(7) == Some('-') &&
  format_is_ascii_digit_at(text, 8) &&
  format_is_ascii_digit_at(text, 9)
}

///|
fn format_first_token(text : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < text.length() {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == ' ' || c == '\t' {
      break
    }
    sb.write_char(c)
    i = i + 1
  }
  sb.to_string()
}

///|
fn format_is_directive(word : String) -> Bool {
  match word {
    "open"
    | "close"
    | "commodity"
    | "balance"
    | "pad"
    | "price"
    | "note"
    | "document"
    | "event"
    | "query"
    | "custom"
    | "plugin"
    | "include"
    | "option"
    | "pushtag"
    | "poptag"
    | "pushmeta"
    | "popmeta"
    | "txn" => true
    _ => false
  }
}

///|
fn format_is_transaction_header(text : String) -> Bool {
  let trimmed = format_trimmed(text)
  if !format_is_date_prefix(trimmed) {
    return false
  }
  if trimmed.length() < 12 {
    return false
  }
  if trimmed.get_char(10) != Some(' ') {
    return false
  }
  let after = format_view(trimmed[11:])
  let word = format_first_token(after)
  !format_is_directive(word)
}

///|
fn format_account_root(word : String) -> String {
  let mut i = 0
  while i < word.length() {
    if word.get_char(i) == Some(':') {
      return format_view(word[0:i])
    }
    i = i + 1
  }
  word
}

///|
fn format_is_account(word : String) -> Bool {
  match format_account_root(word) {
    "Assets" | "Liabilities" | "Equity" | "Income" | "Expenses" => true
    _ => false
  }
}

///|
fn format_split_first(text : String) -> (String, String) {
  let mut i = 0
  while i < text.length() {
    let c = match text.get_char(i) {
      Some(c) => c
      None => break
    }
    if c == ' ' || c == '\t' {
      break
    }
    i = i + 1
  }
  let head = format_view(text[0:i])
  let rest = format_trimmed(format_view(text[i:]))
  (head, rest)
}

///|
priv struct FormatPosting {
  account_part : String
  rest : String
  metadata : Bool
  raw : String
}

///|
fn format_posting(line : String) -> FormatPosting {
  let content = format_trimmed(line)
  let (first, rest) = format_split_first(content)
  if format_is_account(first) {
    { account_part: first, rest, metadata: false, raw: line, }
  } else if first.length() == 1 && rest.length() > 0 {
    let (second, tail) = format_split_first(rest)
    if format_is_account(second) {
      {
        account_part: first + " " + second,
        rest: tail,
        metadata: false,
        raw: line,
      }
    } else {
      { account_part: "", rest: "", metadata: true, raw: line, }
    }
  } else {
    { account_part: "", rest: "", metadata: true, raw: line, }
  }
}

///|
fn format_pad_right(text : String, width : Int32) -> String {
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
fn format_block(
  sb : StringBuilder,
  header : String,
  body : Array[String],
) -> Unit {
  sb.write_string(header)
  sb.write_string("\n")
  let postings : Array[FormatPosting] = []
  let mut width = 0
  for line in body {
    let posting = format_posting(line)
    if !posting.metadata && posting.rest.length() > 0 {
      if posting.account_part.length() > width {
        width = posting.account_part.length()
      }
    }
    postings.push(posting)
  }
  for posting in postings {
    if posting.metadata {
      sb.write_string(format_trim_end(posting.raw))
      sb.write_string("\n")
    } else if posting.rest.length() == 0 {
      sb.write_string("  ")
      sb.write_string(posting.account_part)
      sb.write_string("\n")
    } else {
      sb.write_string("  ")
      sb.write_string(format_pad_right(posting.account_part, width))
      sb.write_string("  ")
      sb.write_string(posting.rest)
      sb.write_string("\n")
    }
  }
}

///|
pub fn format_source(source : String) -> String {
  let lines : Array[String] = []
  for view in source.split("\n") {
    lines.push(format_view(view))
  }
  let line_count = if lines.length() > 0 && lines[lines.length() - 1] == "" {
    lines.length() - 1
  } else {
    lines.length()
  }
  let sb = StringBuilder()
  let mut i = 0
  while i < line_count {
    let line = lines[i]
    if format_is_transaction_header(line) {
      let header = format_trimmed(line)
      let body : Array[String] = []
      i = i + 1
      while i < line_count && format_starts_indented(lines[i]) {
        body.push(lines[i])
        i = i + 1
      }
      format_block(sb, header, body)
      continue
    }
    sb.write_string(format_trim_end(line))
    sb.write_string("\n")
    i = i + 1
  }
  let text = sb.to_string()
  if text.length() > 0 && text.get_char(text.length() - 1) == Some('\n') {
    text
  } else {
    text + "\n"
  }
}
