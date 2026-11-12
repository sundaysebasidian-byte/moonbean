///|
priv struct QueryContext {
  source : QuerySource
  realized : @realization.RealizedLedger
  mut aggregate_row : BqlRow?
  mut error : String?
  running : @booking.Inventory
  mut opens : Map[String, @ast.Entry]?
  mut closes : Map[String, @ast.Entry]?
  mut prices : Map[String, Array[(@ast.Date, @decimal.Decimal)]]?
}

///|
fn QueryContext::new(
  realized : @realization.RealizedLedger,
  source : QuerySource,
) -> QueryContext {
  {
    source,
    realized,
    aggregate_row: None,
    error: None,
    running: @booking.Inventory::new(),
    opens: None,
    closes: None,
    prices: None,
  }
}

///|
fn ensure_account_index(ctx : QueryContext) -> Unit {
  if ctx.opens is Some(_) {
    return
  }
  let opens : Map[String, @ast.Entry] = Map([])
  let closes : Map[String, @ast.Entry] = Map([])
  for entry in ctx.realized.entries {
    match entry.directive {
      DOpen(o) => opens.set(o.account, entry)
      DClose(c) => closes.set(c.account, entry)
      _ => ()
    }
  }
  ctx.opens = Some(opens)
  ctx.closes = Some(closes)
}

///|
fn entry_metadata(entry : @ast.Entry) -> QueryValue {
  let fields = source_metadata(query_location(entry), entry.meta)
  if entry.inferred_tolerances is Some(values) {
    fields.push(
      ("__tolerances__", QDict(values.map(fn(p) { (p.0, QNumber(p.1)) }))),
    )
  }
  QDict(fields)
}

///|
fn directive_value(entry : @ast.Entry) -> QueryValue {
  let fields : Array[(String, QueryValue)] = [
    ("meta", entry_metadata(entry)),
    ("date", QDate(entry.date)),
  ]
  let name = match entry.directive {
    DOpen(o) => {
      fields.append([
        ("account", QText(o.account)),
        (
          "currencies",
          if o.currencies.is_empty() {
            QNull
          } else {
            QList(o.currencies.map(fn(s) { QText(s) }))
          },
        ),
        (
          "booking",
          match o.booking {
            Some(b) => QEnum("Booking", b)
            None => QNull
          },
        ),
      ])
      "Open"
    }
    DClose(c) => {
      fields.push(("account", QText(c.account)))
      "Close"
    }
    DCommodity(c) => {
      fields.push(("currency", QText(c.currency)))
      "Commodity"
    }
    DEvent(e) => {
      fields.append([
        ("type", QText(e.event_type)),
        ("description", QText(e.description)),
      ])
      "Event"
    }
    DPrice(p) => {
      fields.append([
        ("currency", QText(p.currency)),
        ("amount", QAmount(p.amount)),
      ])
      "Price"
    }
    DNote(n) => {
      fields.append([
        ("account", QText(n.account)),
        ("comment", QText(n.comment)),
        ("tags", QFrozenSet(n.tags)),
        ("links", QFrozenSet(n.links)),
      ])
      "Note"
    }
    DDocument(d) => {
      fields.append([
        ("account", QText(d.account)),
        ("filename", QText(document_filename(entry, d))),
        ("tags", QFrozenSet(d.tags)),
        ("links", QFrozenSet(d.links)),
      ])
      "Document"
    }
    DPad(p) => {
      fields.append([
        ("account", QText(p.account)),
        ("source_account", QText(p.source_account)),
      ])
      "Pad"
    }
    DBalance(b) => {
      fields.append([
        ("account", QText(b.account)),
        ("amount", QAmount(b.amount)),
        (
          "tolerance",
          match b.tolerance {
            Some(n) => QNumber(n)
            None => QNull
          },
        ),
        (
          "diff_amount",
          match entry.balance_discrepancy {
            Some(a) => QAmount(a)
            None => QNull
          },
        ),
      ])
      "Balance"
    }
    DQuery(q) => {
      fields.append([("name", QText(q.name)), ("query_string", QText(q.query))])
      "Query"
    }
    DTransaction(t) => {
      fields.append([
        ("flag", QText(t.flag)),
        (
          "payee",
          match t.payee {
            Some(s) => QText(s)
            None => QNull
          },
        ),
        ("narration", QText(t.narration)),
        ("tags", QFrozenSet(t.tags)),
        ("links", QFrozenSet(t.links)),
        (
          "postings",
          QList(booked_postings(t.postings).map(posting_value_record)),
        ),
      ])
      "Transaction"
    }
    DCustom(c) => {
      fields.append([
        ("type", QText(c.custom_type)),
        ("values", QList(c.values.map(custom_value_record))),
      ])
      "Custom"
    }
  }
  QRecord(name, fields)
}

