// Line oriented parser for Beancount v3 syntax.  The parser records errors
// with file and line and keeps going so that a check run reports as many
// problems as possible in one pass.

///|
fn view_to_string(view : StringView) -> String {
  view.to_owned()
}

///|
fn trimmed(text : String) -> String {
  view_to_string(text.trim())
}

///|
fn starts_whitespace(text : String) -> Bool {
  match text.get_char(0) {
    Some(c) => c == ' ' || c == '\t'
    None => false
  }
}

///|
fn is_blank_line(text : String) -> Bool {
  trimmed(text).length() == 0
}

///|
pub fn is_valid_account(account : String) -> Bool {
  @ast.valid_account_name(account)
}

///|
fn lexical_account(account : String) -> Bool {
  let parts = @ast.account_parts(account)
  if parts.length() < 2 {
    return false
  }
  for index in 0..<parts.length() {
    let part = parts[index]
    guard part.get_char(0) is Some(first) else { return false }
    if !((first >= 'A' && first <= 'Z') ||
      first.to_int() >= 128 ||
      (index > 0 && first.is_ascii_digit())) {
      return false
    }
    for i in 1..<part.length() {
      if part.get_char(i) is Some(c) {
        if !(c.is_ascii_alphabetic() ||
          c.is_ascii_digit() ||
          c == '-' ||
          c.to_int() >= 128) {
          return false
        }
      }
    }
  }
  true
}

