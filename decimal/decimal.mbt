// Exact arbitrary-precision decimal arithmetic for moonbean.
//
// Values are stored as `mantissa * 10^-scale`.  The scale is preserved on
// purpose: Beancount infers tolerances from the number of fractional digits a
// user wrote (10.00 and 10 are different inputs), so a normalising decimal
// (such as one that strips trailing zeros) cannot be used here.

///|
pub let decimal_precision : Int32 = 28

///|
pub(all) struct Decimal {
  mantissa : @bigint.BigInt
  scale : Int32
}

///|
pub fn Decimal::new(mantissa : @bigint.BigInt, scale : Int32) -> Decimal {
  { mantissa, scale, }
}

///|
pub fn Decimal::zero() -> Decimal {
  { mantissa: @bigint.BigInt::from_int(0), scale: 0, }
}

///|
pub fn Decimal::zero_scaled(scale : Int32) -> Decimal {
  { mantissa: @bigint.BigInt::from_int(0), scale, }
}

///|
pub fn Decimal::one() -> Decimal {
  { mantissa: @bigint.BigInt::from_int(1), scale: 0, }
}

///|
pub fn Decimal::from_int(value : Int32) -> Decimal {
  { mantissa: @bigint.BigInt::from_int(value), scale: 0, }
}

///|
pub fn Decimal::from_int64(value : Int64) -> Decimal {
  { mantissa: @bigint.BigInt::from_int64(value), scale: 0, }
}

///|
fn pow10(n : Int32) -> @bigint.BigInt {
  let mut result = @bigint.BigInt::from_int(1)
  let ten = @bigint.BigInt::from_int(10)
  let mut i = 0
  while i < n {
    result = result.mul(ten)
    i = i + 1
  }
  result
}

///|
fn bigint_abs(value : @bigint.BigInt) -> @bigint.BigInt {
  if value.compare_int(0) < 0 {
    value.neg()
  } else {
    value
  }
}

///|
fn bigint_sign(value : @bigint.BigInt) -> Int32 {
  value.compare_int(0)
}

///|
fn digit_count(value : @bigint.BigInt) -> Int32 {
  bigint_abs(value).to_string().length()
}

///|
fn bigint_gcd(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let mut x = bigint_abs(a)
  let mut y = bigint_abs(b)
  while !y.is_zero() {
    let r = x.mod(y)
    x = y
    y = r
  }
  x
}

///|
fn bigint_mul_pow10(value : @bigint.BigInt, n : Int32) -> @bigint.BigInt {
  if n <= 0 {
    value
  } else {
    value.mul(pow10(n))
  }
}

///|
fn bigint_div_pow10(value : @bigint.BigInt, n : Int32) -> @bigint.BigInt {
  if n <= 0 {
    value
  } else {
    value.div(pow10(n))
  }
}

// Rounds |value| / 10^k to the nearest integer, ties to even, and restores the
// sign of `value`.

///|
fn bigint_div_pow10_half_even(
  value : @bigint.BigInt,
  n : Int32,
) -> @bigint.BigInt {
  if n <= 0 {
    value
  } else {
    let neg = bigint_sign(value) < 0
    let abs_value = bigint_abs(value)
    let den = pow10(n)
    let quot = abs_value.div(den)
    let rem = abs_value.mod(den)
    let twice = rem.mul(@bigint.BigInt::from_int(2))
    let up = if twice.compare(den) > 0 {
      true
    } else if twice.compare(den) == 0 {
      quot.mod(@bigint.BigInt::from_int(2)).compare_int(0) != 0
    } else {
      false
    }
    let rounded = if up { quot.add(@bigint.BigInt::from_int(1)) } else { quot }
    if neg {
      rounded.neg()
    } else {
      rounded
    }
  }
}

