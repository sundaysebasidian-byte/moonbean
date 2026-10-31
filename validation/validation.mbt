// Semantic validation.  This layer turns a parsed Ledger into a validated
// ledger: entries are ordered by date (non-transactions before transactions),
// accounts are tracked from open to close, transactions are booked against
// inventories, tolerances are inferred, and balance assertions and pads are
// checked.  Diagnostics keep the source location of the directive they refer
// to so that command line output can mirror bean-check.

///|
pub(all) struct AccountInfo {
  account : String
  open_date : @ast.Date
  mut close_date : @ast.Date?
  currencies : Array[String]
  booking : String?
  loc : @ast.Loc
}

///|
pub(all) struct ValidatedLedger {
  entries : Array[@ast.Entry]
  errors : Array[@ast.Diagnostic]
  warnings : Array[@ast.Diagnostic]
  options : @ast.Options
  plugins : Array[@ast.Plugin]
  accounts : Map[String, AccountInfo]
  state : @booking.BookingState
}

///|
pub fn ValidatedLedger::inventory(
  self : ValidatedLedger,
  account : String,
) -> @booking.Inventory {
  match self.state.inventory(account) {
    Some(inv) => inv.copy()
    None => @booking.Inventory::new()
  }
}

///|
pub fn ValidatedLedger::account_info(
  self : ValidatedLedger,
  account : String,
) -> AccountInfo? {
  self.accounts.get(account)
}

///|
pub fn ValidatedLedger::has_errors(self : ValidatedLedger) -> Bool {
  self.errors.length() > 0
}

///|
pub fn ValidatedLedger::error_count(self : ValidatedLedger) -> Int32 {
  self.errors.length()
}

///|
pub fn ValidatedLedger::warning_count(self : ValidatedLedger) -> Int32 {
  self.warnings.length()
}

///|
pub fn ValidatedLedger::account_names(self : ValidatedLedger) -> Array[String] {
  let names = self.accounts.keys().to_array()
  let mut i = 1
  while i < names.length() {
    let current = names[i]
    let mut j = i
    while j > 0 {
      let prev = names[j - 1]
      if prev.lexical_compare(current) > 0 {
        names[j - 1] = current
        names[j] = prev
        j = j - 1
      } else {
        break
      }
    }
    i = i + 1
  }
  names
}

///|
priv struct PadState {
  account : String
  source : String
  date : @ast.Date
  loc : @ast.Loc
  mut consumed : Bool
}

///|
priv struct Context {
  errors : Array[@ast.Diagnostic]
  warnings : Array[@ast.Diagnostic]
  accounts : Map[String, AccountInfo]
  state : @booking.BookingState
  pads : Array[PadState]
  balance_seen : Map[String, @ast.Amount]
  entries : Array[@ast.Entry]
  options : @ast.Options
  plugins : Array[@ast.Plugin]
  known_opens : Map[String, @ast.Date]
}

///|
fn Context::new(ledger : @ast.Ledger) -> Context {
  let known_opens : Map[String, @ast.Date] = Map([])
  for entry in ledger.entries {
    match entry.directive {
      DOpen(open) =>
        if known_opens.get(open.account) is None {
          known_opens.set(open.account, entry.date)
        }
      _ => ()
    }
  }
  {
    errors: [],
    warnings: [],
    accounts: {},
    state: @booking.BookingState::new(),
    pads: [],
    balance_seen: {},
    entries: [],
    options: ledger.options,
    plugins: ledger.plugins,
    known_opens,
  }
}

///|
fn error(
  ctx : Context,
  code : String,
  message : String,
  loc : @ast.Loc,
) -> Unit {
  ctx.errors.push(@ast.Diagnostic::new(code, message, loc))
}

///|
fn warning(
  ctx : Context,
  code : String,
  message : String,
  loc : @ast.Loc,
) -> Unit {
  ctx.warnings.push(@ast.Diagnostic::new(code, message, loc))
}

