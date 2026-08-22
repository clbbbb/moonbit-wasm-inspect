///| Semantic checks that can be performed without executing a module. Parsing
///| establishes binary framing; validation relates the independently decoded
///| index spaces and returns all findings instead of stopping at the first one.

pub enum IssueLevel {
  ErrorIssue
  WarningIssue
} derive(Eq)

pub fn IssueLevel::label(self : IssueLevel) -> String {
  match self {
    ErrorIssue => "error"
    WarningIssue => "warning"
  }
}

pub struct ValidationIssue {
  level : IssueLevel
  rule : String
  message : String
}

pub fn ValidationIssue::description(self : ValidationIssue) -> String {
  self.level.label() + "[" + self.rule + "]: " + self.message
}

pub struct ValidationReport {
  issues : Array[ValidationIssue]
}

pub fn ValidationReport::issues(self : ValidationReport) -> Array[ValidationIssue] { self.issues }

pub fn ValidationReport::has_errors(self : ValidationReport) -> Bool {
  for issue in self.issues {
    if issue.level == ErrorIssue { return true }
  }
  false
}

pub fn ValidationReport::render(self : ValidationReport) -> String {
  if self.issues.length() == 0 { return "validation passed\n" }
  let mut text = "validation findings:\n"
  for issue in self.issues { text = text + "  - " + issue.description() + "\n" }
  text
}

fn imported_count(decoded : DecodedModule, kind : ExternalKind) -> Int {
  let mut count = 0
  for item in decoded.imports() {
    if item.kind == kind { count = count + 1 }
  }
  count
}

fn push_index_issue(
  issues : Array[ValidationIssue],
  rule : String,
  kind : String,
  index : Int,
  limit : Int,
) -> Unit {
  if index < 0 || index >= limit {
    issues.push({
      level: ErrorIssue,
      rule,
      message: kind + " index " + index.to_string() + " is outside 0.." + limit.to_string(),
    })
  }
}

fn validate_function_types(decoded : DecodedModule, issues : Array[ValidationIssue]) -> Unit {
  let type_limit = decoded.types().length()
  let mut function_index = decoded.imported_function_count()
  for type_index in decoded.function_types {
    push_index_issue(issues, "function-type", "type", type_index, type_limit)
    function_index = function_index + 1
  }
}

fn validate_exports(decoded : DecodedModule, issues : Array[ValidationIssue]) -> Unit {
  let function_limit = decoded.imported_function_count() + decoded.defined_function_count()
  let table_limit = imported_count(decoded, TableExternal) + decoded.tables.length()
  let memory_limit = imported_count(decoded, MemoryExternal) + decoded.memories.length()
  let global_limit = imported_count(decoded, GlobalExternal) + decoded.globals.length()
  let tag_limit = imported_count(decoded, TagExternal)
  let names : Array[String] = []
  for item in decoded.exports() {
    for prior_name in names {
      if item.name == prior_name {
        issues.push({
          level: ErrorIssue,
          rule: "export-name",
          message: "export name '" + item.name + "' is duplicated",
        })
      }
    }
    names.push(item.name)
    match item.kind {
      FunctionExternal => push_index_issue(issues, "export-index", "function", item.index, function_limit)
      TableExternal => push_index_issue(issues, "export-index", "table", item.index, table_limit)
      MemoryExternal => push_index_issue(issues, "export-index", "memory", item.index, memory_limit)
      GlobalExternal => push_index_issue(issues, "export-index", "global", item.index, global_limit)
      TagExternal => push_index_issue(issues, "export-index", "tag", item.index, tag_limit)
    }
  }
}

fn validate_start(decoded : DecodedModule, issues : Array[ValidationIssue]) -> Unit {
  match decoded.start_function {
    None => ()
    Some(index) => {
      let limit = decoded.imported_function_count() + decoded.defined_function_count()
      push_index_issue(issues, "start-index", "function", index, limit)
      if index >= decoded.imported_function_count() && index < limit {
        let type_slot = index - decoded.imported_function_count()
        let type_index = decoded.function_types[type_slot]
        if type_index >= 0 && type_index < decoded.types().length() {
          let type_ = decoded.types()[type_index]
          if type_.params().length() != 0 || type_.results().length() != 0 {
            issues.push({
              level: ErrorIssue,
              rule: "start-signature",
              message: "defined start function must have type () -> ()",
            })
          }
        }
      }
    }
  }
}

fn validate_code_bodies(decoded : DecodedModule, issues : Array[ValidationIssue]) -> Unit {
  if decoded.code_bodies.length() != decoded.defined_function_count() {
    issues.push({
      level: ErrorIssue,
      rule: "function-code-count",
      message: "function and code sections have different entry counts",
    })
  }
  for body in decoded.code_bodies {
    if body.instruction_span.size() == 0 {
      issues.push({
        level: ErrorIssue,
        rule: "function-body",
        message: "function body has no terminating instruction sequence",
      })
    }
  }
}

pub fn validate(decoded : DecodedModule) -> ValidationReport {
  let issues : Array[ValidationIssue] = []
  validate_function_types(decoded, issues)
  validate_exports(decoded, issues)
  validate_start(decoded, issues)
  validate_code_bodies(decoded, issues)
  if decoded.memories.length() > 1 {
    issues.push({
      level: WarningIssue,
      rule: "multi-memory",
      message: "multiple memories require consumers to support the multi-memory proposal",
    })
  }
  { issues }
}