///|
/// Parses a plain decimal literal: optional sign, digits, optional fraction.
/// Thousands separators (commas between digits) are accepted.  Exponents are
/// intentionally rejected; Beancount numbers are written in plain notation.
pub fn Decimal::parse(input : String) -> Decimal? {
  let text = input.trim()
  if text.length() == 0 {
    return None
  }
  let mut idx = 0
  let mut negative = false
  let first = text.get_char(0)
  match first {
    Some(c) =>
      if c == '-' || c == '+' {
        negative = c == '-'
        idx = 1
      }
    None => return None
  }
  let int_digits = StringBuilder()
  let frac_digits = StringBuilder()
  let mut seen_digit = false
  let mut seen_dot = false
  let mut last_was_comma = false
  let chars = text.char_length()
  while idx < chars {
    let c = match text.get_char(idx) {
      Some(c) => c
      None => return None
    }
    if c >= '0' && c <= '9' {
      if seen_dot {
        frac_digits.write_char(c)
      } else {
        int_digits.write_char(c)
      }
      seen_digit = true
      last_was_comma = false
    } else if c == '.' {
      if seen_dot {
        return None
      }
      seen_dot = true
      last_was_comma = false
    } else if c == ',' {
      if !seen_digit || seen_dot || last_was_comma {
        return None
      }
      last_was_comma = true
    } else {
      return None
    }
    idx = idx + 1
  }
  if !seen_digit || last_was_comma {
    return None
  }
  let int_part = if int_digits.is_empty() {
    "0"
  } else {
    int_digits.to_string()
  }
  let frac_part = frac_digits.to_string()
  let digits = int_part + frac_part
  let mut mantissa = @bigint.BigInt::from_string(digits)
  if negative && !mantissa.is_zero() {
    mantissa = mantissa.neg()
  }
  Some({ mantissa, scale: frac_part.length(), })
}

///|
pub fn Decimal::is_zero(self : Decimal) -> Bool {
  self.mantissa.is_zero()
}

///|
pub fn Decimal::is_negative(self : Decimal) -> Bool {
  bigint_sign(self.mantissa) < 0
}

///|
pub fn Decimal::is_positive(self : Decimal) -> Bool {
  bigint_sign(self.mantissa) > 0
}

///|
pub fn Decimal::signum(self : Decimal) -> Int32 {
  bigint_sign(self.mantissa)
}

///|
pub fn Decimal::neg(self : Decimal) -> Decimal {
  { mantissa: self.mantissa.neg(), scale: self.scale, }
}

///|
pub fn Decimal::abs(self : Decimal) -> Decimal {
  { mantissa: bigint_abs(self.mantissa), scale: self.scale, }
}

///|
pub fn Decimal::scale(self : Decimal) -> Int32 {
  self.scale
}

///|
pub fn Decimal::mantissa(self : Decimal) -> @bigint.BigInt {
  self.mantissa
}

///|
/// Multiplies the value by 10^k, preserving the represented value.
pub fn Decimal::shift_scale(self : Decimal, k : Int32) -> Decimal {
  { mantissa: bigint_mul_pow10(self.mantissa, k), scale: self.scale + k, }
}

///|
/// Rounds to the nearest value with the requested scale, ties to even.
pub fn Decimal::quantize(self : Decimal, target_scale : Int32) -> Decimal {
  if target_scale == self.scale {
    return self
  }
  if target_scale > self.scale {
    return {
      mantissa: bigint_mul_pow10(self.mantissa, target_scale - self.scale),
      scale: target_scale,
    }
  }
  let drop = self.scale - target_scale
  {
    mantissa: bigint_div_pow10_half_even(self.mantissa, drop),
    scale: target_scale,
  }
}

///|
/// Rounds to `digits` significant digits, ties to even.
pub fn Decimal::round_to_significant(self : Decimal, digits : Int32) -> Decimal {
  if self.mantissa.is_zero() {
    return self
  }
  let current = digit_count(self.mantissa)
  if current <= digits {
    return self
  }
  let drop = current - digits
  let mut rounded = bigint_div_pow10_half_even(self.mantissa, drop)
  let mut scale = self.scale - drop
  if digit_count(rounded) > digits {
    // Rounding carried into a new digit.
    rounded = bigint_div_pow10(rounded, 1)
    scale = scale - 1
  }
  { mantissa: rounded, scale, }
}