///|
pub fn is_valid_currency(currency : String) -> Bool {
  if currency.length() == 0 {
    return false
  }
  let first = match currency.get_char(0) {
    Some(c) => c
    None => return false
  }
  if first == '/' {
    return futures_end(currency, 0) == currency.length()
  }
  if !(first >= 'A' && first <= 'Z') {
    return false
  }
  for i in 1..<currency.length() {
    let c = match currency.get_char(i) {
      Some(c) => c
      None => return false
    }
    let ok = (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '\'' ||
      c == '.' ||
      c == '_' ||
      c == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
// Unquoted ledger currencies also exclude lexer literals and ending punctuation.
fn ledger_currency(currency : String) -> Bool {
  guard is_valid_currency(currency) &&
    currency != "TRUE" &&
    currency != "FALSE" &&
    currency != "NULL" else {
    return false
  }
  guard currency.get_char(currency.length() - 1) is Some(last) else {
    return false
  }
  (last >= 'A' && last <= 'Z') || last.is_ascii_digit()
}

///|
fn is_booking_method(booking : String) -> Bool {
  booking == "STRICT" ||
  booking == "STRICT_WITH_SIZE" ||
  booking == "FIFO" ||
  booking == "LIFO" ||
  booking == "HIFO" ||
  booking == "AVERAGE" ||
  booking == "NONE"
}

///|
fn meta_key_from_word(word : String) -> String? {
  if word.length() < 3 || !word.has_suffix(":") {
    return None
  }
  guard word.get_char(0) is Some(first) && first >= 'a' && first <= 'z' else {
    return None
  }
  let key = word.unsafe_substring(start=0, end=word.length() - 1)
  if key
    .iter()
    .all(fn(c) {
      c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-' || c == '_'
    }) {
    Some(key)
  } else {
    None
  }
}

///|
fn meta_value(tok : Token) -> @ast.MetaValue? {
  match tok.kind {
    Str(s) => Some(@ast.MString(s))
    Tag(t) if t != "" => Some(@ast.MTag(t))
    Word(w) =>
      if w == "NULL" {
        Some(@ast.MNull)
      } else if w == "TRUE" {
        Some(@ast.MBool(true))
      } else if w == "FALSE" {
        Some(@ast.MBool(false))
      } else {
        match @ast.Date::parse(w) {
          Some(d) => Some(@ast.MDate(d))
          None =>
            match @decimal.Decimal::parse(w) {
              Some(n) => Some(@ast.MNumber(n))
              None =>
                if w.contains(":") && lexical_account(w) {
                  Some(@ast.MAccount(w))
                } else if ledger_currency(w) {
                  Some(@ast.MCurrency(w))
                } else {
                  None
                }
            }
        }
      }
    _ => None
  }
}

///|
fn merge_meta(base : @ast.Meta, overlay : @ast.Meta) -> @ast.Meta {
  let result = base.copy()
  for pair in overlay.entries {
    result.set(pair.0, pair.1)
  }
  result
}

///|
fn push_unique(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}

///|
priv struct Cursor {
  tokens : Array[Token]
  mut index : Int32
}

///|
fn Cursor::new(tokens : Array[Token]) -> Cursor {
  { tokens, index: 0, }
}

///|
fn Cursor::peek(self : Cursor) -> Token {
  if self.index < self.tokens.length() {
    self.tokens[self.index]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Cursor::kind(self : Cursor) -> TokenKind {
  self.peek().kind
}

///|
fn Cursor::advance(self : Cursor) -> Token {
  let token = self.peek()
  if self.index < self.tokens.length() {
    self.index = self.index + 1
  }
  token
}

///|
fn Cursor::eof(self : Cursor) -> Bool {
  self.kind() is Eof
}

///|
fn Cursor::take_word(self : Cursor) -> String? {
  match self.kind() {
    Word(w) => {
      self.advance() |> ignore
      Some(w)
    }
    _ => None
  }
}

///|
fn Cursor::take_string(self : Cursor) -> String? {
  match self.kind() {
    Str(s) => {
      self.advance() |> ignore
      Some(s)
    }
    _ => None
  }
}

///|
priv struct Parser {
  file : String
  source : String
  mut offset : Int32
  source_map : Array[@ast.Loc]
  lines : Iter[StringView]
  mut next_line : String?
  mut index : Int32
  query_signed_zero : Array[Bool]
  words : Map[String, String]
  numbers : Map[String, @decimal.Decimal]
  dates : Map[String, @ast.Date]
  ledger : @ast.Ledger
  meta_scopes : Map[String, MetaScope]
  tag_scopes : Map[String, Array[String]]
  pipe_scopes : Map[String, Bool]
  child_currencies : Array[String]
}

///|
fn Parser::new(
  file : String,
  source : String,
  source_map : Array[@ast.Loc],
) -> Parser {
  let lines = source.split("\n")
  {
    file,
    source,
    offset: 0,
    source_map,
    lines,
    next_line: lines.next().map(view_to_string),
    index: 0,
    query_signed_zero: [false],
    words: {},
    numbers: {},
    dates: {},
    ledger: @ast.Ledger::new(),
    meta_scopes: {},
    tag_scopes: {},
    pipe_scopes: {},
    child_currencies: [],
  }
}

///|
fn Parser::loc(self : Parser, line : Int32) -> @ast.Loc {
  if line > 0 && line <= self.source_map.length() {
    self.source_map[line - 1]
  } else {
    @ast.Loc::new(self.file, line)
  }
}

///|
fn Parser::error(
  self : Parser,
  line : Int32,
  code : String,
  message : String,
) -> Unit {
  self.ledger.add_error(@ast.Diagnostic::new(code, message, self.loc(line)))
}

///|
fn Parser::active_tags(self : Parser, line : Int32) -> Array[String] {
  match self.tag_scopes.get(self.loc(line).file) {
    Some(tags) => {
      let unique = []
      for tag in tags {
        push_unique(unique, tag)
      }
      unique
    }
    None => []
  }
}

///|
fn Parser::push_tag(self : Parser, line : Int32, tag : String) -> Unit {
  let file = self.loc(line).file
  match self.tag_scopes.get(file) {
    Some(tags) => tags.push(tag)
    None => self.tag_scopes[file] = [tag]
  }
}

///|
priv struct MetaScope {
  active : @ast.Meta
  history : Map[String, Array[@ast.MetaValue]]
}

///|
fn Parser::push_stack_meta(
  self : Parser,
  file : String,
  key : String,
  value : @ast.MetaValue,
) -> Unit {
  let scope = match self.meta_scopes.get(file) {
    Some(scope) => scope
    None => {
      let scope = { active: @ast.Meta::new(), history: {}, }
      self.meta_scopes.set(file, scope)
      scope
    }
  }
  match scope.history.get(key) {
    Some(values) => values.push(value)
    None => scope.history.set(key, [value])
  }
  scope.active.set(key, value)
}

///|
fn Parser::pop_stack_meta(self : Parser, file : String, key : String) -> Bool {
  guard self.meta_scopes.get(file) is Some(scope) else { return false }
  match scope.history.get(key) {
    Some(values) => {
      values.remove(values.length() - 1) |> ignore
      if values.length() == 0 {
        scope.history.remove(key)
        scope.active.remove(key)
      } else {
        scope.active.set(key, values[values.length() - 1])
      }
      true
    }
    None => false
  }
}

///|
fn Parser::pop_tag(self : Parser, line : Int32, tag : String) -> Bool {
  guard self.tag_scopes.get(self.loc(line).file) is Some(tags) else {
    return false
  }
  let mut i = tags.length()
  while i > 0 {
    i = i - 1
    if tags[i] == tag {
      tags.remove(i) |> ignore
      return true
    }
  }
  false
}

///|
fn collect_indented(
  parser : Parser,
  header : Int32,
) -> Array[(Array[Token], Int32)] {
  let result = []
  let file = parser.loc(header).file
  while parser.next_line is Some(line) {
    if is_blank_line(line) ||
      !starts_whitespace(line) ||
      parser.loc(parser.index + 1).file != file {
      break
    }
    let pair = parser.take_tokens()
    if pair.0.length() > 1 {
      result.push(pair)
    }
  }
  result
}

///|
fn Parser::advance_line(self : Parser) -> Unit {
  if self.next_line is Some(line) {
    self.offset = self.offset + line.length() + 1
  }
  self.index = self.index + 1
  self.next_line = self.lines.next().map(view_to_string)
}

///|
fn parse_metadata_value(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @ast.MetaValue? {
  if cursor.eof() {
    return Some(@ast.MNull)
  }
  if cursor.kind() is Word(word) && parser.looks_like_number(word) {
    guard parse_number_expression(cursor, parser, line) is Some(number) else {
      return None
    }
    if cursor.kind() is Word(currency) &&
      currency != "NULL" &&
      currency != "TRUE" &&
      currency != "FALSE" &&
      ledger_currency(currency) {
      cursor.advance() |> ignore
      return Some(@ast.MAmount(@ast.Amount::new(number, currency)))
    }
    return Some(@ast.MNumber(number))
  }
  let value = meta_value(cursor.peek())
  if value is None && cursor.kind() is Word(word) {
    parser.error(line, "parse.token", "Invalid token: '" + word + "'")
  }
  if value is Some(_) {
    cursor.advance() |> ignore
  }
  value
}

///|
fn parse_meta_line(
  tokens : Array[Token],
  parser : Parser,
  line : Int32,
) -> (String, @ast.MetaValue)? {
  let cursor = Cursor::new(tokens)
  guard cursor.kind() is Word(word) else { return None }
  guard meta_key_from_word(word) is Some(key) else { return None }
  cursor.advance() |> ignore
  guard parse_metadata_value(cursor, parser, line) is Some(value) else {
    return None
  }
  if !cursor.eof() {
    return None
  }
  Some((key, value))
}

///|
fn parse_expr_primary(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @decimal.Decimal? {
  match cursor.kind() {
    Word(word) =>
      if word == "(" {
        cursor.advance() |> ignore
        match parse_expr_sum(cursor, parser, line) {
          None => None
          Some(value) =>
            match cursor.kind() {
              Word(close) =>
                if close == ")" {
                  cursor.advance() |> ignore
                  Some(value)
                } else {
                  parser.error(line, "parse.number", "expected `)` in amount")
                  None
                }
              _ => {
                parser.error(line, "parse.number", "expected `)` in amount")
                None
              }
            }
        }
      } else if word == "+" {
        cursor.advance() |> ignore
        parse_expr_primary(cursor, parser, line)
      } else if word == "-" {
        cursor.advance() |> ignore
        match parse_expr_primary(cursor, parser, line) {
          Some(value) => Some(value.neg())
          None => None
        }
      } else {
        match parser.number(word) {
          Some(number) => {
            cursor.advance() |> ignore
            Some(number)
          }
          None => {
            parser.error(line, "parse.number", "invalid number `" + word + "`")
            None
          }
        }
      }
    _ => {
      parser.error(
        line,
        "parse.number",
        "expected a number, found " + cursor.kind().describe_token(),
      )
      None
    }
  }
}

///|
fn parse_expr_product(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @decimal.Decimal? {
  match parse_expr_primary(cursor, parser, line) {
    None => None
    Some(first) => {
      let mut value = first
      let mut failed = false
      let mut running = true
      while running {
        match cursor.kind() {
          Star => {
            cursor.advance() |> ignore
            match parse_expr_primary(cursor, parser, line) {
              Some(right) => value = value.mul(right)
              None => {
                failed = true
                running = false
              }
            }
          }
          Word(op) =>
            if op == "/" {
              cursor.advance() |> ignore
              match parse_expr_primary(cursor, parser, line) {
                Some(right) =>
                  match value.div(right) {
                    Some(result) => value = result
                    None => {
                      parser.error(line, "parse.number", "division by zero")
                      failed = true
                      running = false
                    }
                  }
                None => {
                  failed = true
                  running = false
                }
              }
            } else {
              running = false
            }
          _ => running = false
        }
      }
      if failed {
        None
      } else {
        Some(value)
      }
    }
  }
}

///|
fn parse_expr_sum(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @decimal.Decimal? {
  match parse_expr_product(cursor, parser, line) {
    None => None
    Some(first) => {
      let mut value = first
      let mut failed = false
      let mut running = true
      while running {
        match cursor.kind() {
          Word(op) =>
            if op == "+" || op == "-" {
              cursor.advance() |> ignore
              match parse_expr_product(cursor, parser, line) {
                Some(right) =>
                  if op == "+" {
                    value = value.add(right)
                  } else {
                    value = value.sub(right)
                  }
                None => {
                  failed = true
                  running = false
                }
              }
            } else {
              running = false
            }
          _ => running = false
        }
      }
      if failed {
        None
      } else {
        Some(value)
      }
    }
  }
}

///|
fn is_expression_start(word : String) -> Bool {
  word == "(" || word == "+" || word == "-"
}

///|
fn Parser::looks_like_number(self : Parser, word : String) -> Bool {
  if is_expression_start(word) {
    return true
  }
  match self.number(word) {
    Some(_) => true
    None => false
  }
}

///|
fn parse_number_expression(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @decimal.Decimal? {
  parse_expr_sum(cursor, parser, line)
}

///|
fn parse_amount(cursor : Cursor, parser : Parser, line : Int32) -> @ast.Amount? {
  let number = match parse_number_expression(cursor, parser, line) {
    Some(n) => n
    None => return None
  }
  let currency = match cursor.take_word() {
    Some(w) =>
      if ledger_currency(w) {
        w
      } else {
        parser.error(line, "parse.currency", "invalid currency `" + w + "`")
        return None
      }
    None => {
      parser.error(
        line,
        "parse.currency",
        "expected a currency after amount, found " +
        cursor.kind().describe_token(),
      )
      return None
    }
  }
  Some(@ast.Amount::new(number, currency))
}

///|
fn TokenKind::describe_token(self : TokenKind) -> String {
  match self {
    Word(w) => "`" + w + "`"
    Str(s) => "\"" + s + "\""
    Invalid(s) => s
    LBrace => "`{`"
    RBrace => "`}`"
    LDoubleBrace => "`{{`"
    RDoubleBrace => "`}}`"
    At => "`@`"
    AtAt => "`@@`"
    Tilde => "`~`"
    Comma => "`,`"
    Star => "`*`"
    Tag(t) => "`#" + t + "`"
    Link(l) => "`^" + l + "`"
    Eof => "end of line"
  }
}

///|
fn parse_cost(cursor : Cursor, parser : Parser, line : Int32) -> @ast.CostSpec? {
  let total = cursor.kind() is LDoubleBrace
  cursor.advance() |> ignore
  let mut number : @decimal.Decimal? = None
  let mut compound_total : @decimal.Decimal? = None
  let mut seen_amount = false
  let mut currency : String? = None
  let mut date : @ast.Date? = None
  let mut label : String? = None
  let mut merge = false
  let closes = fn() {
    if total {
      cursor.kind() is RDoubleBrace
    } else {
      cursor.kind() is RBrace
    }
  }
  if !closes() {
    // Like the reference grammar, a leading comma is legal only when followed by a component.
    if cursor.kind() is Comma {
      cursor.advance() |> ignore
    }
    while true {
      match cursor.kind() {
        Star => {
          if merge {
            parser.error(line, "parse.cost", "Duplicate merge-cost spec")
          }
          merge = true
          cursor.advance() |> ignore
        }
        Str(s) => {
          if label is None {
            label = Some(s)
          } else {
            parser.error(line, "parse.cost", "Duplicate label: " + s)
          }
          cursor.advance() |> ignore
        }
        Tag("") => {
          cursor.advance() |> ignore
          let amount = if cursor.kind() is Word(next) &&
            parser.looks_like_number(next) {
            parse_number_expression(cursor, parser, line)
          } else {
            None
          }
          guard cursor.kind() is Word(c) && ledger_currency(c) else {
            parser.error(line, "parse.cost", "expected cost currency after #")
            return None
          }
          cursor.advance() |> ignore
          if seen_amount {
            parser.error(line, "parse.cost", "Duplicate cost")
          } else {
            seen_amount = true
            compound_total = amount
            currency = Some(c)
          }
        }
        Word(w) =>
          if parser.looks_like_number(w) {
            guard parse_number_expression(cursor, parser, line) is Some(n) else {
              return None
            }
            let has_separator = cursor.kind() is Tag("")
            let total_component = if has_separator {
              cursor.advance() |> ignore
              if cursor.kind() is Word(next) && parser.looks_like_number(next) {
                parse_number_expression(cursor, parser, line)
              } else {
                None
              }
            } else {
              None
            }
            let cur = if cursor.kind() is Word(c) && ledger_currency(c) {
              cursor.advance() |> ignore
              Some(c)
            } else {
              None
            }
            if seen_amount {
              parser.error(line, "parse.cost", "Duplicate cost")
            } else {
              seen_amount = true
              number = Some(n)
              compound_total = total_component
              currency = cur
              if has_separator && total {
                parser.error(
                  line, "parse.cost", "Per-unit cost may not be specified using total cost syntax",
                )
                number = total_component
              }
            }
          } else if parser.date(w) is Some(d) {
            if date is None {
              date = Some(d)
            } else {
              parser.error(
                line,
                "parse.cost",
                "Duplicate date: " + d.to_string(),
              )
            }
            cursor.advance() |> ignore
          } else if ledger_currency(w) {
            if seen_amount {
              parser.error(line, "parse.cost", "Duplicate cost")
            } else {
              seen_amount = true
              currency = Some(w)
            }
            cursor.advance() |> ignore
          } else {
            parser.error(
              line,
              "parse.cost",
              "unexpected " +
              cursor.kind().describe_token() +
              " in cost specification",
            )
            return None
          }
        _ => {
          parser.error(
            line,
            "parse.cost",
            "unexpected " +
            cursor.kind().describe_token() +
            " in cost specification",
          )
          return None
        }
      }
      if closes() {
        break
      }
      if !(cursor.kind() is Comma) {
        parser.error(
          line, "parse.cost", "expected a comma or closing braces in cost specification",
        )
        return None
      }
      cursor.advance() |> ignore
    }
  }
  cursor.advance() |> ignore
  Some({
    number_per: if total {
      None
    } else {
      number
    },
    number_total: if total {
      if compound_total is Some(_) {
        compound_total
      } else {
        number
      }
    } else {
      compound_total
    },
    currency,
    date,
    label,
    merge,
    present: true,
  })
}

///|
fn parse_price_annotation(
  cursor : Cursor,
  parser : Parser,
  line : Int32,
) -> @ast.PriceAnno? {
  let total = match cursor.kind() {
    AtAt => true
    At => false
    _ => return None
  }
  cursor.advance() |> ignore
  match parse_amount(cursor, parser, line) {
    Some(amount) => {
      let amount = if amount.number.is_negative() {
        parser.error(
          line,
          "parse.price",
          "Negative prices are not allowed: " + amount.to_string(),
        )
        @ast.Amount::new(amount.number.abs(), amount.currency)
      } else {
        amount
      }
      if total {
        Some(@ast.PriceAnno::Total(amount))
      } else {
        Some(@ast.PriceAnno::PerUnit(amount))
      }
    }
    None => None
  }
}

///|
fn parse_posting(
  tokens : Array[Token],
  parser : Parser,
  line : Int32,
) -> @ast.Posting? {
  let cursor = Cursor::new(tokens)
  let mut flag : String? = None
  let first = cursor.peek()
  match first.kind {
    Tag("") => {
      flag = Some("#")
      cursor.advance() |> ignore
    }
    Star => {
      flag = Some("*")
      cursor.advance() |> ignore
    }
    Word(w) =>
      if is_flag_word(w) {
        // A single character word is a posting flag only when an account
        // follows; otherwise it is the account itself.
        let next = cursor.tokens
        if cursor.index + 1 < next.length() {
          match next[cursor.index + 1].kind {
            Word(a) =>
              if a.contains(":") {
                flag = Some(w)
                cursor.advance() |> ignore
              }
            _ => ()
          }
        }
      }
    _ => ()
  }
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(
        line,
        "parse.posting",
        "expected an account name, found " + cursor.kind().describe_token(),
      )
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let posting = @ast.Posting::new(account)
  posting.flag = flag
  posting.loc = parser.loc(line)
  match cursor.kind() {
    Word(w) =>
      if parser.looks_like_number(w) {
        match parse_number_expression(cursor, parser, line) {
          Some(number) => {
            let currency = match cursor.take_word() {
              Some(c) =>
                if ledger_currency(c) {
                  c
                } else {
                  parser.error(
                    line,
                    "parse.currency",
                    "invalid currency `" + c + "` in posting",
                  )
                  return None
                }
              // A bare number is resolved against the currencies of the other
              // postings during validation.
              None => ""
            }
            posting.units = Some(@ast.Amount::new(number, currency))
          }
          None => return None
        }
      } else if ledger_currency(w) {
        cursor.advance() |> ignore
        posting.units_currency = Some(w)
      } else {
        parser.error(line, "parse.posting", "unexpected `" + w + "` in posting")
        return None
      }
    _ => ()
  }
  if cursor.kind() is LBrace || cursor.kind() is LDoubleBrace {
    guard parse_cost(cursor, parser, line) is Some(cost) else { return None }
    posting.cost = Some(cost)
  }
  if cursor.kind() is At || cursor.kind() is AtAt {
    posting.price = parse_price_annotation(cursor, parser, line)
    if posting.units is None && posting.price is Some(@ast.Total(amount)) {
      parser.error(
        line,
        "parse.price",
        "Total price on a posting without units: " + amount.to_string() + ".",
      )
      posting.price = None
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.posting",
      "unexpected " + cursor.kind().describe_token() + " at end of posting",
    )
    return None
  }
  Some(posting)
}

///|
fn parse_tags_and_links(
  cursor : Cursor,
  tags : Array[String],
  links : Array[String],
) -> Unit {
  while !cursor.eof() {
    match cursor.kind() {
      Tag(t) if t != "" => {
        push_unique(tags, t)
        cursor.advance() |> ignore
      }
      Link(l) => {
        push_unique(links, l)
        cursor.advance() |> ignore
      }
      _ => break
    }
  }
}

///|
fn parse_transaction(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let mut flag = "*"
  match cursor.kind() {
    Star => {
      flag = "*"
      cursor.advance() |> ignore
    }
    Tag("") => {
      flag = "#"
      cursor.advance() |> ignore
    }
    Word(w) =>
      if w == "txn" {
        flag = "*"
        cursor.advance() |> ignore
      } else if is_flag_word(w) {
        flag = w
        cursor.advance() |> ignore
      }
    _ => ()
  }
  let strings : Array[String] = []
  while true {
    match cursor.kind() {
      Str(s) => {
        strings.push(s)
        cursor.advance() |> ignore
      }
      Word("|") => {
        if !parser.pipe_scopes.get(parser.loc(line).file).unwrap_or(false) {
          parser.error(line, "parse.transaction", "Pipe symbol is deprecated.")
        }
        cursor.advance() |> ignore
      }
      _ => break
    }
  }
  if strings.length() > 2 {
    parser.error(
      line, "parse.transaction", "Too many strings on transaction description",
    )
    collect_indented(parser, line) |> ignore
    return None
  }
  let payee = if strings.length() == 2 { Some(strings[0]) } else { None }
  let narration = strings.last().unwrap_or("")
  let tags : Array[String] = []
  let links : Array[String] = []
  parse_tags_and_links(cursor, tags, links)
  if !cursor.eof() {
    parser.error(
      line, "parse.transaction", "unexpected token after transaction header",
    )
    return None
  }
  let txn = @ast.Transaction::new(flag, payee, narration, tags, links)
  let own_meta = @ast.Meta::new()
  let continuations = collect_indented(parser, line)
  let mut posting_count = 0
  for pair in continuations {
    let line_tokens = pair.0
    let meta_line = pair.1
    if line_tokens.any(fn(t) { t.kind is Invalid(_) }) {
      return None
    }
    if line_tokens[0].kind is Word(w) && w.length() == 2 && w.has_suffix(":") {
      parser.error(meta_line, "parse.meta", "invalid metadata key")
      return None
    }
    let mut handled = false
    match line_tokens[0].kind {
      Word(w) =>
        match meta_key_from_word(w) {
          Some(_) => {
            handled = true
            let before = parser.ledger.errors.length()
            match parse_meta_line(line_tokens, parser, meta_line) {
              Some((key, value)) => {
                let meta = if posting_count > 0 {
                  txn.postings[posting_count - 1].meta
                } else {
                  own_meta
                }
                if meta.get(key) is Some(previous) {
                  if !repeated_metadata_value(previous, value) {
                    parser.error(
                      line,
                      "parse.meta",
                      if posting_count > 0 {
                        "Duplicate posting metadata field: " + key
                      } else {
                        "Duplicate metadata field on entry: " + key
                      },
                    )
                  }
                } else {
                  meta.set(key, value)
                }
              }
              None => {
                if parser.ledger.errors.length() == before {
                  parser.error(meta_line, "parse.meta", "invalid metadata line")
                }
                return None
              }
            }
          }
          None => ()
        }
      Tag(t) if t != "" => handled = true
      Link(_) => handled = true
      _ => ()
    }
    if handled {
      if line_tokens[0].kind is Tag(_) || line_tokens[0].kind is Link(_) {
        let body = Cursor::new(line_tokens)
        let tags = []
        let links = []
        parse_tags_and_links(body, tags, links)
        if !body.eof() {
          parser.error(
            meta_line, "parse.transaction", "unexpected token after tags or links",
          )
          return None
        }
        if posting_count > 0 {
          parser.error(
            line, "parse.transaction", "tags or links not allowed after first posting",
          )
        } else {
          for tag in tags {
            push_unique(txn.tags, tag)
          }
          for link in links {
            push_unique(txn.links, link)
          }
        }
      }
      continue
    }
    match parse_posting(line_tokens, parser, meta_line) {
      Some(posting) => {
        txn.postings.push(posting)
        posting_count = posting_count + 1
      }
      None => return None
    }
  }
  for tag in parser.active_tags(line) {
    push_unique(txn.tags, tag)
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DTransaction(txn),
  )
  entry.meta = match parser.meta_scopes.get(entry.loc.file) {
    Some(scope) => merge_meta(scope.active, own_meta)
    None => own_meta
  }
  Some(entry)
}

///|
fn parse_open(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(line, "parse.open", "open directive is missing an account")
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let currencies = []
  if cursor.kind() is Word(w) && ledger_currency(w) {
    currencies.push(w)
    cursor.advance() |> ignore
  }
  while cursor.kind() is Comma {
    cursor.advance() |> ignore
    guard cursor.take_word() is Some(w) && ledger_currency(w) else {
      parser.error(line, "parse.open", "expected a currency after comma")
      return None
    }
    currencies.push(w)
  }
  let booking = match cursor.take_string() {
    Some("") => None
    other => other
  }
  if !cursor.eof() {
    parser.error(
      line, "parse.open", "unexpected token after open currencies or booking method",
    )
    return None
  }
  let open : @ast.Open = { account, currencies, booking, }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DOpen(open),
  )
  Some(entry)
}

///|
fn parse_close(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(line, "parse.close", "close directive is missing an account")
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.close",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of close directive",
    )
    return None
  }
  let close : @ast.Close = { account, }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DClose(close),
  )
  Some(entry)
}

///|
fn parse_commodity(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let currency = match cursor.take_word() {
    Some(c) => c
    None => {
      parser.error(
        line, "parse.commodity", "commodity directive is missing a currency",
      )
      return None
    }
  }
  if !ledger_currency(currency) {
    parser.error(line, "parse.currency", "invalid currency `" + currency + "`")
    return None
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.commodity",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of commodity directive",
    )
    return None
  }
  let commodity : @ast.Commodity = { currency, }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DCommodity(commodity),
  )
  Some(entry)
}

///|
fn parse_pad(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(line, "parse.pad", "pad directive is missing an account")
      return None
    }
  }
  let source = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(
        line, "parse.pad", "pad directive is missing a source account",
      )
      return None
    }
  }
  if !lexical_account(account) || !lexical_account(source) {
    parser.error(line, "parse.account", "invalid account name in pad directive")
    return None
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.pad",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of pad directive",
    )
    return None
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DPad({ account, source_account: source, }),
  )
  Some(entry)
}

