///|
fn unicode_in_ranges(c : Char, ranges : Array[(Int32, Int32)]) -> Bool {
  let n = c.to_int()
  let mut lo = 0
  let mut hi = ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (a, b) = ranges[mid]
    if n < a {
      hi = mid
    } else if n > b {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
fn unicode_case(text : String, upper : Bool) -> String {
  let chars = text.iter().to_array()
  let out = StringBuilder()
  for i in 0..<chars.length() {
    let c = chars[i]
    if !upper && c == 'Σ' {
      let mut before = i - 1
      while before >= 0 &&
            unicode_in_ranges(chars[before], unicode_ignorable_ranges) {
        before = before - 1
      }
      let mut after = i + 1
      while after < chars.length() &&
            unicode_in_ranges(chars[after], unicode_ignorable_ranges) {
        after = after + 1
      }
      let is_final = before >= 0 &&
        unicode_in_ranges(chars[before], unicode_cased_ranges) &&
        (
          after == chars.length() ||
          !unicode_in_ranges(chars[after], unicode_cased_ranges)
        )
      out.write_char(if is_final { 'ς' } else { 'σ' })
    } else {
      let piece = if upper {
        unicode_upper_piece(c)
      } else {
        unicode_lower_piece(c)
      }
      match piece {
        Some(s) => out.write_string(s)
        None => out.write_char(c)
      }
    }
  }
  out.to_string()
}