///|
pub fn Decimal::round_to_integer(self : Decimal) -> Decimal {
  self.quantize(0)
}

///|
fn align_pair(
  a : Decimal,
  b : Decimal,
) -> (@bigint.BigInt, @bigint.BigInt, Int32) {
  let target = if a.scale > b.scale { a.scale } else { b.scale }
  let left = bigint_mul_pow10(a.mantissa, target - a.scale)
  let right = bigint_mul_pow10(b.mantissa, target - b.scale)
  (left, right, target)
}

///|
pub fn Decimal::add(a : Decimal, b : Decimal) -> Decimal {
  let (left, right, scale) = align_pair(a, b)
  let raw = { mantissa: left.add(right), scale, }
  raw.round_to_significant(decimal_precision)
}

///|
pub fn Decimal::sub(a : Decimal, b : Decimal) -> Decimal {
  let (left, right, scale) = align_pair(a, b)
  let raw = { mantissa: left.sub(right), scale, }
  raw.round_to_significant(decimal_precision)
}

///|
pub fn Decimal::mul(a : Decimal, b : Decimal) -> Decimal {
  let raw = { mantissa: a.mantissa.mul(b.mantissa), scale: a.scale + b.scale, }
  raw.round_to_significant(decimal_precision)
}

///|
fn count_factor(
  value : @bigint.BigInt,
  factor : Int32,
) -> (Int32, @bigint.BigInt) {
  let f = @bigint.BigInt::from_int(factor)
  let mut remaining = value
  let mut count = 0
  while !remaining.is_zero() {
    let q = remaining.div(f)
    let r = remaining.mod(f)
    if r.is_zero() {
      remaining = q
      count = count + 1
    } else {
      break
    }
  }
  (count, remaining)
}

///|
/// Decimal division following Python's `decimal` semantics at precision 28:
/// exact results keep at least the "ideal" exponent, inexact results are
/// rounded to 28 significant digits with ROUND_HALF_EVEN.
pub fn Decimal::div(a : Decimal, b : Decimal) -> Decimal? {
  if b.mantissa.is_zero() {
    return None
  }
  if a.mantissa.is_zero() {
    let ideal = a.scale - b.scale
    let scale = if ideal > 0 { ideal } else { 0 }
    return Some({ mantissa: @bigint.BigInt::from_int(0), scale, })
  }
  let neg = bigint_sign(a.mantissa) != bigint_sign(b.mantissa)
  let num0 = bigint_abs(a.mantissa)
  let den0 = bigint_abs(b.mantissa)
  let ideal_scale = a.scale - b.scale
  // Build a plain fraction num/den.
  let (num1, den1) = if b.scale >= a.scale {
    (bigint_mul_pow10(num0, b.scale - a.scale), den0)
  } else {
    (num0, bigint_mul_pow10(den0, a.scale - b.scale))
  }
  let g = bigint_gcd(num1, den1)
  let num = num1.div(g)
  let den = den1.div(g)
  let (twos, rest2) = count_factor(den, 2)
  let (fives, rest5) = count_factor(rest2, 5)
  let terminating = rest5.compare_int(1) == 0
  let result = if terminating {
    let exact_scale = if twos > fives { twos } else { fives }
    let exact_mantissa = bigint_mul_pow10(num, exact_scale).div(den)
    let scale = if ideal_scale > exact_scale {
      ideal_scale
    } else {
      exact_scale
    }
    let mantissa = bigint_mul_pow10(exact_mantissa, scale - exact_scale)
    let mut d = { mantissa, scale, }
    d = d.round_to_significant(decimal_precision)
    d
  } else {
    // Adjusted exponent d such that 10^d <= num/den < 10^(d+1).
    let mut exp = digit_count(num) - digit_count(den)
    let lower_ok = if exp >= 0 {
      num.compare(bigint_mul_pow10(den, exp)) >= 0
    } else {
      bigint_mul_pow10(num, -exp).compare(den) >= 0
    }
    if !lower_ok {
      exp = exp - 1
    }
    let target_scale = decimal_precision - 1 - exp
    let (scaled_num, scaled_den) = if target_scale >= 0 {
      (bigint_mul_pow10(num, target_scale), den)
    } else {
      (num, bigint_mul_pow10(den, -target_scale))
    }
    let q = scaled_num.div(scaled_den)
    let r = scaled_num.mod(scaled_den)
    let twice = r.mul(@bigint.BigInt::from_int(2))
    let up = if twice.compare(scaled_den) > 0 {
      true
    } else if twice.compare(scaled_den) == 0 {
      q.mod(@bigint.BigInt::from_int(2)).compare_int(0) != 0
    } else {
      false
    }
    let mut mantissa = if up { q.add(@bigint.BigInt::from_int(1)) } else { q }
    let mut scale = target_scale
    if digit_count(mantissa) > decimal_precision {
      mantissa = bigint_div_pow10(mantissa, 1)
      scale = scale - 1
    }
    { mantissa, scale, }
  }
  let signed = if neg { result.neg() } else { result }
  Some(signed)
}

