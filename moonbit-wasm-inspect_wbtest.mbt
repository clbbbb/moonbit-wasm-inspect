///| Compact fixtures use real WebAssembly binary framing rather than mocked

///|
/// parser state. Each one targets an observable boundary of the reader.
fn empty_module() -> Array[Int32] {
  [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
}

///|
fn self_recursive_export_module() -> Array[Int32] {
  [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 1, 4, 1, 0x60, 0, 0, 3, 2, 1,
    0, 7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 0, 10, 6, 1, 4, 0, 0x10, 0, 0x0b,
  ]
}

///|
test "parses the version-one empty module" {
  match parse_module(empty_module()) {
    Err(error) => fail(error.message())
    Ok(binary) => {
      assert_eq(binary.version(), 1)
      assert_eq(binary.section_count(), 0)
      assert_eq(binary.stats().byte_length, 8)
    }
  }
}

///|
test "JSON quoting escapes string delimiters and control bytes" {
  assert_eq(
    json_quote("quote: \" slash: \\ line:\n control:\u{01}"),
    "\"quote: \\\" slash: \\\\ line:\\n control:\\u0001\"",
  )
}

///|
test "analyzes function reachability and direct recursion" {
  let binary = match parse_module(self_recursive_export_module()) {
    Err(error) => fail(error.message())
    Ok(value) => value
  }
  let decoded = match decode_module(binary) {
    Err(error) => fail(error.message())
    Ok(value) => value
  }
  let analysis = match analyze_call_graph(decoded) {
    Err(error) => fail(error.message())
    Ok(value) => value
  }
  assert_eq(analysis.functions.length(), 1)
  assert_eq(analysis.direct_call_edges, 1)
  assert_eq(analysis.reachable_function_count, 1)
  assert_eq(analysis.recursive_function_count, 1)
  assert_true(analysis.functions[0].directly_reachable_from_roots)
  assert_true(analysis.functions[0].recursive)
  assert_eq(analysis.functions[0].export_names, ["run"])
  let json = render_call_graph_analysis_json(analysis)
  assert_true(json.contains("\"recursiveFunctionCount\":1"))
  assert_true(json.contains("\"exportNames\":[\"run\"]"))
}

///|
test "diffs section payload bytes while preserving common prefix length" {
  let left_bytes = empty_module()
  left_bytes.push(0)
  left_bytes.push(5)
  left_bytes.push(3)
  left_bytes.push(0x66)
  left_bytes.push(0x6f)
  left_bytes.push(0x6f)
  left_bytes.push(0x41)
  let right_bytes = empty_module()
  right_bytes.push(0)
  right_bytes.push(5)
  right_bytes.push(3)
  right_bytes.push(0x66)
  right_bytes.push(0x6f)
  right_bytes.push(0x6f)
  right_bytes.push(0x42)
  let left = match parse_module(left_bytes) {
    Err(error) => fail(error.message())
    Ok(value) => value
  }
  let right = match parse_module(right_bytes) {
    Err(error) => fail(error.message())
    Ok(value) => value
  }
  let changes = diff_binary_sections(left, right)
  assert_eq(changes.length(), 1)
  assert_true(changes[0].kind is SectionChanged)
  assert_eq(changes[0].common_prefix_bytes, 4)
  assert_eq(changes[0].differing_bytes, 1)
  assert_true(render_binary_diff(changes).contains("differing-bytes=1"))
  assert_true(render_binary_diff_json(changes).contains("\"differingBytes\":1"))
}

///|
test "rejects a damaged magic number" {
  let bytes = empty_module()
  bytes[1] = 0x62
  match parse_module(bytes) {
    Ok(_) => fail("expected invalid header")
    Err(error) => assert_true(error.message().contains("magic[1]"))
  }
}

///|
test "rejects a truncated section payload" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(5)
  bytes.push(0x60)
  match parse_module(bytes) {
    Ok(_) => fail("expected payload error")
    Err(error) => assert_true(error.message().contains("declared payload"))
  }
}

///|
test "reads a named custom section" {
  let bytes = empty_module()
  bytes.push(0)
  bytes.push(4)
  bytes.push(3)
  bytes.push(0x66)
  bytes.push(0x6f)
  bytes.push(0x6f)
  match parse_module(bytes) {
    Err(error) => fail(error.message())
    Ok(binary) => {
      assert_eq(binary.section_labels(), ["custom:foo"])
      assert_eq(binary.custom_sections("foo").length(), 1)
    }
  }
}

