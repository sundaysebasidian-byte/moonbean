///|
fn aggregate_precedes(
  ctx : QueryContext,
  a : QueryValue,
  b : QueryValue,
  maximum : Bool,
) -> Bool {
  match (a, b) {
    (QSet(a) | QFrozenSet(a), QSet(b) | QFrozenSet(b)) =>
      if maximum {
        b.length() < a.length() && b.all(fn(v) { a.contains(v) })
      } else {
        a.length() < b.length() && a.all(fn(v) { b.contains(v) })
      }
    (QDict(_), QDict(_)) | (QInventory(_), QInventory(_)) => {
      query_error(ctx, "query.oracle_type_error: TypeError object ordering")
      false
    }
    (QAmount(a), QAmount(b)) => {
      let currency = a.currency.lexical_compare(b.currency)
      let number = a.number.compare(b.number)
      if maximum {
        number > 0 || (number == 0 && currency > 0)
      } else {
        currency < 0 || (currency == 0 && number < 0)
      }
    }
    (QPosition(a), QPosition(b)) => {
      if !maximum {
        return position_sort_compare(a, b) < 0
      }
      let number = a.units.number.compare(b.units.number)
      let currency = a.units.currency.lexical_compare(b.units.currency)
      if number != 0 || currency != 0 {
        let n = if number != 0 { number } else { currency }
        return if maximum { n > 0 } else { n < 0 }
      }
      let cost = match (a.cost, b.cost) {
        (None, None) => 0
        (None, Some(_)) => {
          if maximum {
            query_error(ctx, "query.oracle_type_error: TypeError None and Cost")
          }
          -1
        }
        (Some(_), None) => {
          if maximum {
            query_error(ctx, "query.oracle_type_error: TypeError Cost and None")
          }
          1
        }
        (Some(a), Some(b)) => {
          let number = a.number.compare(b.number)
          let currency = a.currency.lexical_compare(b.currency)
          if number != 0 {
            number
          } else if currency != 0 {
            currency
          } else {
            let date = match (a.date, b.date) {
              (Some(a), Some(b)) => a.compare(b)
              (None, None) => 0
              _ => {
                query_error(
                  ctx, "query.oracle_type_error: TypeError None and date",
                )
                0
              }
            }
            if date != 0 {
              date
            } else {
              match (a.label, b.label) {
                (Some(a), Some(b)) => python_text_compare(a, b)
                (None, None) => 0
                _ => {
                  query_error(
                    ctx, "query.oracle_type_error: TypeError None and str",
                  )
                  0
                }
              }
            }
          }
        }
      }
      if maximum {
        cost > 0
      } else {
        cost < 0
      }
    }
    _ =>
      match typed_compare(ctx, a, b) {
        Some(n) => if maximum { n > 0 } else { n < 0 }
        None => {
          query_error(ctx, "query.oracle_type_error: TypeError object ordering")
          false
        }
      }
  }
}
