// Realization: replay validated transactions into inventories up to a chosen
// date.  Validation has already resolved missing amounts and inferred costs,
// so a replay is deterministic and gives reports historical cost lots.

///|
pub(all) struct RealizedLedger {
  entries : Array[@ast.Entry]
  at : @ast.Date?
  options : @ast.Options
  inventories : Map[String, @booking.Inventory]
  accounts : Map[String, @validation.AccountInfo]
  prices : PriceDb
}

///|
fn entry_in_range(entry : @ast.Entry, at : @ast.Date?) -> Bool {
  match at {
    Some(date) => entry.date.less_equal(date)
    None => true
  }
}

///|
fn replay_book(
  state : @booking.BookingState,
  entry : @ast.Entry,
  posting : @ast.Posting,
  default_method : String,
) -> Unit {
  if posting.units is Some(_) {
    @booking.book_posting(
      state,
      posting.account,
      posting,
      entry.date,
      default_method,
    )
    |> ignore
  }
}

///|
fn replay_transaction(
  state : @booking.BookingState,
  entry : @ast.Entry,
  txn : @ast.Transaction,
  default_method : String,
) -> Unit {
  for posting in txn.postings {
    match posting.units {
      Some(units) =>
        match posting.cost {
          Some(_) =>
            if units.number.is_negative() {
              replay_book(state, entry, posting, default_method)
            }
          None => ()
        }
      None => ()
    }
  }
  for posting in txn.postings {
    match posting.units {
      Some(units) =>
        match posting.cost {
          Some(_) =>
            if !units.number.is_negative() {
              replay_book(state, entry, posting, default_method)
            }
          None => replay_book(state, entry, posting, default_method)
        }
      None => ()
    }
  }
}

///|
fn replay_inventories(
  ledger : @validation.ValidatedLedger,
  at : @ast.Date?,
) -> Map[String, @booking.Inventory] {
  let state = @booking.BookingState::new()
  for name in ledger.accounts.keys().to_array() {
    match ledger.accounts.get(name) {
      Some(info) =>
        match info.booking {
          Some(booking) => state.set_booking(name, booking)
          None => ()
        }
      None => ()
    }
  }
  for entry in ledger.entries {
    if entry_in_range(entry, at) {
      match entry.directive {
        DTransaction(txn) =>
          replay_transaction(state, entry, txn, ledger.options.booking_method)
        _ => ()
      }
    }
  }
  let inventories : Map[String, @booking.Inventory] = Map([])
  for name in state.accounts.keys().to_array() {
    match state.accounts.get(name) {
      Some(account) => inventories.set(name, account.inventory.copy())
      None => ()
    }
  }
  for name in ledger.accounts.keys().to_array() {
    if inventories.get(name) is None {
      inventories.set(name, @booking.Inventory::new())
    }
  }
  inventories
}

///|
/// Builds the realized view of a validated ledger, optionally stopping at a
/// date (balance assertions and other non-transaction directives are kept for
/// querying, but only transactions affect inventories).
pub fn realize(
  ledger : @validation.ValidatedLedger,
  at~ : @ast.Date? = None,
) -> RealizedLedger {
  let entries = []
  for entry in ledger.entries {
    if entry_in_range(entry, at) {
      entries.push(entry)
    }
  }
  {
    entries,
    at,
    options: ledger.options,
    inventories: replay_inventories(ledger, at),
    accounts: ledger.accounts,
    prices: PriceDb::from_entries(entries),
  }
}

///|
pub fn RealizedLedger::inventory(
  self : RealizedLedger,
  account : String,
) -> @booking.Inventory {
  match self.inventories.get(account) {
    Some(inventory) => inventory.copy()
    None => @booking.Inventory::new()
  }
}

///|
pub fn RealizedLedger::account_names(self : RealizedLedger) -> Array[String] {
  let names = self.inventories.keys().to_array()
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
pub fn is_subaccount(name : String, parent : String) -> Bool {
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
/// Direct inventory of an account, or the combined inventory of the account
/// and all of its subaccounts when `subtree` is true.
pub fn RealizedLedger::combined_inventory(
  self : RealizedLedger,
  account : String,
  subtree~ : Bool = false,
) -> @booking.Inventory {
  let result = @booking.Inventory::new()
  for name in self.account_names() {
    if name == account || (subtree && is_subaccount(name, account)) {
      match self.inventories.get(name) {
        Some(inventory) =>
          for position in inventory.positions {
            result.add(position)
          }
        None => ()
      }
    }
  }
  result
}

///|
pub fn RealizedLedger::rate(
  self : RealizedLedger,
  base : String,
  quote : String,
) -> @decimal.Decimal? {
  self.prices.rate(base, quote, self.at)
}

///|
pub fn RealizedLedger::convert(
  self : RealizedLedger,
  amount : @ast.Amount,
  target : String,
) -> @ast.Amount? {
  self.prices.convert(amount, target, self.at)
}