///|
fn parse_balance(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(
        line, "parse.balance", "balance directive is missing an account",
      )
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let number = match cursor.kind() {
    Word(w) =>
      if parser.looks_like_number(w) {
        match parse_number_expression(cursor, parser, line) {
          Some(n) => n
          None => return None
        }
      } else {
        parser.error(
          line, "parse.balance", "balance directive is missing an amount",
        )
        return None
      }
    _ => {
      parser.error(
        line, "parse.balance", "balance directive is missing an amount",
      )
      return None
    }
  }
  let mut tolerance : @decimal.Decimal? = None
  if cursor.kind() is Tilde {
    cursor.advance() |> ignore
    match parse_number_expression(cursor, parser, line) {
      Some(n) => tolerance = Some(n)
      None => parser.error(line, "parse.balance", "expected a number after `~`")
    }
  }
  let currency = match cursor.take_word() {
    Some(c) =>
      if ledger_currency(c) {
        c
      } else {
        parser.error(line, "parse.currency", "invalid currency `" + c + "`")
        return None
      }
    None => {
      parser.error(
        line, "parse.balance", "balance directive is missing a currency",
      )
      return None
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.balance",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of balance directive",
    )
    return None
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DBalance({
      account,
      amount: @ast.Amount::new(number, currency),
      tolerance,
    }),
  )
  Some(entry)
}

