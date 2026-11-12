///|
fn account_character_mask(c : Char) -> Int32 {
  let n = c.to_int()
  if n < 128 {
    if c >= 'A' && c <= 'Z' {
      return 5
    }
    if c >= 'a' && c <= 'z' {
      return 4
    }
    if c >= '0' && c <= '9' {
      return 6
    }
    return 0
  }
  let mut low = 0
  let mut high = account_unicode_ranges.length()
  while low < high {
    let mid = low + (high - low) / 2
    let (start, end, mask) = account_unicode_ranges[mid]
    if n < start {
      high = mid
    } else if n > end {
      low = mid + 1
    } else {
      return mask
    }
  }
  0
}

///|
pub fn valid_account_name(account : String) -> Bool {
  let parts = account_parts(account)
  if parts.length() < 2 {
    return false
  }
  for index in 0..<parts.length() {
    let chars = parts[index].iter().to_array()
    if chars.is_empty() {
      return false
    }
    let first = account_character_mask(chars[0])
    if (first & (if index == 0 { 1 } else { 3 })) == 0 {
      return false
    }
    for i in 1..<chars.length() {
      if chars[i] != '-' && (account_character_mask(chars[i]) & 4) == 0 {
        return false
      }
    }
  }
  true
}
