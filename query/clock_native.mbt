///|
extern "c" fn local_date_from_seconds(seconds : Int64) -> Int32 = "moonbean_local_date"

///|
fn system_date_number(milliseconds : UInt64) -> Int32 {
  local_date_from_seconds((milliseconds / 1000UL).reinterpret_as_int64())
}