///|
fn is_booking_method(name : String) -> Bool {
  name == "STRICT" ||
  name == "STRICT_WITH_SIZE" ||
  name == "FIFO" ||
  name == "LIFO" ||
  name == "HIFO" ||
  name == "AVERAGE" ||
  name == "NONE"
}

///|
fn directive_rank(directive : @ast.Directive) -> Int32 {
  match directive {
    DOpen(_) => 0
    DCommodity(_) => 1
    DClose(_) => 2
    DPad(_) => 3
    DBalance(_) => 4
    DPrice(_) => 5
    DNote(_) => 6
    DDocument(_) => 7
    DEvent(_) => 8
    DQuery(_) => 9
    DCustom(_) => 10
    DTransaction(_) => 11
  }
}

///|
fn sorted_entries(entries : Array[@ast.Entry]) -> Array[@ast.Entry] {
  let result = []
  for entry in entries {
    result.push(entry)
  }
  let mut i = 1
  while i < result.length() {
    let current = result[i]
    let mut j = i
    while j > 0 {
      let prev = result[j - 1]
      let date_cmp = prev.date.compare(current.date)
      let rank_cmp = directive_rank(prev.directive).compare(
        directive_rank(current.directive),
      )
      let should_swap = date_cmp > 0 || (date_cmp == 0 && rank_cmp > 0)
      if should_swap {
        result[j - 1] = current
        result[j] = prev
        j = j - 1
      } else {
        break
      }
    }
    i = i + 1
  }
  result
}

///|
fn add_weight(target : Array[@ast.Amount], amount : @ast.Amount) -> Unit {
  for i in 0..<target.length() {
    if target[i].currency == amount.currency {
      target[i] = @ast.Amount::new(
        target[i].number.add(amount.number),
        amount.currency,
      )
      return
    }
  }
  target.push(amount)
}

///|
fn weight_sum(
  weights : Array[@ast.Amount],
  currency : String,
) -> @decimal.Decimal {
  let mut total = @decimal.Decimal::zero()
  for amount in weights {
    if amount.currency == currency {
      total = total.add(amount.number)
    }
  }
  total
}

///|
fn infer_currency(weights : Array[@ast.Amount]) -> String? {
  let nonzero = []
  for amount in weights {
    if !amount.number.is_zero() && !nonzero.contains(amount.currency) {
      nonzero.push(amount.currency)
    }
  }
  if nonzero.length() == 1 {
    return Some(nonzero[0])
  }
  if nonzero.length() == 0 && weights.length() == 1 {
    return Some(weights[0].currency)
  }
  None
}

///|
fn larger(a : @decimal.Decimal, b : @decimal.Decimal) -> @decimal.Decimal {
  if a.less_than(b) {
    b
  } else {
    a
  }
}

///|
fn is_active(info : AccountInfo, date : @ast.Date) -> Bool {
  if date.less_than(info.open_date) {
    return false
  }
  match info.close_date {
    Some(close_date) => !close_date.less_than(date)
    None => true
  }
}

///|
fn check_account(
  ctx : Context,
  account : String,
  date : @ast.Date,
  loc : @ast.Loc,
  require_active : Bool,
) -> AccountInfo? {
  match ctx.accounts.get(account) {
    Some(info) => {
      if require_active && !is_active(info, date) {
        error(
          ctx,
          "validation.inactive_account",
          "Invalid reference to inactive account '" + account + "'",
          loc,
        )
      }
      Some(info)
    }
    None => {
      match ctx.known_opens.get(account) {
        Some(open_date) =>
          if date.less_than(open_date) {
            error(
              ctx,
              "validation.inactive_account",
              "Invalid reference to inactive account '" + account + "'",
              loc,
            )
          } else {
            error(
              ctx,
              "validation.unknown_account",
              "Invalid reference to unknown account '" + account + "'",
              loc,
            )
          }
        None =>
          error(
            ctx,
            "validation.unknown_account",
            "Invalid reference to unknown account '" + account + "'",
            loc,
          )
      }
      None
    }
  }
}

