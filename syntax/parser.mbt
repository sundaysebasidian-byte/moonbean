// Line oriented parser for Beancount v3 syntax.  The parser records errors
// with file and line and keeps going so that a check run reports as many
// problems as possible in one pass.

///|
fn view_to_string(view : StringView) -> String {
  String::from_iter(view.iter())
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
fn is_comment_line(text : String) -> Bool {
  let t = trimmed(text)
  t.length() > 0 && t.get_char(0) == Some(';')
}

///|
fn is_blank_line(text : String) -> Bool {
  trimmed(text).length() == 0
}

///|
pub fn is_valid_account(account : String) -> Bool {
  let parts = @ast.account_parts(account)
  if parts.length() < 2 {
    return false
  }
  for part in parts {
    if part.length() == 0 {
      return false
    }
    let first = match part.get_char(0) {
      Some(c) => c
      None => return false
    }
    if !(first >= 'A' && first <= 'Z') {
      return false
    }
    for i in 1..<part.length() {
      let c = match part.get_char(i) {
        Some(c) => c
        None => return false
      }
      let ok = (c >= 'A' && c <= 'Z') ||
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        c == '-'
      if !ok {
        return false
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
  if word.length() > 1 && word.get_char(word.length() - 1) == Some(':') {
    Some(word.unsafe_substring(start=0, end=word.length() - 1))
  } else {
    None
  }
}

///|
fn meta_value(tok : Token) -> @ast.MetaValue? {
  match tok.kind {
    Str(s) => Some(@ast.MString(s))
    Tag(t) => Some(@ast.MTag(t))
    Word(w) =>
      if w == "TRUE" {
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
                if w.contains(":") && is_valid_account(w) {
                  Some(@ast.MAccount(w))
                } else if is_valid_currency(w) {
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
  lines : Array[String]
  mut index : Int32
  ledger : @ast.Ledger
  meta_stack : @ast.Meta
  tag_stack : Array[String]
}

///|
fn Parser::new(file : String, source : String) -> Parser {
  let lines = []
  for line in source.split("\n") {
    lines.push(view_to_string(line))
  }
  {
    file,
    lines,
    index: 0,
    ledger: @ast.Ledger::new(),
    meta_stack: @ast.Meta::new(),
    tag_stack: [],
  }
}

///|
fn Parser::error(
  self : Parser,
  line : Int32,
  code : String,
  message : String,
) -> Unit {
  self.ledger.add_error(
    @ast.Diagnostic::new(code, message, @ast.Loc::new(self.file, line)),
  )
}

///|
fn Parser::active_tags(self : Parser) -> Array[String] {
  self.tag_stack.copy()
}

///|
fn Parser::push_stack_meta(
  self : Parser,
  key : String,
  value : @ast.MetaValue,
) -> Unit {
  self.meta_stack.set(key, value)
}

///|
fn Parser::pop_stack_meta(self : Parser, key : String) -> Unit {
  self.meta_stack.remove(key)
}

///|
fn Parser::pop_tag(self : Parser, tag : String) -> Bool {
  let mut i = self.tag_stack.length()
  while i > 0 {
    i = i - 1
    if self.tag_stack[i] == tag {
      self.tag_stack.remove(i) |> ignore
      return true
    }
  }
  false
}

///|
fn collect_indented(parser : Parser) -> Array[(String, Int32)] {
  let result = []
  while parser.index < parser.lines.length() {
    let line = parser.lines[parser.index]
    if is_blank_line(line) {
      break
    }
    if !starts_whitespace(line) {
      break
    }
    result.push((line, parser.index + 1))
    parser.index = parser.index + 1
  }
  result
}

///|
fn parse_meta_line(tokens : Array[Token]) -> (String, @ast.MetaValue)? {
  let cursor = Cursor::new(tokens)
  let key = match cursor.peek().kind {
    Word(w) =>
      match meta_key_from_word(w) {
        Some(key) => key
        None => return None
      }
    _ => return None
  }
  cursor.advance() |> ignore
  let value = match meta_value(cursor.peek()) {
    Some(v) => v
    None => return None
  }
  cursor.advance() |> ignore
  if !cursor.eof() {
    return None
  }
  Some((key, value))
}

///|
fn parse_amount(cursor : Cursor, parser : Parser, line : Int32) -> @ast.Amount? {
  let number = match cursor.take_word() {
    Some(w) =>
      match @decimal.Decimal::parse(w) {
        Some(n) => n
        None => {
          parser.error(line, "parse.number", "invalid number `" + w + "`")
          return None
        }
      }
    None => {
      parser.error(
        line,
        "parse.number",
        "expected an amount number, found " + cursor.kind().describe_token(),
      )
      return None
    }
  }
  let currency = match cursor.take_word() {
    Some(w) =>
      if is_valid_currency(w) {
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
  let total = match cursor.kind() {
    LDoubleBrace => true
    LBrace => false
    _ => return None
  }
  cursor.advance() |> ignore
  let mut number : @decimal.Decimal? = None
  let mut currency : String? = None
  let mut date : @ast.Date? = None
  let mut label : String? = None
  let mut merge = false
  while true {
    match cursor.kind() {
      RDoubleBrace => {
        if !total {
          parser.error(
            line, "parse.cost", "unexpected `}}` in cost specification",
          )
        }
        cursor.advance() |> ignore
        break
      }
      RBrace => {
        if total {
          parser.error(
            line, "parse.cost", "unexpected `}` in total cost specification",
          )
        }
        cursor.advance() |> ignore
        break
      }
      Eof => {
        parser.error(line, "parse.cost", "unterminated cost specification")
        break
      }
      Comma => cursor.advance() |> ignore
      Star => {
        merge = true
        cursor.advance() |> ignore
      }
      Tag(_) => {
        parser.error(line, "parse.cost", "unexpected tag in cost specification")
        cursor.advance() |> ignore
      }
      Str(s) => {
        label = Some(s)
        cursor.advance() |> ignore
      }
      Word(w) =>
        match @decimal.Decimal::parse(w) {
          Some(n) => {
            number = Some(n)
            cursor.advance() |> ignore
            match cursor.kind() {
              Word(c) =>
                if is_valid_currency(c) {
                  currency = Some(c)
                  cursor.advance() |> ignore
                }
              _ => ()
            }
          }
          None =>
            match @ast.Date::parse(w) {
              Some(d) => {
                date = Some(d)
                cursor.advance() |> ignore
              }
              None =>
                if is_valid_currency(w) {
                  currency = Some(w)
                  cursor.advance() |> ignore
                } else {
                  parser.error(
                    line,
                    "parse.cost",
                    "unexpected `" + w + "` in cost specification",
                  )
                  cursor.advance() |> ignore
                }
            }
        }
      _ => {
        parser.error(
          line,
          "parse.cost",
          "unexpected " +
          cursor.kind().describe_token() +
          " in cost specification",
        )
        cursor.advance() |> ignore
      }
    }
  }
  let filled : @ast.CostSpec = {
    number_per: if total {
      None
    } else {
      number
    },
    number_total: if total {
      number
    } else {
      None
    },
    currency,
    date,
    label,
    merge,
    present: true,
  }
  Some(filled)
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
    Some(amount) =>
      if total {
        Some(@ast.PriceAnno::Total(amount))
      } else {
        Some(@ast.PriceAnno::PerUnit(amount))
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
    Star => {
      flag = Some("*")
      cursor.advance() |> ignore
    }
    Word(w) =>
      if w.length() == 1 && w != "*" {
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
  if !is_valid_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let posting = @ast.Posting::new(account)
  posting.flag = flag
  match cursor.kind() {
    Word(w) =>
      match @decimal.Decimal::parse(w) {
        Some(number) => {
          cursor.advance() |> ignore
          let currency = match cursor.take_word() {
            Some(c) =>
              if is_valid_currency(c) {
                c
              } else {
                parser.error(
                  line,
                  "parse.currency",
                  "invalid currency `" + c + "` in posting",
                )
                return None
              }
            None => {
              parser.error(
                line, "parse.currency", "posting amount is missing a currency",
              )
              return None
            }
          }
          posting.units = Some(@ast.Amount::new(number, currency))
        }
        None =>
          if is_valid_currency(w) {
            cursor.advance() |> ignore
            posting.units_currency = Some(w)
          } else {
            parser.error(
              line,
              "parse.posting",
              "unexpected `" + w + "` in posting",
            )
            return None
          }
      }
    _ => ()
  }
  if cursor.kind() is LBrace || cursor.kind() is LDoubleBrace {
    posting.cost = parse_cost(cursor, parser, line)
  }
  if cursor.kind() is At || cursor.kind() is AtAt {
    posting.price = parse_price_annotation(cursor, parser, line)
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.posting",
      "unexpected " + cursor.kind().describe_token() + " at end of posting",
    )
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
      Tag(t) => {
        push_unique(tags, t)
        cursor.advance() |> ignore
      }
      Link(l) => {
        push_unique(links, l)
        cursor.advance() |> ignore
      }
      _ => cursor.advance() |> ignore
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
    Word(w) =>
      if w == "txn" {
        flag = "*"
        cursor.advance() |> ignore
      } else if w.length() == 1 {
        flag = w
        cursor.advance() |> ignore
      }
    _ => ()
  }
  let mut payee : String? = None
  let narration = match cursor.kind() {
    Str(s) => {
      cursor.advance() |> ignore
      match cursor.kind() {
        Str(s2) => {
          payee = Some(s)
          cursor.advance() |> ignore
          s2
        }
        _ => s
      }
    }
    _ => {
      parser.error(
        line, "parse.narration", "transaction is missing a narration string",
      )
      return None
    }
  }
  let tags : Array[String] = []
  let links : Array[String] = []
  parse_tags_and_links(cursor, tags, links)
  let txn = @ast.Transaction::new(flag, payee, narration, tags, links)
  let own_meta = @ast.Meta::new()
  let continuations = collect_indented(parser)
  let mut posting_count = 0
  for pair in continuations {
    let text = pair.0
    let meta_line = pair.1
    if is_blank_line(text) || is_comment_line(text) {
      continue
    }
    let line_tokens = tokenize(text)
    let mut handled = false
    match line_tokens[0].kind {
      Word(w) =>
        match meta_key_from_word(w) {
          Some(_) => {
            handled = true
            match parse_meta_line(line_tokens) {
              Some((key, value)) =>
                if posting_count > 0 {
                  txn.postings[posting_count - 1].meta.set(key, value)
                } else {
                  own_meta.set(key, value)
                }
              None =>
                parser.error(meta_line, "parse.meta", "invalid metadata line")
            }
          }
          None => ()
        }
      Tag(t) => {
        handled = true
        push_unique(txn.tags, t)
      }
      Link(l) => {
        handled = true
        push_unique(txn.links, l)
      }
      _ => ()
    }
    if handled {
      continue
    }
    match parse_posting(line_tokens, parser, meta_line) {
      Some(posting) => {
        txn.postings.push(posting)
        posting_count = posting_count + 1
      }
      None => ()
    }
  }
  for tag in parser.active_tags() {
    push_unique(txn.tags, tag)
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DTransaction(txn),
  )
  entry.meta = merge_meta(parser.meta_stack, own_meta)
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
  if !is_valid_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let currencies = []
  let mut booking : String? = None
  while !cursor.eof() {
    match cursor.kind() {
      Comma => cursor.advance() |> ignore
      Str(s) => {
        // Booking method names are validated semantically so that an invalid
        // method produces a bean-check style diagnostic on the open directive.
        booking = Some(s)
        cursor.advance() |> ignore
      }
      Word(w) =>
        if is_booking_method(w) {
          booking = Some(w)
          cursor.advance() |> ignore
        } else if is_valid_currency(w) {
          currencies.push(w)
          cursor.advance() |> ignore
        } else {
          parser.error(
            line,
            "parse.open",
            "unexpected `" + w + "` in open directive",
          )
          cursor.advance() |> ignore
        }
      _ => {
        parser.error(
          line,
          "parse.open",
          "unexpected " + cursor.kind().describe_token() + " in open directive",
        )
        cursor.advance() |> ignore
      }
    }
  }
  let open : @ast.Open = { account, currencies, booking, }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DOpen(open),
  )
  entry.meta = parser.meta_stack.copy()
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
  if !is_valid_account(account) {
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
  }
  let close : @ast.Close = { account, }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DClose(close),
  )
  entry.meta = parser.meta_stack.copy()
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
  if !is_valid_currency(currency) {
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
  }
  let commodity : @ast.Commodity = { currency, }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DCommodity(commodity),
  )
  entry.meta = parser.meta_stack.copy()
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
  if !is_valid_account(account) || !is_valid_account(source) {
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
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DPad({ account, source_account: source, }),
  )
  entry.meta = parser.meta_stack.copy()
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
  if !is_valid_account(account) {
    parser.error(
      line,
      "parse.account",
      "invalid account name `" + account + "`",
    )
    return None
  }
  let number = match cursor.take_word() {
    Some(w) =>
      match @decimal.Decimal::parse(w) {
        Some(n) => n
        None => {
          parser.error(
            line,
            "parse.balance",
            "invalid balance amount `" + w + "`",
          )
          return None
        }
      }
    None => {
      parser.error(
        line, "parse.balance", "balance directive is missing an amount",
      )
      return None
    }
  }
  let mut tolerance : @decimal.Decimal? = None
  if cursor.kind() is Tilde {
    cursor.advance() |> ignore
    match cursor.take_word() {
      Some(w) =>
        match @decimal.Decimal::parse(w) {
          Some(n) => tolerance = Some(n)
          None =>
            parser.error(
              line,
              "parse.balance",
              "invalid balance tolerance `" + w + "`",
            )
        }
      None => parser.error(line, "parse.balance", "expected a number after `~`")
    }
  }
  let currency = match cursor.take_word() {
    Some(c) =>
      if is_valid_currency(c) {
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
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DBalance({
      account,
      amount: @ast.Amount::new(number, currency),
      tolerance,
    }),
  )
  entry.meta = parser.meta_stack.copy()
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
      if is_valid_currency(c) {
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
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DPrice({ currency, amount, }),
  )
  entry.meta = parser.meta_stack.copy()
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
        @ast.Loc::new(parser.file, line),
        @ast.Directive::DEvent({ event_type, description, }),
      )
      entry.meta = parser.meta_stack.copy()
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
        @ast.Loc::new(parser.file, line),
        @ast.Directive::DQuery({ name, query, }),
      )
      entry.meta = parser.meta_stack.copy()
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
  if !is_valid_account(account) {
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
  if !cursor.eof() {
    parser.error(
      line,
      "parse.note",
      "unexpected " +
      cursor.kind().describe_token() +
      " at end of note directive",
    )
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DNote({ account, comment, }),
  )
  entry.meta = parser.meta_stack.copy()
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
  if !is_valid_account(account) {
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
  let tags : Array[String] = []
  let links : Array[String] = []
  parse_tags_and_links(cursor, tags, links)
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DDocument({ account, filename, tags, links, }),
  )
  entry.meta = parser.meta_stack.copy()
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
      Tag(t) => {
        values.push(@ast.CustomValue::CTag(t))
        cursor.advance() |> ignore
      }
      Star => {
        parser.error(line, "parse.custom", "unexpected `*` in custom directive")
        cursor.advance() |> ignore
      }
      Word(w) =>
        if w == "TRUE" || w == "FALSE" {
          values.push(@ast.CustomValue::CBool(w == "TRUE"))
          cursor.advance() |> ignore
        } else {
          match @ast.Date::parse(w) {
            Some(d) => {
              values.push(@ast.CustomValue::CDate(d))
              cursor.advance() |> ignore
            }
            None =>
              match @decimal.Decimal::parse(w) {
                Some(n) => {
                  cursor.advance() |> ignore
                  match cursor.kind() {
                    Word(c) =>
                      if is_valid_currency(c) {
                        values.push(
                          @ast.CustomValue::CAmount(@ast.Amount::new(n, c)),
                        )
                        cursor.advance() |> ignore
                      } else {
                        values.push(@ast.CustomValue::CNumber(n))
                      }
                    _ => values.push(@ast.CustomValue::CNumber(n))
                  }
                }
                None =>
                  if w.contains(":") && is_valid_account(w) {
                    values.push(@ast.CustomValue::CAccount(w))
                    cursor.advance() |> ignore
                  } else if is_valid_currency(w) {
                    values.push(@ast.CustomValue::CCurrency(w))
                    cursor.advance() |> ignore
                  } else {
                    parser.error(
                      line,
                      "parse.custom",
                      "unexpected `" + w + "` in custom directive",
                    )
                    cursor.advance() |> ignore
                  }
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
        cursor.advance() |> ignore
      }
    }
  }
  let entry = @ast.Entry::new(
    date,
    @ast.Loc::new(parser.file, line),
    @ast.Directive::DCustom({ custom_type, values, }),
  )
  entry.meta = parser.meta_stack.copy()
  Some(entry)
}

///|
fn apply_option(
  parser : Parser,
  name : String,
  value : String,
  line : Int32,
) -> Unit {
  parser.ledger.options.add_raw(name, value)
  let options = parser.ledger.options
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
    match @decimal.Decimal::parse(value) {
      Some(n) => options.tolerance_multiplier = n
      None =>
        parser.error(
          line,
          "parse.option",
          "invalid " + name + " `" + value + "`",
        )
    }
  } else if name == "inferred_tolerance_default" {
    let parts = value.split(":")
    let pair = []
    for part in parts {
      pair.push(view_to_string(part))
    }
    if pair.length() == 2 && is_valid_currency(pair[0]) {
      match @decimal.Decimal::parse(pair[1]) {
        Some(n) => options.inferred_tolerance_default.set(pair[0], n)
        None =>
          parser.error(
            line,
            "parse.option",
            "invalid inferred_tolerance_default `" + value + "`",
          )
      }
    } else {
      parser.error(
        line, "parse.option", "inferred_tolerance_default must be CCY:NUMBER",
      )
    }
  } else if name == "infer_tolerance_from_cost" {
    options.infer_tolerance_from_cost = value == "TRUE" || value == "true"
  } else if name == "account_rounding" {
    options.account_rounding = Some(value)
  } else if name == "operating_currency" {
    options.operating_currencies.push(value)
  } else if name == "documents" {
    options.documents.push(value)
  } else if name == "render_commas" {
    options.render_commas = value == "TRUE" || value == "true"
  } else if name == "display_precision" {
    let parts = value.split(":")
    let pair = []
    for part in parts {
      pair.push(view_to_string(part))
    }
    if pair.length() == 2 && is_valid_currency(pair[0]) {
      match @decimal.Decimal::parse(pair[1]) {
        Some(n) => options.display_precision.set(pair[0], n)
        None =>
          parser.error(
            line,
            "parse.option",
            "invalid display_precision `" + value + "`",
          )
      }
    } else {
      parser.error(line, "parse.option", "display_precision must be CCY:NUMBER")
    }
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
  }
  parser.ledger.plugins.push({ name, config, })
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
  }
  parser.ledger.includes.push((path, @ast.Loc::new(parser.file, line)))
}

///|
fn parse_push_tag(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  match cursor.peek().kind {
    Tag(t) => {
      parser.tag_stack.push(t)
      cursor.advance() |> ignore
    }
    _ => {
      parser.error(line, "parse.pushtag", "pushtag expects a tag")
      return
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.pushtag",
      "unexpected " + cursor.kind().describe_token() + " after tag",
    )
  }
}

///|
fn parse_pop_tag(parser : Parser, tokens : Array[Token], line : Int32) -> Unit {
  let cursor = Cursor::new(tokens)
  cursor.index = 1
  match cursor.peek().kind {
    Tag(t) => {
      if !parser.pop_tag(t) {
        parser.error(
          line,
          "parse.poptag",
          "poptag without matching pushtag for `#" + t + "`",
        )
      }
      cursor.advance() |> ignore
    }
    _ => {
      parser.error(line, "parse.poptag", "poptag expects a tag")
      return
    }
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.poptag",
      "unexpected " + cursor.kind().describe_token() + " after tag",
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
    let value = match meta_value(cursor.peek()) {
      Some(v) => v
      None => {
        parser.error(line, "parse.pushmeta", "expected a metadata value")
        return
      }
    }
    cursor.advance() |> ignore
    parser.push_stack_meta(key, value)
  } else {
    parser.pop_stack_meta(key)
  }
  if !cursor.eof() {
    parser.error(
      line,
      "parse.pushmeta",
      "unexpected " + cursor.kind().describe_token() + " after metadata",
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
      match @ast.Date::parse(w) {
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
    Star => parse_transaction(parser, date, tokens, line, 1)
    Str(_) => parse_transaction(parser, date, tokens, line, 1)
    Word(w) =>
      if w.length() == 1 {
        parse_transaction(parser, date, tokens, line, 1)
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
) -> Unit {
  let continuations = collect_indented(parser)
  let own_meta = @ast.Meta::new()
  for pair in continuations {
    let text = pair.0
    let meta_line = pair.1
    if is_blank_line(text) || is_comment_line(text) {
      continue
    }
    let tokens = tokenize(text)
    match parse_meta_line(tokens) {
      Some((key, value)) => own_meta.set(key, value)
      None => parser.error(meta_line, "parse.meta", "invalid metadata line")
    }
  }
  let merged = merge_meta(entry.meta, own_meta)
  entry.meta = merged
  let _ = line
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
        parse_push_tag(parser, tokens, line)
      } else if w == "poptag" {
        parse_pop_tag(parser, tokens, line)
      } else if w == "pushmeta" {
        parse_push_meta(parser, tokens, line, true)
      } else if w == "popmeta" {
        parse_push_meta(parser, tokens, line, false)
      } else {
        match parse_dated_directive(parser, tokens, line) {
          Some(entry) => {
            attach_continuation_meta(parser, entry, line)
            parser.ledger.entries.push(entry)
          }
          None => {
            // Still consume indented lines so that the rest of the file can
            // be parsed and reported.
            let _ = collect_indented(parser)
          }
        }
      }
    _ =>
      match parse_dated_directive(parser, tokens, line) {
        Some(entry) => {
          attach_continuation_meta(parser, entry, line)
          parser.ledger.entries.push(entry)
        }
        None => {
          let _ = collect_indented(parser)
        }
      }
  }
}

///|
pub fn parse_source(file : String, source : String) -> @ast.Ledger {
  let parser = Parser::new(file, source)
  while parser.index < parser.lines.length() {
    let line = parser.lines[parser.index]
    let line_no = parser.index + 1
    parser.index = parser.index + 1
    if is_blank_line(line) || is_comment_line(line) {
      continue
    }
    if starts_whitespace(line) {
      parser.error(
        line_no, "parse.indent", "unexpected indented line outside of a directive",
      )
      continue
    }
    let tokens = tokenize(line)
    parse_toplevel(parser, tokens, line_no)
  }
  parser.ledger
}
