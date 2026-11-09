// JSON export of a validated ledger.  The shape is intentionally stable and
// flat so that other tools can diff it against bean-query output.

///|
fn jstr(text : String) -> String {
  "\"" + @realization.json_escape(text) + "\""
}

///|
fn jopt(text : String?) -> String {
  match text {
    Some(value) => jstr(value)
    None => "null"
  }
}

///|
fn jnum(number : @decimal.Decimal) -> String {
  jstr(number.to_string())
}

///|
fn jdate(date : @ast.Date) -> String {
  jstr(date.to_string())
}

///|
fn jamount(amount : @ast.Amount) -> String {
  "{\"number\":" +
  jnum(amount.number) +
  ",\"currency\":" +
  jstr(amount.currency) +
  "}"
}

///|
fn jmeta(meta : @ast.Meta) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  for i in 0..<meta.entries.length() {
    if i > 0 {
      sb.write_string(",")
    }
    let (key, value) = meta.entries[i]
    sb.write_string(jstr(key))
    sb.write_string(":")
    sb.write_string(
      match value {
        @ast.MString(text) => jstr(text)
        @ast.MNumber(number) => jnum(number)
        @ast.MDate(date) => jdate(date)
        @ast.MAccount(account) => jstr(account)
        @ast.MCurrency(currency) => jstr(currency)
        @ast.MTag(tag) => jstr(tag)
        @ast.MBool(flag) => if flag { "true" } else { "false" }
      },
    )
  }
  sb.write_string("}")
  sb.to_string()
}

///|
fn jloc(loc : @ast.Loc) -> String {
  "{\"file\":" + jstr(loc.file) + ",\"line\":" + loc.line.to_string() + "}"
}

///|
fn jstring_array(values : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<values.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(jstr(values[i]))
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn jcost(spec : @ast.CostSpec) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  sb.write_string("\"per\":")
  sb.write_string(
    match spec.number_per {
      Some(number) => jnum(number)
      None => "null"
    },
  )
  sb.write_string(",\"total\":")
  sb.write_string(
    match spec.number_total {
      Some(number) => jnum(number)
      None => "null"
    },
  )
  sb.write_string(",\"currency\":")
  sb.write_string(jopt(spec.currency))
  sb.write_string(",\"date\":")
  sb.write_string(
    match spec.date {
      Some(date) => jdate(date)
      None => "null"
    },
  )
  sb.write_string(",\"label\":")
  sb.write_string(jopt(spec.label))
  sb.write_string(",\"merge\":")
  sb.write_string(if spec.merge { "true" } else { "false" })
  sb.write_string("}")
  sb.to_string()
}

///|
fn jprice(price : @ast.PriceAnno) -> String {
  let amount = price.amount()
  let total = match price {
    @ast.PerUnit(_) => false
    @ast.Total(_) => true
  }
  "{\"number\":" +
  jnum(amount.number) +
  ",\"currency\":" +
  jstr(amount.currency) +
  ",\"total\":" +
  (if total { "true" } else { "false" }) +
  "}"
}

///|
fn jposting(posting : @ast.Posting) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  sb.write_string("\"flag\":")
  sb.write_string(jopt(posting.flag))
  sb.write_string(",\"account\":")
  sb.write_string(jstr(posting.account))
  sb.write_string(",\"units\":")
  sb.write_string(
    match posting.units {
      Some(units) => jamount(units)
      None => "null"
    },
  )
  sb.write_string(",\"cost\":")
  sb.write_string(
    match posting.cost {
      Some(spec) => jcost(spec)
      None => "null"
    },
  )
  sb.write_string(",\"price\":")
  sb.write_string(
    match posting.price {
      Some(price) => jprice(price)
      None => "null"
    },
  )
  sb.write_string(",\"meta\":")
  sb.write_string(jmeta(posting.meta))
  sb.write_string("}")
  sb.to_string()
}

