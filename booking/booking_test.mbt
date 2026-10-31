///|
fn dec(text : String) -> @decimal.Decimal {
  match @decimal.Decimal::parse(text) {
    Some(value) => value
    None => abort("invalid decimal " + text)
  }
}

///|
fn day(text : String) -> @ast.Date {
  match @ast.Date::parse(text) {
    Some(value) => value
    None => abort("invalid date " + text)
  }
}

///|
fn units(number : String, currency : String) -> @ast.Amount {
  @ast.Amount::new(dec(number), currency)
}

///|
fn bare_posting(number : String, currency : String) -> @ast.Posting {
  let posting = @ast.Posting::new("Assets:Stock")
  posting.units = Some(units(number, currency))
  posting
}

///|
fn costed_posting(
  number : String,
  currency : String,
  cost_number : String,
  cost_currency : String,
  date : String,
) -> @ast.Posting {
  let posting = bare_posting(number, currency)
  posting.cost = Some(
    @ast.CostSpec::new_per(
      dec(cost_number),
      cost_currency,
      Some(day(date)),
      None,
    ),
  )
  posting
}

///|
fn empty_cost_posting(number : String, currency : String) -> @ast.Posting {
  let posting = bare_posting(number, currency)
  posting.cost = Some(@ast.CostSpec::empty())
  posting
}

///|
test "augmentation builds lots and computes cost weight" {
  let state = @booking.BookingState::new()
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  inspect(outcome.issue is None, content="true")
  inspect(outcome.weights.length(), content="1")
  inspect(outcome.weights[0].to_string(), content="1000 USD")
  let inv = state.inventory_for("Assets:Stock")
  inspect(inv.to_string(), content="10 HOOL {100 USD, 2024-01-02}")
}

///|
test "empty cost asks for inference and NONE keeps mixed signs" {
  let state = @booking.BookingState::new()
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    empty_cost_posting("10", "HOOL"),
    day("2024-01-02"),
    "STRICT",
  )
  inspect(outcome.needs_inference, content="true")
  inspect(state.inventory_for("Assets:Stock").positions.length(), content="0")

  let none_state = @booking.BookingState::new()
  none_state.set_booking("Assets:Stock", "NONE")
  let _ = @booking.book_posting(
    none_state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let reduction = @booking.book_posting(
    none_state,
    "Assets:Stock",
    empty_cost_posting("-15", "HOOL"),
    day("2024-01-03"),
    "STRICT",
  )
  inspect(reduction.issue is None, content="true")
  inspect(
    none_state.inventory_for("Assets:Stock").quantity("HOOL").to_string(),
    content="-5",
  )
}

///|
test "FIFO consumes oldest lots" {
  let state = @booking.BookingState::new()
  state.set_booking("Assets:Stock", "FIFO")
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "120", "USD", "2024-01-03"),
    day("2024-01-03"),
    "STRICT",
  )
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    empty_cost_posting("-4", "HOOL"),
    day("2024-01-04"),
    "STRICT",
  )
  inspect(outcome.issue is None, content="true")
  inspect(outcome.weights[0].to_string(), content="-400 USD")
  inspect(
    state.inventory_for("Assets:Stock").to_string(),
    content="6 HOOL {100 USD, 2024-01-02}, 10 HOOL {120 USD, 2024-01-03}",
  )
}

///|
test "strict booking rejects ambiguity and missing lots" {
  let state = @booking.BookingState::new()
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "120", "USD", "2024-01-03"),
    day("2024-01-03"),
    "STRICT",
  )
  let ambiguous = @booking.book_posting(
    state,
    "Assets:Stock",
    empty_cost_posting("-4", "HOOL"),
    day("2024-01-04"),
    "STRICT",
  )
  match ambiguous.issue {
    Some(issue) => inspect(issue.code, content="booking.ambiguous")
    None => abort("expected ambiguity")
  }
  let state2 = @booking.BookingState::new()
  state2.set_booking("Assets:Stock", "FIFO")
  let _ = @booking.book_posting(
    state2,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let insufficient = @booking.book_posting(
    state2,
    "Assets:Stock",
    empty_cost_posting("-15", "HOOL"),
    day("2024-01-03"),
    "STRICT",
  )
  match insufficient.issue {
    Some(issue) => inspect(issue.code, content="booking.insufficient")
    None => abort("expected insufficient lots")
  }
  inspect(
    state2.inventory_for("Assets:Stock").quantity("HOOL").to_string(),
    content="10",
  )
}

