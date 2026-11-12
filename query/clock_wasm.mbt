///|
fn local_date_number() -> Int32 {
  // The MoonBit wasm host exposes epoch milliseconds, with no timezone API.
  match ordinal_date((@env.now() / 86400000UL).to_int() + 719163) {
    QDate(d) => d.year * 10000 + d.month * 100 + d.day
    _ => 0
  }
}