///|
fn check_currency(
  ctx : Context,
  info : AccountInfo?,
  currency : String,
  loc : @ast.Loc,
) -> Unit {
  match info {
    Some(info) =>
      if info.currencies.length() > 0 && !info.currencies.contains(currency) {
        error(
          ctx,
          "validation.currency",
          "Invalid currency " + currency + " for account '" + info.account + "'",
          loc,
        )
      }
    None => ()
  }
}

///|
fn process_open(ctx : Context, entry : @ast.Entry, open : @ast.Open) -> Unit {
  match open.booking {
    Some(booking) =>
      if !is_booking_method(booking) {
        error(
          ctx,
          "validation.booking_method",
          "Invalid booking method: " + booking,
          entry.loc,
        )
      }
    None => ()
  }
  if ctx.accounts.get(open.account) is Some(_) {
    error(
      ctx,
      "validation.duplicate_open",
      "Duplicate open directive for " + open.account,
      entry.loc,
    )
    return
  }
  let info = {
    account: open.account,
    open_date: entry.date,
    close_date: None,
    currencies: open.currencies.copy(),
    booking: open.booking,
    loc: entry.loc,
  }
  ctx.accounts.set(open.account, info)
  match open.booking {
    Some(booking) =>
      if is_booking_method(booking) {
        ctx.state.set_booking(open.account, booking)
      }
    None => ()
  }
}

///|
fn process_close(ctx : Context, entry : @ast.Entry, close : @ast.Close) -> Unit {
  match ctx.accounts.get(close.account) {
    Some(info) =>
      match info.close_date {
        Some(_) =>
          error(
            ctx,
            "validation.duplicate_close",
            "Duplicate close directive for " + close.account,
            entry.loc,
          )
        None => {
          info.close_date = Some(entry.date)
          ctx.accounts.set(close.account, info)
        }
      }
    None =>
      error(
        ctx,
        "validation.close_unopened",
        "Unopened account " + close.account + " is being closed",
        entry.loc,
      )
  }
}

///|
fn process_pad(ctx : Context, entry : @ast.Entry, pad : @ast.Pad) -> Unit {
  check_account(ctx, pad.account, entry.date, entry.loc, true) |> ignore
  check_account(ctx, pad.source_account, entry.date, entry.loc, true) |> ignore
  ctx.pads.push({
    account: pad.account,
    source: pad.source_account,
    date: entry.date,
    loc: entry.loc,
    consumed: false,
  })
}

///|
fn is_subaccount(name : String, parent : String) -> Bool {
  if name == parent {
    return true
  }
  let name_parts = @ast.account_parts(name)
  let parent_parts = @ast.account_parts(parent)
  if name_parts.length() <= parent_parts.length() {
    return false
  }
  for i in 0..<parent_parts.length() {
    if name_parts[i] != parent_parts[i] {
      return false
    }
  }
  true
}

///|
fn accumulated_quantity(
  ctx : Context,
  account : String,
  currency : String,
) -> @decimal.Decimal {
  let mut total = @decimal.Decimal::zero()
  for name in ctx.state.accounts.keys().to_array() {
    if is_subaccount(name, account) {
      match ctx.state.accounts.get(name) {
        Some(state) => total = total.add(state.inventory.quantity(currency))
        None => ()
      }
    }
  }
  total
}

///|
fn balance_tolerance(ctx : Context, balance : @ast.Balance) -> @decimal.Decimal {
  match balance.tolerance {
    Some(explicit) => explicit.abs()
    None =>
      balance.amount.number
      .last_digit_place()
      .abs()
      .mul(ctx.options.tolerance_multiplier)
  }
}

///|
fn padding_narration(
  expected : @ast.Amount,
  difference : @decimal.Decimal,
) -> String {
  "(Padding inserted for Balance of " +
  expected.to_string() +
  " for difference " +
  difference.to_string() +
  " " +
  expected.currency +
  ")"
}