///|
pub fn Decimal::compare(a : Decimal, b : Decimal) -> Int32 {
  let (left, right, _) = align_pair(a, b)
  left.compare(right)
}

///|
pub fn Decimal::equal(a : Decimal, b : Decimal) -> Bool {
  a.compare(b) == 0
}

///|
pub fn Decimal::less_than(a : Decimal, b : Decimal) -> Bool {
  a.compare(b) < 0
}

///|
pub fn Decimal::less_equal(a : Decimal, b : Decimal) -> Bool {
  a.compare(b) <= 0
}

///|
/// Returns 10^-scale, i.e. the value of the least significant digit.
pub fn Decimal::last_digit_place(self : Decimal) -> Decimal {
  if self.scale > 0 {
    { mantissa: @bigint.BigInt::from_int(1), scale: self.scale, }
  } else {
    Decimal::one()
  }
}

///|
/// True when the literal carries fractional digits (Beancount only infers a
/// tolerance from numbers with a fractional part).
pub fn Decimal::has_fractional_digits(self : Decimal) -> Bool {
  self.scale > 0
}

///|
pub fn Decimal::to_string(self : Decimal) -> String {
  let negative = bigint_sign(self.mantissa) < 0
  let digits = bigint_abs(self.mantissa).to_string()
  let sb = StringBuilder()
  if negative && !self.is_zero() {
    sb.write_char('-')
  }
  if self.scale <= 0 {
    sb.write_string(digits)
    if self.scale < 0 {
      sb.write_string("0".repeat(-self.scale))
    }
  } else if digits.length() <= self.scale {
    sb.write_string("0.")
    sb.write_string("0".repeat(self.scale - digits.length()))
    sb.write_string(digits)
  } else {
    let split = digits.length() - self.scale
    let mut i = 0
    for c in digits.iter() {
      if i == split {
        sb.write_char('.')
      }
      sb.write_char(c)
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// Human oriented formatting: trims trailing zeros but keeps at least
/// `min_scale` fractional digits.
pub fn Decimal::to_display(self : Decimal, min_scale~ : Int32 = 0) -> String {
  let raw = self.to_string()
  let dot = match raw.find(".") {
    Some(i) => i
    None => return raw
  }
  let mut end = raw.length()
  while end > dot + 1 + min_scale && raw.get_char(end - 1) == Some('0') {
    end = end - 1
  }
  if end == dot + 1 {
    end = dot
  }
  raw.unsafe_substring(start=0, end~)
}