///|
test "rejects repeated standard sections" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  bytes.push(1)
  bytes.push(0)
  match parse_module(bytes) {
    Ok(_) => fail("expected section-order error")
    Err(error) => assert_true(error.message().contains("strictly ordered"))
  }
}

///|
test "decodes function type export and body metadata" {
  let bytes = empty_module()
  // type section: one () -> () function type
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  // function section: one function using type zero
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  // export section: export function zero as "run"
  bytes.push(7)
  bytes.push(7)
  bytes.push(1)
  bytes.push(3)
  bytes.push(0x72)
  bytes.push(0x75)
  bytes.push(0x6e)
  bytes.push(0)
  bytes.push(0)
  // code section: one body, zero locals, end instruction
  bytes.push(10)
  bytes.push(4)
  bytes.push(1)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x0b)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match decode_module(binary) {
    Err(error) => fail(error.message())
    Ok(decoded) => {
      assert_eq(decoded.types().length(), 1)
      assert_eq(decoded.types()[0].signature(), "() -> ()")
      assert_eq(decoded.defined_function_count(), 1)
      assert_eq(decoded.exports()[0].name, "run")
      assert_eq(decoded.code_bodies.length(), 1)
      assert_eq(decoded.warnings().length(), 0)
    }
  }
}

///|
test "reports function-code count mismatch without losing metadata" {
  let bytes = empty_module()
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match decode_module(binary) {
    Err(error) => fail(error.message())
    Ok(decoded) => assert_eq(decoded.warnings().length(), 1)
  }
}

///|
test "semantic validator accepts a coherent exported function" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  bytes.push(7)
  bytes.push(5)
  bytes.push(1)
  bytes.push(1)
  bytes.push(0x66)
  bytes.push(0)
  bytes.push(0)
  bytes.push(10)
  bytes.push(4)
  bytes.push(1)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x0b)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_false(validate(decoded).has_errors())
}

///|
test "semantic validator identifies an out-of-range export" {
  let bytes = empty_module()
  bytes.push(7)
  bytes.push(5)
  bytes.push(1)
  bytes.push(1)
  bytes.push(0x66)
  bytes.push(0)
  bytes.push(1)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let report = validate(decoded)
  assert_true(report.has_errors())
  assert_true(report.render().contains("export-index"))
}

///|
test "instruction scanner counts constants locals and calls" {
  let bytes = [0x41, 0x2a, 0x21, 0x00, 0x10, 0x01, 0x0b]
  match scan_instructions(bytes, { start: 0, end: bytes.length(), }) {
    Err(error) => fail(error.message())
    Ok(stats) => {
      assert_eq(stats.instruction_count, 4)
      assert_eq(stats.constant_count, 1)
      assert_eq(stats.local_access_count, 1)
      assert_eq(stats.call_count, 1)
    }
  }
}

///|
test "instruction scanner rejects unterminated control flow" {
  let bytes = [0x02, 0x40, 0x01]
  match scan_instructions(bytes, { start: 0, end: bytes.length(), }) {
    Ok(_) => fail("expected missing end")
    Err(error) => assert_true(error.message().contains("final end"))
  }
}

///|
test "decodes active and passive data segments from a binary fixture" {
  let bytes = empty_module()
  // one memory with a one-page minimum
  bytes.push(5)
  bytes.push(3)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  // active memory 0 segment at i32.const 7 with "hi", then passive "x"
  bytes.push(11)
  bytes.push(11)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x41)
  bytes.push(7)
  bytes.push(0x0b)
  bytes.push(2)
  bytes.push(0x68)
  bytes.push(0x69)
  bytes.push(1)
  bytes.push(1)
  bytes.push(0x78)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let segments = match decode_data_segments(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(segments.length(), 2)
  assert_eq(data_segment_bytes(binary, segments[0]), [0x68, 0x69])
  assert_eq(data_segment_bytes(binary, segments[1]), [0x78])
  match segments[0].mode {
    ActiveData(memory, offset) => {
      assert_eq(memory, 0)
      assert_eq(offset.size(), 3)
    }
    PassiveData => fail("expected active segment")
  }
  match segments[1].mode {
    PassiveData => ()
    ActiveData(_, _) => fail("expected passive segment")
  }
}