///|
fn jpostings(postings : Array[@ast.Posting]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<postings.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(jposting(postings[i]))
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn jcustom_value(value : @ast.CustomValue) -> String {
  match value {
    @ast.CString(text) => "{\"kind\":\"string\",\"value\":" + jstr(text) + "}"
    @ast.CBool(flag) =>
      "{\"kind\":\"bool\",\"value\":" +
      (if flag { "true" } else { "false" }) +
      "}"
    @ast.CDate(date) => "{\"kind\":\"date\",\"value\":" + jdate(date) + "}"
    @ast.CNumber(number) =>
      "{\"kind\":\"number\",\"value\":" + jnum(number) + "}"
    @ast.CAmount(amount) =>
      "{\"kind\":\"amount\",\"value\":" + jamount(amount) + "}"
    @ast.CAccount(account) =>
      "{\"kind\":\"account\",\"value\":" + jstr(account) + "}"
    @ast.CCurrency(currency) =>
      "{\"kind\":\"currency\",\"value\":" + jstr(currency) + "}"
    @ast.CTag(tag) => "{\"kind\":\"tag\",\"value\":" + jstr(tag) + "}"
  }
}

///|
fn jcustom(custom : @ast.Custom) -> String {
  let sb = StringBuilder()
  sb.write_string("{\"type\":\"custom\",\"custom_type\":")
  sb.write_string(jstr(custom.custom_type))
  sb.write_string(",\"values\":[")
  for i in 0..<custom.values.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(jcustom_value(custom.values[i]))
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn jdirective(entry : @ast.Entry) -> String {
  match entry.directive {
    @ast.DOpen(open) =>
      "{\"type\":\"open\",\"account\":" +
      jstr(open.account) +
      ",\"currencies\":" +
      jstring_array(open.currencies) +
      ",\"booking\":" +
      jopt(open.booking) +
      "}"
    @ast.DClose(close) =>
      "{\"type\":\"close\",\"account\":" + jstr(close.account) + "}"
    @ast.DCommodity(commodity) =>
      "{\"type\":\"commodity\",\"currency\":" + jstr(commodity.currency) + "}"
    @ast.DPad(pad) =>
      "{\"type\":\"pad\",\"account\":" +
      jstr(pad.account) +
      ",\"source\":" +
      jstr(pad.source_account) +
      "}"
    @ast.DBalance(balance) =>
      "{\"type\":\"balance\",\"account\":" +
      jstr(balance.account) +
      ",\"amount\":" +
      jamount(balance.amount) +
      ",\"tolerance\":" +
      (match balance.tolerance {
        Some(tolerance) => jnum(tolerance)
        None => "null"
      }) +
      "}"
    @ast.DPrice(price) =>
      "{\"type\":\"price\",\"currency\":" +
      jstr(price.currency) +
      ",\"amount\":" +
      jamount(price.amount) +
      "}"
    @ast.DEvent(event) =>
      "{\"type\":\"event\",\"event_type\":" +
      jstr(event.event_type) +
      ",\"description\":" +
      jstr(event.description) +
      "}"
    @ast.DQuery(query) =>
      "{\"type\":\"query\",\"name\":" +
      jstr(query.name) +
      ",\"query\":" +
      jstr(query.query) +
      "}"
    @ast.DCustom(custom) => jcustom(custom)
    @ast.DNote(note) =>
      "{\"type\":\"note\",\"account\":" +
      jstr(note.account) +
      ",\"comment\":" +
      jstr(note.comment) +
      ",\"tags\":" +
      jstring_array(note.tags) +
      ",\"links\":" +
      jstring_array(note.links) +
      "}"
    @ast.DDocument(document) =>
      "{\"type\":\"document\",\"account\":" +
      jstr(document.account) +
      ",\"filename\":" +
      jstr(document.filename) +
      ",\"tags\":" +
      jstring_array(document.tags) +
      ",\"links\":" +
      jstring_array(document.links) +
      "}"
    @ast.DTransaction(txn) =>
      "{\"type\":\"transaction\",\"flag\":" +
      jstr(txn.flag) +
      ",\"payee\":" +
      jopt(txn.payee) +
      ",\"narration\":" +
      jstr(txn.narration) +
      ",\"tags\":" +
      jstring_array(txn.tags) +
      ",\"links\":" +
      jstring_array(txn.links) +
      ",\"postings\":" +
      jpostings(txn.postings) +
      "}"
  }
}

///|
fn jentry(entry : @ast.Entry) -> String {
  let directive = jdirective(entry)
  let prefix = "{\"date\":" +
    jdate(entry.date) +
    ",\"loc\":" +
    jloc(entry.loc) +
    ",\"meta\":" +
    jmeta(entry.meta) +
    ","
  prefix + lib_view(directive[1:])
}

///|
fn jdiagnostic(diagnostic : @ast.Diagnostic) -> String {
  "{\"file\":" +
  jstr(diagnostic.loc.file) +
  ",\"line\":" +
  diagnostic.loc.line.to_string() +
  ",\"code\":" +
  jstr(diagnostic.code) +
  ",\"message\":" +
  jstr(diagnostic.message) +
  "}"
}

///|
fn jdiagnostics(diagnostics : Array[@ast.Diagnostic]) -> String {
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<diagnostics.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(jdiagnostic(diagnostics[i]))
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn jaccount(info : @validation.AccountInfo) -> String {
  "{\"account\":" +
  jstr(info.account) +
  ",\"open\":" +
  jdate(info.open_date) +
  ",\"close\":" +
  (match info.close_date {
    Some(date) => jdate(date)
    None => "null"
  }) +
  ",\"currencies\":" +
  jstring_array(info.currencies) +
  ",\"booking\":" +
  jopt(info.booking) +
  ",\"loc\":" +
  jloc(info.loc) +
  "}"
}

///|
fn jaccounts(ledger : @validation.ValidatedLedger) -> String {
  let names = ledger.account_names()
  let sb = StringBuilder()
  sb.write_string("[")
  for i in 0..<names.length() {
    if i > 0 {
      sb.write_string(",")
    }
    match ledger.account_info(names[i]) {
      Some(info) => sb.write_string(jaccount(info))
      None => ()
    }
  }
  sb.write_string("]")
  sb.to_string()
}

///|
/// Serializes a validated ledger to JSON.  Amounts are emitted as strings so
/// that exact decimal values survive the round trip.
pub fn export_json(
  file : String,
  ledger : @validation.ValidatedLedger,
) -> String {
  let sb = StringBuilder()
  sb.write_string("{\"file\":")
  sb.write_string(jstr(file))
  sb.write_string(",\"errors\":")
  sb.write_string(jdiagnostics(ledger.errors))
  sb.write_string(",\"warnings\":")
  sb.write_string(jdiagnostics(ledger.warnings))
  sb.write_string(",\"accounts\":")
  sb.write_string(jaccounts(ledger))
  sb.write_string(",\"entries\":[")
  for i in 0..<ledger.entries.length() {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(jentry(ledger.entries[i]))
  }
  sb.write_string("]}")
  sb.to_string()
}