///|
fn insert_padding(
  ctx : Context,
  pad : PadState,
  expected : @ast.Amount,
  difference : @decimal.Decimal,
) -> Unit {
  let target = @ast.Posting::new(pad.account)
  target.units = Some(@ast.Amount::new(difference, expected.currency))
  let source = @ast.Posting::new(pad.source)
  source.units = Some(@ast.Amount::new(difference.neg(), expected.currency))
  let txn = @ast.Transaction::new(
    "P",
    None,
    padding_narration(expected, difference),
    [],
    [],
  )
  txn.postings.push(target)
  txn.postings.push(source)
  let entry = @ast.Entry::new(
    pad.date,
    pad.loc,
    @ast.Directive::DTransaction(txn),
  )
  ctx.entries.push(entry)
  ctx.state
  .inventory_for(pad.account)
  .add_amount(@ast.Amount::new(difference, expected.currency))
  ctx.state
  .inventory_for(pad.source)
  .add_amount(@ast.Amount::new(difference.neg(), expected.currency))
}

///|
fn applicable_pad(ctx : Context, account : String, date : @ast.Date) -> Int32? {
  let mut result : Int32? = None
  for i in 0..<ctx.pads.length() {
    let pad = ctx.pads[i]
    if pad.account == account && !pad.consumed && pad.date.less_equal(date) {
      result = Some(i)
    }
  }
  result
}

///|
fn process_balance(
  ctx : Context,
  entry : @ast.Entry,
  balance : @ast.Balance,
) -> Unit {
  let info = check_account(ctx, balance.account, entry.date, entry.loc, false)
  match info {
    Some(info) =>
      if info.currencies.length() > 0 &&
        !info.currencies.contains(balance.amount.currency) {
        error(
          ctx,
          "validation.balance_currency",
          "Invalid currency '" +
          balance.amount.currency +
          "' for Balance directive",
          entry.loc,
        )
      }
    None => ()
  }
  let key = balance.account + "@" + entry.date.to_string()
  match ctx.balance_seen.get(key) {
    Some(previous) =>
      if previous.currency != balance.amount.currency ||
        !previous.number.equal(balance.amount.number) {
        error(
          ctx,
          "validation.duplicate_balance",
          "Duplicate balance assertion with different amounts",
          entry.loc,
        )
      }
    None => ()
  }
  ctx.balance_seen.set(key, balance.amount)
  let actual = accumulated_quantity(
    ctx,
    balance.account,
    balance.amount.currency,
  )
  let tolerance = balance_tolerance(ctx, balance)
  let difference = balance.amount.number.sub(actual)
  let pad_index = applicable_pad(ctx, balance.account, entry.date)
  match pad_index {
    Some(index) => {
      let pad = ctx.pads[index]
      if difference.abs().less_equal(tolerance) {
        // A pad is only consumed when it actually inserts a padding entry.
        return
      }
      pad.consumed = true
      ctx.pads[index] = pad
      insert_padding(ctx, pad, balance.amount, difference)
      return
    }
    None => ()
  }
  if difference.abs().less_equal(tolerance) {
    return
  }
  let direction = if difference.is_positive() {
    "too little"
  } else {
    "too much"
  }
  error(
    ctx,
    "validation.balance",
    "Balance failed for '" +
    balance.account +
    "': expected " +
    balance.amount.to_string() +
    " != accumulated " +
    actual.to_string() +
    " " +
    balance.amount.currency +
    " (" +
    difference.abs().to_string() +
    " " +
    direction +
    ")",
    entry.loc,
  )
}

///|
fn needs_cost_inference(spec : @ast.CostSpec) -> Bool {
  (spec.number_per is None && spec.number_total is None) ||
  spec.currency is None
}

