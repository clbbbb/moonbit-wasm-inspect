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
      _ => text = text + char.to_string()
    }
  }
  text
}

///|
fn json_string(value : String) -> String {
  "\"" + json_escape(value) + "\""
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
pub fn render_structure_json(binary : Module) -> String {
  let sections : Array[String] = []
  for section in binary.sections() {
    let custom = match section.custom_name {
      Some(name) => ",\"name\":" + json_string(name)
      None => ""
    }
    sections.push(
      "{\"id\":" +
      section.id.to_string() +
      ",\"kind\":" +
      json_string(section.kind.label()) +
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
      json_string(issue.level.label()) +
      ",\"rule\":" +
      json_string(issue.rule) +
      ",\"message\":" +
      json_string(issue.message) +
      "}",
    )
  }
  "{\"ok\":" +
  (!report.has_errors()).to_string() +
  ",\"issues\":" +
  json_array(values) +
  "}"
}
