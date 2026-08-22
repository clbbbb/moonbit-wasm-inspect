///| The standard `name` custom section is optional metadata. This decoder

///| handles the module-name and function-name subsections and deliberately

///|
/// preserves unknown subsections so new producers do not break inspection.
pub struct FunctionName {
  index : Int
  name : String
}

///|
pub struct NameSection {
  module_name : String?
  function_names : Array[FunctionName]
  unknown_subsection_ids : Array[Int]
}

///|
pub fn NameSection::function_name(self : NameSection, index : Int) -> String? {
  for item in self.function_names {
    if item.index == index {
      return Some(item.name)
    }
  }
  None
}

///|
pub fn NameSection::render(self : NameSection) -> String {
  let mut text = match self.module_name {
    Some(name) => "module name: " + name + "\n"
    None => "module name: <absent>\n"
  }
  text = text +
    "function names: " +
    self.function_names.length().to_string() +
    "\n"
  for item in self.function_names {
    text = text + "  [" + item.index.to_string() + "] " + item.name + "\n"
  }
  if self.unknown_subsection_ids.length() > 0 {
    text = text +
      "unknown name subsections: " +
      self.unknown_subsection_ids.length().to_string() +
      "\n"
  }
  text
}

///|
fn decode_function_names(
  cursor : Cursor,
) -> Result[Array[FunctionName], DecodeError] {
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let names : Array[FunctionName] = []
  for _ in 0..<count {
    let index = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let name = match cursor.read_name() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    for prior in names {
      if prior.index == index {
        return Err(
          ValidationError(
            cursor.position,
            "function name map contains duplicate index",
          ),
        )
      }
    }
    names.push({ index, name })
  }
  Ok(names)
}

///|
pub fn decode_name_section(
  binary : Module,
) -> Result[NameSection?, DecodeError] {
  let candidates = binary.custom_sections("name")
  if candidates.length() == 0 {
    return Ok(None)
  }
  if candidates.length() > 1 {
    return Err(
      ValidationError(
        candidates[1].full.start,
        "module contains more than one name custom section",
      ),
    )
  }
  let section = candidates[0]
  let outer = Cursor::with_bounds(
    binary.bytes,
    section.payload.start,
    section.payload.end,
  )
  match outer.read_name() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let mut module_name : String? = None
  let function_names : Array[FunctionName] = []
  let unknown : Array[Int] = []
  while !outer.is_finished() {
    let id = match outer.read_u8() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let size = match outer.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let payload = match outer.subcursor(size) {
      Ok(value) => value
      Err(_) =>
        return Err(
          ValidationError(
            outer.position,
            "name subsection extends past custom section",
          ),
        )
    }
    match id {
      0 => {
        if module_name is Some(_) {
          return Err(
            ValidationError(
              payload.position,
              "duplicate module-name subsection",
            ),
          )
        }
        module_name = match payload.read_name() {
          Ok(value) => Some(value)
          Err(error) => return Err(error)
        }
        if !payload.is_finished() {
          return Err(
            ValidationError(
              payload.position,
              "trailing bytes in module-name subsection",
            ),
          )
        }
      }
      1 => {
        let decoded = match decode_function_names(payload) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        for item in decoded {
          function_names.push(item)
        }
        if !payload.is_finished() {
          return Err(
            ValidationError(
              payload.position,
              "trailing bytes in function-name subsection",
            ),
          )
        }
      }
      _ => unknown.push(id)
    }
  }
  Ok(Some({ module_name, function_names, unknown_subsection_ids: unknown }))
}
