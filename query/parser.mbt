// BQL subset parser.  Supported grammar:
//
//   SELECT <expr> [, <expr>]* [FROM postings|transactions|balances]
//     [WHERE <condition>] [GROUP BY <expr> [, <expr>*]]
//     [ORDER BY <expr> [ASC|DESC] [, ...]] [LIMIT <integer>]
//   BALANCES
//   JOURNAL <account> [LIMIT <integer>]
//
// Expressions are columns, literals, and the functions year(), month(),
// root(), parent(), leaf() and the aggregate sum().

///|
priv enum Expr {
  ECol(String)
  EStr(String)
  ENum(@decimal.Decimal)
  EDate(@ast.Date)
  ENull
  EStar
  EBool(Bool)
  ECall(String, Array[Expr])
  EBinary(Expr, String, Expr)
}

///|
priv enum Cond {
  CTrue
  CNot(Cond)
  CAnd(Cond, Cond)
  COr(Cond, Cond)
  CCmp(Expr, String, Expr)
  CIsNull(Expr, Bool)
  CTruthy(Expr)
  CRegex(Expr, @string.Regex)
}

///|
priv struct OrderSpec {
  expr : Expr
  descending : Bool
}

///|
priv enum QuerySource {
  SrcPostings
  SrcBalances
  SrcClose(@ast.Date)
  SrcOpen(@ast.Date, @ast.Date?)
}

///|
priv struct SelectQuery {
  projections : Array[Expr]
  source : QuerySource
  filter : Cond
  having : Cond
  groups : Array[Expr]
  orders : Array[OrderSpec]
  limit : Int32?
}

///|
priv enum ParsedQuery {
  PqSelect(SelectQuery)
  PqBalances
  PqJournal(String, Int32?)
  PqError(String)
}

///|
priv struct QueryParser {
  tokens : Array[BTok]
  mut index : Int32
  mut error : String?
}

///|
fn QueryParser::new(tokens : Array[BTok]) -> QueryParser {
  { tokens, index: 0, error: None, }
}

///|
fn QueryParser::peek(self : QueryParser) -> BTok {
  if self.index < self.tokens.length() {
    self.tokens[self.index]
  } else {
    BEof
  }
}

///|
fn QueryParser::advance(self : QueryParser) -> BTok {
  let token = self.peek()
  if self.index < self.tokens.length() {
    self.index = self.index + 1
  }
  token
}

///|
fn QueryParser::at_end(self : QueryParser) -> Bool {
  self.peek() is BEof
}

///|
fn QueryParser::fail(self : QueryParser, message : String) -> Unit {
  match self.error {
    Some(_) => ()
    None => self.error = Some(message)
  }
}

///|
fn QueryParser::peek_word(self : QueryParser) -> String? {
  match self.peek() {
    BWord(word) => Some(word)
    _ => None
  }
}

///|
fn QueryParser::peek_is_keyword(self : QueryParser, keyword : String) -> Bool {
  match self.peek_word() {
    Some(word) => word.to_lower() == keyword
    None => false
  }
}

///|
fn QueryParser::match_keyword(self : QueryParser, keyword : String) -> Bool {
  if self.peek_is_keyword(keyword) {
    self.advance() |> ignore
    true
  } else {
    false
  }
}

///|
fn QueryParser::expect_keyword(self : QueryParser, keyword : String) -> Bool {
  if self.match_keyword(keyword) {
    true
  } else {
    self.fail("expected `" + keyword + "`")
    false
  }
}

///|
fn QueryParser::take_word(self : QueryParser) -> String? {
  match self.peek() {
    BWord(word) => {
      self.advance() |> ignore
      Some(word)
    }
    _ => None
  }
}

///|
fn QueryParser::peek_sym(self : QueryParser) -> String? {
  match self.peek() {
    BSym(symbol) => Some(symbol)
    _ => None
  }
}

///|
fn QueryParser::match_sym(self : QueryParser, symbol : String) -> Bool {
  if self.peek_sym() == Some(symbol) {
    self.advance() |> ignore
    true
  } else {
    false
  }
}

///|
fn QueryParser::expect_sym(self : QueryParser, symbol : String) -> Bool {
  if self.match_sym(symbol) {
    true
  } else {
    self.fail("expected `" + symbol + "`")
    false
  }
}