///|
fn posting_price(p : @ast.Posting) -> QueryValue {
  match p.price {
    Some(PerUnit(a)) => QAmount(a)
    Some(Total(a)) =>
      match p.units {
        Some(u) =>
          if u.number.is_zero() {
            QAmount(@ast.Amount::new(@decimal.Decimal::zero(), a.currency))
          } else {
            match a.number.div(u.number.abs()) {
              Some(n) => QAmount(@ast.Amount::new(n, a.currency))
              None => QNull
            }
          }
        None => QNull
      }
    None => QNull
  }
}

///|
fn posting_value_record(p : @ast.Posting) -> QueryValue {
  let cost = match (p.cost, p.units) {
    (Some(_), Some(units)) =>
      match posting_cost(p, units) {
        Some(c) =>
          QRecord("Cost", [
            ("number", QNumber(c.number)),
            ("currency", QText(c.currency)),
            (
              "date",
              match c.date {
                Some(d) => QDate(d)
                None => QNull
              },
            ),
            (
              "label",
              match c.label {
                Some(s) => QText(s)
                None => QNull
              },
            ),
          ])
        None => QNull
      }
    _ => QNull
  }
  QRecord("Posting", [
    ("account", QText(p.account)),
    (
      "units",
      match p.units {
        Some(a) => QAmount(a)
        None => QNull
      },
    ),
    ("cost", cost),
    ("price", posting_price(p)),
    (
      "flag",
      match p.flag {
        Some(s) => QText(s)
        None => QNull
      },
    ),
    ("meta", posting_metadata(p)),
  ])
}

///|
fn custom_value_record(value : @ast.CustomValue) -> QueryValue {
  let (v, t) = match value {
    CString(s) | CCurrency(s) | CTag(s) => (QText(s), QPythonType("str"))
    CAccount(s) => (QText(s), QText("<AccountDummy>"))
    CNumber(n) => (QNumber(n), QPythonType("decimal.Decimal"))
    CBool(b) => (QBool(b), QPythonType("bool"))
    CDate(d) => (QDate(d), QPythonType("datetime.date"))
    CAmount(a) => (QAmount(a), QPythonType("beancount.core.amount.Amount"))
  }
  QRecord("ValueType", [("value", v), ("dtype", t)])
}

///|
fn hash_scalar(value : QueryValue) -> String {
  match value {
    QNull => "None"
    QBool(b) => if b { "True" } else { "False" }
    QDict(_) | QRecord(_, _) | QList(_) => python_repr(value)
    _ => value.to_text()
  }
}

///|
fn directive_identity(value : QueryValue) -> String {
  match value {
    QRecord(_, fields) => {
      let out = StringBuilder()
      for (_, field) in fields {
        match field {
          QList(values) => {
            let hashes = values.map(fn(v) {
              match v {
                QRecord(_, _) => directive_identity(v)
                _ => query_md5(hash_scalar(v))
              }
            })
            hashes.sort_by(fn(a, b) { a.lexical_compare(b) })
            out.write_string(hashes.join(""))
          }
          QSet(values) | QFrozenSet(values) => {
            let hashes = values.map(fn(v) { query_md5(v) })
            hashes.sort_by(fn(a, b) { a.lexical_compare(b) })
            out.write_string(hashes.join(""))
          }
          _ => out.write_string(hash_scalar(field))
        }
      }
      query_md5(out.to_string())
    }
    _ => query_md5(hash_scalar(value))
  }
}