///|
fn parse_price(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let currency = match cursor.take_word() {
    Some(c) =>
      if ledger_currency(c) {
        c
      } else {
        parser.error(line, "parse.currency", "invalid currency `" + c + "`")
        return None
      }
    None => {
      parser.error(line, "parse.price", "price directive is missing a currency")
      return None
    }
  }
  let amount = match parse_amount(cursor, parser, line) {
    Some(a) => a
    None => return None
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.price",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of price directive",
    )
    return None
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DPrice({ currency, amount, }),
  )
  Some(entry)
}

///|
fn parse_two_strings(
  parser : Parser,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
  keyword : String,
) -> (String, String)? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let first = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line,
        "parse." + keyword,
        keyword + " directive expects a string",
      )
      return None
    }
  }
  let second = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line,
        "parse." + keyword,
        keyword + " directive expects two strings",
      )
      return None
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse." + keyword,
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of " +
      keyword +
      " directive",
    )
    return None
  }
  Some((first, second))
}

///|
fn parse_event(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  match parse_two_strings(parser, tokens, line, start, "event") {
    Some((event_type, description)) => {
      let entry = @ast.Entry::new(
        date,
        parser.loc(line),
        @ast.Directive::DEvent({ event_type, description, }),
      )
      Some(entry)
    }
    None => None
  }
}

