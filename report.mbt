///| Deterministic text reports for command-line tools, CI logs, and bug

///| reports. The formatter contains no terminal control codes so snapshots are

///|
/// stable across operating systems.
fn append_line(text : String, line : String) -> String {
  text + line + "\n"
}

///|
fn span_text(span : Span) -> String {
  "[" + span.start.to_string() + ", " + span.end.to_string() + ")"
}

///|
pub fn render_structure(binary : Module) -> String {
  let mut text = "WebAssembly binary v" + binary.version().to_string() + "\n"
  text = append_line(text, binary.stats().description())
  text = append_line(text, "sections:")
  for section in binary.sections() {
    let name = match section.custom_name {
      Some(value) => "custom " + value
      None => section.kind.label()
    }
    text = append_line(
      text,
      "  - " +
      name +
      " id=" +
      section.id.to_string() +
      " payload=" +
      span_text(section.payload) +
      " bytes=" +
      section.payload_size().to_string(),
    )
  }
  text
}

///|
fn render_type_list(types : Array[FunctionType]) -> String {
  let mut text = "types: " + types.length().to_string() + "\n"
  let mut index = 0
  for type_ in types {
    text = append_line(
      text,
      "  [" + index.to_string() + "] " + type_.signature(),
    )
    index = index + 1
  }
  text
}

///|
fn render_import_list(imports : Array[Import]) -> String {
  let mut text = "imports: " + imports.length().to_string() + "\n"
  for item in imports {
    let type_suffix = match item.type_index {
      Some(index) => " type=" + index.to_string()
      None => ""
    }
    text = append_line(
      text,
      "  - " +
      item.module_name +
      "." +
      item.name +
      " : " +
      item.kind.label() +
      type_suffix,
    )
  }
  text
}

///|
fn render_export_list(exports : Array[Export]) -> String {
  let mut text = "exports: " + exports.length().to_string() + "\n"
  for item in exports {
    text = append_line(
      text,
      "  - " +
      item.name +
      " : " +
      item.kind.label() +
      " #" +
      item.index.to_string(),
    )
  }
  text
}

///|
fn render_memory_list(memories : Array[MemoryInfo]) -> String {
  let mut text = "memories: " + memories.length().to_string() + "\n"
  let mut index = 0
  for memory in memories {
    let mode = if memory.limits.shared { ", shared" } else { "" }
    let width = if memory.limits.memory64 { ", memory64" } else { "" }
    text = append_line(
      text,
      "  [" +
      index.to_string() +
      "] " +
      memory.limits.description() +
      mode +
      width,
    )
    index = index + 1
  }
  text
}

///|
fn render_table_list(tables : Array[TableInfo]) -> String {
  let mut text = "tables: " + tables.length().to_string() + "\n"
  let mut index = 0
  for table in tables {
    text = append_line(
      text,
      "  [" +
      index.to_string() +
      "] " +
      table.element_type.label() +
      " " +
      table.limits.description(),
    )
    index = index + 1
  }
  text
}

///|
fn render_global_list(globals : Array[GlobalInfo]) -> String {
  let mut text = "globals: " + globals.length().to_string() + "\n"
  let mut index = 0
  for global in globals {
    let mutability = if global.mutable { "mutable" } else { "immutable" }
    text = append_line(
      text,
      "  [" +
      index.to_string() +
      "] " +
      global.value_type.label() +
      " " +
      mutability +
      " init=" +
      span_text(global.init_span),
    )
    index = index + 1
  }
  text
}

///|
pub fn render_decoded(decoded : DecodedModule) -> String {
  let mut text = render_structure(decoded.binary())
  text = text + render_type_list(decoded.types())
  text = text + render_import_list(decoded.imports())
  text = text + render_table_list(decoded.tables)
  text = text + render_memory_list(decoded.memories)
  text = text + render_global_list(decoded.globals)
  text = append_line(
    text,
    "defined functions: " + decoded.defined_function_count().to_string(),
  )
  text = append_line(
    text,
    "code bodies: " + decoded.code_bodies.length().to_string(),
  )
  text = text + render_export_list(decoded.exports())
  match decoded.start_function {
    Some(index) =>
      text = append_line(text, "start function: " + index.to_string())
    None => ()
  }
  if decoded.warnings().length() > 0 {
    text = append_line(text, "warnings:")
    for warning in decoded.warnings() {
      text = append_line(text, "  - " + warning)
    }
  }
  text
}

///|
pub struct SectionDifference {
  label : String
  left_size : Int?
  right_size : Int?
}

///|
pub fn SectionDifference::description(self : SectionDifference) -> String {
  let left = match self.left_size {
    Some(value) => value.to_string()
    None => "missing"
  }
  let right = match self.right_size {
    Some(value) => value.to_string()
    None => "missing"
  }
  self.label + ": " + left + " -> " + right
}

///|
pub fn diff_structure(
  left : Module,
  right : Module,
) -> Array[SectionDifference] {
  let differences : Array[SectionDifference] = []
  for kind_id in 0..<14 {
    let kind = match section_kind_from_id(kind_id) {
      Some(value) => value
      None => continue
    }
    let left_size = match left.find_section(kind) {
      Some(section) => Some(section.payload_size())
      None => None
    }
    let right_size = match right.find_section(kind) {
      Some(section) => Some(section.payload_size())
      None => None
    }
    if left_size != right_size {
      differences.push({ label: kind.label(), left_size, right_size })
    }
  }
  differences
}

///|
pub fn render_structure_diff(left : Module, right : Module) -> String {
  let differences = diff_structure(left, right)
  if differences.length() == 0 {
    "No structural section differences.\n"
  } else {
    let mut text = "Structural section differences:\n"
    for difference in differences {
      text = append_line(text, "  - " + difference.description())
    }
    text
  }
}
