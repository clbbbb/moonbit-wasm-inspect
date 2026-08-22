///| Decoders for the index-bearing sections of a version-1 WebAssembly module.

///| They are intentionally separate from `parse_module`: a caller can choose a

///|
/// fast structural inspection or a complete metadata pass.
fn section_cursor(binary : Module, kind : SectionKind) -> Cursor? {
  match binary.find_section(kind) {
    None => None
    Some(section) =>
      Some(
        Cursor::with_bounds(
          binary.bytes,
          section.payload.start,
          section.payload.end,
        ),
      )
  }
}

///|
fn expect_finished(
  cursor : Cursor,
  kind : SectionKind,
) -> Result[Unit, DecodeError] {
  if cursor.is_finished() {
    Ok(())
  } else {
    Err(
      InvalidSection(
        kind.id(),
        cursor.position,
        "trailing bytes in decoded payload",
      ),
    )
  }
}

///|
fn read_value_type(cursor : Cursor) -> Result[ValueType, DecodeError] {
  let position = cursor.position
  match cursor.read_u8() {
    Err(error) => Err(error)
    Ok(byte) =>
      match value_type_from_byte(byte) {
        Some(value) => Ok(value)
        None =>
          Err(UnsupportedFeature("value type " + byte.to_string(), position))
      }
  }
}

