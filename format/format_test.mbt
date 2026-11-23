///|
test "formats transaction postings into an aligned column" {
  let source = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-01-02 * \"Lunch\"\n" +
    "  Expenses:Food    10.00 USD\n" +
    "  Assets:Cash -10.00 USD\n"
  let formatted = @format.format_source(source)
  let expected = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-01-02 * \"Lunch\"\n" +
    "  Expenses:Food  10.00 USD\n" +
    "  Assets:Cash    -10.00 USD\n"
  inspect(formatted, content=expected)
  inspect(@format.format_source(formatted), content=expected)
}

///|
test "formatted output parses and validates cleanly" {
  let source = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-01-02 * \"Lunch\"\n" +
    "  Expenses:Food        10.00 USD\n" +
    "  Assets:Cash   -10.00 USD\n"
  let formatted = @format.format_source(source)
  let ledger = @validation.validate_ledger(
    @syntax.parse_source("formatted.beancount", formatted),
  )
  inspect(ledger.errors.length(), content="0")
  inspect(ledger.accounts.length(), content="2")
}

///|
test "posting flags and metadata stay attached" {
  let source = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-01-02 ! \"Shop\" \"Store\"\n" +
    "  ! Expenses:Food 5 USD\n" +
    "    note: \"tax\"\n" +
    "  Assets:Cash -5 USD\n"
  let formatted = @format.format_source(source)
  inspect(formatted.contains("  ! Expenses:Food  5 USD"), content="true")
  inspect(formatted.contains("    note: \"tax\""), content="true")
  inspect(formatted.contains("  Assets:Cash      -5 USD"), content="true")
}

///|
test "directive lines keep their content and trailing spaces disappear" {
  let source = "option \"title\" \"Test\"   \n" +
    "; a comment  \n" +
    "2024-01-01 open Assets:Cash USD   \n"
  let formatted = @format.format_source(source)
  inspect(
    formatted,
    content="option \"title\" \"Test\"\n; a comment\n2024-01-01 open Assets:Cash USD\n",
  )
}

///|
test "plain postings without amounts are left unaligned" {
  let source = "2024-01-01 open Assets:Cash USD\n" +
    "2024-01-01 open Expenses:Food USD\n" +
    "2024-01-02 * \"Lunch\"\n" +
    "  Expenses:Food 10 USD\n" +
    "  Assets:Cash\n"
  let formatted = @format.format_source(source)
  inspect(formatted.contains("  Expenses:Food  10 USD"), content="true")
  inspect(formatted.contains("  Assets:Cash\n"), content="true")
}

///|
test "multiline literals retain whitespace through formatting" {
  let source = "2024-01-01 open Assets:A\n2024-01-02 * \"first  \n  second\r\n\nlast\"\n  Assets:A 1 USD\n  Assets:A -1 USD\n"
  assert_eq(@format.format_source(source), source)
  let ledger = @syntax.parse_source("multi.bean", @format.format_source(source))
  assert_eq(ledger.errors.length(), 0)
  guard ledger.entries[1].directive is DTransaction(txn) else { abort("txn") }
  assert_eq(txn.narration, "first  \n  second\r\n\nlast")
}

///|
test "formats explicit txn and tab-delimited transaction headers" {
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Expenses:Food USD\n2024-01-02\ttxn \"lunch\"\n      Expenses:Food  5 USD\n Assets:Cash -5 USD\n2024-01-03   txn \"again\"\n  Expenses:Food  7 USD\n Assets:Cash -7 USD\n"
  let output = @format.format_source(source)
  assert_true(output.contains("  Assets:Cash    -5 USD"))
  assert_true(output.contains("  Assets:Cash    -7 USD"))
  assert_eq(@format.format_source(output), output)
  let checked = @validation.validate_ledger(
    @syntax.parse_source("formatted.bean", output),
  )
  assert_true(!checked.has_errors())
  assert_eq(checked.entries.length(), 4)
}

