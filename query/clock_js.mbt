///|
extern "js" fn local_date_from_milliseconds(milliseconds : Double) -> Int32 =
  #| ms => { const d = new Date(ms); return d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate(); }

///|
fn system_date_number(milliseconds : UInt64) -> Int32 {
  local_date_from_milliseconds(milliseconds.to_double())
}