///|
fn book_explicit(
  ctx : Context,
  entry : @ast.Entry,
  index : Int32,
  posting : @ast.Posting,
  weights : Array[@ast.Amount],
  booked : Map[Int32, Array[@ast.Posting]],
) -> Bool {
  let outcome = @booking.book_posting(
    ctx.state,
    posting.account,
    posting,
    entry.date,
    ctx.options.booking_method,
  )
  match outcome.issue {
    Some(issue) => {
      error(ctx, "validation.booking", issue.message, entry.loc)
      false
    }
    None =>
      if outcome.needs_inference {
        error(
          ctx,
          "validation.cost",
          "Failed to categorize posting " + (index + 1).to_string(),
          entry.loc,
        )
        false
      } else {
        if outcome.positions.length() > 0 {
          booked.set(
            index,
            outcome.positions.map(fn(position) {
              {
                ..posting,
                units: Some(position.units),
                cost: position.cost.map(fn(cost) {
                  @ast.CostSpec::new_per(
                    cost.number,
                    cost.currency,
                    cost.date,
                    cost.label,
                  )
                }),
              }
            }),
          )
        }
        for weight in outcome.weights {
          add_weight(weights, weight)
        }
        true
      }
  }
}

///|
fn infer_cost(
  ctx : Context,
  entry : @ast.Entry,
  index : Int32,
  posting : @ast.Posting,
  weights : Array[@ast.Amount],
) -> Unit {
  let units = match posting.units {
    Some(units) => units
    None => return
  }
  let spec = match posting.cost {
    Some(spec) => spec
    None => return
  }
  let currency = match spec.currency {
    Some(currency) => Some(currency)
    None => infer_currency(weights)
  }
  match currency {
    None =>
      error(
        ctx,
        "validation.cost",
        "Failed to categorize posting " + (index + 1).to_string(),
        entry.loc,
      )
    Some(currency) => {
      let number = match spec.number_per {
        Some(number) => Some(number)
        None =>
          match spec.number_total {
            Some(total) =>
              if units.number.is_zero() {
                None
              } else {
                total.div(units.number.abs())
              }
            None =>
              if units.number.is_zero() {
                None
              } else {
                weight_sum(weights, currency).neg().div(units.number)
              }
          }
      }
      match number {
        None =>
          error(
            ctx,
            "validation.cost",
            "Failed to categorize posting " + (index + 1).to_string(),
            entry.loc,
          )
        Some(number) => {
          let date = match spec.date {
            Some(date) => date
            None => entry.date
          }
          let cost = @ast.Cost::new(number, currency, Some(date), spec.label)
          posting.cost = Some(
            @ast.CostSpec::new_per(number, currency, Some(date), spec.label),
          )
          let booked = @booking.book_augmentation_with_cost(
            ctx.state,
            posting.account,
            units,
            cost,
            posting.price,
          )
          for weight in booked {
            add_weight(weights, weight)
          }
        }
      }
    }
  }
}

///|
fn interpolate_missing(
  ctx : Context,
  entry : @ast.Entry,
  posting : @ast.Posting,
  weights : Array[@ast.Amount],
) -> Unit {
  if posting.cost is Some(_) {
    error(
      ctx,
      "validation.cost",
      "Failed to categorize posting with a missing amount and a cost",
      entry.loc,
    )
    return
  }
  let currency = match posting.units_currency {
    Some(currency) => Some(currency)
    None => infer_currency(weights)
  }
  match currency {
    None =>
      error(
        ctx,
        "validation.missing",
        "Cannot infer the missing posting amount",
        entry.loc,
      )
    Some(currency) => {
      let amount = match posting.price {
        Some(price) =>
          match price {
            PerUnit(unit_price) => {
              let per = unit_price.number
              if per.is_zero() {
                @decimal.Decimal::zero()
              } else {
                match weight_sum(weights, unit_price.currency).neg().div(per) {
                  Some(value) => value
                  None => @decimal.Decimal::zero()
                }
              }
            }
            Total(_) => weight_sum(weights, currency).neg()
          }
        None => weight_sum(weights, currency).neg()
      }
      posting.units = Some(@ast.Amount::new(amount, currency))
      match posting.price {
        Some(price) =>
          match price {
            PerUnit(unit_price) =>
              add_weight(
                weights,
                @ast.Amount::new(
                  amount.mul(unit_price.number),
                  unit_price.currency,
                ),
              )
            Total(total) =>
              add_weight(
                weights,
                @ast.Amount::new(total.number, total.currency),
              )
          }
        None => add_weight(weights, @ast.Amount::new(amount, currency))
      }
    }
  }
}