///|
fn QueryParser::take_int(self : QueryParser) -> Int32? {
  match self.peek() {
    BInt(value) => {
      self.advance() |> ignore
      Some(value)
    }
    BNum(_) => {
      self.fail("expected an integer")
      None
    }
    _ => {
      self.fail("expected an integer")
      None
    }
  }
}

///|
fn parse_primary(parser : QueryParser) -> Expr? {
  match parser.peek() {
    BWord(word) => {
      parser.advance() |> ignore
      let lower = word.to_lower()
      if parser.match_sym("(") {
        let args : Array[Expr] = []
        if !parser.match_sym(")") {
          let mut done = false
          while !done {
            if parser.match_sym("*") {
              args.push(EStar)
            } else {
              match parse_expr(parser) {
                Some(expr) => args.push(expr)
                None => return None
              }
            }
            if parser.match_sym(",") {
              continue
            }
            done = true
          }
          if !parser.expect_sym(")") {
            return None
          }
        }
        match lower {
          "year"
          | "month"
          | "root"
          | "parent"
          | "leaf"
          | "sum"
          | "count"
          | "meta" => Some(ECall(lower, args))
          _ => {
            parser.fail("unknown function `" + word + "`")
            None
          }
        }
      } else if lower == "null" {
        Some(ENull)
      } else if lower == "true" {
        Some(EBool(true))
      } else if lower == "false" {
        Some(EBool(false))
      } else {
        match lower {
          "date"
          | "flag"
          | "payee"
          | "narration"
          | "account"
          | "root"
          | "parent"
          | "leaf"
          | "units"
          | "currency"
          | "cost"
          | "value"
          | "position"
          | "tags"
          | "links"
          | "weight" => Some(ECol(lower))
          _ => {
            parser.fail("unsupported column `" + word + "`")
            None
          }
        }
      }
    }
    BStr(value) => {
      parser.advance() |> ignore
      Some(EStr(value))
    }
    BInt(value) => {
      parser.advance() |> ignore
      Some(ENum(@decimal.Decimal::from_int(value)))
    }
    BNum(number) => {
      parser.advance() |> ignore
      Some(ENum(number))
    }
    BDate(date) => {
      parser.advance() |> ignore
      Some(EDate(date))
    }
    BSym(symbol) =>
      if symbol == "(" {
        parser.advance() |> ignore
        let expr = parse_expr(parser)
        if !parser.expect_sym(")") {
          return None
        }
        expr
      } else if symbol == "-" || symbol == "+" {
        parser.advance() |> ignore
        match parse_primary(parser) {
          Some(expr) =>
            Some(EBinary(ENum(@decimal.Decimal::zero()), symbol, expr))
          None => None
        }
      } else if symbol == "*" {
        parser.advance() |> ignore
        Some(EStar)
      } else {
        parser.fail("expected an expression")
        None
      }
    BEof => {
      parser.fail("unexpected end of query")
      None
    }
  }
}

///|
fn parse_binary(parser : QueryParser, min_prec : Int32) -> Expr? {
  let mut left = match parse_primary(parser) {
    Some(e) => e
    None => return None
  }
  while true {
    let op = match parser.peek_sym() {
      Some(s) => s
      None => break
    }
    let prec = match op {
      "+" | "-" => 1
      "*" | "/" => 2
      _ => 0
    }
    if prec < min_prec || prec == 0 {
      break
    }
    parser.advance() |> ignore
    let right = match parse_binary(parser, prec + 1) {
      Some(e) => e
      None => return None
    }
    left = EBinary(left, op, right)
  }
  Some(left)
}

///|
fn parse_expr(parser : QueryParser) -> Expr? {
  parse_binary(parser, 1)
}