///|
fn parse_query(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  match parse_two_strings(parser, tokens, line, start, "query") {
    Some((name, query)) => {
      let entry = @ast.Entry::new(
        date,
        parser.loc(line),
        @ast.Directive::DQuery({ name, query, }),
      )
      Some(entry)
    }
    None => None
  }
}

///|
fn parse_note(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(line, "parse.note", "note directive is missing an account")
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let comment = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.note", "note directive is missing a comment string",
      )
      return None
    }
  }
  let tags = parser.active_tags(line)
  let links : Array[String] = []
  parse_tags_and_links(cursor, tags, links)
  if !cursor.eof() {
    if cursor.kind() is Word(word) && !ledger_currency(word) {
      parser.error(line, "parse.token", "Invalid token: '" + word + "'")
    } else {
      parser.error(
        line,
        "parse.note",
        "unexpected " +
        cursor.kind().describe_token() +
        " at end of note directive",
      )
    }
    return None
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DNote({ account, comment, tags, links, }),
  )
  Some(entry)
}

///|
fn parse_document(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let account = match cursor.take_word() {
    Some(a) => a
    None => {
      parser.error(
        line, "parse.document", "document directive is missing an account",
      )
      return None
    }
  }
  if !lexical_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let filename = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.document", "document directive is missing a filename",
      )
      return None
    }
  }
  let tags = parser.active_tags(line)
  let links : Array[String] = []
  parse_tags_and_links(cursor, tags, links)
  if !cursor.eof() {
    parser.error(
      line, "parse.document", "unexpected token after document filename, tags or links",
    )
    return None
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DDocument({ account, filename, tags, links, }),
  )
  Some(entry)
}

