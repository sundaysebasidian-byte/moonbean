// JavaScript-facing API for the browser playground.
//
// Every export takes one JSON string and returns one JSON string. Failures are
// reported as `{"ok":false,"error":{"code":...,"message":...}}`; nothing here
// throws. The ledger text is passed as `source`, so the package needs no file
// system access and the generated bundle has no `node:` imports.

///|
priv suberror ApiError {
  ApiError(String, String)
}

///|
fn obj(fields : Array[(String, Json)]) -> Json {
  let m : Map[String, Json] = Map([])
  for pair in fields {
    m[pair.0] = pair.1
  }
  Json::object(m)
}

///|
fn strings_json(values : Array[String]) -> Json {
  let items : Array[Json] = []
  for value in values {
    items.push(Json::string(value))
  }
  Json::array(items)
}

///|
fn int_json(value : Int32) -> Json {
  Json::number(value.to_double())
}

///|
fn fail(code : String, message : String) -> ApiError {
  ApiError(code, message)
}

///|
fn failure_json(
  code : String,
  message : String,
  extra : Array[(String, Json)],
) -> Json {
  let fields : Array[(String, Json)] = [
    ("ok", Json::boolean(false)),
    (
      "error",
      obj([("code", Json::string(code)), ("message", Json::string(message))]),
    ),
  ]
  for field in extra {
    fields.push(field)
  }
  obj(fields)
}

///|
fn ok_with(fields : Array[(String, Json)]) -> Json {
  let all : Array[(String, Json)] = [("ok", Json::boolean(true))]
  for field in fields {
    all.push(field)
  }
  obj(all)
}

///|
fn respond(body : () -> Json raise Error) -> String {
  let result = body() catch {
    ApiError(code, message) => failure_json(code, message, [])
    InvalidLedger(diagnostics) =>
      failure_json(
        "ledger_invalid",
        diagnostics.length().to_string() + " errors in the ledger",
        [("errors", diagnostics_json(diagnostics))],
      )
    _ => failure_json("internal", "unexpected error", [])
  }
  result.stringify()
}

///|
priv suberror LedgerError {
  InvalidLedger(Array[@ast.Diagnostic])
}

///|
fn parse_request(text : String) -> Map[String, Json] raise Error {
  let parsed = @json.parse(text) catch {
    _ => raise fail("bad_request", "request is not valid JSON")
  }
  match parsed {
    Object(m) => m
    _ => raise fail("bad_request", "request must be a JSON object")
  }
}

///|
fn string_field(req : Map[String, Json], name : String) -> String raise Error {
  match req.get(name) {
    Some(String(s)) => s
    _ => raise fail("bad_request", "missing string field '" + name + "'")
  }
}

///|
fn opt_string_field(
  req : Map[String, Json],
  name : String,
) -> String? raise Error {
  match req.get(name) {
    None | Some(Null) => None
    Some(String(s)) => if s == "" { None } else { Some(s) }
    _ => raise fail("bad_request", "field '" + name + "' must be a string")
  }
}

///|
fn bool_field(req : Map[String, Json], name : String) -> Bool {
  match req.get(name) {
    Some(True) => true
    _ => false
  }
}

///|
fn date_field(req : Map[String, Json], name : String) -> @ast.Date? raise Error {
  match opt_string_field(req, name) {
    None => None
    Some(text) =>
      match @ast.Date::parse(text) {
        Some(date) => Some(date)
        None =>
          raise fail(
            "bad_request",
            "field '" + name + "' is not a YYYY-MM-DD date",
          )
      }
  }
}

///|
fn diagnostic_json(diagnostic : @ast.Diagnostic) -> Json {
  obj([
    ("line", int_json(diagnostic.loc.line)),
    ("code", Json::string(diagnostic.code)),
    ("message", Json::string(diagnostic.message)),
  ])
}

///|
fn diagnostics_json(diagnostics : Array[@ast.Diagnostic]) -> Json {
  let items : Array[Json] = []
  for diagnostic in diagnostics {
    items.push(diagnostic_json(diagnostic))
  }
  Json::array(items)
}

///|
fn lines_of(source : String) -> Array[String] {
  let lines : Array[String] = []
  for view in source.split("\n") {
    lines.push(String::from_iter(view.iter()))
  }
  lines
}

///|
/// `include` needs a file system. In the browser each include is kept as a
/// warning on its own line instead of being silently ignored.
fn include_warnings(source : String) -> Array[Json] {
  let items : Array[Json] = []
  let lines = lines_of(source)
  for i in 0..<lines.length() {
    match @moonbean.include_target(lines[i]) {
      Some(path) =>
        items.push(
          obj([
            ("line", int_json(i + 1)),
            ("code", Json::string("include.unavailable")),
            (
              "message",
              Json::string(
                "include \"" +
                path +
                "\" is not loaded; the playground reads one text only",
              ),
            ),
          ]),
        )
      None => ()
    }
  }
  items
}

///|
fn load_ledger(
  req : Map[String, Json],
) -> @validation.ValidatedLedger raise Error {
  let source = string_field(req, "source")
  @moonbean.check_source("ledger.beancount", source)
}

///|
fn load_valid_ledger(
  req : Map[String, Json],
) -> @validation.ValidatedLedger raise Error {
  let ledger = load_ledger(req)
  if ledger.has_errors() {
    raise InvalidLedger(ledger.errors)
  }
  ledger
}

///|
fn parse_embedded(text : String) -> Json raise Error {
  @json.parse(text) catch {
    _ => raise fail("internal", "engine produced invalid JSON")
  }
}

