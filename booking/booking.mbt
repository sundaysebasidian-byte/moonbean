// Lots and booking.  A posting without a cost clause is a plain currency
// position: it is never matched against cost basis lots.  A posting with `{}`
// (or another cost clause) is booked against the inventory, and reductions are
// resolved with the account's booking method.

///|
pub(all) struct BookingIssue {
  code : String
  message : String
}

///|
pub fn BookingIssue::new(code : String, message : String) -> BookingIssue {
  { code, message, }
}

///|
pub(all) struct BookingOutcome {
  weights : Array[@ast.Amount]
  issue : BookingIssue?
  needs_inference : Bool
}

///|
fn outcome_ok(weights : Array[@ast.Amount]) -> BookingOutcome {
  { weights, issue: None, needs_inference: false, }
}

///|
fn outcome_issue(code : String, message : String) -> BookingOutcome {
  {
    weights: [],
    issue: Some(BookingIssue::new(code, message)),
    needs_inference: false,
  }
}

///|
fn needs_inference_outcome() -> BookingOutcome {
  { weights: [], issue: None, needs_inference: true, }
}

///|
fn price_weight(
  units : @decimal.Decimal,
  price : @ast.PriceAnno,
) -> @ast.Amount {
  match price {
    PerUnit(amount) =>
      @ast.Amount::new(units.mul(amount.number), amount.currency)
    Total(amount) => {
      let sign = if units.signum() < 0 { -1 } else { 1 }
      @ast.Amount::new(
        amount.number.mul(@decimal.Decimal::from_int(sign)),
        amount.currency,
      )
    }
  }
}

///|
fn cost_weight(units : @decimal.Decimal, cost : @ast.Cost) -> @ast.Amount {
  @ast.Amount::new(units.mul(cost.number), cost.currency)
}

///|
fn spec_has_number(spec : @ast.CostSpec) -> Bool {
  spec.number_per is Some(_) || spec.number_total is Some(_)
}

///|
fn spec_number_per(
  spec : @ast.CostSpec,
  need : @decimal.Decimal,
) -> @decimal.Decimal? {
  match spec.number_per {
    Some(number) => Some(number)
    None =>
      match spec.number_total {
        Some(total) => if need.is_zero() { None } else { total.div(need) }
        None => None
      }
  }
}

///|
fn date_equal(a : @ast.Date?, b : @ast.Date?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => x.equal(y)
    _ => false
  }
}

///|
fn label_equal(a : String?, b : String?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => x == y
    _ => false
  }
}

///|
fn cost_matches_spec(
  cost : @ast.Cost?,
  spec : @ast.CostSpec,
  need : @decimal.Decimal,
) -> Bool {
  let target = spec_number_per(spec, need)
  match cost {
    None =>
      target is None &&
      spec.currency is None &&
      spec.date is None &&
      spec.label is None
    Some(c) => {
      let number_ok = match target {
        Some(number) => c.number.equal(number)
        None => true
      }
      let currency_ok = match spec.currency {
        Some(currency) => c.currency == currency
        None => true
      }
      let date_ok = match spec.date {
        Some(d) => date_equal(c.date, Some(d))
        None => true
      }
      let label_ok = match spec.label {
        Some(l) => label_equal(c.label, Some(l))
        None => true
      }
      number_ok && currency_ok && date_ok && label_ok
    }
  }
}

///|
fn cost_date(cost : @ast.Cost?) -> @ast.Date? {
  match cost {
    Some(c) => c.date
    None => None
  }
}

///|
fn compare_optional_date(a : @ast.Date?, b : @ast.Date?) -> Int32 {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => x.compare(y)
  }
}

///|
fn cost_number(cost : @ast.Cost?) -> @decimal.Decimal {
  match cost {
    Some(c) => c.number
    None => @decimal.Decimal::zero()
  }
}