///|
fn read_value_vector(cursor : Cursor) -> Result[Array[ValueType], DecodeError] {
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let values : Array[ValueType] = []
  for _ in 0..<count {
    match read_value_type(cursor) {
      Ok(value) => values.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(values)
}

///|
fn read_external_kind(cursor : Cursor) -> Result[ExternalKind, DecodeError] {
  let position = cursor.position
  match cursor.read_u8() {
    Err(error) => Err(error)
    Ok(0) => Ok(FunctionExternal)
    Ok(1) => Ok(TableExternal)
    Ok(2) => Ok(MemoryExternal)
    Ok(3) => Ok(GlobalExternal)
    Ok(4) => Ok(TagExternal)
    Ok(value) =>
      Err(
        InvalidSection(
          2,
          position,
          "unknown external kind " + value.to_string(),
        ),
      )
  }
}

///|
fn read_limits(cursor : Cursor) -> Result[Limits, DecodeError] {
  let position = cursor.position
  let flags = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if flags < 0 || flags > 7 {
    return Err(
      UnsupportedFeature("limits flags " + flags.to_string(), position),
    )
  }
  let minimum = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let maximum = if (flags & 1) != 0 {
    match cursor.read_var_u32() {
      Ok(value) => Some(value)
      Err(error) => return Err(error)
    }
  } else {
    None
  }
  match maximum {
    Some(value) if value < minimum =>
      Err(ValidationError(position, "limits maximum is less than minimum"))
    _ =>
      Ok({
        minimum,
        maximum,
        shared: (flags & 2) != 0,
        memory64: (flags & 4) != 0,
      })
  }
}

///|
fn skip_const_expr(cursor : Cursor) -> Result[Span, DecodeError] {
  let start = cursor.position
  let mut done = false
  while !done {
    let position = cursor.position
    match cursor.read_u8() {
      Err(error) => return Err(error)
      Ok(0x0b) => done = true
      Ok(0x41) =>
        match cursor.read_var_i32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      Ok(0x42) => {
        // i64.const is encoded as signed LEB128 and may need ten bytes.
        let mut count = 0
        let mut finished = false
        while !finished {
          if count == 10 {
            return Err(InvalidLeb128(position, "i64 constant is too long"))
          }
          match cursor.read_u8() {
            Err(error) => return Err(error)
            Ok(byte) => {
              count = count + 1
              finished = (byte & 0x80) == 0
            }
          }
        }
      }
      Ok(0x43) =>
        match cursor.skip(4) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      Ok(0x44) =>
        match cursor.skip(8) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      Ok(0x23) | Ok(0xd0) | Ok(0xd2) =>
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      Ok(opcode) =>
        return Err(
          UnsupportedFeature(
            "constant-expression opcode " + opcode.to_string(),
            position,
          ),
        )
    }
  }
  Ok({ start, end: cursor.position })
}

///|
fn decode_type_section(
  binary : Module,
) -> Result[Array[FunctionType], DecodeError] {
  let cursor = match section_cursor(binary, Type) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let types : Array[FunctionType] = []
  for _ in 0..<count {
    let position = cursor.position
    match cursor.read_u8() {
      Ok(0x60) => ()
      Ok(value) =>
        return Err(
          UnsupportedFeature("type form " + value.to_string(), position),
        )
      Err(error) => return Err(error)
    }
    let params = match read_value_vector(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let results = match read_value_vector(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    types.push({ params, results })
  }
  match expect_finished(cursor, Type) {
    Ok(_) => Ok(types)
    Err(error) => Err(error)
  }
}

///|
fn decode_import_section(binary : Module) -> Result[Array[Import], DecodeError] {
  let cursor = match section_cursor(binary, Import) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let imports : Array[Import] = []
  for _ in 0..<count {
    let module_name = match cursor.read_name() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let name = match cursor.read_name() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let kind = match read_external_kind(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let type_index = match kind {
      FunctionExternal | TagExternal =>
        match cursor.read_var_u32() {
          Ok(value) => Some(value)
          Err(error) => return Err(error)
        }
      TableExternal => {
        match read_value_type(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        match read_limits(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        None
      }
      MemoryExternal => {
        match read_limits(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        None
      }
      GlobalExternal => {
        match read_value_type(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        match cursor.read_u8() {
          Ok(0) | Ok(1) => ()
          Ok(value) =>
            return Err(
              ValidationError(
                cursor.position - 1,
                "invalid global mutability " + value.to_string(),
              ),
            )
          Err(error) => return Err(error)
        }
        None
      }
    }
    imports.push({ module_name, name, kind, type_index })
  }
  match expect_finished(cursor, Import) {
    Ok(_) => Ok(imports)
    Err(error) => Err(error)
  }
}

///|
fn decode_function_section(binary : Module) -> Result[Array[Int], DecodeError] {
  let cursor = match section_cursor(binary, Function) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let types : Array[Int] = []
  for _ in 0..<count {
    match cursor.read_var_u32() {
      Ok(value) => types.push(value)
      Err(error) => return Err(error)
    }
  }
  match expect_finished(cursor, Function) {
    Ok(_) => Ok(types)
    Err(error) => Err(error)
  }
}

///|
fn decode_table_section(
  binary : Module,
) -> Result[Array[TableInfo], DecodeError] {
  let cursor = match section_cursor(binary, Table) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tables : Array[TableInfo] = []
  for _ in 0..<count {
    let element_type = match read_value_type(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    match element_type {
      FuncRef | ExternRef => ()
      _ =>
        return Err(
          ValidationError(
            cursor.position - 1,
            "table element type must be a reference type",
          ),
        )
    }
    let limits = match read_limits(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    tables.push({ element_type, limits })
  }
  match expect_finished(cursor, Table) {
    Ok(_) => Ok(tables)
    Err(error) => Err(error)
  }
}

///|
fn decode_memory_section(
  binary : Module,
) -> Result[Array[MemoryInfo], DecodeError] {
  let cursor = match section_cursor(binary, Memory) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let memories : Array[MemoryInfo] = []
  for _ in 0..<count {
    let limits = match read_limits(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if limits.shared && limits.maximum is None {
      return Err(
        ValidationError(cursor.position, "shared memories require a maximum"),
      )
    }
    memories.push({ limits, })
  }
  match expect_finished(cursor, Memory) {
    Ok(_) => Ok(memories)
    Err(error) => Err(error)
  }
}

///|
fn decode_global_section(
  binary : Module,
) -> Result[Array[GlobalInfo], DecodeError] {
  let cursor = match section_cursor(binary, Global) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let globals : Array[GlobalInfo] = []
  for _ in 0..<count {
    let value_type = match read_value_type(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let mutable = match cursor.read_u8() {
      Ok(0) => false
      Ok(1) => true
      Ok(value) =>
        return Err(
          ValidationError(
            cursor.position - 1,
            "invalid global mutability " + value.to_string(),
          ),
        )
      Err(error) => return Err(error)
    }
    let init_span = match skip_const_expr(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    globals.push({ value_type, mutable, init_span })
  }
  match expect_finished(cursor, Global) {
    Ok(_) => Ok(globals)
    Err(error) => Err(error)
  }
}

///|
fn decode_export_section(binary : Module) -> Result[Array[Export], DecodeError] {
  let cursor = match section_cursor(binary, Export) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let exports : Array[Export] = []
  for _ in 0..<count {
    let name = match cursor.read_name() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let kind = match read_external_kind(cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let index = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    exports.push({ name, kind, index })
  }
  match expect_finished(cursor, Export) {
    Ok(_) => Ok(exports)
    Err(error) => Err(error)
  }
}

///|
fn decode_start_section(binary : Module) -> Result[Int?, DecodeError] {
  let cursor = match section_cursor(binary, Start) {
    Some(value) => value
    None => return Ok(None)
  }
  let index = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match expect_finished(cursor, Start) {
    Ok(_) => Ok(Some(index))
    Err(error) => Err(error)
  }
}

///|
fn decode_code_section(binary : Module) -> Result[Array[CodeBody], DecodeError] {
  let cursor = match section_cursor(binary, Code) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let bodies : Array[CodeBody] = []
  for _ in 0..<count {
    let body_size = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let body = match cursor.subcursor(body_size) {
      Ok(value) => value
      Err(_) =>
        return Err(
          InvalidSection(
            Code.id(),
            cursor.position,
            "function body extends past code section",
          ),
        )
    }
    let group_count = match body.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let locals : Array[ValueType] = []
    for _ in 0..<group_count {
      let local_count = match body.read_var_u32() {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let type_ = match read_value_type(body) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for _ in 0..<local_count {
        locals.push(type_)
      }
    }
    let instruction_start = body.position
    match body.skip(body.remaining()) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    bodies.push({
      locals,
      instruction_span: { start: instruction_start, end: body.position },
      byte_length: body_size,
    })
  }
  match expect_finished(cursor, Code) {
    Ok(_) => Ok(bodies)
    Err(error) => Err(error)
  }
}

///|
fn decode_data_count_section(binary : Module) -> Result[Int?, DecodeError] {
  let cursor = match section_cursor(binary, DataCount) {
    Some(value) => value
    None => return Ok(None)
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match expect_finished(cursor, DataCount) {
    Ok(_) => Ok(Some(count))
    Err(error) => Err(error)
  }
}

///|
fn decode_tag_section(binary : Module) -> Result[Array[TagInfo], DecodeError] {
  let cursor = match section_cursor(binary, Tag) {
    Some(value) => value
    None => return Ok([])
  }
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tags : Array[TagInfo] = []
  for _ in 0..<count {
    let position = cursor.position
    match cursor.read_u8() {
      Ok(0) => ()
      Ok(attribute) =>
        return Err(
          UnsupportedFeature("tag attribute " + attribute.to_string(), position),
        )
      Err(error) => return Err(error)
    }
    let type_index = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    tags.push({ type_index, })
  }
  match expect_finished(cursor, Tag) {
    Ok(_) => Ok(tags)
    Err(error) => Err(error)
  }
}

///|
pub fn decode_module(binary : Module) -> Result[DecodedModule, DecodeError] {
  let types = match decode_type_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let imports = match decode_import_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let function_types = match decode_function_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tables = match decode_table_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let memories = match decode_memory_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let globals = match decode_global_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let exports = match decode_export_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let start_function = match decode_start_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let element_segments = match decode_element_segments(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let code_bodies = match decode_code_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let data_segments = match decode_data_segments(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let data_count = match decode_data_count_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let tags = match decode_tag_section(binary) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let warnings : Array[String] = []
  if function_types.length() != code_bodies.length() {
    warnings.push(
      "function section has " +
      function_types.length().to_string() +
      " entries but code section has " +
      code_bodies.length().to_string(),
    )
  }
  Ok({
    binary,
    types,
    imports,
    function_types,
    tables,
    memories,
    globals,
    exports,
    start_function,
    code_bodies,
    element_segments,
    data_segments,
    data_count,
    tags,
    warnings,
  })
}