///|
fn document_filename(entry : @ast.Entry, document : @ast.Document) -> String {
  let file = @path.Path(document.filename)
  if file.is_absolute() {
    file.normalize().to_string()
  } else {
    @path.Path(entry.loc.file).dirname().join(file).normalize().to_string()
  }
}

///|
fn query_error(ctx : QueryContext, message : String) -> Unit {
  if ctx.error is None {
    ctx.error = Some(message)
  }
}

///|
fn running_balance(ctx : QueryContext, row : BqlRow) -> QueryValue {
  if row.extra is Some(extra) && extra.running is Some(inventory) {
    return QInventory(inventory)
  }
  ctx.running.add(row.position)
  let snapshot = ctx.running.copy()
  let extra = match row.extra {
    Some(extra) => extra
    None => {
      let extra = new_row_extra(None, None, None)
      row.extra = Some(extra)
      extra
    }
  }
  extra.running = Some(snapshot)
  QInventory(snapshot)
}

///|
fn origin_expr(expr : Expr) -> Bool {
  match expr {
    ECol(
      "entry"
      | "id"
      | "meta"
      | "filename"
      | "lineno"
      | "location"
      | "posting_flag"
      | "price"
    ) => true
    ECall("meta" | "entry_meta" | "any_meta", _) => true
    _ => false
  }
}

///|
fn expr_any(expr : Expr, predicate : (Expr) -> Bool) -> Bool {
  if predicate(expr) {
    return true
  }
  match expr {
    EPredicate(c) => cond_any(c, predicate)
    ECall(_, args) => args.any(fn(e) { expr_any(e, predicate) })
    EBinary(a, _, b) => expr_any(a, predicate) || expr_any(b, predicate)
    _ => false
  }
}

///|
fn cond_any(cond : Cond, predicate : (Expr) -> Bool) -> Bool {
  match cond {
    CTrue => false
    CNot(c) => cond_any(c, predicate)
    CAnd(a, b) | COr(a, b) => cond_any(a, predicate) || cond_any(b, predicate)
    CCmp(a, _, b) => expr_any(a, predicate) || expr_any(b, predicate)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _) => expr_any(e, predicate)
  }
}

///|
fn query_any(query : SelectQuery, predicate : (Expr) -> Bool) -> Bool {
  query.projections.any(fn(e) { expr_any(e, predicate) }) ||
  query.groups.any(fn(e) { expr_any(e, predicate) }) ||
  query.orders.any(fn(o) { expr_any(o.expr, predicate) }) ||
  cond_any(query.filter, predicate) ||
  cond_any(query.having, predicate)
}

///|
fn query_location(entry : @ast.Entry) -> @ast.Loc {
  entry.query_origin.unwrap_or(entry.loc)
}