///|
test "decodes active passive and declarative element segments" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  bytes.push(4)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x70)
  bytes.push(0)
  bytes.push(1)
  // active table 0, passive, and declarative segments, each containing function 0
  bytes.push(9)
  bytes.push(15)
  bytes.push(3)
  bytes.push(0)
  bytes.push(0x41)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  bytes.push(0)
  bytes.push(3)
  bytes.push(0)
  bytes.push(1)
  bytes.push(0)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let segments = match decode_element_segments(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(segments.length(), 3)
  assert_eq(segments[0].functions, [0])
  assert_eq(segments[1].functions, [0])
  assert_eq(segments[2].functions, [0])
  match segments[0].mode {
    ActiveElement(table, _) => assert_eq(table, 0)
    _ => fail("expected active element segment")
  }
  match segments[1].mode {
    PassiveElement => ()
    _ => fail("expected passive element segment")
  }
  match segments[2].mode {
    DeclarativeElement => ()
    _ => fail("expected declarative element segment")
  }
}

///|
test "decodes the standard name custom section" {
  let bytes = empty_module()
  bytes.push(0)
  bytes.push(32)
  bytes.push(4)
  bytes.push(0x6e)
  bytes.push(0x61)
  bytes.push(0x6d)
  bytes.push(0x65)
  // module name subsection: "demo"
  bytes.push(0)
  bytes.push(5)
  bytes.push(4)
  bytes.push(0x64)
  bytes.push(0x65)
  bytes.push(0x6d)
  bytes.push(0x6f)
  // function names: 0 -> run, 2 -> helper
  bytes.push(1)
  bytes.push(14)
  bytes.push(2)
  bytes.push(0)
  bytes.push(3)
  bytes.push(0x72)
  bytes.push(0x75)
  bytes.push(0x6e)
  bytes.push(2)
  bytes.push(6)
  bytes.push(0x68)
  bytes.push(0x65)
  bytes.push(0x6c)
  bytes.push(0x70)
  bytes.push(0x65)
  bytes.push(0x72)
  // an unknown subsection is retained rather than rejected
  bytes.push(9)
  bytes.push(2)
  bytes.push(0xaa)
  bytes.push(0xbb)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match decode_name_section(binary) {
    Err(error) => fail(error.message())
    Ok(None) => fail("expected name section")
    Ok(Some(names)) => {
      assert_eq(names.module_name, Some("demo"))
      assert_eq(names.function_name(0), Some("run"))
      assert_eq(names.function_name(2), Some("helper"))
      assert_eq(names.unknown_subsection_ids, [9])
    }
  }
}

///|
test "renders structural and validation reports as JSON" {
  let bytes = empty_module()
  bytes.push(0)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0x78)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(
    render_structure_json(binary),
    "{\"version\":1,\"bytes\":12,\"sections\":[{\"id\":0,\"kind\":\"custom\",\"start\":10,\"end\":12,\"name\":\"x\"}]}",
  )
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(
    render_validation_json(validate(decoded)),
    "{\"ok\":true,\"issues\":[]}",
  )
}

///|
test "detects features required by section and instruction fixtures" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  bytes.push(4)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x6f)
  bytes.push(0)
  bytes.push(1)
  // Two memories; the second is shared, 64-bit, and bounded.
  bytes.push(5)
  bytes.push(6)
  bytes.push(2)
  bytes.push(0)
  bytes.push(1)
  bytes.push(7)
  bytes.push(1)
  bytes.push(2)
  // A body with bulk-memory and SIMD opcode prefixes.
  bytes.push(10)
  bytes.push(8)
  bytes.push(1)
  bytes.push(6)
  bytes.push(0)
  bytes.push(0xfc)
  bytes.push(0)
  bytes.push(0xfd)
  bytes.push(14)
  bytes.push(0x0b)
  bytes.push(12)
  bytes.push(1)
  bytes.push(0)
  bytes.push(13)
  bytes.push(1)
  bytes.push(0)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(
    render_features(detect_features(decoded)),
    "required features:\n  - multi-memory\n  - memory64\n  - threads\n  - reference-types\n  - bulk-memory\n  - exception-handling\n  - simd\n",
  )
}

