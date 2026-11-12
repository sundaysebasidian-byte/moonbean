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
  EPredicate(Cond)
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
  CRegex(Expr, String, @string.Regex)
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
  SrcRelation(SelectQuery)
  SrcFrom(Cond, @ast.Date?, @ast.Date?, Bool, Bool)
}

///|
priv struct SelectQuery {
  projections : Array[Expr]
  names : Array[String]
  labels : Array[String]
  pivot : (Int32, Int32)?
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
  PqPrint(Cond, QuerySource)
  PqJournal(String, Int32?)
  PqError(String)
}

///|
priv struct QueryParser {
  tokens : Array[BTok]
  text : String
  positions : Array[Int32]
  mut index : Int32
  mut error : String?
}

///|
fn QueryParser::new(
  tokens : Array[BTok],
  text~ : String = "",
  positions~ : Array[Int32] = [],
) -> QueryParser {
  { tokens, text, positions, index: 0, error: None, }
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
        if lower == "count" && parser.match_keyword("distinct") {
          parser.fail("DISTINCT is not valid in COUNT arguments")
          return None
        }
        let args : Array[Expr] = []
        if !parser.match_sym(")") {
          let mut done = false
          while !done {
            if parser.match_sym("*") {
              if lower != "count" {
                parser.fail("unexpected star")
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
          _ => Some(ECol(lower))
        }
      }
    }
    BStr(value) => {
      let quoted = !parser.positions.is_empty() &&
        parser.text.get_char(parser.positions[parser.index]) == Some('"')
      parser.advance() |> ignore
      Some(if quoted { ECall("__quoted", [EStr(value)]) } else { EStr(value) })
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
        let first = match parse_expr(parser) {
          Some(e) => e
          None => return None
        }
        if parser.match_sym(",") {
          let values : Array[QueryValue] = []
          let mut expr = first
          let mut first_item = true
          while true {
            match literal_value(expr) {
              Some(v) => if first_item || !(v is QNull) { values.push(v) }
              None => {
                parser.fail("list elements must be literals")
                return None
              }
            }
            first_item = false
            if parser.match_sym(")") {
              return Some(EValue(QList(values)))
            }
            expr = match parse_expr(parser) {
              Some(e) => e
              None => return None
            }
            if !parser.match_sym(",") {
              if !parser.expect_sym(")") {
                return None
              }
              match literal_value(expr) {
                Some(v) => if !(v is QNull) { values.push(v) }
                None => {
                  parser.fail("list elements must be literals")
                  return None
                }
              }
              return Some(EValue(QList(values)))
            }
          }
        }
        if !parser.expect_sym(")") {
          return None
        }
        Some(first)
      } else if symbol == "-" || symbol == "+" {
        parser.advance() |> ignore
        match parse_primary(parser) {
          Some(expr) =>
            Some(EBinary(ENum(@decimal.Decimal::zero()), symbol, expr))
          None => None
        }
      } else if symbol == "*" {
        parser.advance() |> ignore
        parser.fail("unexpected star")
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
      "*" | "/" | "%" => 2
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
  match parse_cond_or(parser) {
    Some(CTruthy(expr)) => Some(expr)
    Some(cond) => Some(EPredicate(cond))
    None => None
  }
}

///|
fn parse_cond_atom(parser : QueryParser) -> Cond? {
  match parse_binary(parser, 1) {
    Some(left) =>
      if parser.match_keyword("between") {
        let low = match parse_binary(parser, 1) {
          Some(e) => e
          None => return None
        }
        if !parser.expect_keyword("and") {
          return None
        }
        let high = match parse_binary(parser, 1) {
          Some(e) => e
          None => return None
        }
        Some(CTruthy(ECall("__between", [left, low, high])))
      } else if parser.match_keyword("in") {
        parse_binary(parser, 1).map(fn(right) {
          CTruthy(ECall("__in", [left, right]))
        })
      } else if parser.peek() is BWord(word) &&
        word.to_lower() == "not" &&
        parser.tokens.get(parser.index + 1) is Some(BWord(next)) &&
        next.to_lower() == "in" {
        parser.advance() |> ignore
        parser.advance() |> ignore
        parse_binary(parser, 1).map(fn(right) {
          CTruthy(ECall("__notin", [left, right]))
        })
      } else if parser.match_sym("~") {
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
            Some(CRegex(left, pattern, regex))
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
              match parse_binary(parser, 1) {
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
fn parse_source_base(parser : QueryParser) -> QuerySource? {
  if parser.match_sym("(") {
    if !parser.expect_keyword("select") {
      return None
    }
    match parse_select(parser) {
      PqSelect(query) => {
        if !parser.expect_sym(")") {
          return None
        }
        return Some(SrcRelation(query))
      }
      PqError(message) => {
        parser.fail(message)
        return None
      }
      _ => return None
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
  let projections : Array[Expr] = []
  let aliases : Array[String?] = []
  let expressions : Array[String] = []
  if !star {
    while true {
      let start = parser.index
      match parse_expr(parser) {
        Some(expr) => projections.push(expr)
        None => return PqError(parser.error.unwrap_or("expected a projection"))
      }
      expressions.push(
        if projections.last().unwrap() is ECol(name) {
          name
        } else if parser.positions.is_empty() {
          oracle_expr_label(projections.last().unwrap())
        } else {
          parser.text[parser.positions[start]:parser.positions[parser.index]]
          .trim()
          .to_owned()
        },
      )
      let column_alias = if parser.match_keyword("as") {
        match parser.advance() {
          BWord(name) => Some(name.to_lower())
          BStr(name) => {
            if parser.positions.is_empty() ||
              parser.text.get_char(parser.positions[parser.index - 1]) !=
              Some('"') {
              return PqError("expected a column alias")
            }
            Some(name)
          }
          _ => return PqError("expected a column alias")
        }
      } else {
        None
      }
      aliases.push(column_alias)
      if !parser.match_sym(",") {
        break
      }
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
    let names = if source is SrcRelation(inner) {
      inner.names
    } else if source is SrcDirectives(table) {
      table_star(table)
    } else if source is SrcTransactions {
      ["date", "flag", "payee", "narration", "tags", "links", "accounts"]
    } else {
      ["date", "flag", "payee", "narration", "position"]
    }
    for name in names {
      projections.push(ECol(name))
      aliases.push(None)
      expressions.push(name)
    }
  }
  let names = projections.mapi(fn(i, _) { aliases[i].unwrap_or(expressions[i]) })
  let labels = projections.mapi(fn(i, e) {
    aliases[i].unwrap_or(
      if expr_any(e, fn(e) { e is ECall("__quoted", _) }) {
        expressions[i]
      } else {
        expr_label(e)
      },
    )
  })
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
          groups.push(
            resolve_reference(parser, item, projections, names, "GROUP-BY"),
          )
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
  let has_having = parser.match_keyword("having")
  if has_having {
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
          let expr = resolve_reference(
            parser, expr, projections, names, "ORDER-BY",
          )
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
  let mut pivot = None
  if parser.match_keyword("pivot") {
    if !parser.expect_keyword("by") {
      return PqError("expected BY")
    }
    let first = parse_pivot_reference(parser, projections, names)
    if !parser.expect_sym(",") {
      return PqError("PIVOT BY requires two columns")
    }
    let second = parse_pivot_reference(parser, projections, names)
    if first == second && parser.error is None {
      return PqError(
        "compilation query.invalid_reference: the two PIVOT BY columns cannot be the same column",
      )
    }
    pivot = Some((first, second))
  }
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
  if !parser.at_end() && parser.peek_sym() != Some(")") {
    return PqError("unexpected input after query")
  }
  if parser.error is Some(message) {
    return PqError(message)
  }
  for i in 0..<projections.length() {
    projections[i] = resolve_quoted(projections[i], source)
  }
  for i in 0..<groups.length() {
    groups[i] = resolve_quoted(groups[i], source)
  }
  for i in 0..<orders.length() {
    orders[i] = { ..orders[i], expr: resolve_quoted(orders[i].expr, source), }
  }
  filter = resolve_quoted_condition(filter, source)
  having = resolve_quoted_condition(having, source)
  let implicit_groups = groups.is_empty()
  if implicit_groups && has_having {
    return PqError("HAVING requires explicit GROUP BY")
  }
  if has_having && aggregate_free_cond(having) {
    return PqError(
      "compilation query.invalid_aggregate: HAVING must be aggregate",
    )
  }
  if projections.any(fn(e) { contains_sum(e) && unaggregated_column(e) }) {
    return PqError("compilation query.invalid_aggregate: mixed expression")
  }
  if groups.is_empty() && projections.any(contains_sum) {
    for projection in projections {
      if !contains_sum(projection) {
        groups.push(projection)
      }
    }
  }
  let aggregate_query = projections.any(contains_sum) || !groups.is_empty()
  if aggregate_query {
    for projection in projections {
      if !contains_sum(projection) &&
        !groups.any(fn(g) { same_expr(g, projection) }) {
        return PqError("compilation query.invalid_group: uncovered projection")
      }
    }
    for order in orders {
      if !contains_sum(order.expr) &&
        !groups.any(fn(g) { same_expr(g, order.expr) }) {
        return PqError("compilation query.invalid_group: uncovered ORDER BY")
      }
    }
  }
  if groups.any(contains_sum) || !aggregate_free_cond(filter) {
    return PqError("compilation query.invalid_aggregate")
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
  if !(source is SrcDirectives(_)) &&
    !(source is SrcTransactions) &&
    !(source is SrcRelation(_)) {
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
      return PqError("compilation query.invalid_column")
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
    if implicit_groups && (kind == "set" || kind == "frozenset") {
      continue
    }
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
    names,
    labels,
    pivot,
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
fn parse_legacy_journal(parser : QueryParser) -> ParsedQuery {
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
  let parser = QueryParser::new(tokens, text~, positions~)
  if parser.at_end() {
    return PqError("empty query")
  }
  let result = match parser.take_word() {
    Some(word) =>
      match word.to_lower() {
        "print" => parse_print(parser)
        "select" => parse_select(parser)
        "balances" => parse_balances(parser)
        "journal" => parse_journal(parser)
        _ => PqError("unknown statement `" + word + "`")
      }
    None => PqError("query must start with SELECT, BALANCES or JOURNAL")
  }
  let result = if !(result is PqError(_)) &&
    tokens[0] is BWord(word) &&
    word.to_lower() == "select" &&
    !parser.at_end() {
    PqError("unexpected input after query")
  } else {
    result
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
  let mut mode = ""
  if parser.match_keyword("at") {
    mode = match parser.take_word() {
      Some(word) => word
      None => return PqError("expected valuation function")
    }
  }
  let tokens = [BWord("account"), BSym(","), BWord("sum"), BSym("(")]
  if mode != "" {
    tokens.append([BWord(mode), BSym("(")])
  }
  tokens.push(BWord("position"))
  if mode != "" {
    tokens.push(BSym(")"))
  }
  tokens.push(BSym(")"))
  for i in parser.index..<(parser.tokens.length() - 1) {
    tokens.push(parser.tokens[i])
  }
  tokens.append([BWord("group"), BWord("by"), BWord("account"), BEof])
  match parse_select(QueryParser::new(tokens)) {
    PqSelect(query) => {
      let label = if mode == "" {
        "SUM((position))"
      } else {
        "SUM(" + mode + "(position))"
      }
      PqSelect({
        ..query,
        labels: ["account", label],
        names: ["account", label],
        orders: [
          {
            expr: ECall("account_sortkey", [ECol("account")]),
            descending: false,
          },
        ],
      })
    }
    other => other
  }
}

///|
fn transaction_expr(expr : Expr) -> Bool {
  match expr {
    EPredicate(c) => transaction_cond(c)
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
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => transaction_expr(e)
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
    EPredicate(c) => table_cond(c, table)
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
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => table_expr(e, table)
  }
}

///|
fn posting_expr(expr : Expr) -> Bool {
  match expr {
    EPredicate(c) => posting_cond(c)
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
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => posting_expr(e)
  }
}

///|
fn aggregate_free_cond(cond : Cond) -> Bool {
  match cond {
    CTrue => true
    CNot(c) => aggregate_free_cond(c)
    CAnd(a, b) | COr(a, b) => aggregate_free_cond(a) && aggregate_free_cond(b)
    CCmp(a, _, b) => !contains_sum(a) && !contains_sum(b)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => !contains_sum(e)
  }
}

///|
fn unaggregated_column(expr : Expr) -> Bool {
  match expr {
    EPredicate(c) => unaggregated_condition(c)
    ECol(_) => true
    ECall("sum" | "count" | "first" | "last" | "min" | "max", _) => false
    ECall(_, args) => args.any(unaggregated_column)
    EBinary(a, _, b) => unaggregated_column(a) || unaggregated_column(b)
    _ => false
  }
}

///|
fn same_expr(a : Expr, b : Expr) -> Bool {
  match (a, b) {
    (EPredicate(a), EPredicate(b)) => same_condition(a, b)
    (ECol(a), ECol(b)) | (EStr(a), EStr(b)) => a == b
    (EValue(a), EValue(b)) => a.to_json() == b.to_json()
    (ENum(a), ENum(b)) => a.to_string() == b.to_string()
    (EDate(a), EDate(b)) => a.to_string() == b.to_string()
    (EBool(a), EBool(b)) => a == b
    (ENull, ENull) | (EStar, EStar) => true
    (EBinary(a, op, b), EBinary(c, other, d)) =>
      op == other && same_expr(a, c) && same_expr(b, d)
    (ECall(name, args), ECall(other, values)) =>
      name == other &&
      args.length() == values.length() &&
      args.iter().zip(values.iter()).all(fn(pair) { same_expr(pair.0, pair.1) })
    _ => false
  }
}

///|
fn unaggregated_condition(cond : Cond) -> Bool {
  match cond {
    CTrue => false
    CNot(c) => unaggregated_condition(c)
    CAnd(a, b) | COr(a, b) =>
      unaggregated_condition(a) || unaggregated_condition(b)
    CCmp(a, _, b) => unaggregated_column(a) || unaggregated_column(b)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => unaggregated_column(e)
  }
}

///|
fn parse_print(parser : QueryParser) -> ParsedQuery {
  let mut filter = CTrue
  let mut period = SrcDirectives("entries")
  if parser.match_keyword("from") {
    if !(parser.peek() is BWord(word) &&
      ["open", "close", "clear"].contains(word.to_lower())) {
      filter = match parse_cond_or(parser) {
        Some(c) => c
        None => return PqError(parser.error.unwrap_or("invalid PRINT filter"))
      }
    }
    if parser.peek() is BWord(word) &&
      ["open", "close", "clear"].contains(word.to_lower()) {
      period = match parse_source(parser) {
        Some(s) => s
        None => {
          let error = parser.error.unwrap_or("invalid PRINT period")
          return PqError(
            if error == "OPEN ON requires a date after 0001-01-01" {
              "query.oracle_type_error: OverflowError date value out of range"
            } else {
              error
            },
          )
        }
      }
    }
  }
  if !parser.at_end() {
    return PqError("unexpected input after PRINT")
  }
  let errors : Array[String] = []
  if !aggregate_free_cond(filter) {
    return PqError("compilation query.invalid_aggregate: FROM clause")
  }
  filter = resolve_quoted_condition(filter, SrcDirectives("entries"))
  projection_condition_types(filter, SrcDirectives("entries"), errors)
  if !errors.is_empty() {
    return PqError(errors[0])
  }
  PqPrint(filter, period)
}

///|
fn parse_source(parser : QueryParser) -> QuerySource? {
  if parser.peek_sym() == Some("#") ||
    parser.peek_sym() == Some("(") ||
    (
      parser.peek() is BWord(word) &&
      [
        "postings", "transactions", "balances", "entries", "commodities", "documents",
        "events", "notes", "prices",
      ].contains(word.to_lower())
    ) {
    return parse_source_base(parser)
  }
  let mut filter = CTrue
  if !(parser.peek() is BWord(word) &&
    ["open", "close", "clear"].contains(word.to_lower())) {
    filter = match parse_cond_or(parser) {
      Some(c) => c
      None => return None
    }
  }
  let mut start = None
  let mut end = None
  let mut close_all = false
  if parser.match_keyword("open") {
    if !parser.expect_keyword("on") {
      return None
    }
    start = match parser.advance() {
      BDate(d) => {
        if ordinal(d) == 1 {
          parser.fail(
            "query.oracle_type_error: OverflowError opening date out of range",
          )
          return None
        }
        Some(d)
      }
      _ => {
        parser.fail("OPEN ON requires a date")
        return None
      }
    }
  }
  if parser.match_keyword("close") {
    if parser.match_keyword("on") {
      end = match parser.advance() {
        BDate(d) => Some(d)
        _ => {
          parser.fail("CLOSE ON requires a date")
          return None
        }
      }
    } else {
      close_all = true
    }
  }
  let clear = parser.match_keyword("clear")
  let errors : Array[String] = []
  filter = resolve_quoted_condition(filter, SrcPostings)
  projection_condition_types(filter, SrcPostings, errors)
  if !aggregate_free_cond(filter) {
    errors.push("compilation query.invalid_aggregate: FROM clause")
  }
  if !errors.is_empty() {
    parser.fail(errors[0])
    return None
  }
  Some(SrcFrom(filter, start, end, close_all, clear))
}

///|
fn parse_journal(parser : QueryParser) -> ParsedQuery {
  if parser.peek() is BWord(word) &&
    !["at", "from"].contains(word.to_lower()) &&
    word.to_lower() != "limit" {
    return parse_legacy_journal(parser)
  }
  if parser.peek() is BStr(_) &&
    parser.tokens.get(parser.index + 1) is Some(BWord(word)) &&
    word.to_lower() == "limit" {
    return parse_legacy_journal(parser)
  }
  let account = match parser.peek() {
    BStr(pattern) => {
      parser.advance() |> ignore
      Some(pattern)
    }
    _ => None
  }
  let mut mode = ""
  if parser.match_keyword("at") {
    mode = match parser.take_word() {
      Some(s) => s
      None => return PqError("expected valuation function")
    }
  }
  let source = if parser.match_keyword("from") {
    match parse_source(parser) {
      Some(s) => s
      None => return PqError(parser.error.unwrap_or("invalid FROM clause"))
    }
  } else {
    SrcPostings
  }
  if !parser.at_end() {
    return PqError("unexpected input after JOURNAL")
  }
  let filter = match account {
    Some(pattern) => {
      let regex = @string.Regex("(?i:" + pattern + ")") catch {
        _ =>
          return PqError(
            "query.oracle_type_error: PatternError invalid journal regex",
          )
      }
      CRegex(ECol("account"), pattern, regex)
    }
    None => CTrue
  }
  let valuation = fn(column : String) {
    if mode == "" {
      ECol(column)
    } else {
      ECall(mode.to_lower(), [ECol(column)])
    }
  }
  let projections = [
    ECol("date"),
    ECol("flag"),
    ECall("maxwidth", [ECol("payee"), ENum(@decimal.Decimal::from_int(48))]),
    ECall("maxwidth", [ECol("narration"), ENum(@decimal.Decimal::from_int(80))]),
    ECol("account"),
    valuation("position"),
    valuation("balance"),
  ]
  let errors : Array[String] = []
  for expr in projections {
    expression_type(expr, source, errors) |> ignore
  }
  if !errors.is_empty() {
    return PqError(errors[0])
  }
  let labels = [
    "date",
    "flag",
    "MAXWIDTH(payee, 48)",
    "MAXWIDTH(narration, 80)",
    "account",
    if mode == "" {
      "position"
    } else {
      mode + "(position)"
    },
    if mode == "" {
      "balance"
    } else {
      mode + "(balance)"
    },
  ]
  PqSelect({
    projections,
    names: labels,
    labels,
    source,
    filter,
    groups: [],
    orders: [],
    limit: None,
    having: CTrue,
    distinct: false,
    pivot: None,
  })
}
