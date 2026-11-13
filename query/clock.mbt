///|
let local_date_provider : Ref[((Double) -> Int32)?] = { val: None, }

///|
/// Install a host calendar callback taking Unix epoch milliseconds and returning
/// YYYYMMDD. None, zero or an invalid date uses the target's default calendar
/// (UTC on WebAssembly). The callback is consulted on every clock read.
pub fn set_local_date_provider(provider : ((Double) -> Int32)?) -> Unit {
  local_date_provider.val = provider
}

///|
fn local_date_number() -> Int32 {
  let milliseconds = @env.now()
  if local_date_provider.val is Some(provider) {
    let date = provider(milliseconds.to_double())
    if @ast.Date::new(date / 10000, date / 100 % 100, date % 100) is Some(_) {
      return date
    }
  }
  system_date_number(milliseconds)
}
