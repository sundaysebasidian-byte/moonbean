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