///|
fn parse_custom(
  parser : Parser,
  date : @ast.Date,
  tokens : Array[Token],
  line : Int32,
  start : Int32,
) -> @ast.Entry? {
  let cursor = Cursor::new(tokens)
  cursor.index = start
  let custom_type = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.custom", "custom directive is missing a type string",
      )
      return None
    }
  }
  let values = []
  while !cursor.eof() {
    match cursor.kind() {
      Str(s) => {
        values.push(@ast.CustomValue::CString(s))
        cursor.advance() |> ignore
      }
      Word(w) =>
        if w == "TRUE" || w == "FALSE" {
          values.push(@ast.CustomValue::CBool(w == "TRUE"))
          cursor.advance() |> ignore
        } else {
          match parser.date(w) {
            Some(d) => {
              values.push(@ast.CustomValue::CDate(d))
              cursor.advance() |> ignore
            }
            None =>
              if parser.looks_like_number(w) {
                guard parse_number_expression(cursor, parser, line) is Some(n) else {
                  return None
                }
                if cursor.kind() is Word(c) &&
                  c != "TRUE" &&
                  c != "FALSE" &&
                  c != "NULL" &&
                  ledger_currency(c) {
                  values.push(@ast.CustomValue::CAmount(@ast.Amount::new(n, c)))
                  cursor.advance() |> ignore
                } else {
                  values.push(@ast.CustomValue::CNumber(n))
                }
              } else if w.contains(":") && lexical_account(w) {
                values.push(@ast.CustomValue::CAccount(w))
                cursor.advance() |> ignore
              } else {
                parser.error(
                  line,
                  "parse.custom",
                  "unexpected `" + w + "` in custom directive",
                )
                return None
              }
          }
        }
      _ => {
        parser.error(
          line,
          "parse.custom",
          "unexpected " +
          cursor.kind().describe_token() +
          " in custom directive",
        )
        return None
      }
    }
  }
  let entry = @ast.Entry::new(
    date,
    parser.loc(line),
    @ast.Directive::DCustom({ custom_type, values, }),
  )
  Some(entry)
}

///|
// Options have a separate grammar from ledger quantities: the last colon
// followed by a decimal prefix separates a free-form key and unsigned value.
fn decimal_option_pair(value : String) -> (String, @decimal.Decimal)? {
  let mut separator = -1
  let mut offset = 0
  for c in value {
    if c == '\n' {
      break
    }
    if c == ':' &&
      value.get_char(offset + 1) is Some(first) &&
      (first == '.' || @decimal.decimal_digit(first) is Some(_)) {
      separator = offset
    }
    offset += if c.to_int() > 0xFFFF { 2 } else { 1 }
  }
  if separator < 0 {
    return None
  }
  let number = StringBuilder()
  for c in value[separator + 1:] {
    if c == '.' {
      number.write_char(c)
    } else if @decimal.decimal_digit(c) is Some(n) {
      number.write_char((48 + n).unsafe_to_char())
    } else {
      break
    }
  }
  @decimal.Decimal::parse(number.to_string()).map(fn(n) {
    (value[:separator].to_owned(), n)
  })
}

///|
// Beancount 3.2.3 public option descriptor names (see compatibility-inventory.json).
let ledger_option_names : Array[String] = [
  "account_current_conversions", "account_current_earnings", "account_previous_balances",
  "account_previous_conversions", "account_previous_earnings", "account_rounding",
  "account_unrealized_gains", "allow_deprecated_none_for_tags_and_links", "allow_pipe_separator",
  "booking_method", "commodities", "conversion_currency", "dcontext", "display_precision",
  "documents", "filename", "include", "infer_tolerance_from_cost", "inferred_tolerance_default",
  "inferred_tolerance_multiplier", "input_hash", "insert_pythonpath", "long_string_maxlines",
  "name_assets", "name_equity", "name_expenses", "name_income", "name_liabilities",
  "operating_currency", "plugin", "plugin_processing_mode", "render_commas", "title",
  "tolerance_multiplier", "use_precise_interpolation",
]

///|
fn scalar_decimal_option(value : String) -> @decimal.Decimal? {
  if value == "" {
    return Some(@decimal.Decimal::zero())
  }
  let compact = StringBuilder()
  for c in value {
    if [',', '_', ' ', '\t', '\r', '\n', '\u000b', '\u000c'].contains(c) {
      continue
    }
    if @decimal.decimal_digit(c) is Some(digit) {
      compact.write_char((48 + digit).unsafe_to_char())
    } else {
      compact.write_char(if c == 'E' { 'e' } else { c })
    }
  }
  let parts = compact.to_string().split("e").to_array()
  if parts.length() > 2 {
    return None
  }
  guard @decimal.Decimal::parse(parts[0].to_owned()) is Some(number) else {
    return None
  }
  if parts.length() == 1 {
    return Some(number)
  }
  let exponent = parts[1].to_owned()
  let mut digits = exponent
  let sign = if exponent.has_prefix("-") { -1 } else { 1 }
  if exponent.has_prefix("-") || exponent.has_prefix("+") {
    digits = exponent[1:].to_owned()
  }
  if digits.is_empty() {
    return None
  }
  let mut power = 0
  for c in digits {
    if !c.is_ascii_digit() {
      return None
    }
    power = power * 10 + c.to_int() - 48
    if power > 10000 {
      return None
    }
  }
  Some(@decimal.Decimal::new(number.mantissa(), number.scale() - sign * power))
}

///|
fn apply_option(
  parser : Parser,
  name : String,
  value : String,
  line : Int32,
) -> Unit {
  if !ledger_option_names.contains(name) {
    parser.error(line, "parse.option", "Invalid option: '" + name + "'")
    return
  }
  if name == "filename" || name == "plugin" {
    parser.error(line, "parse.option", "option `" + name + "` is read-only")
    return
  }
  if name == "plugin_processing_mode" && value != "raw" && value != "default" {
    parser.error(
      line,
      "parse.option",
      "invalid plugin_processing_mode `" + value + "`",
    )
    return
  }
  let account_root = [
    "name_assets", "name_liabilities", "name_equity", "name_income", "name_expenses",
  ].contains(name)
  let account_leaf = name.has_prefix("account_")
  if (
      account_root &&
      (value.contains(":") || !@ast.valid_account_name(value + ":X"))
    ) ||
    (account_leaf && !@ast.valid_account_name("Assets:" + value)) {
    parser.error(
      line,
      "parse.option",
      "Invalid account value '" + value + "' for " + name,
    )
    return
  }
  let is_root = parser.loc(line).file == parser.file || account_root
  if !is_root && name == "operating_currency" {
    parser.child_currencies.push(value)
    return
  }
  // Validate child directives without letting their typed options leak into
  // the root ledger. Per-file parse controls such as pipes have their own map.
  let options = if is_root {
    parser.ledger.options
  } else {
    @ast.Options::new()
  }
  options.add_raw(name, value)
  if name == "title" {
    options.title = Some(value)
  } else if name == "booking_method" {
    if is_booking_method(value) {
      options.booking_method = value
    } else {
      parser.error(
        line,
        "parse.option",
        "unknown booking method `" + value + "`",
      )
    }
  } else if name == "tolerance_multiplier" ||
    name == "inferred_tolerance_multiplier" {
    if name == "inferred_tolerance_multiplier" {
      parser.error(
        line, "validation.deprecated_option", "Renamed to 'tolerance_multiplier'.",
      )
    }
    match scalar_decimal_option(value) {
      Some(n) => options.tolerance_multiplier = n
      None =>
        parser.error(
          line,
          "parse.option",
          "invalid " + name + " `" + value + "`",
        )
    }
  } else if name == "inferred_tolerance_default" || name == "display_precision" {
    match decimal_option_pair(value) {
      Some((key, n)) => {
        let target = if name == "display_precision" {
          options.display_precision
        } else {
          options.inferred_tolerance_default
        }
        target.set(key, n)
      }
      None =>
        parser.error(
          line,
          "parse.option",
          "Invalid value '" + value + "' for " + name,
        )
    }
  } else if name == "infer_tolerance_from_cost" {
    options.infer_tolerance_from_cost = ["true", "on", "1"].contains(
      value.to_lower(),
    )
  } else if name == "allow_pipe_separator" {
    parser.pipe_scopes[parser.loc(line).file] = ["true", "1", "yes"].contains(
      value.to_lower(),
    )
    parser.error(
      line, "parse.option", "Allowing pipe separator temporarily; this will go away eventually.",
    )
  } else if name == "account_rounding" {
    options.account_rounding = Some(value)
  } else if name == "operating_currency" {
    options.operating_currencies.push(value)
  } else if name == "documents" {
    options.documents.push(value)
  } else if name == "render_commas" {
    options.render_commas = ["true", "1", "yes"].contains(value.to_lower())
  }
}

