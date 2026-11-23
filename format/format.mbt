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
fn format_header_date(text : String) -> Bool {
  if text.length() < 4 || !text.get_char(0).unwrap().is_ascii_digit() {
    return false
  }
  let tokens = @syntax.tokenize(text)
  tokens.length() == 2 &&
  tokens[0].kind is Word(normalized) &&
  normalized.length() == 10 &&
  normalized.get_char(4) == Some('-') &&
  normalized.get_char(7) == Some('-') &&
  normalized.iter().all(fn(c) { c.is_ascii_digit() || c == '-' })
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
    | "popmeta" => true
    _ => false
  }
}

///|
fn format_is_transaction_header(text : String) -> Bool {
  let trimmed = format_trimmed(text)
  let (date, after) = format_split_first(trimmed)
  if !format_header_date(date) || after.is_empty() {
    return false
  }

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
    i = i + (if c.to_int() > 0xFFFF { 2 } else { 1 })
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
priv struct FormatRecord {
  text : String
  preserve : Bool
}

///|
fn format_block(
  sb : StringBuilder,
  header : String,
  body : Array[FormatRecord],
) -> Unit {
  sb.write_string(header)
  sb.write_string("\n")
  let postings : Array[FormatPosting] = []
  let mut width = 0
  for line in body {
    let posting = format_posting(line.text)
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
fn format_records(source : String) -> Array[FormatRecord] {
  let records = []
  let mut start = 0
  while start < source.length() {
    let physical = start +
      source[start:].find("\n").unwrap_or(source.length() - start)
    let logical = if source[start:physical].find("\"") is Some(_) {
      @syntax.logical_line_end(source, start~)
    } else {
      physical
    }
    records.push({
      text: source[start:logical].to_owned(),
      preserve: logical > physical,
    })
    start = logical + 1
  }
  records
}

///|
pub fn format_source(source : String) -> String {
  let lines = format_records(source)
  let line_count = lines.length()
  let sb = StringBuilder()
  let mut i = 0
  while i < line_count {
    let line = lines[i]
    if format_is_transaction_header(line.text) {
      let header = if line.preserve {
        line.text
      } else {
        format_trimmed(line.text)
      }
      let body : Array[FormatRecord] = []
      i = i + 1
      while i < line_count && format_starts_indented(lines[i].text) {
        body.push(lines[i])
        i = i + 1
      }
      if line.preserve || body.any(fn(record) { record.preserve }) {
        sb.write_string(line.text)
        sb.write_string("\n")
        for record in body {
          sb.write_string(record.text)
          sb.write_string("\n")
        }
      } else {
        format_block(sb, header, body)
      }
      continue
    }
    sb.write_string(
      if line.preserve {
        line.text
      } else {
        format_trim_end(line.text)
      },
    )
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
