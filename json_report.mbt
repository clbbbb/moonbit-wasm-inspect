///| Dependency-free JSON rendering for metadata that has already been parsed.

///| Strings are escaped here rather than delegated to callers, making reports

///|
/// safe to consume in CI artifacts and editor integrations.
fn json_escape(value : String) -> String {
  let mut text = ""
  for char in value {
    match char {
      '"' => text = text + "\\\""
      '\\' => text = text + "\\\\"
      '\n' => text = text + "\\n"
      '\r' => text = text + "\\r"
      '\t' => text = text + "\\t"
      _ if char.to_int() < 0x20 =>
        text = text + "\\u00" + json_hex_byte(char.to_int())
      _ => text = text + char.to_string()
    }
  }
  text
}

///|
pub fn json_quote(value : String) -> String {
  "\"" + json_escape(value) + "\""
}

///|
fn json_hex_digit(value : Int32) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    15 => "f"
    _ => "0"
  }
}

///|
fn json_hex_byte(value : Int32) -> String {
  json_hex_digit((value >> 4) & 0x0f) + json_hex_digit(value & 0x0f)
}

///|
fn json_array(values : Array[String]) -> String {
  let mut text = "["
  let mut first = true
  for value in values {
    if !first {
      text = text + ","
    }
    text = text + value
    first = false
  }
  text + "]"
}

///|
fn json_string_array(values : Array[String]) -> String {
  let encoded : Array[String] = []
  for value in values {
    encoded.push(json_quote(value))
  }
  json_array(encoded)
}

///|
fn json_int32_array(values : Array[Int32]) -> String {
  let encoded : Array[String] = []
  for value in values {
    encoded.push(value.to_string())
  }
  json_array(encoded)
}

///|
fn json_optional_int32(value : Int32?) -> String {
  match value {
    Some(number) => number.to_string()
    None => "null"
  }
}

///|
fn json_optional_string(value : String?) -> String {
  match value {
    Some(text) => json_quote(text)
    None => "null"
  }
}

///|
pub fn render_call_graph_analysis_json(report : CallGraphAnalysis) -> String {
  let functions : Array[String] = []
  for function in report.functions() {
    functions.push(
      "{\"index\":" +
      function.function_index.to_string() +
      ",\"typeIndex\":" +
      json_optional_int32(function.type_index) +
      ",\"imported\":" +
      function.imported.to_string() +
      ",\"importName\":" +
      json_optional_string(function.import_name) +
      ",\"exportNames\":" +
      json_string_array(function.export_names) +
      ",\"directCallees\":" +
      json_int32_array(function.direct_callees) +
      ",\"instructionCount\":" +
      function.instruction_count.to_string() +
      ",\"bodyBytes\":" +
      function.body_bytes.to_string() +
      ",\"controlBlocks\":" +
      function.control_blocks.to_string() +
      ",\"branches\":" +
      function.branches.to_string() +
      ",\"calls\":" +
      function.calls.to_string() +
      ",\"memoryAccesses\":" +
      function.memory_accesses.to_string() +
      ",\"localAccesses\":" +
      function.local_accesses.to_string() +
      ",\"cyclomaticEstimate\":" +
      function.cyclomatic_estimate.to_string() +
      ",\"directlyReachableFromRoots\":" +
      function.directly_reachable_from_roots.to_string() +
      ",\"recursive\":" +
      function.recursive.to_string() +
      "}",
    )
  }
  "{\"functions\":" +
  json_array(functions) +
  ",\"directCallEdges\":" +
  report.direct_call_edges.to_string() +
  ",\"indirectCallSites\":" +
  report.indirect_call_sites.to_string() +
  ",\"exportedFunctionCount\":" +
  report.exported_function_count.to_string() +
  ",\"directlyReachableFunctionCount\":" +
  report.reachable_function_count.to_string() +
  ",\"unreachedDefinedFunctionCount\":" +
  report.unreachable_defined_count.to_string() +
  ",\"recursiveFunctionCount\":" +
  report.recursive_function_count.to_string() +
  "}"
}

///|
pub fn render_binary_diff_json(changes : Array[BinarySectionChange]) -> String {
  let values : Array[String] = []
  for change in changes {
    values.push(
      "{\"section\":" +
      json_quote(change.section_label) +
      ",\"occurrence\":" +
      change.occurrence.to_string() +
      ",\"change\":" +
      json_quote(change.kind.label()) +
      ",\"leftIndex\":" +
      json_optional_int32(change.left_index) +
      ",\"rightIndex\":" +
      json_optional_int32(change.right_index) +
      ",\"leftBytes\":" +
      change.left_bytes.to_string() +
      ",\"rightBytes\":" +
      change.right_bytes.to_string() +
      ",\"commonPrefixBytes\":" +
      change.common_prefix_bytes.to_string() +
      ",\"differingBytes\":" +
      change.differing_bytes.to_string() +
      "}",
    )
  }
  json_array(values)
}

///|
pub fn render_structure_json(binary : Module) -> String {
  let sections : Array[String] = []
  for section in binary.sections() {
    let custom = match section.custom_name {
      Some(name) => ",\"name\":" + json_quote(name)
      None => ""
    }
    sections.push(
      "{\"id\":" +
      section.id.to_string() +
      ",\"kind\":" +
      json_quote(section.kind.label()) +
      ",\"start\":" +
      section.payload.start.to_string() +
      ",\"end\":" +
      section.payload.end.to_string() +
      custom +
      "}",
    )
  }
  "{\"version\":" +
  binary.version().to_string() +
  ",\"bytes\":" +
  binary.byte_length().to_string() +
  ",\"sections\":" +
  json_array(sections) +
  "}"
}

///|
pub fn render_validation_json(report : ValidationReport) -> String {
  let values : Array[String] = []
  for issue in report.issues() {
    values.push(
      "{\"level\":" +
      json_quote(issue.level.label()) +
      ",\"rule\":" +
      json_quote(issue.rule) +
      ",\"message\":" +
      json_quote(issue.message) +
      "}",
    )
  }
  "{\"ok\":" +
  (!report.has_errors()).to_string() +
  ",\"issues\":" +
  json_array(values) +
  "}"
}
