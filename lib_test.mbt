///|
fn facade_ledger() -> String {
  "option \"title\" \"Facade\"\n" +
  "2024-01-01 open Assets:Cash USD\n" +
  "2024-01-01 open Equity:Opening USD\n" +
  "2024-01-02 * \"Opening\"\n" +
  "  Assets:Cash  100 USD\n" +
  "  Equity:Opening  -100 USD\n" +
  "2024-01-03 balance Assets:Cash 100 USD\n"
}

///|
test "path helpers normalize and join" {
  inspect(@moonbean.path_dirname("docs/main.beancount"), content="docs")
  inspect(@moonbean.path_dirname("main.beancount"), content="")
  inspect(@moonbean.path_dirname("/a/b/c"), content="/a/b")
  inspect(
    @moonbean.path_join("docs", "a.beancount"),
    content="docs/a.beancount",
  )
  inspect(
    @moonbean.path_join("docs/sub", "../a.beancount"),
    content="docs/a.beancount",
  )
  inspect(
    @moonbean.path_join("docs", "/abs/a.beancount"),
    content="/abs/a.beancount",
  )
  inspect(@moonbean.path_join("", "a.beancount"), content="a.beancount")
  inspect(
    @moonbean.path_join("/tmp/docs", "includes/a.beancount"),
    content="/tmp/docs/includes/a.beancount",
  )
  inspect(
    @moonbean.path_join("/tmp/docs", "../a.beancount"),
    content="/tmp/a.beancount",
  )
  inspect(@moonbean.path_dirname("/a"), content="/")
  inspect(@moonbean.path_join("/", "a.beancount"), content="/a.beancount")
}

///|
test "expand_includes follows nested includes and reports missing" {
  let files : Map[String, String] = Map([])
  files.set("docs/a.beancount", "include \"sub/b.beancount\"\n")
  files.set("docs/sub/b.beancount", "2024-01-01 open Equity:Opening USD\n")
  let read = fn(path) {
    match files.get(path) {
      Some(content) => Some(content)
      None => None
    }
  }
  let source = "include \"a.beancount\"\n" +
    "include \"missing.beancount\"\n" +
    "2024-01-01 open Assets:Cash USD\n"
  let expanded = @moonbean.expand_includes(source, "docs", read)
  inspect(expanded.missing.length(), content="1")
  inspect(expanded.missing[0], content="docs/missing.beancount")
  inspect(expanded.source.contains("Equity:Opening"), content="true")
  inspect(expanded.source.contains("Assets:Cash"), content="true")
  inspect(
    expanded.source.contains("include \"missing.beancount\""),
    content="true",
  )
}

///|
test "expand_includes resolves absolute base directories" {
  let files : Map[String, String] = Map([])
  files.set("/tmp/docs/a.beancount", "2024-01-01 open Assets:Cash USD\n")
  files.set(
    "/tmp/docs/includes/b.beancount", "2024-01-01 open Equity:Opening USD\n",
  )
  let read = fn(path) {
    match files.get(path) {
      Some(content) => Some(content)
      None => None
    }
  }
  let source = "include \"a.beancount\"\n" +
    "include \"includes/b.beancount\"\n"
  let expanded = @moonbean.expand_includes(source, "/tmp/docs", read)
  inspect(expanded.missing.length(), content="0")
  inspect(expanded.source.contains("Assets:Cash"), content="true")
  inspect(expanded.source.contains("Equity:Opening"), content="true")
}

///|
test "check, realize, query and format facade" {
  let ledger = @moonbean.check_source("facade.beancount", facade_ledger())
  inspect(ledger.errors.length(), content="0")
  inspect(ledger.accounts.length(), content="2")
  let result = @moonbean.realize(ledger)
  let inventory = result.inventory("Assets:Cash")
  let positions = inventory.positions
  inspect(positions.length(), content="1")
  inspect(positions[0].units.to_string(), content="100 USD")
  let queried = @moonbean.run_query(
    ledger, "SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account",
  )
  inspect(queried.is_ok(), content="true")
  inspect(queried.rows.length(), content="2")
  let formatted = @moonbean.format_source(facade_ledger())
  inspect(formatted.contains("100 USD"), content="true")
}

///|
test "export_json describes entries and accounts" {
  let ledger = @moonbean.check_source("facade.beancount", facade_ledger())
  let json = @moonbean.export_json("facade.beancount", ledger)
  inspect(json.contains("\"errors\":[]"), content="true")
  inspect(json.contains("\"type\":\"transaction\""), content="true")
  inspect(json.contains("\"type\":\"balance\""), content="true")
  inspect(json.contains("\"account\":\"Assets:Cash\""), content="true")
  inspect(json.contains("\"number\":\"100\""), content="true")
  inspect(json.contains("\"code\""), content="false")
}

///|
test "export_json includes diagnostics for a bad ledger" {
  let ledger = @moonbean.check_source(
    "bad.beancount", "2024-01-02 * \"No open\"\n  Assets:Cash 1 USD\n  Equity:Opening -1 USD\n",
  )
  inspect(ledger.errors.length() > 0, content="true")
  let json = @moonbean.export_json("bad.beancount", ledger)
  inspect(json.contains("\"line\":1"), content="true")
  inspect(
    json.contains("\"code\":\"validation.unknown_account\""),
    content="true",
  )
}

///|
test "include walker rejects self and mutual cycles with original include locations" {
  let files : Map[String, String] = {
    "/docs/self": "include \"./self\"",
    "/docs/a": "include \"sub/../b\"",
    "/docs/b": "include \"/docs/a\"",
  }
  let self = @moonbean.check_expanded(
    "/docs/self",
    "/docs",
    files.get("/docs/self").unwrap(),
    fn(p) { files.get(p) },
  )
  inspect(self.errors.length(), content="1")
  inspect(self.errors[0].code, content="include.cycle")
  inspect(self.errors[0].loc.to_string(), content="/docs/self:1")
  let mutual = @moonbean.check_expanded(
    "/docs/a",
    "/docs",
    files.get("/docs/a").unwrap(),
    fn(p) { files.get(p) },
  )
  inspect(mutual.errors[0].code, content="include.cycle")
  inspect(mutual.errors[0].loc.to_string(), content="/docs/b:1")
}

///|
test "include stack permits deep acyclic loads and repeated siblings" {
  let files : Map[String, String] = Map([])
  for i in 0..<300 {
    files.set("d/" + i.to_string(), "include \"" + (i + 1).to_string() + "\"")
  }
  files.set("d/300", "2024-01-01 open Assets:Cash USD")
  let result = @moonbean.expand_includes("include \"0\"\ninclude \"0\"", "d", fn(
    p,
  ) {
    files.get(p)
  })
  inspect(result.errors.length(), content="0")
  inspect(result.source.split("Assets:Cash").count(), content="3")
  inspect(@moonbean.path_join("/", "../../a"), content="/a")
}

///|
test "include paths handle drive roots and relative root filenames" {
  inspect(
    @moonbean.path_join("C:\\Docs", "C:\\Docs\\sub\\..\\a"),
    content="c:/docs/a",
  )
  inspect(@moonbean.path_join("C:/", "../../a"), content="c:/a")
  inspect(
    @moonbean.path_join("//server/share", "../a"),
    content="//server/share/a",
  )
  let result = @moonbean.check_expanded("main", "/docs", "include \"main\"", fn(
    _,
  ) {
    abort("cycle must be detected before reading")
  })
  inspect(result.errors[0].code, content="include.cycle")
}