///|
test "decodes data-count and tag sections with consistent index spaces" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  bytes.push(4)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x70)
  bytes.push(0)
  bytes.push(1)
  bytes.push(5)
  bytes.push(3)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  bytes.push(9)
  bytes.push(7)
  bytes.push(1)
  bytes.push(0)
  bytes.push(0x41)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(1)
  bytes.push(0)
  bytes.push(10)
  bytes.push(4)
  bytes.push(1)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(11)
  bytes.push(7)
  bytes.push(1)
  bytes.push(0)
  bytes.push(0x41)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(1)
  bytes.push(0x61)
  bytes.push(12)
  bytes.push(1)
  bytes.push(1)
  bytes.push(13)
  bytes.push(3)
  bytes.push(1)
  bytes.push(0)
  bytes.push(0)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  assert_eq(decoded.data_count, Some(1))
  assert_eq(decoded.data_segments.length(), 1)
  assert_eq(decoded.element_segments.length(), 1)
  assert_eq(decoded.defined_tag_count(), 1)
  assert_false(validate(decoded).has_errors())
}

///|
test "validates data element and tag indices across their index spaces" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0)
  bytes.push(4)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x70)
  bytes.push(0)
  bytes.push(1)
  bytes.push(5)
  bytes.push(3)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  // table 1 and function 1 are both out of range.
  bytes.push(9)
  bytes.push(9)
  bytes.push(1)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0x41)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(0)
  bytes.push(1)
  bytes.push(1)
  bytes.push(10)
  bytes.push(4)
  bytes.push(1)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x0b)
  // memory 1 is out of range; data count also disagrees with the one segment.
  bytes.push(11)
  bytes.push(8)
  bytes.push(1)
  bytes.push(2)
  bytes.push(1)
  bytes.push(0x41)
  bytes.push(0)
  bytes.push(0x0b)
  bytes.push(1)
  bytes.push(0x61)
  bytes.push(12)
  bytes.push(1)
  bytes.push(2)
  // tag type 1 is out of range because only type 0 exists.
  bytes.push(13)
  bytes.push(3)
  bytes.push(1)
  bytes.push(0)
  bytes.push(1)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let report = validate(decoded).render()
  assert_true(report.contains("element-table-index"))
  assert_true(report.contains("element-function-index"))
  assert_true(report.contains("data-memory-index"))
  assert_true(report.contains("data-count"))
  assert_true(report.contains("tag-type"))
}

///|
test "instruction summaries retain direct calls branches and proposal immediates" {
  let control = [0x02, 0x40, 0x0d, 0, 0x10, 1, 0x0c, 0, 0x0b, 0x0b]
  match scan_instructions(control, { start: 0, end: control.length(), }) {
    Err(error) => fail(error.message())
    Ok(stats) => {
      assert_eq(stats.control_block_count, 1)
      assert_eq(stats.branch_count, 2)
      assert_eq(stats.called_functions, [1])
    }
  }
  let prefixed = [0xfc, 9, 0, 0xfd, 14, 0x0b]
  match scan_instructions(prefixed, { start: 0, end: prefixed.length(), }) {
    Err(error) => fail(error.message())
    Ok(stats) => {
      assert_eq(stats.bulk_memory_instruction_count, 1)
      assert_eq(stats.simd_instruction_count, 1)
    }
  }
}

///|
test "builds a direct call graph for defined code bodies" {
  let bytes = empty_module()
  bytes.push(1)
  bytes.push(4)
  bytes.push(1)
  bytes.push(0x60)
  bytes.push(0)
  bytes.push(0)
  bytes.push(3)
  bytes.push(3)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0)
  // function 0 calls function 1; function 1 has an empty body.
  bytes.push(10)
  bytes.push(9)
  bytes.push(2)
  bytes.push(4)
  bytes.push(0)
  bytes.push(0x10)
  bytes.push(1)
  bytes.push(0x0b)
  bytes.push(2)
  bytes.push(0)
  bytes.push(0x0b)
  let binary = match parse_module(bytes) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  let decoded = match decode_module(binary) {
    Ok(value) => value
    Err(error) => fail(error.message())
  }
  match build_call_graph(decoded) {
    Err(error) => fail(error.message())
    Ok(graph) => {
      assert_eq(graph.length(), 2)
      assert_eq(graph[0].function_index, 0)
      assert_eq(graph[0].callees, [1])
      assert_eq(graph[1].callees, [])
    }
  }
}
