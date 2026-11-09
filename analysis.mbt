///| A per-function static inventory. Imported functions have no body and use

///|
/// zero instruction metrics; defined functions carry scanner-derived values.
pub struct FunctionAnalysis {
  function_index : Int32
  type_index : Int32?
  imported : Bool
  import_name : String?
  export_names : Array[String]
  direct_callees : Array[Int32]
  instruction_count : Int32
  body_bytes : Int32
  control_blocks : Int32
  branches : Int32
  calls : Int32
  memory_accesses : Int32
  local_accesses : Int32
  cyclomatic_estimate : Int32
  directly_reachable_from_roots : Bool
  recursive : Bool
}

///|
pub fn FunctionAnalysis::description(self : FunctionAnalysis) -> String {
  let role = if self.imported { "import" } else { "defined" }
  let reachability = if self.directly_reachable_from_roots {
    "direct-call reachable"
  } else {
    "not reached by direct calls"
  }
  let import_label = match self.import_name {
    Some(name) => ", imported from " + name
    None => ""
  }
  let recursion = if self.recursive { ", recursive" } else { "" }
  "function #" +
  self.function_index.to_string() +
  " " +
  role +
  ", instructions=" +
  self.instruction_count.to_string() +
  ", body-bytes=" +
  self.body_bytes.to_string() +
  ", branches=" +
  self.branches.to_string() +
  ", calls=" +
  self.calls.to_string() +
  ", fan-out=" +
  self.direct_callees.length().to_string() +
  ", cyclomatic-estimate=" +
  self.cyclomatic_estimate.to_string() +
  ", " +
  reachability +
  import_label +
  recursion
}

///|
pub struct CallGraphAnalysis {
  functions : Array[FunctionAnalysis]
  direct_call_edges : Int32
  indirect_call_sites : Int32
  exported_function_count : Int32
  reachable_function_count : Int32
  unreachable_defined_count : Int32
  recursive_function_count : Int32
}

///|
pub fn CallGraphAnalysis::functions(
  self : CallGraphAnalysis,
) -> Array[FunctionAnalysis] {
  self.functions
}

///|
pub fn CallGraphAnalysis::render(self : CallGraphAnalysis) -> String {
  let mut text = "function call graph analysis\n"
  text = text + "functions: " + self.functions.length().to_string() + "\n"
  text = text +
    "direct call edges: " +
    self.direct_call_edges.to_string() +
    "\n"
  text = text +
    "indirect call sites: " +
    self.indirect_call_sites.to_string() +
    "\n"
  text = text +
    "exported functions: " +
    self.exported_function_count.to_string() +
    "\n"
  text = text +
    "reachable functions: " +
    self.reachable_function_count.to_string() +
    "\n"
  text = text +
    "unreachable defined functions: " +
    self.unreachable_defined_count.to_string() +
    "\n"
  text = text +
    "recursive functions: " +
    self.recursive_function_count.to_string() +
    "\n"
  text = text + "details:\n"
  for function in self.functions {
    text = text + "  - " + function.description() + "\n"
    if function.export_names.length() > 0 {
      text = text + "    exports: "
      let mut first_export = true
      for name in function.export_names {
        if !first_export {
          text = text + ", "
        }
        text = text + name
        first_export = false
      }
      text = text + "\n"
    }
    if function.direct_callees.length() > 0 {
      text = text + "    calls: "
      let mut first_callee = true
      for callee in function.direct_callees {
        if !first_callee {
          text = text + ", "
        }
        text = text + "#" + callee.to_string()
        first_callee = false
      }
      text = text + "\n"
    }
  }
  text
}

///|
fn append_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn function_export_names(decoded : DecodedModule) -> Array[Array[String]] {
  let total = decoded.imported_function_count() +
    decoded.defined_function_count()
  let names : Array[Array[String]] = []
  for _ in 0..<total {
    names.push([])
  }
  for exported_item in decoded.exports() {
    if exported_item.kind == FunctionExternal &&
      exported_item.index >= 0 &&
      exported_item.index < total {
      append_unique_name(names[exported_item.index], exported_item.name)
    }
  }
  names
}

///|
fn function_type_indices(decoded : DecodedModule) -> Array[Int32?] {
  let indices : Array[Int32?] = []
  for imported_item in decoded.imports {
    if imported_item.kind == FunctionExternal {
      indices.push(imported_item.type_index)
    }
  }
  for index in decoded.function_types {
    indices.push(Some(index))
  }
  indices
}

///|
fn function_import_names(decoded : DecodedModule) -> Array[String?] {
  let names : Array[String?] = []
  for imported_item in decoded.imports {
    if imported_item.kind == FunctionExternal {
      names.push(Some(imported_item.module_name + "." + imported_item.name))
    }
  }
  names
}

