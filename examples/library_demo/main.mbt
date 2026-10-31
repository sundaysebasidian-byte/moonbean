// Minimal embedding demo.  Everything below is pure MoonBit: the same code
// compiles for native, wasm-gc and JavaScript hosts.
//
//   moon run examples/library_demo

///|
fn demo_ledger() -> String {
  "option \"title\" \"Library demo\"\n" +
  "2024-01-01 open Assets:Cash USD\n" +
  "2024-01-01 open Equity:Opening USD\n" +
  "2024-01-01 open Expenses:Food USD\n" +
  "2024-01-02 * \"Opening\"\n" +
  "  Assets:Cash     100.00 USD\n" +
  "  Equity:Opening -100.00 USD\n" +
  "2024-01-03 * \"Cafe\" \"Coffee\"\n" +
  "  Assets:Cash      -8.00 USD\n" +
  "  Expenses:Food     8.00 USD\n"
}

///|
fn main {
  let source = demo_ledger()
  let ledger = @moonbean.check_source("demo.beancount", source)
  println("errors: " + ledger.error_count().to_string())
  let realized = @moonbean.realize(ledger)
  println("Assets:Cash inventory:")
  for position in realized.inventory("Assets:Cash").positions {
    println("  " + position.to_string())
  }
  let result = @moonbean.run_query(
    ledger, "SELECT account, sum(units) FROM postings GROUP BY account ORDER BY account",
  )
  println(result.to_text())
  println(@moonbean.format_source(source))
}