///|
fn parse_option(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  let name = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.option", "option directive is missing a name string",
      )
      return
    }
  }
  let value = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.option", "option directive is missing a value string",
      )
      return
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.option",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of option directive",
    )
    return
  }
  apply_option(parser, name, value, line)
}

///|
fn parse_plugin(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  let name = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.plugin", "plugin directive is missing a name string",
      )
      return
    }
  }
  let mut config : String? = None
  if !cursor.eof() {
    config = cursor.take_string()
    if config is None {
      parser.error(
        line, "parse.plugin", "plugin configuration must be a string",
      )
      return
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.plugin",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of plugin directive",
    )
    return
  }
  parser.ledger.plugins.push({ name, config, loc: parser.loc(line), })
}

///|
fn parse_include(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  let path = match cursor.take_string() {
    Some(s) => s
    None => {
      parser.error(
        line, "parse.include", "include directive is missing a path string",
      )
      return
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.include",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of include directive",
    )
    return
  }
  parser.ledger.includes.push((path, parser.loc(line)))
}

///|
fn parse_tag_control(
  parser : Parser,
  tokens : Array[Token],
  line : Int32,
  push : Bool,
) -> Unit {
  let code = if push { "parse.pushtag" } else { "parse.poptag" }
  guard tokens.length() == 3 && tokens[1].kind is Tag(tag) && tag != "" else {
    parser.error(line, code, "expected exactly one tag")
    return
  }
  if push {
    parser.push_tag(line, tag)
  } else if !parser.pop_tag(line, tag) {
    parser.error(
      line,
      code,
      "poptag without matching pushtag for `#" + tag + "`",
    )
  }
}

///|
fn parse_push_meta(
  parser : Parser,
  tokens : Array[Token],
  line : Int32,
  push : Bool,
) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  let key = match cursor.peek().kind {
    Word(w) =>
      match meta_key_from_word(w) {
        Some(k) => k
        None => {
          parser.error(
            line, "parse.pushmeta", "expected a metadata key ending in `:`",
          )
          return
        }
      }
    _ => {
      parser.error(
        line, "parse.pushmeta", "expected a metadata key ending in `:`",
      )
      return
    }
  }
  cursor.advance() |> ignore
  if push {
    let value = match parse_metadata_value(cursor, parser, line) {
      Some(v) => v
      None => {
        parser.error(line, "parse.pushmeta", "expected a metadata value")
        return
      }
    }
    if !cursor.eof() {
      parser.error(
        line, "parse.pushmeta", "unexpected token after metadata value",
      )
      return
    }
    parser.push_stack_meta(parser.loc(line).file, key, value)
  } else if !cursor.eof() {
    parser.error(line, "parse.popmeta", "unexpected token after metadata key")
  } else if !parser.pop_stack_meta(parser.loc(line).file, key) {
    parser.error(
      line,
      "parse.popmeta",
      "popmeta without matching pushmeta for `" + key + "`",
    )
  }
}

///|
fn parse_dated_directive(
  parser : Parser,
  tokens : Array[Token],
  line : Int32,
) -> @ast.Entry? {
  let date = match tokens[0].kind {
    Word(w) =>
      match parser.date(w) {
        Some(d) => d
        None => {
          parser.error(line, "parse.date", "invalid date `" + w + "`")
          return None
        }
      }
    _ => {
      parser.error(
        line, "parse.date", "expected a date at the start of the line",
      )
      return None
    }
  }
  if tokens.length() < 2 {
    parser.error(line, "parse.directive", "date is not followed by a directive")
    return None
  }
  match tokens[1].kind {
    Word("open") => parse_open(parser, date, tokens, line, 2)
    Word("close") => parse_close(parser, date, tokens, line, 2)
    Word("commodity") => parse_commodity(parser, date, tokens, line, 2)
    Word("pad") => parse_pad(parser, date, tokens, line, 2)
    Word("balance") => parse_balance(parser, date, tokens, line, 2)
    Word("price") => parse_price(parser, date, tokens, line, 2)
    Word("event") => parse_event(parser, date, tokens, line, 2)
    Word("query") => parse_query(parser, date, tokens, line, 2)
    Word("note") => parse_note(parser, date, tokens, line, 2)
    Word("document") => parse_document(parser, date, tokens, line, 2)
    Word("custom") => parse_custom(parser, date, tokens, line, 2)
    Word("txn") => parse_transaction(parser, date, tokens, line, 1)
    Star | Tag("") => parse_transaction(parser, date, tokens, line, 1)
    Word(w) =>
      if is_flag_word(w) {
        parse_transaction(parser, date, tokens, line, 1)
      } else if w.length() == 1 {
        parser.error(line, "parse.token", "Invalid token: '" + w + "'")
        None
      } else {
        parser.error(line, "parse.directive", "unknown directive `" + w + "`")
        None
      }
    _ => {
      parser.error(line, "parse.directive", "invalid directive after date")
      None
    }
  }
}

///|
fn attach_continuation_meta(
  parser : Parser,
  entry : @ast.Entry,
  line : Int32,
) -> Bool {
  let continuations = collect_indented(parser, line)
  let own_meta = @ast.Meta::new()
  let mut lexical_error = false
  for pair in continuations {
    let tokens = pair.0
    let meta_line = pair.1
    if tokens.any(fn(t) { t.kind is Invalid(_) }) {
      lexical_error = true
      continue
    }
    if tokens[0].kind is Word(w) && w.length() == 2 && w.has_suffix(":") {
      lexical_error = true
    }
    let before = parser.ledger.errors.length()
    match parse_meta_line(tokens, parser, meta_line) {
      Some((key, value)) => own_meta.set(key, value)
      None => {
        if parser.ledger.errors.length() == before {
          parser.error(meta_line, "parse.meta", "invalid metadata line")
        }
        lexical_error = true
      }
    }
  }
  let merged = merge_meta(entry.meta, own_meta)
  entry.meta = merged
  let _ = line
  !lexical_error
}

