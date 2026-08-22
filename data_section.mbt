///| Data-section decoding exposes passive and active initialisation segments

///| without copying their byte payloads. Keeping source spans makes the API

///|
/// suitable for large modules and for tools that need to hash only one blob.
pub enum DataMode {
  ActiveData(Int, Span)
  PassiveData
}

///|
pub struct DataSegment {
  mode : DataMode
  bytes : Span
}

///|
pub fn DataSegment::byte_length(self : DataSegment) -> Int {
  self.bytes.size()
}

///|
pub fn DataSegment::description(self : DataSegment) -> String {
  match self.mode {
    ActiveData(memory, offset) =>
      "active memory=" +
      memory.to_string() +
      " offset=" +
      span_text(offset) +
      " bytes=" +
      self.byte_length().to_string()
    PassiveData => "passive bytes=" + self.byte_length().to_string()
  }
}

///|
fn read_blob_span(cursor : Cursor) -> Result[Span, DecodeError] {
  let size = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let start = cursor.position
  match cursor.skip(size) {
    Ok(_) => Ok({ start, end: start + size })
    Err(_) =>
      Err(ValidationError(start, "data payload extends past section boundary"))
  }
}

///|
pub fn decode_data_segments(
  binary : Module,
) -> Result[Array[DataSegment], DecodeError] {
  let cursor = match section_cursor(binary, Data) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let segments : Array[DataSegment] = []
  for _ in 0..<count {
    let flag_position = cursor.position
    let flags = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let mode = match flags {
      0 => {
        let offset = match skip_const_expr(cursor) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        ActiveData(0, offset)
      }
      1 => PassiveData
      2 => {
        let memory = match cursor.read_var_u32() {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let offset = match skip_const_expr(cursor) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        ActiveData(memory, offset)
      }
      _ =>
        return Err(
          UnsupportedFeature(
            "data segment flag " + flags.to_string(),
            flag_position,
          ),
        )
    }
    let bytes = match read_blob_span(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    segments.push({ mode, bytes })
  }
  match expect_finished(cursor, Data) {
    Ok(_) => Ok(segments)
    Err(error) => Err(error)
  }
}

///|
pub fn data_segment_bytes(binary : Module, segment : DataSegment) -> Array[Int] {
  let output : Array[Int] = []
  for position in segment.bytes.start..<segment.bytes.end {
    output.push(binary.bytes[position])
  }
  output
}

///|
pub fn render_data_segments(segments : Array[DataSegment]) -> String {
  let mut text = "data segments: " + segments.length().to_string() + "\n"
  let mut index = 0
  for segment in segments {
    text = text +
      "  [" +
      index.to_string() +
      "] " +
      segment.description() +
      "\n"
    index = index + 1
  }
  text
}
