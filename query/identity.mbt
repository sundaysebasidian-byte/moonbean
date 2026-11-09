// RFC 1321 MD5, implemented for stable directive identities (not security use).

///|
let md5_constants : Array[UInt32] = [
  3614090360U, 3905402710U, 606105819U, 3250441966U, 4118548399U, 1200080426U, 2821735955U,
  4249261313U, 1770035416U, 2336552879U, 4294925233U, 2304563134U, 1804603682U, 4254626195U,
  2792965006U, 1236535329U, 4129170786U, 3225465664U, 643717713U, 3921069994U, 3593408605U,
  38016083U, 3634488961U, 3889429448U, 568446438U, 3275163606U, 4107603335U, 1163531501U,
  2850285829U, 4243563512U, 1735328473U, 2368359562U, 4294588738U, 2272392833U, 1839030562U,
  4259657740U, 2763975236U, 1272893353U, 4139469664U, 3200236656U, 681279174U, 3936430074U,
  3572445317U, 76029189U, 3654602809U, 3873151461U, 530742520U, 3299628645U, 4096336452U,
  1126891415U, 2878612391U, 4237533241U, 1700485571U, 2399980690U, 4293915773U, 2240044497U,
  1873313359U, 4264355552U, 2734768916U, 1309151649U, 4149444226U, 3174756917U, 718787259U,
  3951481745U,
]

///|
let md5_shifts : Array[Int32] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9,
  14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
]

///|
fn query_md5(text : String) -> String {
  let bytes : Array[UInt32] = []
  for c in text.iter() {
    let n = c.to_int().reinterpret_as_uint()
    if n < 128U {
      bytes.push(n)
    } else if n < 2048U {
      bytes.append([192U | (n >> 6), 128U | (n & 63U)])
    } else if n < 65536U {
      bytes.append([224U | (n >> 12), 128U | ((n >> 6) & 63U), 128U | (n & 63U)])
    } else {
      bytes.append([
        240U | (n >> 18),
        128U | ((n >> 12) & 63U),
        128U | ((n >> 6) & 63U),
        128U | (n & 63U),
      ])
    }
  }
  let length = bytes.length().to_int64() * 8L
  bytes.push(128U)
  while bytes.length() % 64 != 56 {
    bytes.push(0U)
  }
  for i in 0..<8 {
    bytes.push(
      ((length >> (8 * i)) & 255L).to_int().reinterpret_as_uint() & 255U,
    )
  }
  let state = [0x67452301U, 0xefcdab89U, 0x98badcfeU, 0x10325476U]
  let words : Array[UInt32] = Array::make(16, 0U)
  for block = 0; block < bytes.length(); block = block + 64 {
    for j in 0..<16 {
      let k = block + j * 4
      words[j] = bytes[k] |
        (bytes[k + 1] << 8) |
        (bytes[k + 2] << 16) |
        (bytes[k + 3] << 24)
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    for i in 0..<64 {
      let (f, g) = if i < 16 {
        ((b & c) | ((b ^ 0xffffffffU) & d), i)
      } else if i < 32 {
        ((d & b) | ((d ^ 0xffffffffU) & c), (5 * i + 1) % 16)
      } else if i < 48 {
        (b ^ c ^ d, (3 * i + 5) % 16)
      } else {
        (c ^ (b | (d ^ 0xffffffffU)), 7 * i % 16)
      }
      let n = a + f + md5_constants[i] + words[g]
      let shift = md5_shifts[i]
      a = d
      d = c
      c = b
      b = b + ((n << shift) | (n >> (32 - shift)))
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
  }
  let out = StringBuilder()
  for word in state {
    for j in 0..<4 {
      out.write_string(
        repr_hex(((word >> (j * 8)) & 255U).reinterpret_as_int(), 2),
      )
    }
  }
  out.to_string()
}

///|
test "MD5 identity encoding known vectors" {
  assert_eq(query_md5(""), "d41d8cd98f00b204e9800998ecf8427e")
  assert_eq(query_md5("abc"), "900150983cd24fb0d6963f7d28e17f72")
  assert_eq(
    query_md5("abcdefghijklmnopqrstuvwxyz"),
    "c3fcd3d76192e4007dfb496cca67e13b",
  )
}
