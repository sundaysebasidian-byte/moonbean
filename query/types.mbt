///|
fn type_argument(actual : String, expected : String) -> Bool {
  actual == expected ||
  (actual == "nonetype" && expected == "object") ||
  (actual == "inventory" && expected == "dict") ||
  expected == "any" ||
  (
    expected == "numeric" &&
    (actual == "int" || actual == "decimal" || actual == "nonetype")
  ) ||
  (
    actual == "nonetype" &&
    (expected == "str_or_null" || expected == "list_or_null")
  ) ||
  (expected == "str_or_null" && actual == "str") ||
  (expected == "date_or_null" && (actual == "date" || actual == "nonetype")) ||
  (expected == "int_or_null" && (actual == "int" || actual == "nonetype")) ||
  (expected == "bool_or_null" && (actual == "bool" || actual == "nonetype")) ||
  (
    expected == "ordered_scalar" &&
    ["int", "decimal", "str", "date", "nonetype"].contains(actual)
  ) ||
  (expected == "list_or_null" && actual == "list") ||
  (
    expected == "scalar" &&
    ["str", "date", "int", "decimal", "bool", "nonetype"].contains(actual)
  ) ||
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
    "account_sortkey", "getprice", "convert", "value", "possign", "date_part", "date_trunc",
    "date_bin", "interval", "today", "parse_date", "joinstr", "maxwidth", "grep",
    "grepn", "findfirst", "has_account", "subst",
  ].contains(name)
}

///|
fn expression_type(
  expr : Expr,
  source : QuerySource,
  errors : Array[String],
) -> String {
  match expr {
    EPredicate(cond) => {
      projection_condition_types(cond, source, errors)
      "bool"
    }
    ECol(name) => {
      let kind = column_type(source, name)
      if kind == "unknown" {
        errors.push("compilation query.invalid_column: " + name)
      }
      kind
    }
    EValue(value) =>
      match value {
        QInt(_) => "int"
        QNumber(_) | QNegativeZero(_) => "decimal"
        QInterval(_, _) => "relativedelta"
        QList(_) => "list"
        QBool(_) => "bool"
        QDate(_) => "date"
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
      if op == "-" && ta == "date" && tb == "date" {
        "int"
      } else if (op == "+" || op == "-") &&
        ta == "relativedelta" &&
        tb == "relativedelta" {
        // The pinned oracle declares interval subtraction as date despite returning an interval.
        if op == "-" {
          "date"
        } else {
          "relativedelta"
        }
      } else if (op == "+" || op == "-") &&
        (
          (ta == "date" && ["int", "relativedelta"].contains(tb)) ||
          (tb == "date" && ta == "relativedelta") ||
          (tb == "date" && ta == "int" && op == "+")
        ) {
        "date"
      } else if ["int", "decimal"].contains(ta) &&
        ["int", "decimal"].contains(tb) {
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
      if name == "percentile_disc" && args.length() == 2 {
        match literal_value(args[1]) {
          Some(QNull) => ()
          Some(v) if value_number(v) is Some(n) &&
            !n.is_negative() &&
            n.compare(@decimal.Decimal::from_int(1)) <= 0 => ()
          _ =>
            errors.push(
              "compilation query.invalid_signature: percentile fraction must be a numeric literal in [0,1] or NULL",
            )
        }
      }
      if name == "__dynamic_regex" {
        for i in 0..<2 {
          let kind = expression_type(args[i], source, errors)
          if !["str", "object"].contains(kind) {
            errors.push(
              "compilation query.invalid_signature: regex requires text",
            )
          }
        }
        return "bool"
      }
      if name == "__filter_aggregate" {
        if args[1] is EPredicate(condition) {
          condition_types(condition, source, errors)
        }
        return expression_type(args[0], source, errors)
      }
      if name == "__case" {
        let mut result = "nonetype"
        for i in 0..<args.length() {
          let kind = expression_type(args[i], source, errors)
          if i % 2 == 1 || i == args.length() - 1 {
            if result == "nonetype" {
              result = kind
            } else if kind != "nonetype" && kind != result {
              errors.push(
                "compilation query.invalid_signature: CASE branches require uniform types",
              )
            }
          }
        }
        return result
      }
      if name == "coalesce" {
        let types = args.map(fn(e) { expression_type(e, source, errors) })
        if !types.is_empty() && !types.all(fn(t) { t == types[0] }) {
          errors.push(
            "compilation query.invalid_signature: coalesce requires uniform types",
          )
        }
        return types.get(0).unwrap_or("object")
      }
      if ["entry_meta", "any_meta"].contains(name) &&
        column_type(source, "entry") == "unknown" {
        errors.push("compilation query.invalid_column: entry")
      }
      if name == "__distinct" || name == "__not_distinct" {
        let ts = args.map(fn(e) { expression_type(e, source, errors) })
        if !ts.all(fn(t) { type_argument(t, "scalar") }) {
          errors.push(
            "compilation query.invalid_signature: DISTINCT FROM needs scalar values",
          )
        }
        return "bool"
      }
      if name == "__in" || name == "__notin" || name == "__between" {
        let ts = args.map(fn(e) { expression_type(e, source, errors) })
        if name == "__between" &&
          !(ts.all(fn(t) { ["int", "decimal"].contains(t) }) ||
          ts.all(fn(t) { t == "str" }) ||
          ts.all(fn(t) { t == "date" })) {
          errors.push("compilation query.invalid_signature: BETWEEN operands")
        }
        return "bool"
      }
      if source is SrcRelation(_) {
        let dependency = match name {
          "meta" => "meta"
          "entry_meta" | "any_meta" => "entry"
          "has_account" => "accounts"
          _ => ""
        }
        if dependency != "" && column_type(source, dependency) == "unknown" {
          errors.push("compilation query.invalid_column: " + dependency)
        }
        if name == "any_meta" && column_type(source, "meta") == "unknown" {
          errors.push("compilation query.invalid_column: meta")
        }
      }
      if name == "has_account" && column_type(source, "accounts") == "unknown" {
        errors.push("compilation query.invalid_column: accounts")
      }
      let ts = args.map(fn(e) { expression_type(e, source, errors) })
      if ts.contains("generic_set") {
        errors.push("query.oracle_type_error: generic accounts type")
        return "unknown"
      }
      if extension_type(name, ts) is Some(t) {
        return t
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
        "interval" => "relativedelta"
        "date_bin" | "today" | "parse_date" => "date"
        "date_part" => "int"
        "date_trunc" => "date"
        "joinstr" | "maxwidth" | "grep" | "grepn" | "findfirst" | "subst" =>
          "str"
        "has_account" => "bool"
        "getprice" => "decimal"
        "convert" | "value" =>
          if ts[0] == "inventory" {
            "inventory"
          } else {
            "amount"
          }
        "possign" => ts[0]
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
      let legacy = fn(e) {
        expr_any(e, fn(e) { e is ECol("units" | "cost" | "value" | "weight") })
      }
      if legacy(a) || legacy(b) {
        expression_type(a, source, errors) |> ignore
        expression_type(b, source, errors) |> ignore
      } else {
        projection_condition_types(cond, source, errors)
      }
    }
    CRegex(_, _, _, true) => projection_condition_types(cond, source, errors)
    CIsNull(e, _) | CTruthy(e) | CRegex(e, _, _, false) =>
      expression_type(e, source, errors) |> ignore
  }
}
