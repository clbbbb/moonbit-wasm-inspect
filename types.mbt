///| Core public data types used by the binary reader and module inspector.

pub enum DecodeError {
  UnexpectedEof(Int)
  InvalidLeb128(Int, String)
  InvalidHeader(String)
  InvalidSection(Int, Int, String)
  InvalidIndex(String, Int, Int)
  UnsupportedFeature(String, Int)
  InvalidUtf8(Int)
  ValidationError(Int, String)
}

pub fn DecodeError::message(self : DecodeError) -> String {
  match self {
    UnexpectedEof(position) => "unexpected end of input at " + position.to_string()
    InvalidLeb128(position, reason) =>
      "invalid LEB128 at " + position.to_string() + ": " + reason
    InvalidHeader(reason) => "invalid WebAssembly header: " + reason
    InvalidSection(id, position, reason) =>
      "invalid section " + id.to_string() + " at " + position.to_string() + ": " + reason
    InvalidIndex(kind, index, limit) =>
      "invalid " + kind + " index " + index.to_string() + " (limit " + limit.to_string() + ")"
    UnsupportedFeature(feature, position) =>
      "unsupported feature " + feature + " at " + position.to_string()
    InvalidUtf8(position) => "invalid UTF-8-like byte sequence at " + position.to_string()
    ValidationError(position, message) => "validation error at " + position.to_string() + ": " + message
  }
}

pub struct Span {
  start : Int
  end : Int
}

pub fn Span::size(self : Span) -> Int { self.end - self.start }

pub fn Span::contains(self : Span, position : Int) -> Bool {
  position >= self.start && position < self.end
}

pub struct Cursor {
  bytes : Array[Int]
  pub mut position : Int
  limit : Int
}

pub fn Cursor::new(bytes : Array[Int]) -> Cursor {
  { bytes, position: 0, limit: bytes.length() }
}

fn Cursor::with_bounds(bytes : Array[Int], position : Int, limit : Int) -> Cursor {
  { bytes, position, limit }
}

pub fn Cursor::remaining(self : Cursor) -> Int { self.limit - self.position }

pub fn Cursor::is_finished(self : Cursor) -> Bool { self.position == self.limit }

pub fn Cursor::span(self : Cursor) -> Span { { start: self.position, end: self.limit } }
