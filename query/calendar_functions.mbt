///|
fn calendar_function(ctx : QueryContext, name : String, part : String, date : @ast.Date) -> QueryValue {
  let day = ordinal(date)
  let weekday = (day - 1) % 7
  if name == "date_part" {
    match part {
      "year" => query_int(date.year)
      "month" => query_int(date.month)
      "quarter" => query_int((date.month - 1) / 3 + 1)
      "dow" => query_int(weekday)
      "isodow" => query_int(weekday + 1)
      "decade" => query_int(date.year / 10)
      "century" => query_int((date.year - 1) / 100 + 1)
      "millennium" => query_int((date.year - 1) / 1000 + 1)
      "epoch" => QInt(@bigint.BigInt::from_int(day - 719163).mul(@bigint.BigInt::from_int(86400)))
      "week" => {
        let thursday = day + 3 - weekday
        let year = match ordinal_date(thursday) { QDate(d) => d.year; _ => date.year }
        let jan4 = ordinal(@ast.Date::new(year, 1, 4).unwrap())
        query_int((day - (jan4 - (jan4 - 1) % 7)) / 7 + 1)
      }
      _ => QNull
    }
  } else {
    let (year, month, dom) = match part {
      "year" => (date.year, 1, 1)
      "month" => (date.year, date.month, 1)
      "quarter" => (date.year, (date.month - 1) / 3 * 3 + 1, 1)
      "decade" => (date.year / 10 * 10, 1, 1)
      "century" => ((date.year - 1) / 100 * 100 + 1, 1, 1)
      "millennium" => ((date.year - 1) / 1000 * 1000 + 1, 1, 1)
      "week" => return ordinal_date(day - weekday)
      _ => return QNull
    }
    match @ast.Date::new(year, month, dom) {
      Some(d) => QDate(d)
      None => { query_error(ctx, "query.oracle_type_error: ValueError date out of range"); QNull }
    }
  }
}