///|
fn posting_tolerance(
  ctx : Context,
  postings : Array[@ast.Posting],
  currency : String,
) -> @decimal.Decimal {
  let mut tolerance = @decimal.Decimal::zero()
  for posting in postings {
    let units = match posting.units {
      Some(units) => units
      None => continue
    }
    if units.currency == currency && units.number.has_fractional_digits() {
      tolerance = larger(
        tolerance,
        units.number
        .last_digit_place()
        .abs()
        .mul(ctx.options.tolerance_multiplier),
      )
    }
    if ctx.options.infer_tolerance_from_cost {
      match posting.cost {
        Some(spec) =>
          match spec.number_per {
            Some(number) =>
              match spec.currency {
                Some(cost_currency) =>
                  if cost_currency == currency {
                    tolerance = larger(
                      tolerance,
                      number
                      .last_digit_place()
                      .abs()
                      .mul(units.number.abs())
                      .mul(ctx.options.tolerance_multiplier),
                    )
                  }
                None => ()
              }
            None =>
              match spec.number_total {
                Some(total) =>
                  match spec.currency {
                    Some(cost_currency) =>
                      if cost_currency == currency {
                        tolerance = larger(
                          tolerance,
                          total
                          .last_digit_place()
                          .abs()
                          .mul(ctx.options.tolerance_multiplier),
                        )
                      }
                    None => ()
                  }
                None => ()
              }
          }
        None => ()
      }
    }
  }
  match ctx.options.inferred_tolerance_default.get(currency) {
    Some(default) => larger(tolerance, default)
    None => tolerance
  }
}

///|
fn check_balanced(
  ctx : Context,
  entry : @ast.Entry,
  postings : Array[@ast.Posting],
  weights : Array[@ast.Amount],
) -> Unit {
  let totals = []
  for weight in weights {
    add_weight(totals, weight)
  }
  for total in totals {
    if total.number.is_zero() {
      continue
    }
    let tolerance = posting_tolerance(ctx, postings, total.currency)
    if total.number.abs().less_equal(tolerance) {
      continue
    }
    error(
      ctx,
      "validation.unbalanced",
      "Transaction does not balance: (" +
      total.number.to_string() +
      " " +
      total.currency +
      ")",
      entry.loc,
    )
  }
}

///|
fn add_currency(currencies : Array[String], currency : String) -> Unit {
  if currency == "" {
    return
  }
  if !currencies.contains(currency) {
    currencies.push(currency)
  }
}

///|
fn transaction_currencies(postings : Array[@ast.Posting]) -> Array[String] {
  let currencies : Array[String] = []
  for posting in postings {
    match posting.units {
      Some(units) => add_currency(currencies, units.currency)
      None => ()
    }
    match posting.units_currency {
      Some(currency) => add_currency(currencies, currency)
      None => ()
    }
    match posting.cost {
      Some(spec) =>
        match spec.currency {
          Some(currency) => add_currency(currencies, currency)
          None => ()
        }
      None => ()
    }
    match posting.price {
      Some(price) => add_currency(currencies, price.amount().currency)
      None => ()
    }
  }
  currencies
}

///|
/// Resolves postings written with a bare number and no currency. When the
/// transaction mentions exactly one currency it is applied to every such
/// posting; otherwise the transaction cannot be categorized.
fn resolve_missing_currencies(
  ctx : Context,
  entry : @ast.Entry,
  postings : Array[@ast.Posting],
) -> Bool {
  let missing : Array[Int32] = []
  for i in 0..<postings.length() {
    match postings[i].units {
      Some(units) => if units.currency == "" { missing.push(i) }
      None => ()
    }
  }
  if missing.length() == 0 {
    return true
  }
  let currencies = transaction_currencies(postings)
  if currencies.length() != 1 {
    let target = postings[missing[0]].loc
    let loc = if target.line > 0 { target } else { entry.loc }
    error(
      ctx,
      "validation.cost",
      "Failed to categorize posting " + (missing[0] + 1).to_string(),
      loc,
    )
    return false
  }
  for index in missing {
    let units = postings[index].units.unwrap()
    postings[index].units = Some(@ast.Amount::new(units.number, currencies[0]))
  }
  true
}

