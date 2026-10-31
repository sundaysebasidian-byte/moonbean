// Cost basis inventories.  A position is a number of units of one currency
// augmented with an optional cost basis, mirroring Beancount's inventory model.

///|
pub(all) struct Position {
  units : @ast.Amount
  cost : @ast.Cost?
}

///|
pub fn Position::new(units : @ast.Amount, cost : @ast.Cost?) -> Position {
  { units, cost, }
}

///|
pub fn Position::to_string(self : Position) -> String {
  match self.cost {
    Some(cost) => self.units.to_string() + " " + cost.to_string()
    None => self.units.to_string()
  }
}

///|
fn cost_same(a : @ast.Cost?, b : @ast.Cost?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(ca), Some(cb)) => {
      if !ca.number.equal(cb.number) || ca.currency != cb.currency {
        return false
      }
      let date_same = match (ca.date, cb.date) {
        (None, None) => true
        (Some(da), Some(db)) => da.equal(db)
        _ => false
      }
      if !date_same {
        return false
      }
      match (ca.label, cb.label) {
        (None, None) => true
        (Some(la), Some(lb)) => la == lb
        _ => false
      }
    }
    _ => false
  }
}

///|
pub(all) struct Inventory {
  positions : Array[Position]
}

///|
pub fn Inventory::new() -> Inventory {
  { positions: [], }
}

///|
pub fn Inventory::is_empty(self : Inventory) -> Bool {
  self.positions.length() == 0
}

///|
pub fn Inventory::quantity(
  self : Inventory,
  currency : String,
) -> @decimal.Decimal {
  let mut total = @decimal.Decimal::zero()
  for position in self.positions {
    if position.units.currency == currency {
      total = total.add(position.units.number)
    }
  }
  total
}

///|
pub fn Inventory::currencies(self : Inventory) -> Array[String] {
  let result = []
  for position in self.positions {
    if !result.contains(position.units.currency) {
      result.push(position.units.currency)
    }
  }
  result
}

///|
pub fn Inventory::add(self : Inventory, position : Position) -> Unit {
  for i in 0..<self.positions.length() {
    let existing = self.positions[i]
    if existing.units.currency == position.units.currency &&
      cost_same(existing.cost, position.cost) {
      let total = existing.units.number.add(position.units.number)
      if total.is_zero() {
        self.positions.remove(i) |> ignore
      } else {
        self.positions[i] = {
          units: @ast.Amount::new(total, existing.units.currency),
          cost: existing.cost,
        }
      }
      return
    }
  }
  if !position.units.number.is_zero() {
    self.positions.push(position)
  }
}

///|
pub fn Inventory::add_amount(self : Inventory, amount : @ast.Amount) -> Unit {
  self.add({ units: amount, cost: None, })
}

///|
pub fn Inventory::remove_at(self : Inventory, index : Int32) -> Unit {
  if index >= 0 && index < self.positions.length() {
    self.positions.remove(index) |> ignore
  }
}

///|
pub fn Inventory::copy(self : Inventory) -> Inventory {
  { positions: self.positions.copy(), }
}

///|
pub fn Inventory::to_string(self : Inventory) -> String {
  if self.positions.length() == 0 {
    return "(empty)"
  }
  let sb = StringBuilder()
  let mut first = true
  for position in self.positions {
    if !first {
      sb.write_string(", ")
    }
    sb.write_string(position.to_string())
    first = false
  }
  sb.to_string()
}

///|
pub fn Inventory::average_cost(
  self : Inventory,
  currency : String,
) -> @ast.Cost? {
  let mut units = @decimal.Decimal::zero()
  let mut total_cost = @decimal.Decimal::zero()
  let mut cost_currency : String? = None
  let mut label : String? = None
  for position in self.positions {
    if position.units.currency == currency {
      match position.cost {
        Some(cost) => {
          units = units.add(position.units.number)
          total_cost = total_cost.add(position.units.number.mul(cost.number))
          cost_currency = Some(cost.currency)
          if label is None {
            label = cost.label
          }
        }
        None => ()
      }
    }
  }
  if units.is_zero() {
    return None
  }
  match cost_currency {
    Some(currency) =>
      match total_cost.div(units) {
        Some(per) => Some(@ast.Cost::new(per, currency, None, label))
        None => None
      }
    None => None
  }
}

///|
pub(all) struct AccountInventory {
  inventory : Inventory
  booking : String?
}

///|
pub(all) struct BookingState {
  accounts : Map[String, AccountInventory]
}

///|
pub fn BookingState::new() -> BookingState {
  { accounts: {}, }
}

///|
pub fn BookingState::set_booking(
  self : BookingState,
  account : String,
  booking : String,
) -> Unit {
  match self.accounts.get(account) {
    Some(state) =>
      self.accounts.set(account, {
        inventory: state.inventory,
        booking: Some(booking),
      })
    None =>
      self.accounts.set(account, {
        inventory: Inventory::new(),
        booking: Some(booking),
      })
  }
}

///|
pub fn BookingState::inventory_for(
  self : BookingState,
  account : String,
) -> Inventory {
  match self.accounts.get(account) {
    Some(state) => state.inventory
    None => {
      let inventory = Inventory::new()
      self.accounts.set(account, { inventory, booking: None, })
      inventory
    }
  }
}

///|
pub fn BookingState::inventory(
  self : BookingState,
  account : String,
) -> Inventory? {
  match self.accounts.get(account) {
    Some(state) => Some(state.inventory)
    None => None
  }
}

///|
pub fn BookingState::method_for(
  self : BookingState,
  account : String,
  default_method : String,
) -> String {
  match self.accounts.get(account) {
    Some(state) =>
      match state.booking {
        Some(booking) => booking
        None => default_method
      }
    None => default_method
  }
}

///|
pub fn BookingState::accounts_list(self : BookingState) -> Array[String] {
  self.accounts.keys().to_array()
}
