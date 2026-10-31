// Calendar dates used by Beancount directives.  No timezone is involved.

///|
pub(all) struct Date {
  year : Int32
  month : Int32
  day : Int32
}

///|
pub fn Date::is_leap(year : Int32) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
pub fn Date::days_in_month(year : Int32, month : Int32) -> Int32 {
  if month == 2 {
    if Date::is_leap(year) {
      29
    } else {
      28
    }
  } else if month == 4 || month == 6 || month == 9 || month == 11 {
    30
  } else {
    31
  }
}

///|
pub fn Date::new(year : Int32, month : Int32, day : Int32) -> Date? {
  if year < 1 || year > 9999 {
    return None
  }
  if month < 1 || month > 12 {
    return None
  }
  if day < 1 || day > Date::days_in_month(year, month) {
    return None
  }
  Some({ year, month, day, })
}

///|
fn parse_fixed_digits(text : String, start : Int32, count : Int32) -> Int32? {
  let mut value = 0
  let mut i = 0
  while i < count {
    let c = match text.get_char(start + i) {
      Some(c) => c
      None => return None
    }
    if !c.is_ascii_digit() {
      return None
    }
    value = value * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  Some(value)
}

///|
pub fn Date::parse(text : String) -> Date? {
  let value = text
  if value.length() != 10 ||
    value.get_char(4) != Some('-') ||
    value.get_char(7) != Some('-') {
    return None
  }
  let year = match parse_fixed_digits(value, 0, 4) {
    Some(v) => v
    None => return None
  }
  let month = match parse_fixed_digits(value, 5, 2) {
    Some(v) => v
    None => return None
  }
  let day = match parse_fixed_digits(value, 8, 2) {
    Some(v) => v
    None => return None
  }
  Date::new(year, month, day)
}

///|
fn pad2(value : Int32) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
pub fn Date::to_string(self : Date) -> String {
  let y = if self.year < 1000 {
    "0".repeat(4 - self.year.to_string().length()) + self.year.to_string()
  } else {
    self.year.to_string()
  }
  y + "-" + pad2(self.month) + "-" + pad2(self.day)
}

///|
pub fn Date::compare(a : Date, b : Date) -> Int32 {
  if a.year != b.year {
    a.year.compare(b.year)
  } else if a.month != b.month {
    a.month.compare(b.month)
  } else {
    a.day.compare(b.day)
  }
}

///|
pub fn Date::equal(a : Date, b : Date) -> Bool {
  a.compare(b) == 0
}

///|
pub fn Date::less_equal(a : Date, b : Date) -> Bool {
  a.compare(b) <= 0
}

///|
pub fn Date::less_than(a : Date, b : Date) -> Bool {
  a.compare(b) < 0
}

///|
pub fn Date::day_of_year(self : Date) -> Int32 {
  let mut total = self.day
  let mut month = 1
  while month < self.month {
    total = total + Date::days_in_month(self.year, month)
    month = month + 1
  }
  total
}
