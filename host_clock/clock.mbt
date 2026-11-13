///|
/// Opt into the moonbean:clock.local_date(f64) -> i32 WebAssembly import.
/// Hosts return YYYYMMDD, or zero to use UTC. Native/JS keep their local clock.
/// Supply host_clock/imports.mjs when instantiating a JS-hosted Wasm module.
pub fn install() -> Unit {
  @query.set_local_date_provider(Some(host_local_date))
}
