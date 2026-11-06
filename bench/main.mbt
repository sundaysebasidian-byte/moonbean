///|
fn number(s : String) -> Int32 {
  let mut n = 0
  for c in s.iter() {
    n = n * 10 + c.to_int() - 48
  }
  n
}

///|
fn setting(name : String, fallback : String) -> String {
  @env.get_env_var(name).unwrap_or(fallback)
}

///|
fn generate(count : Int32, policy : String) -> String {
  let b = StringBuilder()
  b.write_string(
    "2024-01-01 open Assets:Stock HOOL \"\{policy}\"\n2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n2024-01-02 pad Assets:Cash Equity:Opening\n2024-01-03 balance Assets:Cash 1 USD\n",
  )
  let mut seed = 20261101U
  for i = 0; i < count / 8; i = i + 1 {
    seed = seed * 1664525U + 1013904223U
    let price = (seed % 90U).reinterpret_as_int() + 10
    for j = 0; j < 2; j = j + 1 {
      let cost = price + j * 2
      b.write_string(
        "2024-01-04 * \"Buy \{i}/\{j}\"\n  Assets:Stock 1 HOOL {\{cost} USD}\n  Assets:Cash -\{cost} USD\n",
      )
    }
    for j = 0; j < 2; j = j + 1 {
      let cost = if policy == "AVERAGE" { price + 1 } else { price + j * 2 }
      let selector = if policy == "STRICT" { "{\{cost} USD}" } else { "{}" }
      b.write_string(
        "2024-01-04 * \"Sell \{i}/\{j}\"\n  Assets:Stock -1 HOOL \{selector}\n  Assets:Cash \{cost} USD\n",
      )
    }
  }
  b.to_string()
}

///|
fn measure(name : String, runs : Int32, action : () -> Int32) -> Unit {
  let mut sink = 0
  for i = 0; i < runs + 2; i = i + 1 {
    let start = @env.now()
    let mut batches = 0
    while true {
      sink = sink ^ action()
      batches = batches + 1
      if @env.now() - start >= 20UL {
        break
      }
    }
    let elapsed = (@env.now() - start).to_double() / 1000.0
    println(
      "{\"stage\":\"\{name}\",\"warmup\":\{i < 2},\"seconds\":\{elapsed / batches.to_double()},\"batch\":\{batches},\"sink\":\{sink}}",
    )
  }
}

///|
fn main {
  let count = number(setting("BENCH_COUNT", "1000"))
  let runs = number(setting("BENCH_RUNS", "15"))
  let policy = setting("BENCH_METHOD", "FIFO")
  let source = generate(count, policy)
  let parsed = @syntax.parse_source("generated.bean", source)
  let valid = @validation.validate_ledger(parsed)
  if valid.has_errors() {
    for error in valid.errors {
      println(@moonbean.diagnostic_text(error))
    }
    abort("invalid generated fixture")
  }
  if policy == "FIFO" {
    measure("parse", runs, fn() {
      @syntax.parse_source("generated.bean", source).entries.length()
    })
  }
  measure("booking_\{policy}", runs, fn() {
    let state = @booking.BookingState::new()
    state.set_booking("Assets:Stock", policy)
    let mut n = 0
    for entry in parsed.entries {
      if entry.directive is DTransaction(txn) {
        for posting in txn.postings {
          let outcome = @booking.book_posting(
            state,
            posting.account,
            posting,
            entry.date,
            policy,
          )
          if outcome.issue is Some(_) {
            abort("booking failed")
          }
          n = n + outcome.positions.length()
        }
      }
    }
    n
  })
  measure("validate_pad_\{policy}", runs, fn() {
    @validation.validate_ledger(parsed).entries.length()
  })
  if policy != "FIFO" {
    return
  }
  measure("realize", runs, fn() { @moonbean.realize(valid).accounts.length() })
  measure("format", runs, fn() { @moonbean.format_source(source).length() })
  for
    (name, query) in [
      ("aggregate", "SELECT count(*)"),
      ("group", "SELECT account, sum(units) GROUP BY account"),
      ("order", "SELECT narration ORDER BY narration"),
      ("regex", "SELECT count(*) WHERE account ~ 'Stock'"),
      ("transactions", "SELECT count(*) FROM transactions"),
      ("length", "SELECT length(narration) FROM transactions"),
      ("substr", "SELECT substr(narration, 0, 3) FROM transactions"),
    ] {
    if name == "order" && count >= 100000 {
      continue
    }
    measure(name, runs, fn() {
      let result = @moonbean.run_query(valid, query)
      if result.error is Some(_) {
        abort("query failed")
      }
      result.rows.length()
    })
  }
}