///|
fn parse_cond_atom(parser : QueryParser) -> Cond? {
  if parser.match_sym("(") {
    match parse_cond_or(parser) {
      Some(cond) => if parser.expect_sym(")") { Some(cond) } else { None }
      None => None
    }
  } else {
    match parse_expr(parser) {
      Some(left) =>
        if parser.match_sym("~") {
          match parser.advance() {
            BStr(pattern) => {
              let regex = @string.Regex("(?i:" + pattern + ")") catch {
                _ => {
                  parser.fail("invalid or unsupported regular expression")
                  return None
                }
              }
              Some(CRegex(left, regex))
            }
            _ => {
              parser.fail("regex requires a literal pattern")
              None
            }
          }
        } else if parser.match_keyword("is") {
          let negated = parser.match_keyword("not")
          if parser.expect_keyword("null") {
            Some(CIsNull(left, negated))
          } else {
            None
          }
        } else {
          match parser.peek_sym() {
            Some(symbol) =>
              if symbol == "=" ||
                symbol == "==" ||
                symbol == "!=" ||
                symbol == "<>" ||
                symbol == "<" ||
                symbol == "<=" ||
                symbol == ">" ||
                symbol == ">=" {
                parser.advance() |> ignore
                match parse_expr(parser) {
                  Some(right) => Some(CCmp(left, symbol, right))
                  None => None
                }
              } else {
                Some(CTruthy(left))
              }
            None => Some(CTruthy(left))
          }
        }
      None => None
    }
  }
}

///|
fn parse_cond_not(parser : QueryParser) -> Cond? {
  if parser.match_keyword("not") {
    match parse_cond_not(parser) {
      Some(cond) => Some(CNot(cond))
      None => None
    }
  } else {
    parse_cond_atom(parser)
  }
}

///|
fn parse_cond_and(parser : QueryParser) -> Cond? {
  match parse_cond_not(parser) {
    Some(left) => {
      let mut cond = left
      while parser.match_keyword("and") {
        match parse_cond_not(parser) {
          Some(right) => cond = CAnd(cond, right)
          None => return None
        }
      }
      Some(cond)
    }
    None => None
  }
}

///|
fn parse_cond_or(parser : QueryParser) -> Cond? {
  match parse_cond_and(parser) {
    Some(left) => {
      let mut cond = left
      while parser.match_keyword("or") {
        match parse_cond_and(parser) {
          Some(right) => cond = COr(cond, right)
          None => return None
        }
      }
      Some(cond)
    }
    None => None
  }
}

///|
fn parse_expr_list(parser : QueryParser) -> Array[Expr]? {
  let items : Array[Expr] = []
  match parse_expr(parser) {
    Some(expr) => items.push(expr)
    None => return None
  }
  while parser.match_sym(",") {
    match parse_expr(parser) {
      Some(expr) => items.push(expr)
      None => return None
    }
  }
  Some(items)
}

///|
fn parse_source(parser : QueryParser) -> QuerySource? {
  if parser.match_keyword("open") {
    if !parser.expect_keyword("on") {
      return None
    }
    let start = match parser.advance() {
      BDate(date) => date
      _ => {
        parser.fail("OPEN ON requires a date")
        return None
      }
    }
    if start.year == 1 && start.month == 1 && start.day == 1 {
      parser.fail("OPEN ON requires a date after 0001-01-01")
      return None
    }
    let mut close = None
    if parser.match_keyword("close") {
      if !parser.expect_keyword("on") {
        return None
      }
      close = match parser.advance() {
        BDate(date) => Some(date)
        _ => {
          parser.fail("CLOSE ON requires a date")
          return None
        }
      }
    }
    return Some(SrcOpen(start, close))
  }
  if parser.match_keyword("close") {
    if !parser.expect_keyword("on") {
      return None
    }
    return match parser.advance() {
      BDate(date) => Some(SrcClose(date))
      _ => {
        parser.fail("CLOSE ON requires a date")
        None
      }
    }
  }
  match parser.take_word() {
    Some(word) =>
      match word.to_lower() {
        "postings" => Some(SrcPostings)
        "balances" => Some(SrcBalances)
        _ => {
          parser.fail("unknown FROM source `" + word + "`")
          None
        }
      }
    None => {
      parser.fail("expected a FROM source")
      None
    }
  }
}

