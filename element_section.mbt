///| Element segments initialise tables or provide passive/declarative function

///| references. The MVP decoder supports the function-index forms used by the

///|
/// core binary format and reports expression-based reference forms explicitly.
pub enum ElementMode {
  ActiveElement(Int, Span)
  PassiveElement
  DeclarativeElement
}

///|
pub struct ElementSegment {
  mode : ElementMode
  functions : Array[Int]
}

///|
pub fn ElementSegment::description(self : ElementSegment) -> String {
  let mode = match self.mode {
    ActiveElement(table, _) => "active table=" + table.to_string()
    PassiveElement => "passive"
    DeclarativeElement => "declarative"
  }
  mode + " functions=" + self.functions.length().to_string()
}

///|
fn read_function_indices(cursor : Cursor) -> Result[Array[Int], DecodeError] {
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let indices : Array[Int] = []
  for _ in 0..<count {
    match cursor.read_var_u32() {
      Ok(value) => indices.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(indices)
}

///|
pub fn decode_element_segments(
  binary : Module,
) -> Result[Array[ElementSegment], DecodeError] {
  let cursor = match section_cursor(binary, Element) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let segments : Array[ElementSegment] = []
  for _ in 0..<count {
    let position = cursor.position
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
        ActiveElement(0, offset)
      }
      1 => {
        match cursor.read_u8() {
          Ok(0) => ()
          Ok(_) =>
            return Err(UnsupportedFeature("non-funcref element type", position))
          Err(error) => return Err(error)
        }
        PassiveElement
      }
      2 => {
        let table = match cursor.read_var_u32() {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        let offset = match skip_const_expr(cursor) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        match cursor.read_u8() {
          Ok(0) => ()
          Ok(_) =>
            return Err(UnsupportedFeature("non-funcref element type", position))
          Err(error) => return Err(error)
        }
        ActiveElement(table, offset)
      }
      3 => {
        match cursor.read_u8() {
          Ok(0) => ()
          Ok(_) =>
            return Err(UnsupportedFeature("non-funcref element type", position))
          Err(error) => return Err(error)
        }
        DeclarativeElement
      }
      4..=7 =>
        return Err(
          UnsupportedFeature("expression-based element segment", position),
        )
      _ =>
        return Err(
          UnsupportedFeature(
            "element segment flag " + flags.to_string(),
            position,
          ),
        )
    }
    let functions = match read_function_indices(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    segments.push({ mode, functions })
  }
  match expect_finished(cursor, Element) {
    Ok(_) => Ok(segments)
    Err(error) => Err(error)
  }
}

///|
pub fn render_element_segments(segments : Array[ElementSegment]) -> String {
  let mut text = "element segments: " + segments.length().to_string() + "\n"
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
