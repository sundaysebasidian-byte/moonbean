///|
fn type_argument(actual : String, expected : String) -> Bool {
  actual == expected ||
  expected == "any" ||
  (actual == "bool" && expected == "int")
}

///|
fn function_implemented(name : String) -> Bool {
  [
    "upper", "lower", "length", "substr", "root", "parent", "leaf", "year", "month",
    "day", "quarter", "weekday", "yearmonth", "date", "date_add", "date_diff", "meta",
    "entry_meta", "any_meta", "getitem", "open_meta", "open_date", "close_date",
    "commodity_meta", "currency_meta", "str", "repr", "bool", "int", "decimal", "abs",
    "neg", "units", "cost", "currency", "commodity", "number", "empty", "only", "filter_currency",
    "safediv", "sum", "count", "first", "last", "min", "max", "round", "splitcomp",
    "account_sortkey",
  ].contains(name)
}

///|
fn expression_type(
  expr : Expr,
  source : QuerySource,
  errors : Array[String],
) -> String {
  match expr {
    ECol(name) => column_type(source, name)
    EValue(value) =>
      match value {
        QInt(_) => "int"
        QNumber(_) => "decimal"
        QText(_) => "str"
        QNull => "nonetype"
        _ => "object"
      }
    EStr(_) => "str"
    ENum(n) => if n.scale() == 0 { "int" } else { "decimal" }
    EDate(_) => "date"
    EBool(_) => "bool"
    ENull => "nonetype"
    EStar => "*"
    EBinary(a, op, b) => {
      let ta = expression_type(a, source, errors)
      let tb = expression_type(b, source, errors)
      if ["int", "decimal"].contains(ta) && ["int", "decimal"].contains(tb) {
        if ta == "int" && tb == "int" && op != "/" {
          "int"
        } else {
          "decimal"
        }
      } else {
        errors.push(
          "compilation query.invalid_signature: arithmetic " + ta + " " + tb,
        )
        "unknown"
      }
    }
    ECall(name, args) => {
      let ts = args.map(fn(e) { expression_type(e, source, errors) })
      if ts.contains("generic_set") {
        errors.push("query.oracle_type_error: generic accounts type")
        return "unknown"
      }
      let valid = oracle_signatures.any(fn(s) {
        s.0 == name &&
        s.1.length() == ts.length() &&
        s.1.iter().zip(ts.iter()).all(fn(p) { type_argument(p.1, p.0) })
      })
      if !valid {
        errors.push(
          "compilation query.invalid_signature: " +
          name +
          "(" +
          ts.join(",") +
          ")",
        )
        return "unknown"
      }
      if !function_implemented(name) {
        errors.push("unsupported query.unsupported.function `" + name + "`")
        return "unknown"
      }
      match name {
        "first" | "last" | "min" | "max" | "round" => ts[0]
        "sum" =>
          if ["amount", "position", "inventory"].contains(ts[0]) {
            "inventory"
          } else {
            ts[0]
          }
        "count" | "length" | "year" | "month" | "day" | "date_diff" | "int" =>
          "int"
        "yearmonth" | "date" | "date_add" | "open_date" | "close_date" => "date"
        "account_sortkey"
        | "splitcomp"
        | "str"
        | "repr"
        | "upper"
        | "lower"
        | "substr"
        | "root"
        | "parent"
        | "leaf"
        | "currency"
        | "commodity"
        | "quarter"
        | "weekday" => "str"
        "bool" | "empty" => "bool"
        "meta" | "entry_meta" | "any_meta" | "getitem" => "object"
        "open_meta" | "commodity_meta" | "currency_meta" =>
          if args.length() == 1 {
            "dict"
          } else {
            "object"
          }
        "decimal" | "number" | "safediv" => "decimal"
        "abs" | "neg" => ts[0]
        "units" | "cost" =>
          if ts[0] == "position" {
            "amount"
          } else {
            "inventory"
          }
        "only" => "amount"
        "filter_currency" => ts[0]
        _ => "unknown"
      }
    }
  }
}

///|
fn condition_types(
  cond : Cond,
  source : QuerySource,
  errors : Array[String],
) -> Unit {
  match cond {
    CTrue => ()
    CNot(c) => condition_types(c, source, errors)
    CAnd(a, b) | COr(a, b) => {
      condition_types(a, source, errors)
      condition_types(b, source, errors)
    }
    CCmp(a, _, b) => {
      expression_type(a, source, errors) |> ignore
      expression_type(b, source, errors) |> ignore
    }
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _) =>
      expression_type(e, source, errors) |> ignore
  }
}
