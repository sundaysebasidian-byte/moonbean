///|
extern "c" fn local_date_from_seconds(seconds : Int64) -> Int32 = "moonbean_local_date"

///|
fn local_date_number() -> Int32 {
  local_date_from_seconds((@env.now() / 1000UL).reinterpret_as_int64())
}
