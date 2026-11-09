// Argument signatures from public beanquery 0.2.0 .help targets.

///|
let oracle_signatures : Array[(String, Array[String])] = [
  ("abs", ["decimal"]),
  ("abs", ["inventory"]),
  ("abs", ["position"]),
  ("account_sortkey", ["str"]),
  ("any_meta", ["str"]),
  ("bool", ["any"]),
  ("close_date", ["str"]),
  ("commodity", ["amount"]),
  ("commodity_meta", ["str"]),
  ("commodity_meta", ["str", "str"]),
  ("convert", ["amount", "str"]),
  ("convert", ["amount", "str", "date"]),
  ("convert", ["position", "str"]),
  ("convert", ["position", "str", "date"]),
  ("convert", ["inventory", "str"]),
  ("convert", ["inventory", "str", "date"]),
  ("cost", ["position"]),
  ("cost", ["inventory"]),
  ("currency", ["amount"]),
  ("currency_meta", ["str"]),
  ("currency_meta", ["str", "str"]),
  ("date", ["date"]),
  ("date", ["object"]),
  ("date", ["str"]),
  ("date", ["int", "int", "int"]),
  ("date_add", ["date", "int"]),
  ("date_bin", ["str", "date", "date"]),
  ("date_bin", ["relativedelta", "date", "date"]),
  ("date_diff", ["date", "date"]),
  ("date_part", ["str", "date"]),
  ("date_trunc", ["str", "date"]),
  ("day", ["date"]),
  ("decimal", ["bool"]),
  ("decimal", ["decimal"]),
  ("decimal", ["int"]),
  ("decimal", ["object"]),
  ("decimal", ["str"]),
  ("empty", ["inventory"]),
  ("entry_meta", ["str"]),
  ("filter_currency", ["inventory", "str"]),
  ("filter_currency", ["position", "str"]),
  ("findfirst", ["str", "set"]),
  ("getitem", ["dict", "str"]),
  ("getitem", ["dict", "str", "any"]),
  ("getprice", ["str", "str"]),
  ("getprice", ["str", "str", "date"]),
  ("grep", ["str", "str"]),
  ("grepn", ["str", "str", "int"]),
  ("has_account", ["str"]),
  ("int", ["bool"]),
  ("int", ["decimal"]),
  ("int", ["int"]),
  ("int", ["object"]),
  ("int", ["str"]),
  ("interval", ["str"]),
  ("joinstr", ["set"]),
  ("leaf", ["str"]),
  ("length", ["list"]),
  ("length", ["set"]),
  ("length", ["str"]),
  ("lower", ["str"]),
  ("maxwidth", ["str", "int"]),
  ("meta", ["str"]),
  ("month", ["date"]),
  ("neg", ["amount"]),
  ("neg", ["decimal"]),
  ("neg", ["inventory"]),
  ("neg", ["position"]),
  ("number", ["amount"]),
  ("only", ["str", "inventory"]),
  ("open_date", ["str"]),
  ("open_meta", ["str"]),
  ("open_meta", ["str", "str"]),
  ("parent", ["str"]),
  ("parse_date", ["str"]),
  ("parse_date", ["str", "str"]),
  ("possign", ["amount", "str"]),
  ("possign", ["decimal", "str"]),
  ("possign", ["inventory", "str"]),
  ("possign", ["position", "str"]),
  ("quarter", ["date"]),
  ("repr", ["any"]),
  ("root", ["str"]),
  ("root", ["str", "int"]),
  ("round", ["decimal"]),
  ("round", ["decimal", "int"]),
  ("round", ["int"]),
  ("round", ["int", "int"]),
  ("safediv", ["decimal", "decimal"]),
  ("safediv", ["decimal", "int"]),
  ("splitcomp", ["str", "str", "int"]),
  ("str", ["any"]),
  ("subst", ["str", "str", "str"]),
  ("substr", ["str", "int", "int"]),
  ("today", []),
  ("units", ["position"]),
  ("units", ["inventory"]),
  ("upper", ["str"]),
  ("value", ["inventory"]),
  ("value", ["inventory", "date"]),
  ("value", ["position"]),
  ("value", ["position", "date"]),
  ("weekday", ["date"]),
  ("year", ["date"]),
  ("yearmonth", ["date"]),
  ("count", ["*"]),
  ("count", ["any"]),
  ("first", ["any"]),
  ("last", ["any"]),
  ("max", ["any"]),
  ("min", ["any"]),
  ("sum", ["amount"]),
  ("sum", ["inventory"]),
  ("sum", ["decimal"]),
  ("sum", ["int"]),
  ("sum", ["position"]),
]