///|
fn parse_select(parser : QueryParser) -> ParsedQuery {
  let projections = match parse_expr_list(parser) {
    Some(items) => items
    None =>
      return PqError(
        match parser.error {
          Some(message) => message
          None => "expected a projection"
        },
      )
  }
  let mut source = SrcPostings
  if parser.match_keyword("from") {
    match parse_source(parser) {
      Some(found) => source = found
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "invalid FROM clause"
          },
        )
    }
  }
  let mut filter = CTrue
  if parser.match_keyword("where") {
    match parse_cond_or(parser) {
      Some(cond) => filter = cond
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "invalid WHERE clause"
          },
        )
    }
  }
  let groups : Array[Expr] = []
  if parser.match_keyword("group") {
    if !parser.expect_keyword("by") {
      return PqError(
        match parser.error {
          Some(message) => message
          None => "expected BY"
        },
      )
    }
    match parse_expr_list(parser) {
      Some(items) =>
        for item in items {
          groups.push(item)
        }
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "invalid GROUP BY clause"
          },
        )
    }
  }
  let mut having = CTrue
  if parser.match_keyword("having") {
    match parse_cond_or(parser) {
      Some(cond) => having = cond
      None => return PqError("invalid HAVING clause")
    }
  }
  let orders : Array[OrderSpec] = []
  if parser.match_keyword("order") {
    if !parser.expect_keyword("by") {
      return PqError(
        match parser.error {
          Some(message) => message
          None => "expected BY"
        },
      )
    }
    let mut more = true
    while more {
      match parse_expr(parser) {
        Some(expr) => {
          let mut descending = false
          if parser.match_keyword("desc") {
            descending = true
          } else {
            parser.match_keyword("asc") |> ignore
          }
          orders.push({ expr, descending, })
        }
        None =>
          return PqError(
            match parser.error {
              Some(message) => message
              None => "invalid ORDER BY clause"
            },
          )
      }
      more = parser.match_sym(",")
    }
  }
  let mut limit = None
  if parser.match_keyword("limit") {
    match parser.take_int() {
      Some(value) => {
        if value < 0 {
          return PqError("LIMIT must be non-negative")
        }
        limit = Some(value)
      }
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "invalid LIMIT"
          },
        )
    }
  }
  if !parser.at_end() {
    return PqError("unexpected input after query")
  }
  PqSelect({ projections, source, filter, having, groups, orders, limit, })
}

///|
fn parse_journal(parser : QueryParser) -> ParsedQuery {
  let account = match parser.peek() {
    BWord(word) => {
      parser.advance() |> ignore
      word
    }
    BStr(value) => {
      parser.advance() |> ignore
      value
    }
    _ => return PqError("JOURNAL expects an account name")
  }
  let mut limit = None
  if parser.match_keyword("limit") {
    match parser.take_int() {
      Some(value) => {
        if value < 0 {
          return PqError("LIMIT must be non-negative")
        }
        limit = Some(value)
      }
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "invalid LIMIT"
          },
        )
    }
  }
  if !parser.at_end() {
    return PqError("unexpected input after JOURNAL")
  }
  PqJournal(account, limit)
}

///|
fn parse_query(text : String) -> ParsedQuery {
  let parser = QueryParser::new(lex_bql(text))
  if parser.at_end() {
    return PqError("empty query")
  }
  match parser.take_word() {
    Some(word) =>
      match word.to_lower() {
        "select" => parse_select(parser)
        "balances" =>
          if parser.at_end() {
            PqBalances
          } else {
            parse_balances(parser)
          }
        "journal" => parse_journal(parser)
        _ => PqError("unknown statement `" + word + "`")
      }
    None => PqError("query must start with SELECT, BALANCES or JOURNAL")
  }
}

///|
fn parse_balances(parser : QueryParser) -> ParsedQuery {
  let mut mode = "position"
  if parser.match_keyword("at") {
    mode = match parser.take_word() {
      Some(word) =>
        match word.to_lower() {
          "units" => "units"
          "cost" => "weight"
          _ => return PqError("BALANCES AT supports UNITS or COST")
        }
      None => return PqError("BALANCES AT expects a function")
    }
  }
  let tokens = [
    BWord("account"),
    BSym(","),
    BWord("sum"),
    BSym("("),
    BWord(mode),
    BSym(")"),
  ]
  for i in parser.index..<(parser.tokens.length() - 1) {
    tokens.push(parser.tokens[i])
  }
  for
    token in [
      BWord("group"),
      BWord("by"),
      BWord("account"),
      BWord("order"),
      BWord("by"),
      BWord("account"),
      BEof,
    ] {
    tokens.push(token)
  }
  parse_select(QueryParser::new(tokens))
}
