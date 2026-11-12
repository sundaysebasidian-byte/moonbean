///|
let month_names : Array[String] = [
  "january", "february", "march", "april", "may", "june", "july", "august", "september",
  "october", "november", "december",
]

///|
fn month_number(text : String) -> Int32? {
  let lower = text.to_lower()
  for i in 0..<12 {
    if lower == month_names[i] ||
      lower == month_names[i][:3].to_owned() ||
      (i == 8 && lower == "sept") {
      return Some(i + 1)
    }
  }
  None
}

///|
fn parsed_date(
  ctx : QueryContext,
  year : Int32,
  month : Int32,
  day : Int32,
) -> QueryValue {
  match @ast.Date::new(year, month, day) {
    Some(d) => QDate(d)
    None => {
      query_error(
        ctx, "query.oracle_type_error: ValueError invalid parsed date",
      )
      QNull
    }
  }
}

///|
fn strptime_date(
  ctx : QueryContext,
  text : String,
  format : String,
) -> QueryValue {
  let format = format
    .replace_all(old="%c", new="%a %b %d %H:%M:%S %Y")
    .replace_all(old="%x", new="%m/%d/%y")
    .replace_all(old="%X", new="%H:%M:%S")
  let pattern = StringBuilder()
  pattern.write_char('^')
  let fields : Array[Char] = []
  let mut i = 0
  while i < format.length() {
    let c = format.get_char(i).unwrap()
    i = i + 1
    if c == '%' {
      if i == format.length() {
        query_error(ctx, "query.oracle_type_error: ValueError stray percent")
        return QNull
      }
      let field = format.get_char(i).unwrap()
      i = i + 1
      if field == '%' {
        pattern.write_char('%')
        continue
      }
      if fields.contains(field) {
        query_error(
          ctx, "query.oracle_type_error: error duplicate format directive",
        )
        return QNull
      }
      let part = match field {
        'Y' | 'G' => "[0-9][0-9][0-9][0-9]"
        'y' => "[0-9][0-9]"
        'd' => " ?[0-9][0-9]?"
        'm' | 'H' | 'I' | 'M' | 'S' | 'U' | 'W' | 'V' => "[0-9][0-9]?"
        'j' => "[0-9][0-9]?[0-9]?"
        'f' => "[0-9][0-9]?[0-9]?[0-9]?[0-9]?[0-9]?"
        'w' | 'u' => "[0-9]"
        'a' | 'A' | 'b' | 'B' | 'p' | 'Z' => "[a-zA-Z]*"
        'z' => "Z|[+\\-][0-9][0-9]:?[0-9][0-9](?::?[0-9][0-9](?:[.][0-9]+)?)?"
        _ => {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid strptime directive",
          )
          return QNull
        }
      }
      pattern.write_char('(')
      pattern.write_string(part)
      pattern.write_char(')')
      fields.push(field)
    } else if python_whitespace(c) {
      pattern.write_string("[ \t\n\r]+")
    } else {
      if ".^$*+?{}[]|()\\".contains(c.to_string()) {
        pattern.write_char('\\')
      }
      pattern.write_char(c)
    }
  }
  pattern.write_char('$')
  let regex = @string.Regex("(?i:" + pattern.to_string() + ")") catch {
    _ => {
      query_error(
        ctx, "query.oracle_type_error: ValueError invalid date format",
      )
      return QNull
    }
  }
  let matched = match regex.execute(text) {
    Some(m) => m
    None => {
      query_error(
        ctx, "query.oracle_type_error: ValueError date does not match format",
      )
      return QNull
    }
  }
  let mut year = 1900
  let mut month = 1
  let mut day = 1
  let mut ordinal_day = None
  let mut week = None
  let mut week_kind = ' '
  let mut weekday = 0
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut iso_year = None
  let mut group = 1
  for field in fields {
    let raw = matched.group(group).unwrap().to_owned()
    let n = bql_parse_int(raw.trim().to_owned())
    match field {
      'Y' => year = n
      'G' => iso_year = Some(n)
      'y' => year = if n <= 68 { 2000 + n } else { 1900 + n }
      'm' => month = n
      'd' => day = n
      'b' | 'B' =>
        match
          (if (field == 'b' && raw.length() != 3) ||
            (field == 'B' && !month_names.contains(raw.to_lower())) {
            None
          } else {
            month_number(raw)
          }) {
          Some(m) => month = m
          None => {
            query_error(
              ctx, "query.oracle_type_error: ValueError invalid month",
            )
            return QNull
          }
        }
      'j' => ordinal_day = Some(n)
      'U' | 'W' | 'V' => {
        week = Some(n)
        week_kind = field
      }
      'w' | 'u' => {
        if n > (if field == 'w' { 6 } else { 7 }) || (field == 'u' && n == 0) {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid weekday",
          )
          return QNull
        }
        weekday = if field == 'w' { (n + 6) % 7 } else { n - 1 }
      }
      'H' | 'I' => {
        if field == 'I' && (n < 1 || n > 12) {
          query_error(ctx, "query.oracle_type_error: ValueError invalid hour")
          return QNull
        }
        hour = n
      }
      'M' => minute = n
      'S' => second = n
      'z' => {
        let digits = raw.replace_all(old=":", new="")
        if digits != "Z" &&
          (
            bql_parse_int(digits[1:3].to_owned()) > 23 ||
            bql_parse_int(digits[3:5].to_owned()) > 59
          ) {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid timezone offset",
          )
          return QNull
        }
      }
      'a' | 'A' => {
        let names = [
          "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        ]
        let mut found = false
        for j in 0..<7 {
          if raw.to_lower() == names[j] ||
            raw.to_lower() == names[j][:3].to_owned() {
            weekday = j
            found = true
          }
        }
        if !found {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid weekday",
          )
          return QNull
        }
      }
      'p' =>
        if raw.to_lower() != "am" && raw.to_lower() != "pm" {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid meridiem",
          )
          return QNull
        }
      'Z' =>
        if !["", "utc", "gmt"].contains(raw.to_lower()) {
          query_error(
            ctx, "query.oracle_type_error: ValueError invalid timezone",
          )
          return QNull
        }
      _ => ()
    }
    group = group + 1
  }
  if hour > 23 || minute > 59 || second > 59 || year < 1 || year > 9999 {
    query_error(
      ctx, "query.oracle_type_error: ValueError parsed field out of range",
    )
    return QNull
  }
  let has_weekday = fields.any(fn(c) { ['a', 'A', 'w', 'u'].contains(c) })
  if (iso_year is Some(_) || week_kind == 'V') &&
    !(iso_year is Some(_) && week_kind == 'V' && has_weekday) {
    query_error(
      ctx, "query.oracle_type_error: ValueError incomplete ISO week date",
    )
    return QNull
  }
  if has_weekday && week is Some(w) {
    if w > 53 || weekday < 0 || weekday > 6 {
      query_error(ctx, "query.oracle_type_error: ValueError invalid week")
      return QNull
    }
    if week_kind == 'V' {
      let y = match iso_year {
        Some(y) => y
        None => {
          query_error(
            ctx, "query.oracle_type_error: ValueError ISO year required",
          )
          return QNull
        }
      }
      let jan4 = ordinal(@ast.Date::new(y, 1, 4).unwrap())
      return ordinal_date(jan4 - (jan4 - 1) % 7 + (w - 1) * 7 + weekday)
    }
    let jan1 = ordinal(@ast.Date::new(year, 1, 1).unwrap())
    let start = if week_kind == 'U' { 6 } else { 0 }
    let jan_weekday = (jan1 - 1) % 7
    let offset = (weekday - start + 7) % 7
    return ordinal_date(
      jan1 + (start - jan_weekday + 7) % 7 + (w - 1) * 7 + offset,
    )
  }
  if ordinal_day is Some(n) {
    if n < 1 || n > 366 {
      query_error(
        ctx, "query.oracle_type_error: ValueError invalid day of year",
      )
      return QNull
    }
    return ordinal_date(ordinal(@ast.Date::new(year, 1, 1).unwrap()) + n - 1)
  }
  parsed_date(ctx, year, month, day)
}

