///|
/// Numeric value of a Unicode decimal digit (Nd), using the pinned Unicode 16 data.
pub fn decimal_digit(c : Char) -> Int32? {
  let n = c.to_int()
  if n < 128 {
    return if c.is_ascii_digit() { Some(n - 48) } else { None }
  }
  for start in unicode_decimal_starts {
    if n < start {
      break
    }
    if n < start + 10 {
      return Some(n - start)
    }
  }
  None
}
