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
  EValue(QueryValue)
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
  SrcTransactions
  SrcBalances
  SrcDirectives(String)
  SrcClose(@ast.Date)
  SrcOpen(@ast.Date, @ast.Date?)
}

///|
priv struct SelectQuery {
  projections : Array[Expr]
  distinct : Bool
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
              if lower != "count" {
                parser.fail("unsupported query.unsupported.star")
                return None
              }
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
        if ["sum", "count", "first", "last", "min", "max"].contains(lower) &&
          args.any(contains_sum) {
          parser.fail("compilation query.invalid_aggregate")
          return None
        }
        if oracle_signatures.any(fn(s) { s.0 == lower }) {
          Some(ECall(lower, args))
        } else {
          parser.fail(
            "compilation query.invalid_signature: unknown function `" +
            word +
            "`",
          )
          None
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
          | "accounts"
          | "weight"
          | "posting_flag"
          | "other_accounts"
          | "number"
          | "cost_number"
          | "cost_currency"
          | "cost_date"
          | "cost_label"
          | "price"
          | "balance"
          | "entry"
          | "location"
          | "type"
          | "id"
          | "filename"
          | "lineno"
          | "year"
          | "month"
          | "day"
          | "name"
          | "amount"
          | "tolerance"
          | "discrepancy"
          | "description"
          | "comment"
          | "meta"
          | "open"
          | "close" => Some(ECol(lower))
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
        parser.fail("unsupported query.unsupported.star")
        None
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
                  parser.fail(
                    "unsupported query.unsupported.regex: invalid or unsupported regular expression",
                  )
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
  let hashed = parser.match_sym("#")
  match parser.take_word() {
    Some(word) => {
      if hashed &&
        ![
          "postings", "transactions", "entries", "accounts", "balances", "commodities",
          "documents", "events", "notes", "prices",
        ].contains(word) {
        parser.fail("unsupported query.unsupported.source `#" + word + "`")
        return None
      }
      if !hashed && word.to_lower() == "accounts" {
        parser.fail(
          "unsupported query.unsupported.source_filter: bare accounts is a transaction filter",
        )
        return None
      }
      match word.to_lower() {
        "postings" => Some(SrcPostings)
        "transactions" => Some(SrcTransactions)
        "balances" =>
          if hashed {
            Some(SrcDirectives("balances"))
          } else {
            Some(SrcBalances)
          }
        "entries"
        | "accounts"
        | "commodities"
        | "documents"
        | "events"
        | "notes"
        | "prices" => Some(SrcDirectives(word.to_lower()))
        _ => {
          parser.fail("unknown FROM source `" + word + "`")
          None
        }
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
  let distinct = parser.match_keyword("distinct")
  let star = parser.match_sym("*")
  let projections = if star {
    []
  } else {
    match parse_expr_list(parser) {
      Some(items) => items
      None =>
        return PqError(
          match parser.error {
            Some(message) => message
            None => "expected a projection"
          },
        )
    }
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
  if star {
    let names = if source is SrcDirectives(table) {
      table_star(table)
    } else if source is SrcTransactions {
      ["date", "flag", "payee", "narration", "tags", "links", "accounts"]
    } else {
      ["date", "flag", "payee", "narration", "position"]
    }
    for name in names {
      projections.push(ECol(name))
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
  if groups.any(contains_sum) || !aggregate_free_cond(filter) {
    return PqError("compilation query.invalid_aggregate")
  }

  // Opening summary rows do not retain the synthetic transaction's account set.
  if source is SrcOpen(_, _) &&
    parser.tokens.any(fn(token) {
      match token {
        BWord(word) => word.to_lower() == "accounts"
        _ => false
      }
    }) {
    return PqError("unsupported query.unsupported.period_column")
  }
  if distinct && !projections.all(distinct_expr) {
    return PqError("unsupported query.unsupported.distinct_type")
  }
  if source is SrcDirectives(table) {
    let check = fn(expr) { table_expr(expr, table) }
    if !projections.all(check) ||
      !groups.all(check) ||
      !orders.all(fn(o) { check(o.expr) }) ||
      !table_cond(filter, table) ||
      !table_cond(having, table) {
      return PqError("compilation query.invalid_column")
    }
  }
  if !(source is SrcDirectives(_)) && !(source is SrcTransactions) {
    let valid = fn(expr) { posting_expr(expr) }
    if !projections.all(valid) ||
      !groups.all(valid) ||
      !orders.all(fn(o) { valid(o.expr) }) ||
      !posting_cond(filter) ||
      !posting_cond(having) {
      return PqError("unsupported query.unsupported.column")
    }
  }
  if source is SrcTransactions {
    if !projections.all(transaction_expr) ||
      !groups.all(transaction_expr) ||
      !orders.all(fn(o) { transaction_expr(o.expr) }) ||
      !transaction_cond(filter) ||
      !transaction_cond(having) {
      return PqError("unsupported query.unsupported.transaction_column")
    }
  }
  let errors : Array[String] = []
  for e in projections {
    expression_type(e, source, errors) |> ignore
  }
  for e in groups {
    expression_type(e, source, errors) |> ignore
  }
  for o in orders {
    expression_type(o.expr, source, errors) |> ignore
  }
  condition_types(filter, source, errors)
  condition_types(having, source, errors)
  if !errors.is_empty() {
    return PqError(errors[0])
  }
  for expr in groups {
    let kind = expression_type(expr, source, [])
    if ["dict", "list", "set", "inventory"].contains(kind) {
      return PqError("compilation query.invalid_group: non-hashable " + kind)
    }
    if kind == "frozenset" || kind == "generic_set" {
      return PqError(
        "query.oracle_type_error: TypeError oracle generic group type",
      )
    }
  }
  PqSelect({
    projections,
    distinct,
    source,
    filter,
    having,
    groups,
    orders,
    limit,
  })
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
  let unsupported : Array[String] = []
  let positions : Array[Int32] = []
  let tokens = lex_bql(text, unsupported~, positions~)
  if unsupported.length() > 0 {
    return PqError(unsupported[0])
  }
  for i in 0..<(tokens.length() - 1) {
    if tokens[i] is BSym("#") && positions[i + 1] != positions[i] + 1 {
      return PqError(
        "syntax query.invalid_source" +
        bql_lex_error(text, positions[i]).replace(
          old="lexical query.invalid_character",
          new="",
        ),
      )
    }
  }
  for i in 0..<tokens.length() {
    if tokens[i] is BStr(value) &&
      text.get_char(positions[i]) is Some('"') &&
      (table_columns("entries") +
      table_columns("prices") +
      table_columns("notes") +
      table_columns("accounts") +
      table_columns("balances") +
      table_columns("commodities")).contains(value.to_lower()) {
      return PqError(
        "unsupported query.unsupported.quoted_identifier" +
        bql_lex_error(text, positions[i]).replace(
          old="lexical query.invalid_character",
          new="",
        ),
      )
    }
  }
  let parser = QueryParser::new(tokens)
  if parser.at_end() {
    return PqError("empty query")
  }
  let result = match parser.take_word() {
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
  match result {
    PqError(message) => {
      let index = (parser.index - 1).max(0).min(positions.length() - 1)
      let location = bql_lex_error(text, positions[index]).replace(
        old="lexical query.invalid_character",
        new="",
      )
      PqError(message + location)
    }
    _ => result
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

///|
fn transaction_expr(expr : Expr) -> Bool {
  match expr {
    ECol(
      "date"
      | "flag"
      | "payee"
      | "narration"
      | "tags"
      | "links"
      | "accounts"
      | "meta"
    ) => true
    ECol(_) => false
    ECall("sum", _) => false
    ECall(_, args) => args.all(transaction_expr)
    EBinary(a, _, b) => transaction_expr(a) && transaction_expr(b)
    _ => true
  }
}

///|
fn transaction_cond(cond : Cond) -> Bool {
  match cond {
    CTrue => true
    CNot(c) => transaction_cond(c)
    CAnd(a, b) | COr(a, b) => transaction_cond(a) && transaction_cond(b)
    CCmp(a, _, b) => transaction_expr(a) && transaction_expr(b)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _) => transaction_expr(e)
  }
}

///|
fn distinct_expr(expr : Expr) -> Bool {
  match expr {
    ECol("meta" | "entry" | "open" | "close") => false
    ECall("sum", _) => false
    ECall(_, args) => args.all(distinct_expr)
    EBinary(a, _, b) => distinct_expr(a) && distinct_expr(b)
    _ => true
  }
}

///|
fn table_columns(table : String) -> Array[String] {
  match table {
    "entries" =>
      [
        "id", "type", "filename", "lineno", "date", "year", "month", "day", "flag",
        "payee", "narration", "description", "tags", "links", "meta", "accounts",
      ]
    "accounts" => ["account", "open", "close"]
    "balances" =>
      ["meta", "date", "account", "amount", "tolerance", "discrepancy"]
    "commodities" => ["meta", "date", "name"]
    "documents" => ["meta", "date", "account", "filename", "tags", "links"]
    "events" => ["meta", "date", "type", "description"]
    "notes" => ["meta", "date", "account", "comment", "tags", "links"]
    "prices" => ["meta", "date", "currency", "amount"]
    _ => []
  }
}

///|
fn table_star(table : String) -> Array[String] {
  match table {
    "entries" => table_columns(table)
    "prices" => ["date", "currency", "amount"]
    "events" => ["date", "type", "description"]
    "documents" => ["date", "account", "filename", "tags", "links"]
    "balances" => ["date", "account", "amount", "tolerance", "discrepancy"]
    "notes" => ["date", "account", "comment", "tags", "links"]
    _ => table_columns(table)
  }
}

///|
fn table_expr(expr : Expr, table : String) -> Bool {
  match expr {
    ECol(name) => table_columns(table).contains(name)
    ECall(_, args) => args.all(fn(arg) { table_expr(arg, table) })
    EBinary(a, _, b) => table_expr(a, table) && table_expr(b, table)
    _ => true
  }
}

///|
fn table_cond(cond : Cond, table : String) -> Bool {
  match cond {
    CTrue => true
    CNot(c) => table_cond(c, table)
    CAnd(a, b) | COr(a, b) => table_cond(a, table) && table_cond(b, table)
    CCmp(a, _, b) => table_expr(a, table) && table_expr(b, table)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _) => table_expr(e, table)
  }
}

///|
fn posting_expr(expr : Expr) -> Bool {
  match expr {
    ECol(
      "name"
      | "amount"
      | "tolerance"
      | "discrepancy"
      | "comment"
      | "open"
      | "close"
    ) => false
    ECall(_, args) => args.all(posting_expr)
    EBinary(a, _, b) => posting_expr(a) && posting_expr(b)
    _ => true
  }
}

///|
fn posting_cond(cond : Cond) -> Bool {
  match cond {
    CTrue => true
    CNot(c) => posting_cond(c)
    CAnd(a, b) | COr(a, b) => posting_cond(a) && posting_cond(b)
    CCmp(a, _, b) => posting_expr(a) && posting_expr(b)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _) => posting_expr(e)
  }
}

///|
fn aggregate_free_cond(cond : Cond) -> Bool {
  match cond {
    CTrue => true
    CNot(c) => aggregate_free_cond(c)
    CAnd(a, b) | COr(a, b) => aggregate_free_cond(a) && aggregate_free_cond(b)
    CCmp(a, _, b) => !contains_sum(a) && !contains_sum(b)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _) => !contains_sum(e)
  }
}