///|
fn convert_field(
  req : Map[String, Json],
  ledger : @validation.ValidatedLedger,
) -> String? raise Error {
  // An absent field falls back to the single operating currency, exactly like
  // the CLI; an explicit empty string keeps the original currencies.
  match req.get("convert") {
    Some(String(s)) => if s == "" { None } else { Some(s) }
    Some(Null) | None =>
      if ledger.options.operating_currencies.length() == 1 {
        Some(ledger.options.operating_currencies[0])
      } else {
        None
      }
    _ => raise fail("bad_request", "field 'convert' must be a string")
  }
}

///|
fn ledger_meta(
  ledger : @validation.ValidatedLedger,
  convert : String?,
) -> Array[(String, Json)] {
  [
    ("operating_currencies", strings_json(ledger.options.operating_currencies)),
    (
      "convert",
      match convert {
        Some(currency) => Json::string(currency)
        None => Json::null()
      },
    ),
  ]
}

///|
/// Request: `{"source": "<ledger text>"}`.
/// Response: `{"ok":true,"valid":bool,"errors":[{line,code,message}],
/// "warnings":[...],"title":string|null,"operating_currencies":[...],
/// "accounts":[...],"entries":n}`.
pub fn check(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    let source = string_field(req, "source")
    let ledger = @moonbean.check_source("ledger.beancount", source)
    let warnings = diagnostic_items(ledger.warnings)
    for item in include_warnings(source) {
      warnings.push(item)
    }
    ok_with([
      ("valid", Json::boolean(!ledger.has_errors())),
      ("errors", diagnostics_json(ledger.errors)),
      ("warnings", Json::array(warnings)),
      (
        "title",
        match ledger.options.title {
          Some(title) => Json::string(title)
          None => Json::null()
        },
      ),
      (
        "operating_currencies",
        strings_json(ledger.options.operating_currencies),
      ),
      ("accounts", strings_json(ledger.account_names())),
      ("entries", int_json(ledger.entries.length())),
    ])
  })
}

///|
fn diagnostic_items(diagnostics : Array[@ast.Diagnostic]) -> Array[Json] {
  let items : Array[Json] = []
  for diagnostic in diagnostics {
    items.push(diagnostic_json(diagnostic))
  }
  items
}

///|
fn report_response(
  req : Map[String, Json],
  build : (@realization.RealizedLedger, String?) -> @realization.Report,
) -> Json raise Error {
  let ledger = load_valid_ledger(req)
  let convert = convert_field(req, ledger)
  let realized = @moonbean.realize(ledger, at=date_field(req, "at"))
  let report = build(realized, convert)
  let fields = [("report", parse_embedded(report.to_json()))]
  for field in ledger_meta(ledger, convert) {
    fields.push(field)
  }
  ok_with(fields)
}

///|
/// Request: `{"source", "convert"?, "at"?}`. `convert` defaults to the single
/// operating currency; pass `""` to keep original currencies.
/// Response: `{"ok":true,"report":{title,rows,totals},"operating_currencies","convert"}`.
pub fn balance_sheet(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    report_response(req, fn(realized, convert) {
      @realization.balance_sheet(realized, convert~)
    })
  })
}

///|
/// Request: `{"source", "convert"?, "at"?, "start"?}`; `start` limits the
/// period to postings on or after that date.
pub fn income_statement(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    let start = date_field(req, "start")
    report_response(req, fn(realized, convert) {
      @realization.income_statement(realized, start~, convert~)
    })
  })
}

///|
/// Request: `{"source", "convert"?, "at"?}`.
pub fn trial_balance(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    report_response(req, fn(realized, convert) {
      @realization.trial_balance(realized, convert~)
    })
  })
}

///|
/// Request: `{"source", "account", "subtree"?, "at"?}`.
/// Response: `{"ok":true,"rows":[{date,flag,payee,narration,account,amount,running}]}`.
pub fn register(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    let ledger = load_valid_ledger(req)
    let account = string_field(req, "account")
    let realized = @moonbean.realize(ledger, at=date_field(req, "at"))
    let rows = @realization.register_rows(
      realized,
      account,
      subtree=bool_field(req, "subtree"),
    )
    ok_with([("rows", parse_embedded(@realization.register_to_json(rows)))])
  })
}

///|
/// Request: `{"source", "bql", "at"?}`.
/// Response: `{"ok":true,"columns":[...],"rows":[[...]]}`; a query the engine
/// rejects comes back as `{"ok":false,"error":{"code":"query",...}}`.
pub fn query(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    let ledger = load_valid_ledger(req)
    let statement = string_field(req, "bql")
    let result = @moonbean.run_query(
      ledger,
      statement,
      at=date_field(req, "at"),
    )
    match result.error {
      Some(message) => raise fail("query", message)
      None => {
        let parsed = parse_embedded(result.to_json())
        match parsed {
          Object(m) =>
            ok_with([
              ("columns", m.get("columns").unwrap_or(Json::array([]))),
              ("rows", m.get("rows").unwrap_or(Json::array([]))),
            ])
          _ => raise fail("internal", "engine produced invalid JSON")
        }
      }
    }
  })
}

///|
/// Request: `{"source"}`. Response: `{"ok":true,"output":"<aligned text>",
/// "changed":bool}`. Formatting never needs a valid ledger.
pub fn format(request : String) -> String {
  respond(fn() raise Error {
    let req = parse_request(request)
    let source = string_field(req, "source")
    let output = @moonbean.format_source(source)
    ok_with([
      ("output", Json::string(output)),
      ("changed", Json::boolean(output != source)),
    ])
  })
}
