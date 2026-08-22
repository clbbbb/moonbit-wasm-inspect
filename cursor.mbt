///| Bounds-checked binary cursor. WebAssembly bytes are modelled as integers

///| in the inclusive range 0..255 so callers can construct examples without

///|
/// relying on a filesystem or a host-specific byte type.
pub fn Cursor::read_u8(self : Cursor) -> Result[Int, DecodeError] {
  if self.position >= self.limit {
    Err(UnexpectedEof(self.position))
  } else {
    let value = self.bytes[self.position]
    self.position = self.position + 1
    Ok(value)
  }
}

///|
pub fn Cursor::peek_u8(self : Cursor) -> Result[Int, DecodeError] {
  if self.position >= self.limit {
    Err(UnexpectedEof(self.position))
  } else {
    Ok(self.bytes[self.position])
  }
}

///|
pub fn Cursor::skip(self : Cursor, count : Int) -> Result[Unit, DecodeError] {
  if count < 0 || count > self.remaining() {
    Err(UnexpectedEof(self.position))
  } else {
    self.position = self.position + count
    Ok(())
  }
}

///|
pub fn Cursor::read_slice(
  self : Cursor,
  count : Int,
) -> Result[Array[Int], DecodeError] {
  if count < 0 || count > self.remaining() {
    Err(UnexpectedEof(self.position))
  } else {
    let output : Array[Int] = []
    let stop = self.position + count
    while self.position < stop {
      output.push(self.bytes[self.position])
      self.position = self.position + 1
    }
    Ok(output)
  }
}

///|
pub fn Cursor::subcursor(
  self : Cursor,
  count : Int,
) -> Result[Cursor, DecodeError] {
  if count < 0 || count > self.remaining() {
    Err(UnexpectedEof(self.position))
  } else {
    let start = self.position
    self.position = self.position + count
    Ok(Cursor::with_bounds(self.bytes, start, start + count))
  }
}

///|
pub fn Cursor::read_var_u32(self : Cursor) -> Result[Int, DecodeError] {
  let start = self.position
  let mut result = 0
  let mut shift = 0
  let mut finished = false
  while !finished {
    if shift >= 35 {
      return Err(InvalidLeb128(start, "more than five bytes"))
    }
    match self.read_u8() {
      Err(error) => return Err(error)
      Ok(byte) => {
        let payload = byte & 0x7f
        result = result | (payload << shift)
        if (byte & 0x80) == 0 {
          if shift == 28 && payload > 0x0f {
            return Err(InvalidLeb128(start, "u32 overflow"))
          }
          finished = true
        } else {
          shift = shift + 7
        }
      }
    }
  }
  Ok(result)
}

///|
pub fn Cursor::read_var_i32(self : Cursor) -> Result[Int, DecodeError] {
  let start = self.position
  let mut result = 0
  let mut shift = 0
  let mut final_byte = 0
  let mut finished = false
  while !finished {
    if shift >= 35 {
      return Err(InvalidLeb128(start, "more than five bytes"))
    }
    match self.read_u8() {
      Err(error) => return Err(error)
      Ok(byte) => {
        final_byte = byte
        result = result | ((byte & 0x7f) << shift)
        shift = shift + 7
        if (byte & 0x80) == 0 {
          finished = true
        }
      }
    }
  }
  if shift < 32 && (final_byte & 0x40) != 0 {
    result = result | (-1 << shift)
  }
  Ok(result)
}

///|
pub fn Cursor::read_name(self : Cursor) -> Result[String, DecodeError] {
  let start = self.position
  match self.read_var_u32() {
    Err(error) => Err(error)
    Ok(length) =>
      match self.read_slice(length) {
        Err(error) => Err(error)
        Ok(bytes) => {
          let mut text = ""
          for byte in bytes {
            if byte < 0x20 || byte > 0x7e {
              return Err(InvalidUtf8(start))
            }
            text = text + byte.unsafe_to_char().to_string()
          }
          Ok(text)
        }
      }
  }
}