///|
fn column_type(source : QuerySource, name : String) -> String {
  let table = match source {
    SrcDirectives(t) => t
    SrcTransactions => "entries"
    _ => "postings"
  }
  match (table, name) {
    ("accounts", "account") => "str"
    ("accounts", "open") => "directive"
    ("accounts", "close") => "directive"
    ("balances", "meta") => "dict"
    ("balances", "date") => "date"
    ("balances", "account") => "str"
    ("balances", "amount") => "amount"
    ("balances", "tolerance") => "decimal"
    ("balances", "discrepancy") => "amount"
    ("commodities", "meta") => "dict"
    ("commodities", "date") => "date"
    ("commodities", "name") => "str"
    ("documents", "meta") => "dict"
    ("documents", "date") => "date"
    ("documents", "account") => "str"
    ("documents", "filename") => "str"
    ("documents", "tags") => "frozenset"
    ("documents", "links") => "frozenset"
    ("entries", "id") => "str"
    ("entries", "type") => "str"
    ("entries", "filename") => "str"
    ("entries", "lineno") => "int"
    ("entries", "date") => "date"
    ("entries", "year") => "int"
    ("entries", "month") => "int"
    ("entries", "day") => "int"
    ("entries", "flag") => "str"
    ("entries", "payee") => "str"
    ("entries", "narration") => "str"
    ("entries", "description") => "str"
    ("entries", "tags") => "set"
    ("entries", "links") => "set"
    ("entries", "meta") => "dict"
    ("entries", "accounts") => "generic_set"
    ("events", "meta") => "dict"
    ("events", "date") => "date"
    ("events", "type") => "str"
    ("events", "description") => "str"
    ("notes", "meta") => "dict"
    ("notes", "date") => "date"
    ("notes", "account") => "str"
    ("notes", "comment") => "str"
    ("notes", "tags") => "frozenset"
    ("notes", "links") => "frozenset"
    ("postings", "type") => "str"
    ("postings", "id") => "str"
    ("postings", "date") => "date"
    ("postings", "year") => "int"
    ("postings", "month") => "int"
    ("postings", "day") => "int"
    ("postings", "filename") => "str"
    ("postings", "lineno") => "int"
    ("postings", "location") => "str"
    ("postings", "flag") => "str"
    ("postings", "payee") => "str"
    ("postings", "narration") => "str"
    ("postings", "description") => "str"
    ("postings", "tags") => "set"
    ("postings", "links") => "set"
    ("postings", "posting_flag") => "str"
    ("postings", "account") => "str"
    ("postings", "other_accounts") => "set"
    ("postings", "number") => "decimal"
    ("postings", "currency") => "str"
    ("postings", "cost_number") => "decimal"
    ("postings", "cost_currency") => "str"
    ("postings", "cost_date") => "date"
    ("postings", "cost_label") => "str"
    ("postings", "position") => "position"
    ("postings", "price") => "amount"
    ("postings", "weight") => "amount"
    ("postings", "balance") => "inventory"
    ("postings", "meta") => "dict"
    ("postings", "entry") => "directive"
    ("postings", "accounts") => "generic_set"
    ("prices", "meta") => "dict"
    ("prices", "date") => "date"
    ("prices", "currency") => "str"
    ("prices", "amount") => "amount"
    ("transactions", "meta") => "dict"
    ("transactions", "date") => "date"
    ("transactions", "flag") => "str"
    ("transactions", "payee") => "str"
    ("transactions", "narration") => "str"
    ("transactions", "tags") => "set"
    ("transactions", "links") => "set"
    ("transactions", "accounts") => "generic_set"
    (_, "units" | "weight" | "cost" | "value") => "amount"
    (_, "root" | "parent" | "leaf") => "str"
    _ => "unknown"
  }
}