///|
fn process_transaction(
  ctx : Context,
  entry : @ast.Entry,
  txn : @ast.Transaction,
) -> Unit {
  let postings = txn.postings
  let booked : Map[Int32, Array[@ast.Posting]] = Map([])
  let mut booking_failed = !resolve_missing_currencies(ctx, entry, postings)
  for posting in postings {
    let info = check_account(ctx, posting.account, entry.date, entry.loc, true)
    match posting.units {
      Some(units) =>
        if units.currency != "" {
          check_currency(ctx, info, units.currency, entry.loc)
        }
      None => ()
    }
  }
  let weights : Array[@ast.Amount] = []
  let deferred : Array[Int32] = []
  let missing : Array[Int32] = []
  // Reductions are booked first so that augmentations in the same transaction
  // cannot change which lots are matched.
  for i in 0..<postings.length() {
    let posting = postings[i]
    match posting.units {
      Some(units) =>
        match posting.cost {
          Some(_) =>
            if units.number.is_negative() {
              if !book_explicit(ctx, entry, i, posting, weights, booked) {
                booking_failed = true
              }
            }
          None => ()
        }
      None => ()
    }
  }
  for i in 0..<postings.length() {
    let posting = postings[i]
    match posting.units {
      Some(units) =>
        match posting.cost {
          Some(spec) =>
            if !units.number.is_negative() {
              if needs_cost_inference(spec) {
                deferred.push(i)
              } else if !book_explicit(ctx, entry, i, posting, weights, booked) {
                booking_failed = true
              }
            }
          None =>
            if !book_explicit(ctx, entry, i, posting, weights, booked) {
              booking_failed = true
            }
        }
      None => missing.push(i)
    }
  }
  if deferred.length() > 1 {
    for index in deferred {
      let target = postings[index].loc
      let loc = if target.line > 0 { target } else { entry.loc }
      error(
        ctx,
        "validation.cost",
        "Failed to categorize posting " + (index + 1).to_string(),
        loc,
      )
    }
    booking_failed = true
  } else if deferred.length() == 1 {
    infer_cost(ctx, entry, deferred[0], postings[deferred[0]], weights)
  }
  if missing.length() > 1 {
    let last = missing[missing.length() - 1]
    let target = postings[last].loc
    let loc = if target.line > 0 { target } else { entry.loc }
    error(
      ctx, "validation.missing", "You may not have more than one auto-posting per currency",
      loc,
    )
    booking_failed = true
  } else if missing.length() == 1 {
    interpolate_missing(ctx, entry, postings[missing[0]], weights)
  }
  // A transaction whose postings cannot be booked is aborted before balancing,
  // matching Beancount's error precedence.
  if !booking_failed {
    check_balanced(ctx, entry, postings, weights)
    let detailed : Array[@ast.Posting] = []
    for i in 0..<postings.length() {
      match booked.get(i) {
        Some(parts) => detailed.append(parts)
        None => detailed.push(postings[i])
      }
    }
    postings.clear()
    postings.append(detailed)
  }
}

