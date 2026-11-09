// Core data model for moonbean, kept independent from parsing and booking so
// that native, wasm-gc and js builds share the same representation.

///|
pub(all) struct Loc {
  file : String
  line : Int32
}

///|
pub fn Loc::new(file : String, line : Int32) -> Loc {
  { file, line, }
}

///|
pub fn Loc::to_string(self : Loc) -> String {
  self.file + ":" + self.line.to_string()
}

///|
pub(all) struct Diagnostic {
  code : String
  message : String
  loc : Loc
}

///|
pub fn Diagnostic::new(
  code : String,
  message : String,
  loc : Loc,
) -> Diagnostic {
  { code, message, loc, }
}

///|
pub fn Diagnostic::to_string(self : Diagnostic) -> String {
  self.loc.to_string() + ": " + self.message
}

///|
pub(all) enum MetaValue {
  MString(String)
  MNumber(@decimal.Decimal)
  MDate(Date)
  MAccount(String)
  MCurrency(String)
  MTag(String)
  MBool(Bool)
}

///|
pub fn MetaValue::to_string(self : MetaValue) -> String {
  match self {
    MString(s) => "\"" + s.replace_all(old="\"", new="\\\"") + "\""
    MNumber(n) => n.to_string()
    MDate(d) => d.to_string()
    MAccount(a) => a
    MCurrency(c) => c
    MTag(t) => "#" + t
    MBool(b) => if b { "TRUE" } else { "FALSE" }
  }
}

///|
pub(all) struct Meta {
  entries : Array[(String, MetaValue)]
}

///|
pub fn Meta::new() -> Meta {
  { entries: [], }
}

///|
pub fn Meta::is_empty(self : Meta) -> Bool {
  self.entries.length() == 0
}