///|
fn flexible_date(ctx : QueryContext, input : String) -> QueryValue {
  let today = match query_today(ctx) {
    QDate(d) => d
    _ => return QNull
  }
  let mut text = normalize_python_digits(input.trim().to_owned())
  if text.length() == 14 && text.iter().all(fn(c) { c.is_ascii_digit() }) {
    if bql_parse_int(text[8:10].to_owned()) > 23 ||
      bql_parse_int(text[10:12].to_owned()) > 59 ||
      bql_parse_int(text[12:].to_owned()) > 59 {
      query_error(ctx, "query.oracle_type_error: ParserError invalid time")
      return QNull
    }
    text = text[:8].to_owned()
  }
  let time_patterns = [
    "(^|[Tt ]+)([0-9][0-9]?):([0-9][0-9])(?::([0-9][0-9])(?:[.,][0-9]+)?)?([ ]*[aApP][mM])?(?:[ ]*(?:[A-Z]{1,5}|(?:UTC|GMT)[+\\-][0-9][0-9]?(?::[0-9][0-9])?|[+\\-][0-9][0-9](?::?[0-9][0-9])?))?$",
    "([Tt ]+)([0-9][0-9])([0-9][0-9])([0-9][0-9])?()$", "(^|[Tt ]+)([0-9][0-9]?)()()([ ]*[aApP][mM])$",
    "([Tt])([0-9][0-9])()()()$", "(^|[Tt ]+)([0-9][0-9]?)[hH](?:([0-9][0-9]?)[mM])?(?:([0-9][0-9]?)[sS])?()$",
  ]
  for index in 0..<time_patterns.length() {
    let pattern = time_patterns[index]
    let regex = @string.Regex(pattern) catch {
      _ => {
        query_error(
          ctx, "query.oracle_type_error: invalid internal time pattern",
        )
        return QNull
      }
    }
    if regex.execute(text) is Some(m) {
      if index == 1 &&
        m.before().iter().filter(fn(c) { c.is_ascii_digit() }).count() < 6 {
        continue
      }
      let hour = bql_parse_int(m.group(2).unwrap().to_owned())
      let minute = bql_parse_int(
        m.group(3).map(fn(s) { s.to_owned() }).unwrap_or("0"),
      )
      let second = bql_parse_int(
        m.group(4).map(fn(s) { s.to_owned() }).unwrap_or("0"),
      )
      let meridiem = m.group(5).map(fn(s) { s.trim().to_owned() }).unwrap_or("")
      if hour > 23 ||
        minute > 59 ||
        second > 59 ||
        (meridiem != "" && hour > 12) {
        query_error(ctx, "query.oracle_type_error: ParserError invalid time")
        return QNull
      }
      text = m.before().trim().to_owned()
      if text == "" {
        return QDate(today)
      }
      break
    }
  }
  let mut year = today.year
  let mut month = today.month
  let mut day = today.day
  let mut explicit_day = false
  if (text.length() == 8 || text.length() == 6) &&
    text.iter().all(fn(c) { c.is_ascii_digit() }) {
    if text.length() == 8 {
      return parsed_date(
        ctx,
        bql_parse_int(text[:4].to_owned()),
        bql_parse_int(text[4:6].to_owned()),
        bql_parse_int(text[6:].to_owned()),
      )
    }
    let a = bql_parse_int(text[:2].to_owned())
    let b = bql_parse_int(text[2:4].to_owned())
    let c = bql_parse_int(text[4:].to_owned())
    let short_year = if a > 31 { a } else { c }
    let y = today.year / 100 * 100 + short_year
    let year = if y >= today.year + 50 {
      y - 100
    } else if y < today.year - 50 {
      y + 100
    } else {
      y
    }
    let month = if a > 12 { b } else { a }
    let day = if a > 31 { c } else if a > 12 { a } else { b }
    return parsed_date(ctx, year, month, day)
  }

  let tokens : Array[String] = []
  let mut token = StringBuilder()
  let mut numeric = false
  for c in text.iter() {
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      let is_numeric = c.is_ascii_digit()
      if token.to_string() != "" && numeric != is_numeric {
        tokens.push(token.to_string())
        token = StringBuilder()
      }
      token.write_char(c)
      numeric = is_numeric
    } else if " -/.,\t\n".contains(c.to_string()) {
      if token.to_string() != "" {
        tokens.push(token.to_string())
        token = StringBuilder()
      }
    } else {
      query_error(
        ctx, "query.oracle_type_error: ParserError unknown date format",
      )
      return QNull
    }
  }
  if token.to_string() != "" {
    tokens.push(token.to_string())
  }
  let numbers : Array[String] = []
  let mut named_month = false
  let mut weekday = None
  for t in tokens {
    let weekdays = [
      "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    for i in 0..<7 {
      if t.to_lower() == weekdays[i] ||
        t.to_lower() == weekdays[i][:3].to_owned() {
        weekday = Some(i)
      }
    }
    if month_number(t) is Some(m) {
      month = m
      named_month = true
    } else if t.iter().all(fn(c) { c.is_ascii_digit() }) {
      numbers.push(t)
    } else if ![
        "mon", "monday", "tue", "tuesday", "wed", "wednesday", "thu", "thursday",
        "fri", "friday", "sat", "saturday", "sun", "sunday", "st", "nd", "rd", "th",
        "at", "on", "of", "ad",
      ].contains(t.to_lower()) {
      query_error(
        ctx, "query.oracle_type_error: ParserError unknown date format",
      )
      return QNull
    }
  }
  if !named_month && numbers.is_empty() {
    if weekday is Some(day) {
      return ordinal_date(
        ordinal(today) + (day - (ordinal(today) - 1) % 7 + 7) % 7,
      )
    }
    query_error(ctx, "query.oracle_type_error: ParserError no date")
    return QNull
  }
  let expand_year = fn(s : String) {
    let n = bql_parse_int(s)
    if s.length() >= 3 {
      n
    } else {
      let y = today.year / 100 * 100 + n
      if y >= today.year + 50 {
        y - 100
      } else if y < today.year - 50 {
        y + 100
      } else {
        y
      }
    }
  }
  if named_month {
    if numbers.length() > 2 {
      query_error(ctx, "query.oracle_type_error: ParserError extra date fields")
      return QNull
    }
    for n in numbers {
      if n.length() >= 3 || bql_parse_int(n) > 31 {
        year = expand_year(n)
      } else if !explicit_day {
        day = bql_parse_int(n)
        explicit_day = true
      } else {
        year = expand_year(n)
      }
    }
  } else {
    match numbers.length() {
      1 =>
        if numbers[0].length() >= 3 || bql_parse_int(numbers[0]) > 31 {
          year = expand_year(numbers[0])
        } else {
          day = bql_parse_int(numbers[0])
          explicit_day = true
        }
      2 =>
        if numbers[0].length() >= 3 {
          year = bql_parse_int(numbers[0])
          month = bql_parse_int(numbers[1])
        } else if numbers[1].length() >= 3 {
          year = bql_parse_int(numbers[1])
          month = bql_parse_int(numbers[0])
        } else {
          month = bql_parse_int(numbers[0])
          day = bql_parse_int(numbers[1])
          explicit_day = true
        }
      3 => {
        if numbers[0].length() >= 3 || bql_parse_int(numbers[0]) > 31 {
          year = expand_year(numbers[0])
          month = bql_parse_int(numbers[1])
          day = bql_parse_int(numbers[2])
        } else {
          year = expand_year(numbers[2])
          let a = bql_parse_int(numbers[0])
          let b = bql_parse_int(numbers[1])
          month = if a > 12 { b } else { a }
          day = if a > 12 { a } else { b }
        }
        explicit_day = true
      }
      _ => {
        query_error(
          ctx, "query.oracle_type_error: ParserError invalid date fields",
        )
        return QNull
      }
    }
  }
  if !explicit_day && month >= 1 && month <= 12 {
    day = day.min(@ast.Date::days_in_month(year, month))
  }
  parsed_date(ctx, year, month, day)
}