///|
test "strict with size disambiguates by lot size" {
  let state = @booking.BookingState::new()
  state.set_booking("Assets:Stock", "STRICT_WITH_SIZE")
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("5", "HOOL", "120", "USD", "2024-01-03"),
    day("2024-01-03"),
    "STRICT",
  )
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    empty_cost_posting("-5", "HOOL"),
    day("2024-01-04"),
    "STRICT",
  )
  inspect(outcome.issue is None, content="true")
  inspect(outcome.weights[0].to_string(), content="-600 USD")
}

///|
test "explicit cost picks a matching lot and total cost is divided" {
  let state = @booking.BookingState::new()
  state.set_booking("Assets:Stock", "FIFO")
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "120", "USD", "2024-01-03"),
    day("2024-01-03"),
    "STRICT",
  )
  let reduction = costed_posting("-4", "HOOL", "120", "USD", "2024-01-03")
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    reduction,
    day("2024-01-04"),
    "STRICT",
  )
  inspect(outcome.issue is None, content="true")
  inspect(outcome.weights[0].to_string(), content="-480 USD")
  let total_state = @booking.BookingState::new()
  let total_posting = bare_posting("10", "HOOL")
  total_posting.cost = Some(@ast.CostSpec::new_total(dec("1050"), "USD"))
  let total = @booking.book_posting(
    total_state,
    "Assets:Stock",
    total_posting,
    day("2024-01-02"),
    "STRICT",
  )
  inspect(total.weights[0].to_string(), content="1050 USD")
  inspect(
    total_state.inventory_for("Assets:Stock").to_string(),
    content="10 HOOL {105 USD, 2024-01-02}",
  )
}

///|
test "average booking uses weighted average cost" {
  let state = @booking.BookingState::new()
  state.set_booking("Assets:Stock", "AVERAGE")
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "120", "USD", "2024-01-03"),
    day("2024-01-03"),
    "STRICT",
  )
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    empty_cost_posting("-5", "HOOL"),
    day("2024-01-04"),
    "STRICT",
  )
  inspect(outcome.issue is None, content="true")
  inspect(outcome.weights[0].to_string(), content="-550 USD")
  let inventory = state.inventory_for("Assets:Stock")
  inspect(inventory.positions.length(), content="1")
  inspect(inventory.positions[0].units.to_string(), content="15 HOOL")
  inspect(
    match inventory.positions[0].cost {
      Some(cost) => cost.number.to_string()
      None => abort("average lot must have a cost")
    },
    content="110",
  )
}

///|
test "posting without cost clause does not consume cost basis" {
  let state = @booking.BookingState::new()
  state.set_booking("Assets:Stock", "FIFO")
  let _ = @booking.book_posting(
    state,
    "Assets:Stock",
    costed_posting("10", "HOOL", "100", "USD", "2024-01-02"),
    day("2024-01-02"),
    "STRICT",
  )
  let no_cost = bare_posting("-4", "HOOL")
  let outcome = @booking.book_posting(
    state,
    "Assets:Stock",
    no_cost,
    day("2024-01-03"),
    "STRICT",
  )
  inspect(outcome.weights[0].to_string(), content="-4 HOOL")
  inspect(
    state.inventory_for("Assets:Stock").to_string(),
    content="10 HOOL {100 USD, 2024-01-02}, -4 HOOL",
  )
}
