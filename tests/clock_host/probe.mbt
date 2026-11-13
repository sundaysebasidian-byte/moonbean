///|
pub fn install() -> Unit {
  @host_clock.install()
}

///|
pub fn probe() -> String {
  let ledger = @moonbean.check_source(
    "clock.bean", "2024-01-01 open Assets:A USD\n2024-01-01 open Equity:A USD\n2024-01-02 * \"clock\"\n  Assets:A 1 USD\n  Equity:A -1 USD\n",
  )
  @moonbean.run_query(
    ledger, "SELECT today(),parse_date('March'),parse_date('50-06-15') LIMIT 1",
  ).to_json()
}