///|
fn dict_get(value : QueryValue, key : String) -> QueryValue? {
  match value {
    QDict(fields) => {
      for (name, v) in fields {
        if name == key {
          return Some(v)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn record_metadata(ctx : QueryContext, value : QueryValue) -> QueryValue {
  if value is QRecord(_, fields) {
    for (name, field) in fields {
      if name == "meta" {
        return field
      }
    }
  }
  query_error(ctx, "query.oracle_type_error: AttributeError directive metadata")
  QNull
}

///|
fn representation_expr(expr : Expr) -> Bool {
  match expr {
    ECol("id" | "meta" | "entry" | "open" | "close") => true
    ECall(
      "str"
      | "repr"
      | "meta"
      | "entry_meta"
      | "any_meta"
      | "open_meta"
      | "commodity_meta"
      | "currency_meta",
      _
    ) => true
    _ => false
  }
}

///|
fn structural_value(value : QueryValue) -> Bool {
  match value {
    QDict(_) | QRecord(_, _) | QList(_) | QEnum(_, _) | QPythonType(_) => true
    _ => false
  }
}

///|
fn typed_compare(ctx : QueryContext, a : QueryValue, b : QueryValue) -> Int32? {
  if a is QText(a) && b is QText(b) {
    return Some(python_text_compare(a, b))
  }
  let sequence = match (a, b) {
    (QList(a), QList(b)) => Some((a, b))
    (QRecord(_, a), QRecord(_, b)) =>
      Some((a.map(fn(p) { p.1 }), b.map(fn(p) { p.1 })))
    _ => None
  }
  if sequence is Some((a, b)) {
    for i in 0..<a.length().min(b.length()) {
      if !membership_equal(a[i], b[i]) {
        if a[i] is QNull || b[i] is QNull {
          query_error(ctx, "query.oracle_type_error: TypeError None ordering")
          return None
        }
        return typed_compare(ctx, a[i], b[i])
      }
    }
    return Some(a.length().compare(b.length()))
  }
  if !(a is QNull) &&
    !(b is QNull) &&
    (structural_value(a) || structural_value(b)) {
    query_error(
      ctx, "query.oracle_type_error: TypeError structural object ordering",
    )
    None
  } else {
    value_compare(a, b)
  }
}

///|
priv struct RowExtra {
  entry : @ast.Entry?
  source : String?
  posting : @ast.Posting?
  mut running : @booking.Inventory?
  mut cells : Map[String, QueryValue]?
}

///|
fn new_row_extra(
  entry : @ast.Entry?,
  source : String?,
  posting : @ast.Posting?,
) -> RowExtra {
  { entry, source, posting, running: None, cells: None, }
}

///|
fn row_entry(row : BqlRow) -> @ast.Entry? {
  match row.extra {
    Some(extra) => extra.entry
    None => None
  }
}

///|
fn row_posting(row : BqlRow) -> @ast.Posting? {
  match row.extra {
    Some(extra) => extra.posting
    None => None
  }
}

///|
fn posting_metadata(posting : @ast.Posting) -> QueryValue {
  if posting.loc.file == "" && posting.loc.line == 0 && posting.meta.is_empty() {
    QNull
  } else {
    QDict(source_metadata(posting.loc, posting.meta))
  }
}

///|
fn booked_postings(postings : Array[@ast.Posting]) -> Array[@ast.Posting] {
  if postings.length() < 3 {
    return postings
  }
  let currency = fn(p : @ast.Posting) {
    if p.units is Some(a) {
      if posting_cost(p, a) is Some(c) {
        c.currency
      } else if posting_price(p) is QAmount(price) {
        price.currency
      } else {
        a.currency
      }
    } else {
      ""
    }
  }
  let currencies : Array[String] = []
  for p in postings {
    let c = currency(p)
    if !currencies.contains(c) {
      currencies.push(c)
    }
  }
  if currencies.length() < 2 {
    return postings
  }
  let result = postings.copy()
  result
  .mut_view()
  .stable_sort_by(fn(a, b) {
    currencies
    .search(currency(a))
    .unwrap()
    .compare(currencies.search(currency(b)).unwrap())
  })
  result
}

///|
fn constant_query_error(expr : Expr) -> String? {
  let pure = [
    "abs", "bool", "coalesce", "date", "date_add", "date_bin", "date_diff", "date_part",
    "date_trunc", "day", "decimal", "empty", "findfirst", "filter_currency", "getitem",
    "grep", "grepn", "int", "interval", "joinstr", "leaf", "length", "lower", "maxwidth",
    "month", "neg", "number", "parent", "parse_date", "quarter", "repr", "root",
    "round", "safediv", "splitcomp", "str", "subst", "substr", "today", "upper",
    "weekday", "year", "yearmonth",
  ]
  if expr_any(expr, fn(e) {
      match e {
        ECol(_) | EStar => true
        ECall(name, _) => !pure.contains(name)
        _ => false
      }
    }) ||
    !expr_any(expr, fn(e) { e is ECall(_, _) || e is EBinary(_, _, _) }) {
    return None
  }
  let errors : Array[String] = []
  expression_type(expr, SrcPostings, errors) |> ignore
  if !errors.is_empty() {
    return None
  }
  let ledger : @realization.RealizedLedger = {
    entries: [],
    at: None,
    options: @ast.Options::new(),
    inventories: Map([]),
    accounts: Map([]),
    prices: @realization.PriceDb::new(),
  }
  let ctx = QueryContext::new(ledger, SrcPostings)
  eval_expr(ctx, expr, relation_rows([], [[]])[0]) |> ignore
  ctx.error
}
