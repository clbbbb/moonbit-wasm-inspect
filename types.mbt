///|
/// Core public data types used by the binary reader and module inspector.
pub enum DecodeError {
  UnexpectedEof(Int32)
  InvalidLeb128(Int32, String)
  InvalidHeader(String)
  InvalidSection(Int32, Int32, String)
  UnsupportedFeature(String, Int32)
  InvalidUtf8(Int32)
  ValidationError(Int32, String)
}

///|
pub fn DecodeError::message(self : DecodeError) -> String {
  match self {
    UnexpectedEof(position) =>
      "unexpected end of input at " + position.to_string()
    InvalidLeb128(position, reason) =>
      "invalid LEB128 at " + position.to_string() + ": " + reason
    InvalidHeader(reason) => "invalid WebAssembly header: " + reason
    InvalidSection(id, position, reason) =>
      "invalid section " +
      id.to_string() +
      " at " +
      position.to_string() +
      ": " +
      reason
    UnsupportedFeature(feature, position) =>
      "unsupported feature " + feature + " at " + position.to_string()
    InvalidUtf8(position) =>
      "invalid UTF-8-like byte sequence at " + position.to_string()
    ValidationError(position, message) =>
      "validation error at " + position.to_string() + ": " + message
  }
}

///|
pub struct Span {
  start : Int32
  end : Int32
}

///|
pub fn Span::size(self : Span) -> Int32 {
  self.end - self.start
}

///|
pub fn Span::contains(self : Span, position : Int32) -> Bool {
  position >= self.start && position < self.end
}

///|
pub struct Cursor {
  bytes : Array[Int32]
  mut position : Int32
  limit : Int32
}

///|
pub fn Cursor::new(bytes : Array[Int32]) -> Cursor {
  { bytes, position: 0, limit: bytes.length(), }
}

///|
fn Cursor::with_bounds(
  bytes : Array[Int32],
  position : Int32,
  limit : Int32,
) -> Cursor {
  { bytes, position, limit, }
}

///|
pub fn Cursor::remaining(self : Cursor) -> Int32 {
  self.limit - self.position
}

///|
pub fn Cursor::is_finished(self : Cursor) -> Bool {
  self.position == self.limit
}

///|
pub fn Cursor::span(self : Cursor) -> Span {
  { start: self.position, end: self.limit, }
}
