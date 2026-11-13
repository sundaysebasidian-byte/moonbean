///|
fn system_date_number(milliseconds : UInt64) -> Int32 {
  match ordinal_date((milliseconds / 86400000UL).to_int() + 719163) {
    QDate(d) => d.year * 10000 + d.month * 100 + d.day
    _ => 0
  }
}