///|
pub fn Meta::get(self : Meta, key : String) -> MetaValue? {
  for entry in self.entries {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
pub fn Meta::has(self : Meta, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
pub fn Meta::set(self : Meta, key : String, value : MetaValue) -> Unit {
  let mut replaced = false
  for i in 0..<self.entries.length() {
    if self.entries[i].0 == key {
      self.entries[i] = (key, value)
      replaced = true
    }
  }
  if !replaced {
    self.entries.push((key, value))
  }
}

///|
pub fn Meta::remove(self : Meta, key : String) -> Unit {
  let kept = []
  for entry in self.entries {
    if entry.0 != key {
      kept.push(entry)
    }
  }
  self.entries.clear()
  for entry in kept {
    self.entries.push(entry)
  }
}

///|
pub fn Meta::copy(self : Meta) -> Meta {
  { entries: self.entries.copy(), }
}

///|
pub(all) struct Amount {
  number : @decimal.Decimal
  currency : String
}

///|
pub fn Amount::new(number : @decimal.Decimal, currency : String) -> Amount {
  { number, currency, }
}

///|
pub fn Amount::to_string(self : Amount) -> String {
  self.number.to_string() + " " + self.currency
}

///|
pub(all) struct Cost {
  number : @decimal.Decimal
  currency : String
  date : Date?
  label : String?
}

///|
pub fn Cost::new(
  number : @decimal.Decimal,
  currency : String,
  date : Date?,
  label : String?,
) -> Cost {
  { number, currency, date, label, }
}

///|
pub fn Cost::to_string(self : Cost) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  sb.write_string(self.number.to_string())
  sb.write_string(" ")
  sb.write_string(self.currency)
  if self.date is Some(d) {
    sb.write_string(", ")
    sb.write_string(d.to_string())
  }
  if self.label is Some(l) {
    sb.write_string(", \"")
    sb.write_string(l)
    sb.write_string("\"")
  }
  sb.write_string("}")
  sb.to_string()
}

///|
pub(all) struct CostSpec {
  number_per : @decimal.Decimal?
  number_total : @decimal.Decimal?
  currency : String?
  date : Date?
  label : String?
  merge : Bool
  present : Bool
}

///|
pub fn CostSpec::empty() -> CostSpec {
  {
    number_per: None,
    number_total: None,
    currency: None,
    date: None,
    label: None,
    merge: false,
    present: true,
  }
}

///|
pub fn CostSpec::new_per(
  number : @decimal.Decimal,
  currency : String,
  date : Date?,
  label : String?,
) -> CostSpec {
  {
    number_per: Some(number),
    number_total: None,
    currency: Some(currency),
    date,
    label,
    merge: false,
    present: true,
  }
}

///|
pub fn CostSpec::new_total(
  number : @decimal.Decimal,
  currency : String,
) -> CostSpec {
  {
    number_per: None,
    number_total: Some(number),
    currency: Some(currency),
    date: None,
    label: None,
    merge: false,
    present: true,
  }
}

///|
pub fn CostSpec::is_empty_spec(self : CostSpec) -> Bool {
  self.number_per is None &&
  self.number_total is None &&
  self.currency is None &&
  self.date is None &&
  self.label is None &&
  !self.merge
}

///|
pub fn CostSpec::to_string(self : CostSpec) -> String {
  let sb = StringBuilder()
  if self.number_total is Some(total) {
    sb.write_string("{{")
    sb.write_string(total.to_string())
    if self.currency is Some(c) {
      sb.write_string(" ")
      sb.write_string(c)
    }
    sb.write_string("}}")
  } else {
    sb.write_string("{")
    let mut first = true
    if self.number_per is Some(number) {
      sb.write_string(number.to_string())
      if self.currency is Some(c) {
        sb.write_string(" ")
        sb.write_string(c)
      }
      first = false
    } else if self.currency is Some(c) {
      sb.write_string(c)
      first = false
    }
    if self.date is Some(d) {
      if !first {
        sb.write_string(", ")
      }
      sb.write_string(d.to_string())
      first = false
    }
    if self.label is Some(l) {
      if !first {
        sb.write_string(", ")
      }
      sb.write_string("\"")
      sb.write_string(l)
      sb.write_string("\"")
      first = false
    }
    if self.merge {
      if !first {
        sb.write_string(", ")
      }
      sb.write_string("*")
    }
    sb.write_string("}")
  }
  sb.to_string()
}

///|
pub(all) enum PriceAnno {
  PerUnit(Amount)
  Total(Amount)
}

///|
pub fn PriceAnno::amount(self : PriceAnno) -> Amount {
  match self {
    PerUnit(a) => a
    Total(a) => a
  }
}

///|
pub fn PriceAnno::to_string(self : PriceAnno) -> String {
  match self {
    PerUnit(a) => "@ " + a.to_string()
    Total(a) => "@@ " + a.to_string()
  }
}

///|
pub(all) struct Posting {
  mut flag : String?
  account : String
  mut units : Amount?
  mut units_currency : String?
  mut cost : CostSpec?
  mut price : PriceAnno?
  meta : Meta
  mut loc : Loc
}

///|
pub fn Posting::new(account : String) -> Posting {
  {
    flag: None,
    account,
    units: None,
    units_currency: None,
    cost: None,
    price: None,
    meta: Meta::new(),
    loc: Loc::new("", 0),
  }
}

///|
pub(all) struct Transaction {
  flag : String
  payee : String?
  narration : String
  tags : Array[String]
  links : Array[String]
  postings : Array[Posting]
}

///|
pub fn Transaction::new(
  flag : String,
  payee : String?,
  narration : String,
  tags : Array[String],
  links : Array[String],
) -> Transaction {
  { flag, payee, narration, tags, links, postings: [], }
}

///|
pub(all) struct Open {
  account : String
  currencies : Array[String]
  booking : String?
}

///|
pub(all) struct Close {
  account : String
}

///|
pub(all) struct Commodity {
  currency : String
}

///|
pub(all) struct Pad {
  account : String
  source_account : String
}

///|
pub(all) struct Balance {
  account : String
  amount : Amount
  tolerance : @decimal.Decimal?
}

///|
pub(all) struct Price {
  currency : String
  amount : Amount
}

///|
pub(all) struct Event {
  event_type : String
  description : String
}

///|
pub(all) struct QueryDirective {
  name : String
  query : String
}

///|
pub(all) struct Note {
  account : String
  comment : String
  tags : Array[String]
  links : Array[String]
}

///|
pub(all) struct Document {
  account : String
  filename : String
  tags : Array[String]
  links : Array[String]
}

///|
pub(all) enum CustomValue {
  CString(String)
  CBool(Bool)
  CDate(Date)
  CNumber(@decimal.Decimal)
  CAmount(Amount)
  CAccount(String)
  CCurrency(String)
  CTag(String)
}

///|
pub fn CustomValue::to_string(self : CustomValue) -> String {
  match self {
    CString(s) => "\"" + s + "\""
    CBool(b) => if b { "TRUE" } else { "FALSE" }
    CDate(d) => d.to_string()
    CNumber(n) => n.to_string()
    CAmount(a) => a.to_string()
    CAccount(a) => a
    CCurrency(c) => c
    CTag(t) => "#" + t
  }
}

///|
pub(all) struct Custom {
  custom_type : String
  values : Array[CustomValue]
}

///|
pub(all) enum Directive {
  DOpen(Open)
  DClose(Close)
  DCommodity(Commodity)
  DPad(Pad)
  DBalance(Balance)
  DPrice(Price)
  DEvent(Event)
  DQuery(QueryDirective)
  DCustom(Custom)
  DNote(Note)
  DDocument(Document)
  DTransaction(Transaction)
}

///|
pub(all) struct Entry {
  date : Date
  loc : Loc
  mut meta : Meta
  mut inferred_tolerances : Array[(String, @decimal.Decimal)]?
  mut balance_discrepancy : Amount?
  mut query_origin : Loc?
  directive : Directive
}

///|
pub fn Entry::new(date : Date, loc : Loc, directive : Directive) -> Entry {
  {
    date,
    loc,
    meta: Meta::new(),
    inferred_tolerances: None,
    balance_discrepancy: None,
    query_origin: None,
    directive,
  }
}

///|
pub fn Entry::is_transaction(self : Entry) -> Bool {
  self.directive is DTransaction(_)
}

///|
pub(all) struct Plugin {
  name : String
  config : String?
  loc : Loc
}

///|
pub(all) struct Options {
  mut title : String?
  mut booking_method : String
  mut tolerance_multiplier : @decimal.Decimal
  inferred_tolerance_default : Map[String, @decimal.Decimal]
  mut infer_tolerance_from_cost : Bool
  mut account_rounding : String?
  operating_currencies : Array[String]
  documents : Array[String]
  display_precision : Map[String, @decimal.Decimal]
  mut render_commas : Bool
  raw : Array[(String, String)]
}

///|
pub fn Options::new() -> Options {
  {
    title: None,
    booking_method: "STRICT",
    tolerance_multiplier: @decimal.Decimal::parse("0.5").unwrap(),
    inferred_tolerance_default: {},
    infer_tolerance_from_cost: false,
    account_rounding: None,
    operating_currencies: [],
    documents: [],
    display_precision: {},
    render_commas: false,
    raw: [],
  }
}

///|
pub fn Options::add_raw(self : Options, name : String, value : String) -> Unit {
  self.raw.push((name, value))
}

///|
pub fn Options::get(self : Options, name : String) -> String? {
  let mut result = None
  for pair in self.raw {
    if pair.0 == name {
      result = Some(pair.1)
    }
  }
  result
}

///|
pub fn Options::get_all(self : Options, name : String) -> Array[String] {
  let result = []
  for pair in self.raw {
    if pair.0 == name {
      result.push(pair.1)
    }
  }
  result
}

///|
pub(all) struct Ledger {
  entries : Array[Entry]
  errors : Array[Diagnostic]
  mut options : Options
  plugins : Array[Plugin]
  includes : Array[(String, Loc)]
}

///|
pub fn Ledger::new() -> Ledger {
  {
    entries: [],
    errors: [],
    options: Options::new(),
    plugins: [],
    includes: [],
  }
}

///|
pub fn Ledger::add_error(self : Ledger, error : Diagnostic) -> Unit {
  self.errors.push(error)
}

///|
pub fn account_parts(account : String) -> Array[String] {
  let parts = []
  for part in account.split(":") {
    parts.push(String::from_iter(part.iter()))
  }
  parts
}

///|
pub fn account_root(account : String) -> String {
  let parts = account_parts(account)
  if parts.length() == 0 {
    ""
  } else {
    parts[0]
  }
}

///|
pub fn account_leaf(account : String) -> String {
  let parts = account_parts(account)
  if parts.length() == 0 {
    ""
  } else {
    parts[parts.length() - 1]
  }
}

///|
pub fn account_parent(account : String) -> String {
  let parts = account_parts(account)
  if parts.length() <= 1 {
    ""
  } else {
    let sb = StringBuilder()
    let mut i = 0
    while i < parts.length() - 1 {
      if i > 0 {
        sb.write_string(":")
      }
      sb.write_string(parts[i])
      i = i + 1
    }
    sb.to_string()
  }
}

///|
/// Resolves an equity subaccount option, including the configured equity root.
pub fn Options::equity_account(
  self : Options,
  option : String,
  default_suffix : String,
) -> String {
  let mut root = "Equity"
  let mut suffix = default_suffix
  for (key, value) in self.raw {
    if key == "name_equity" {
      root = value
    }
    if key == option {
      suffix = value
    }
  }
  root + ":" + suffix
}