///|
/// Validates a parsed ledger and returns the bookable, ordered representation
/// used by reports and the query engine.
pub fn validate_ledger(ledger : @ast.Ledger) -> ValidatedLedger {
  let ctx = Context::new(ledger)
  for diagnostic in ledger.errors {
    ctx.errors.push(diagnostic)
  }
  for plugin in ledger.plugins {
    warning(
      ctx,
      "validation.plugin",
      "Plugin '" + plugin.name + "' is not supported and will be ignored",
      plugin.loc,
    )
  }
  for pair in ledger.options.raw {
    if pair.0 == "inferred_tolerance_multiplier" {
      warning(
        ctx,
        "validation.deprecated_option",
        "Renamed to 'tolerance_multiplier'.",
        @ast.Loc::new(ledger_file_name(ledger), 0),
      )
    }
  }
  let ordered = sorted_entries(ledger.entries)
  for entry in ordered {
    match entry.directive {
      DOpen(open) => process_open(ctx, entry, open)
      DClose(close) => process_close(ctx, entry, close)
      DPad(pad) => process_pad(ctx, entry, pad)
      DBalance(balance) => process_balance(ctx, entry, balance)
      DTransaction(txn) => process_transaction(ctx, entry, txn)
      DNote(note) =>
        check_account(ctx, note.account, entry.date, entry.loc, false) |> ignore
      DDocument(document) =>
        check_account(ctx, document.account, entry.date, entry.loc, false)
        |> ignore
      DCommodity(_) | DPrice(_) | DEvent(_) | DQuery(_) | DCustom(_) => ()
    }
    ctx.entries.push(entry)
  }
  for pad in ctx.pads {
    if !pad.consumed {
      error(ctx, "validation.pad", "Unused Pad entry", pad.loc)
    }
  }
  let entries = sorted_entries(ctx.entries)
  let accounts : Map[String, AccountInfo] = Map([])
  for name in ctx.accounts.keys().to_array() {
    match ctx.accounts.get(name) {
      Some(info) => accounts.set(name, info)
      None => ()
    }
  }
  {
    entries,
    errors: ctx.errors,
    warnings: ctx.warnings,
    options: ctx.options,
    plugins: ctx.plugins,
    accounts,
    state: ctx.state,
  }
}

///|
fn ledger_file_name(ledger : @ast.Ledger) -> String {
  if ledger.entries.length() > 0 {
    ledger.entries[0].loc.file
  } else {
    "<ledger>"
  }
}

///|
fn txn_signature(entry : @ast.Entry, txn : @ast.Transaction) -> String {
  let sb = StringBuilder()
  sb.write_string(entry.date.to_string())
  sb.write_string("|")
  sb.write_string(txn.flag)
  sb.write_string("|")
  match txn.payee {
    Some(payee) => sb.write_string(payee)
    None => ()
  }
  sb.write_string("|")
  sb.write_string(txn.narration)
  for tag in txn.tags {
    sb.write_string("|#")
    sb.write_string(tag)
  }
  for link in txn.links {
    sb.write_string("|^")
    sb.write_string(link)
  }
  for posting in txn.postings {
    sb.write_string("|")
    match posting.flag {
      Some(flag) => sb.write_string(flag)
      None => ()
    }
    sb.write_string(posting.account)
    match posting.units {
      Some(units) => {
        sb.write_string(" ")
        sb.write_string(units.number.to_string())
        sb.write_string(" ")
        sb.write_string(units.currency)
      }
      None => ()
    }
    match posting.cost {
      Some(cost) => {
        sb.write_string(" ")
        sb.write_string(cost.to_string())
      }
      None => ()
    }
    match posting.price {
      Some(price) => {
        sb.write_string(" ")
        sb.write_string(price.to_string())
      }
      None => ()
    }
  }
  sb.to_string()
}

///|
/// Finds exact duplicate transactions (same date, flag, narration, postings,
/// and so on).  This check is exposed separately because bean-check does not
/// report duplicates by default.
pub fn find_duplicate_transactions(
  entries : Array[@ast.Entry],
) -> Array[(@ast.Loc, @ast.Loc)] {
  let seen : Map[String, @ast.Loc] = Map([])
  let duplicates = []
  for entry in entries {
    match entry.directive {
      DTransaction(txn) => {
        let signature = txn_signature(entry, txn)
        match seen.get(signature) {
          Some(first) => duplicates.push((first, entry.loc))
          None => seen.set(signature, entry.loc)
        }
      }
      _ => ()
    }
  }
  duplicates
}
