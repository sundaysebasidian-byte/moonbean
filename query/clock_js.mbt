///|
extern "js" fn local_date_from_milliseconds(milliseconds : Double) -> Int32 =
  #| ms => { const d = new Date(ms); return d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate(); }

///|
fn local_date_number() -> Int32 {
  local_date_from_milliseconds(@env.now().to_double())
}