///|
fn sorted_candidates(
  inv : Inventory,
  candidates : Array[Int32],
  booking : String,
) -> Array[Int32] {
  let result = candidates.copy()
  let mut i = 1
  while i < result.length() {
    let current = result[i]
    let mut j = i
    while j > 0 {
      let prev = result[j - 1]
      let prev_pos = inv.positions[prev]
      let cur_pos = inv.positions[current]
      let mut swap = false
      if booking == "LIFO" {
        swap = compare_optional_date(
            cost_date(prev_pos.cost),
            cost_date(cur_pos.cost),
          ) <
          0
      } else if booking == "HIFO" {
        let cmp = cost_number(prev_pos.cost).compare(cost_number(cur_pos.cost))
        if cmp < 0 {
          swap = true
        } else if cmp == 0 {
          swap = compare_optional_date(
              cost_date(prev_pos.cost),
              cost_date(cur_pos.cost),
            ) >
            0
        }
      } else {
        swap = compare_optional_date(
            cost_date(prev_pos.cost),
            cost_date(cur_pos.cost),
          ) >
          0
      }
      if swap {
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
fn min_decimal(a : @decimal.Decimal, b : @decimal.Decimal) -> @decimal.Decimal {
  if a.less_equal(b) {
    a
  } else {
    b
  }
}

///|
fn posting_label(posting : @ast.Posting) -> String {
  match posting.units {
    Some(units) => units.to_string()
    None => posting.account
  }
}

///|
fn select_lots(
  inv : Inventory,
  need : @decimal.Decimal,
  currency : String,
  spec : @ast.CostSpec,
  booking : String,
  posting : @ast.Posting,
) -> (Array[(Int32, @decimal.Decimal)], BookingIssue?) {
  let candidates = []
  for i in 0..<inv.positions.length() {
    let position = inv.positions[i]
    if position.units.currency == currency &&
      cost_matches_spec(position.cost, spec, need) {
      candidates.push(i)
    }
  }
  let label = posting_label(posting) + " {}"
  let inventory_text = inv.to_string()
  if candidates.length() == 0 {
    return (
      [],
      Some(
        BookingIssue::new(
          "booking.no_match",
          "No position matches \"" + label + "\": " + inventory_text,
        ),
      ),
    )
  }
  let plan = []
  if booking == "STRICT" {
    if candidates.length() > 1 {
      return (
        [],
        Some(
          BookingIssue::new(
            "booking.ambiguous",
            "Ambiguous matches for \"" + label + "\": " + inventory_text,
          ),
        ),
      )
    }
    let index = candidates[0]
    let available = inv.positions[index].units.number
    if available.less_than(need) {
      return (
        [],
        Some(
          BookingIssue::new(
            "booking.insufficient",
            "Not enough lots to reduce \"" + label + "\": " + inventory_text,
          ),
        ),
      )
    }
    plan.push((index, need))
    return (plan, None)
  }
  if booking == "STRICT_WITH_SIZE" {
    let mut exact = None
    for index in candidates {
      if inv.positions[index].units.number.equal(need) && exact is None {
        exact = Some(index)
      }
    }
    match exact {
      Some(index) => {
        plan.push((index, need))
        return (plan, None)
      }
      None =>
        if candidates.length() == 1 {
          let index = candidates[0]
          if inv.positions[index].units.number.less_than(need) {
            return (
              [],
              Some(
                BookingIssue::new(
                  "booking.insufficient",
                  "Not enough lots to reduce \"" +
                  label +
                  "\": " +
                  inventory_text,
                ),
              ),
            )
          }
          plan.push((index, need))
          return (plan, None)
        } else {
          return (
            [],
            Some(
              BookingIssue::new(
                "booking.ambiguous",
                "Ambiguous matches for \"" + label + "\": " + inventory_text,
              ),
            ),
          )
        }
    }
  }
  let sorted = sorted_candidates(inv, candidates, booking)
  let mut remaining = need
  for index in sorted {
    if remaining.is_zero() {
      break
    }
    let available = inv.positions[index].units.number
    if available.is_positive() {
      let take = min_decimal(remaining, available)
      plan.push((index, take))
      remaining = remaining.sub(take)
    }
  }
  if !remaining.is_zero() {
    return (
      [],
      Some(
        BookingIssue::new(
          "booking.insufficient",
          "Not enough lots to reduce \"" + label + "\": " + inventory_text,
        ),
      ),
    )
  }
  (plan, None)
}

///|
fn apply_plan(inv : Inventory, plan : Array[(Int32, @decimal.Decimal)]) -> Unit {
  if plan.length() == 0 {
    return
  }
  let old_positions = inv.positions.copy()
  inv.positions.clear()
  for i in 0..<old_positions.length() {
    let position = old_positions[i]
    let mut consumed = @decimal.Decimal::zero()
    for entry in plan {
      if entry.0 == i {
        consumed = entry.1
      }
    }
    let remaining = position.units.number.sub(consumed)
    if !remaining.is_zero() {
      inv.positions.push({
        units: @ast.Amount::new(remaining, position.units.currency),
        cost: position.cost,
      })
    }
  }
}

///|
fn add_weights(target : Array[@ast.Amount], amount : @ast.Amount) -> Unit {
  if amount.number.is_zero() && target.length() > 0 {
    // Still record zero weights: they carry currency information used by
    // cost inference.
  }
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
fn plan_weights(
  inv : Inventory,
  plan : Array[(Int32, @decimal.Decimal)],
  units_currency : String,
  price : @ast.PriceAnno?,
  average : @ast.Cost?,
) -> Array[@ast.Amount] {
  let weights = []
  match average {
    Some(cost) => {
      let mut total = @decimal.Decimal::zero()
      for entry in plan {
        total = total.add(entry.1)
      }
      add_weights(weights, cost_weight(total, cost))
    }
    None =>
      for entry in plan {
        let position = inv.positions[entry.0]
        match position.cost {
          Some(cost) => add_weights(weights, cost_weight(entry.1, cost))
          None =>
            match price {
              Some(price_anno) =>
                add_weights(weights, price_weight(entry.1, price_anno))
              None =>
                add_weights(weights, @ast.Amount::new(entry.1, units_currency))
            }
        }
      }
  }
  weights
}

///|
fn negate_weights(weights : Array[@ast.Amount]) -> Array[@ast.Amount] {
  let result = []
  for weight in weights {
    result.push(@ast.Amount::new(weight.number.neg(), weight.currency))
  }
  result
}

///|
fn resolve_cost(
  spec : @ast.CostSpec,
  units : @ast.Amount,
  txn_date : @ast.Date,
) -> @ast.Cost? {
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
        None => None
      }
  }
  match number {
    Some(number) =>
      match spec.currency {
        Some(currency) => {
          let date = match spec.date {
            Some(d) => d
            None => txn_date
          }
          Some(@ast.Cost::new(number, currency, Some(date), spec.label))
        }
        None => None
      }
    None => None
  }
}

///|
fn book_augmentation(
  state : BookingState,
  account : String,
  units : @ast.Amount,
  cost : @ast.Cost,
  price : @ast.PriceAnno?,
) -> Array[@ast.Amount] {
  let inv = state.inventory_for(account)
  inv.add({ units, cost: Some(cost), })
  if state.method_for(account, "") == "AVERAGE" {
    inv.merge_average(units.currency)
  }
  let weights = []
  add_weights(weights, cost_weight(units.number, cost))
  let _ = price
  weights
}

///|
pub fn book_augmentation_with_cost(
  state : BookingState,
  account : String,
  units : @ast.Amount,
  cost : @ast.Cost,
  price : @ast.PriceAnno?,
) -> Array[@ast.Amount] {
  book_augmentation(state, account, units, cost, price)
}

///|
fn reduce_with_average(
  inv : Inventory,
  units : @ast.Amount,
  posting : @ast.Posting,
) -> BookingOutcome {
  let need = units.number.abs()
  let average = inv.average_cost(units.currency)
  match average {
    None =>
      outcome_issue(
        "booking.no_match",
        "No position matches \"" +
        posting_label(posting) +
        " {}: " +
        inv.to_string(),
      )
    Some(cost) => {
      let candidates = []
      for i in 0..<inv.positions.length() {
        if inv.positions[i].units.currency == units.currency &&
          inv.positions[i].units.number.is_positive() {
          candidates.push(i)
        }
      }
      let plan = []
      let mut remaining = need
      for index in candidates {
        if remaining.is_zero() {
          break
        }
        let take = min_decimal(remaining, inv.positions[index].units.number)
        plan.push((index, take))
        remaining = remaining.sub(take)
      }
      if !remaining.is_zero() {
        return outcome_issue(
          "booking.insufficient",
          "Not enough lots to reduce \"" +
          posting_label(posting) +
          " {}: " +
          inv.to_string(),
        )
      }
      let weights = plan_weights(
        inv,
        plan,
        units.currency,
        posting.price,
        Some(cost),
      )
      apply_plan(inv, plan)
      outcome_ok(negate_weights(weights))
    }
  }
}

///|
pub fn book_posting(
  state : BookingState,
  account : String,
  posting : @ast.Posting,
  txn_date : @ast.Date,
  default_method : String,
) -> BookingOutcome {
  let units = match posting.units {
    Some(units) => units
    None => return outcome_ok([])
  }
  let inv = state.inventory_for(account)
  match posting.cost {
    None => {
      inv.add({ units, cost: None, })
      let weights = []
      match posting.price {
        Some(price) => add_weights(weights, price_weight(units.number, price))
        None => add_weights(weights, units)
      }
      outcome_ok(weights)
    }
    Some(spec) =>
      if units.number.signum() >= 0 {
        let cost = resolve_cost(spec, units, txn_date)
        match cost {
          Some(cost) =>
            outcome_ok(
              book_augmentation(state, account, units, cost, posting.price),
            )
          None =>
            if spec_has_number(spec) && spec.currency is Some(_) {
              outcome_issue(
                "booking.cost",
                "could not resolve cost for " + posting_label(posting),
              )
            } else {
              needs_inference_outcome()
            }
        }
      } else {
        let booking = if spec.merge {
          // `{*}` merges every costed lot into one held at average cost and
          // then reduces that single averaged position.
          inv.merge_average(units.currency)
          "AVERAGE"
        } else {
          state.method_for(account, default_method)
        }
        if booking == "NONE" {
          let resolved = resolve_cost(spec, units, txn_date)
          match resolved {
            Some(cost) => {
              inv.add({ units, cost: Some(cost), })
              let weights = []
              add_weights(weights, cost_weight(units.number, cost))
              outcome_ok(weights)
            }
            None => {
              inv.add({ units, cost: None, })
              let weights = []
              match posting.price {
                Some(price) =>
                  add_weights(weights, price_weight(units.number, price))
                None => add_weights(weights, units)
              }
              outcome_ok(weights)
            }
          }
        } else if booking == "AVERAGE" {
          reduce_with_average(inv, units, posting)
        } else {
          let need = units.number.abs()
          let (plan, issue) = select_lots(
            inv,
            need,
            units.currency,
            spec,
            booking,
            posting,
          )
          match issue {
            Some(issue) =>
              { weights: [], issue: Some(issue), needs_inference: false, }
            None => {
              let weights = plan_weights(
                inv,
                plan,
                units.currency,
                posting.price,
                None,
              )
              apply_plan(inv, plan)
              outcome_ok(negate_weights(weights))
            }
          }
        }
      }
  }
}