///|
test "multiline records retain exact text while unrelated transactions still align" {
  let literal_span = "2024-01-02 * \"A  \nmultiline 😀 \n narration \"\n    detail: \"kept  \n span \"\n"
  let source = "2024-01-01 open Assets:Cash USD\n2024-01-01 open Expenses:Food USD\n" +
    literal_span +
    " Expenses:Food 5 USD\n Assets:Cash -5 USD\n" +
    "2024-01-03 * \"ordinary\"\n       Expenses:Food 7 USD\n Assets:Cash -7 USD\n"
  let output = @format.format_source(source)
  assert_true(output.contains(literal_span))
  assert_true(output.contains("  Assets:Cash    -7 USD"))
  assert_eq(@format.format_source(output), output)
  let a = @syntax.parse_source("same.bean", source)
  let b = @syntax.parse_source("same.bean", output)
  assert_true(a.errors.is_empty() && b.errors.is_empty())
  if a.entries[2].directive is DTransaction(x) &&
    b.entries[2].directive is DTransaction(y) {
    assert_eq(x.narration, y.narration)
    assert_eq(x.postings.length(), y.postings.length())
  } else {
    fail("missing multiline transaction")
  }
}

///|
test "astral posting components retain full Unicode and round-trip" {
  let source = "2024-01-01 open Assets:𐐀𐐁-Reserve USD\n2024-01-01 open Expenses:Café USD\n2024-01-01 open Equity:Offset USD\n2024-01-02 * \"Unicode accounts\"\n     ! Assets:𐐀𐐁-Reserve 5.00 USD\n Expenses:Café 4.00 USD\n Equity:Offset -9.00 USD\n"
  let output = @format.format_source(source)
  let original = @syntax.parse_source("same.bean", source)
  let round_trip = @syntax.parse_source("same.bean", output)
  assert_true(original.errors.is_empty())
  assert_true(round_trip.errors.is_empty())
  assert_true(output.contains("! Assets:𐐀𐐁-Reserve"))
  assert_true(output.contains("  Expenses:Café"))
  assert_true(output.contains("  Equity:Offset"))
  assert_eq(@format.format_source(output), output)
  guard original.entries[3].directive is DTransaction(before) &&
    round_trip.entries[3].directive is DTransaction(after) else {
    abort("missing transaction")
  }
  assert_eq(
    before.postings.map(fn(p) { p.account }),
    after.postings.map(fn(p) { p.account }),
  )
  assert_eq(
    before.postings.map(fn(p) { p.units.unwrap().to_string() }),
    after.postings.map(fn(p) { p.units.unwrap().to_string() }),
  )
}

///|
test "every accepted ledger date spelling aligns postings without rewriting its date" {
  for date in ["2024/1/2", "2024-01-2", "00002024/1-02", "2024-01-02"] {
    let source = date +
      " * \"rent\"\n      Expenses:Rent  20 USD\n Assets:Cash -20 USD\n"
    let expected = date +
      " * \"rent\"\n  Expenses:Rent  20 USD\n  Assets:Cash    -20 USD\n"
    assert_eq(@syntax.parse_source("rent.bean", source).errors.length(), 0)
    assert_eq(@format.format_source(source), expected)
    assert_eq(@format.format_source(expected), expected)
  }
}

///|
test "localized postings align without reinterpreting metadata as an account" {
  let input =
    #|option "name_assets" "Actif"
    #|option "name_expenses" "Depenses"
    #|2024-01-03 * "Rent"
    #|    ! Actif:Cash -15 USD
    #|  Depenses:Loyer 15 USD
    #|    note: "rent: July"
    #|
  let output = @format.format_source(input)
  let lines = output.split("\n").to_array()
  assert_true(lines[3].has_prefix("  ! Actif:Cash"))
  assert_eq(lines[3].find("-15 USD"), lines[4].find("15 USD"))
  assert_true(lines[5].has_suffix("note: \"rent: July\""))
  assert_eq(@syntax.parse_source("fr.bean", output).errors.length(), 0)
  assert_eq(@format.format_source(output), output)
}
