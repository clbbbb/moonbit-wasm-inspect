///| Structural parser for WebAssembly binary modules. It validates the file

///| header, section framing, known section IDs, and standard-section ordering

///|
/// before any section-specific decoder is invoked.
fn read_header_byte(
  cursor : Cursor,
  expected : Int,
  label : String,
) -> Result[Unit, DecodeError] {
  match cursor.read_u8() {
    Err(error) => Err(error)
    Ok(actual) =>
      if actual == expected {
        Ok(())
      } else {
        Err(
          InvalidHeader(
            label +
            " expected " +
            expected.to_string() +
            " but found " +
            actual.to_string(),
          ),
        )
      }
  }
}

///|
fn parse_header(cursor : Cursor) -> Result[Int, DecodeError] {
  match read_header_byte(cursor, 0x00, "magic[0]") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match read_header_byte(cursor, 0x61, "magic[1]") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match read_header_byte(cursor, 0x73, "magic[2]") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match read_header_byte(cursor, 0x6d, "magic[3]") {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let mut version = 0
  let mut shift = 0
  while shift < 32 {
    match cursor.read_u8() {
      Err(error) => return Err(error)
      Ok(byte) => version = version | (byte << shift)
    }
    shift = shift + 8
  }
  if version != 1 {
    Err(
      InvalidHeader(
        "only binary format version 1 is supported, found " +
        version.to_string(),
      ),
    )
  } else {
    Ok(version)
  }
}

///|
fn check_section_order(
  kind : SectionKind,
  previous : Int,
  position : Int,
) -> Result[Int, DecodeError] {
  if kind == Custom {
    Ok(previous)
  } else if kind.id() <= previous {
    Err(
      InvalidSection(
        kind.id(),
        position,
        "standard sections must be strictly ordered and unique",
      ),
    )
  } else {
    Ok(kind.id())
  }
}

///|
fn custom_section_name(payload : Cursor) -> Result[String?, DecodeError] {
  if payload.is_finished() {
    Err(
      ValidationError(payload.position, "custom section must begin with a name"),
    )
  } else {
    match payload.read_name() {
      Ok(name) => Ok(Some(name))
      Err(error) => Err(error)
    }
  }
}

///|
pub fn parse_module(bytes : Array[Int]) -> Result[Module, DecodeError] {
  let cursor = Cursor::new(bytes)
  let version = match parse_header(cursor) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let sections : Array[Section] = []
  let mut previous_standard = 0
  while !cursor.is_finished() {
    let full_start = cursor.position
    let id = match cursor.read_u8() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let kind = match section_kind_from_id(id) {
      Some(value) => value
      None => return Err(InvalidSection(id, full_start, "unknown section id"))
    }
    previous_standard = match
      check_section_order(kind, previous_standard, full_start) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let declared_size = match cursor.read_var_u32() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let payload_start = cursor.position
    let payload_cursor = match cursor.subcursor(declared_size) {
      Ok(value) => value
      Err(_) =>
        return Err(
          InvalidSection(
            id, full_start, "declared payload extends past end of module",
          ),
        )
    }
    let custom_name = if kind == Custom {
      match custom_section_name(payload_cursor) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    } else {
      None
    }
    sections.push({
      id,
      kind,
      payload: { start: payload_start, end: payload_start + declared_size },
      full: { start: full_start, end: cursor.position },
      custom_name,
    })
  }
  Ok({ bytes, sections, version })
}

///|
pub struct ModuleStats {
  byte_length : Int
  section_count : Int
  custom_section_count : Int
  payload_bytes : Int
}

///|
pub fn ModuleStats::description(self : ModuleStats) -> String {
  "module has " +
  self.section_count.to_string() +
  " sections (" +
  self.custom_section_count.to_string() +
  " custom), " +
  self.byte_length.to_string() +
  " bytes total and " +
  self.payload_bytes.to_string() +
  " payload bytes"
}

///|
pub fn Module::stats(self : Module) -> ModuleStats {
  let mut custom = 0
  let mut payload = 0
  for section in self.sections {
    payload = payload + section.payload_size()
    if section.kind == Custom {
      custom = custom + 1
    }
  }
  {
    byte_length: self.byte_length(),
    section_count: self.section_count(),
    custom_section_count: custom,
    payload_bytes: payload,
  }
}

///|
pub fn Module::has_section(self : Module, kind : SectionKind) -> Bool {
  match self.find_section(kind) {
    Some(_) => true
    None => false
  }
}

///|
pub fn Module::section_labels(self : Module) -> Array[String] {
  let labels : Array[String] = []
  for section in self.sections {
    let label = match section.custom_name {
      Some(name) => "custom:" + name
      None => section.kind.label()
    }
    labels.push(label)
  }
  labels
}