///|
fn mark_reachable_functions(
  decoded : DecodedModule,
  summaries : Array[FunctionCallSummary],
  function_count : Int32,
) -> Array[Bool] {
  let reachable : Array[Bool] = []
  for _ in 0..<function_count {
    reachable.push(false)
  }
  let queue : Array[Int32] = []
  for exported_item in decoded.exports() {
    if exported_item.kind == FunctionExternal &&
      exported_item.index >= 0 &&
      exported_item.index < function_count &&
      !reachable[exported_item.index] {
      reachable[exported_item.index] = true
      queue.push(exported_item.index)
    }
  }
  match decoded.start_function {
    Some(index) if index >= 0 && index < function_count && !reachable[index] => {
      reachable[index] = true
      queue.push(index)
    }
    _ => ()
  }
  let mut queue_position = 0
  while queue_position < queue.length() {
    let caller = queue[queue_position]
    queue_position = queue_position + 1
    for summary in summaries {
      if summary.function_index == caller {
        for callee in summary.callees {
          if callee >= 0 && callee < function_count && !reachable[callee] {
            reachable[callee] = true
            queue.push(callee)
          }
        }
      }
    }
  }
  reachable
}

///|
fn function_reaches_itself(
  function_index : Int32,
  summaries : Array[FunctionCallSummary],
  function_count : Int32,
) -> Bool {
  let visited : Array[Bool] = []
  for _ in 0..<function_count {
    visited.push(false)
  }
  let pending : Array[Int32] = []
  for summary in summaries {
    if summary.function_index == function_index {
      for callee in summary.callees {
        if callee == function_index {
          return true
        }
        if callee >= 0 && callee < function_count && !visited[callee] {
          visited[callee] = true
          pending.push(callee)
        }
      }
    }
  }
  let mut cursor = 0
  while cursor < pending.length() {
    let current = pending[cursor]
    cursor = cursor + 1
    for summary in summaries {
      if summary.function_index == current {
        for callee in summary.callees {
          if callee == function_index {
            return true
          }
          if callee >= 0 && callee < function_count && !visited[callee] {
            visited[callee] = true
            pending.push(callee)
          }
        }
      }
    }
  }
  false
}

///|
pub fn analyze_call_graph(
  decoded : DecodedModule,
) -> Result[CallGraphAnalysis, DecodeError] {
  let summaries = match build_call_graph(decoded) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let type_indices = function_type_indices(decoded)
  let import_names = function_import_names(decoded)
  let export_names = function_export_names(decoded)
  let function_count = type_indices.length()
  let imported_count = decoded.imported_function_count()
  let reachable = mark_reachable_functions(decoded, summaries, function_count)
  let functions : Array[FunctionAnalysis] = []
  let mut indirect_calls = 0
  let mut edge_count = 0
  let mut reachable_count = 0
  let mut unreachable_defined = 0
  let mut recursive_count = 0
  let mut exported_count = 0
  for index in 0..<function_count {
    if export_names[index].length() > 0 {
      exported_count = exported_count + 1
    }
    if reachable[index] {
      reachable_count = reachable_count + 1
    } else if index >= imported_count {
      unreachable_defined = unreachable_defined + 1
    }
    let is_imported = index < imported_count
    let callees : Array[Int32] = []
    let mut instructions = 0
    let mut body_bytes = 0
    let mut blocks = 0
    let mut branches = 0
    let mut call_sites = 0
    let mut memory_accesses = 0
    let mut local_accesses = 0
    if !is_imported {
      for summary in summaries {
        if summary.function_index == index {
          for callee in summary.callees {
            callees.push(callee)
          }
          call_sites = summary.callees.length()
        }
      }
      let body_index = index - imported_count
      if body_index >= 0 && body_index < decoded.code_bodies.length() {
        let body = decoded.code_bodies[body_index]
        body_bytes = body.byte_length
        let stats = match scan_code_body(decoded.binary(), body) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        instructions = stats.instruction_count
        blocks = stats.control_block_count
        branches = stats.branch_count
        call_sites = stats.call_count
        memory_accesses = stats.memory_access_count
        local_accesses = stats.local_access_count
        edge_count = edge_count + stats.called_functions.length()
        indirect_calls = indirect_calls +
          (stats.call_count - stats.called_functions.length())
      }
    }
    let recursive = if is_imported {
      false
    } else {
      function_reaches_itself(index, summaries, function_count)
    }
    if recursive {
      recursive_count = recursive_count + 1
    }
    functions.push({
      function_index: index,
      type_index: type_indices[index],
      imported: is_imported,
      import_name: if is_imported {
        import_names[index]
      } else {
        None
      },
      export_names: export_names[index],
      direct_callees: callees,
      instruction_count: instructions,
      body_bytes,
      control_blocks: blocks,
      branches,
      calls: call_sites,
      memory_accesses,
      local_accesses,
      cyclomatic_estimate: branches + 1,
      directly_reachable_from_roots: reachable[index],
      recursive,
    })
  }
  Ok({
    functions,
    direct_call_edges: edge_count,
    indirect_call_sites: indirect_calls,
    exported_function_count: exported_count,
    reachable_function_count: reachable_count,
    unreachable_defined_count: unreachable_defined,
    recursive_function_count: recursive_count,
  })
}

///|
pub fn render_function_analysis(
  decoded : DecodedModule,
) -> Result[String, DecodeError] {
  match analyze_call_graph(decoded) {
    Ok(report) => Ok(report.render())
    Err(error) => Err(error)
  }
}