///|
fn parse_toplevel(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  if tokens[0].kind is Eof {
    return
  }
  match tokens[0].kind {
    Word(w) =>
      if w == "option" {
        parse_option(parser, tokens, line)
      } else if w == "plugin" {
        parse_plugin(parser, tokens, line)
      } else if w == "include" {
        parse_include(parser, tokens, line)
      } else if w == "pushtag" {
        parse_tag_control(parser, tokens, line, true)
      } else if w == "poptag" {
        parse_tag_control(parser, tokens, line, false)
      } else if w == "pushmeta" {
        parse_push_meta(parser, tokens, line, true)
      } else if w == "popmeta" {
        parse_push_meta(parser, tokens, line, false)
      } else {
        match parse_dated_directive(parser, tokens, line) {
          Some(entry) =>
            if attach_continuation_meta(parser, entry, line) {
              parser.ledger.entries.push(entry)
            }
          None => {
            // Still consume indented lines so that the rest of the file can
            // be parsed and reported.
            let _ = collect_indented(parser, line)
          }
        }
      }
    _ =>
      match parse_dated_directive(parser, tokens, line) {
        Some(entry) =>
          if attach_continuation_meta(parser, entry, line) {
            parser.ledger.entries.push(entry)
          }
        None => {
          let _ = collect_indented(parser, line)
        }
      }
  }
}

///|
pub fn parse_source(
  file : String,
  source : String,
  source_map~ : Array[@ast.Loc] = [],
) -> @ast.Ledger {
  let parser = Parser::new(file, source, source_map)
  while parser.next_line is Some(line) {
    let line_no = parser.index + 1
    if is_blank_line(line) || ignored_heading(line) {
      parser.advance_line()
      continue
    }
    if starts_whitespace(line) {
      parser.error(
        line_no, "parse.indent", "unexpected indented line outside of a directive",
      )
      parser.advance_line()
      continue
    }
    let (tokens, _) = parser.take_tokens()
    if tokens.length() == 1 {
      continue
    }
    if tokens.any(fn(t) { t.kind is Invalid(_) }) {
      collect_indented(parser, line_no) |> ignore
      continue
    }
    parse_toplevel(parser, tokens, line_no)
  }
  for file, tags in parser.tag_scopes {
    for tag in tags {
      parser.ledger.add_error(
        @ast.Diagnostic::new(
          "parse.pushtag",
          "Unbalanced pushed tag: '" + tag + "'",
          @ast.Loc::new(file, 0),
        ),
      )
    }
  }
  for file, scope in parser.meta_scopes {
    for key, _ in scope.history {
      parser.ledger.add_error(
        @ast.Diagnostic::new(
          "parse.pushmeta",
          "Unbalanced metadata key '" + key + "'",
          @ast.Loc::new(file, 0),
        ),
      )
    }
  }
  if parser.query_signed_zero[0] {
    for entry in parser.ledger.entries {
      entry.query_exact_decimal = false
    }
  }
  if !parser.child_currencies.is_empty() {
    let all = parser.ledger.options.operating_currencies
    let merged = []
    for currency in all {
      push_unique(merged, currency)
    }
    for currency in parser.child_currencies {
      push_unique(merged, currency)
    }
    all.clear()
    all.append(merged)
  }
  parser.ledger
}

///|
fn Parser::tokens(self : Parser, text : String) -> Array[Token] {
  tokenize_guarded(text, Some(self.query_signed_zero), words=Some(self.words))
}

///|
// These immutable literals are often repeated across a ledger. Bound each
// parse-local cache so unique input cannot retain an unbounded second index.
let literal_cache_limit = 1024

///|
fn Parser::number(self : Parser, text : String) -> @decimal.Decimal? {
  if self.numbers.get(text) is Some(number) {
    return Some(number)
  }
  let normalized = normal_ledger_number(text)
  if normalized.contains(",") {
    let mut width = 0
    let mut grouped = false
    for c in normalized {
      if c == '.' {
        break
      }
      if c == ',' {
        if width == 0 || width > 3 || (grouped && width != 3) {
          return None
        }
        grouped = true
        width = 0
      } else if c.is_ascii_digit() {
        width += 1
      }
    }
    if grouped && width != 3 {
      return None
    }
  }
  let result = @decimal.Decimal::parse(normalized)
  if result is Some(number) && self.numbers.length() < literal_cache_limit {
    self.numbers[text] = number
  }
  result
}

///|
fn Parser::date(self : Parser, text : String) -> @ast.Date? {
  if self.dates.get(text) is Some(date) {
    return Some(date)
  }
  let result = @ast.Date::parse(text)
  if result is Some(date) && self.dates.length() < literal_cache_limit {
    self.dates[text] = date
  }
  result
}

///|
fn Parser::take_tokens(self : Parser) -> (Array[Token], Int32) {
  let line = self.index + 1
  let start = self.offset
  let text = self.next_line.unwrap()
  self.advance_line()
  let mut tokens = self.tokens(text)
  let mut logical = text
  if tokens.length() > 1 &&
    tokens[tokens.length() - 2].kind is Invalid(raw) &&
    raw.has_prefix("\"") {
    let end = multiline_line_end(
      self.source,
      start + tokens[tokens.length() - 2].pos,
      start + text.length(),
    )
    if end > start + text.length() {
      while self.offset <= end && self.next_line is Some(_) {
        self.advance_line()
      }
      logical = self.source[start:end].to_owned()
      tokens = self.tokens(logical)
    }
  }
  if start + logical.length() == self.source.length() && tokens.length() > 1 {
    let last = tokens.length() - 2
    if tokens[last].kind is Word(word) &&
      word.length() == 1 &&
      word.get_char(0) is Some(c) &&
      c >= 'A' &&
      c <= 'Z' &&
      tokens[last].pos + 1 == logical.length() {
      tokens[last] = { ..tokens[last], kind: Invalid(word), }
    }
  }
  for token in tokens {
    if token.kind is Invalid(raw) {
      let offset = logical[0:token.pos]
        .iter()
        .filter(fn(c) { c == '\n' })
        .count()
      self.error(
        line + offset,
        "parse.token",
        "Invalid token: '" +
        raw.replace_all(old="\\", new="\\\\").replace_all(old="'", new="\\'") +
        "'",
      )
    }
  }
  (tokens, line)
}

///|
// Oracle duplicate checks permit cached account, empty/Latin-1 single-character
// string and singleton values. Equal numbers, dates and amounts still conflict.
fn repeated_metadata_value(a : @ast.MetaValue, b : @ast.MetaValue) -> Bool {
  match (a, b) {
    (MString(a), MString(b)) =>
      a == b &&
      (
        a == "" ||
        (a.length() == 1 && a.get_char(0) is Some(c) && c.to_int() <= 255)
      )
    (MAccount(a), MAccount(b)) => a == b
    (MBool(a), MBool(b)) => a == b
    (MNull, MNull) => true
    _ => false
  }
}
