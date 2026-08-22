///| Compact fixtures use real WebAssembly binary framing rather than mocked
///| parser state. Each one targets an observable boundary of the reader.

fn empty_module() -> Array[Int] { [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00] }

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

test "rejects a damaged magic number" {
  let bytes = empty_module()
  bytes[1] = 0x62
  match parse_module(bytes) {
    Ok(_) => fail("expected invalid header")
    Err(error) => assert_true(error.message().contains("magic[1]"))
  }
}

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

test "decodes function type export and body metadata" {
  let bytes = empty_module()
  // type section: one () -> () function type
  bytes.push(1); bytes.push(4); bytes.push(1); bytes.push(0x60); bytes.push(0); bytes.push(0)
  // function section: one function using type zero
  bytes.push(3); bytes.push(2); bytes.push(1); bytes.push(0)
  // export section: export function zero as "run"
  bytes.push(7); bytes.push(7); bytes.push(1); bytes.push(3); bytes.push(0x72); bytes.push(0x75); bytes.push(0x6e); bytes.push(0); bytes.push(0)
  // code section: one body, zero locals, end instruction
  bytes.push(10); bytes.push(4); bytes.push(1); bytes.push(2); bytes.push(0); bytes.push(0x0b)
  let binary = match parse_module(bytes) { Ok(value) => value; Err(error) => fail(error.message()) }
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

test "reports function-code count mismatch without losing metadata" {
  let bytes = empty_module()
  bytes.push(3); bytes.push(2); bytes.push(1); bytes.push(0)
  let binary = match parse_module(bytes) { Ok(value) => value; Err(error) => fail(error.message()) }
  match decode_module(binary) {
    Err(error) => fail(error.message())
    Ok(decoded) => assert_eq(decoded.warnings().length(), 1)
  }
}

test "semantic validator accepts a coherent exported function" {
  let bytes = empty_module()
  bytes.push(1); bytes.push(4); bytes.push(1); bytes.push(0x60); bytes.push(0); bytes.push(0)
  bytes.push(3); bytes.push(2); bytes.push(1); bytes.push(0)
  bytes.push(7); bytes.push(5); bytes.push(1); bytes.push(1); bytes.push(0x66); bytes.push(0); bytes.push(0)
  bytes.push(10); bytes.push(4); bytes.push(1); bytes.push(2); bytes.push(0); bytes.push(0x0b)
  let binary = match parse_module(bytes) { Ok(value) => value; Err(error) => fail(error.message()) }
  let decoded = match decode_module(binary) { Ok(value) => value; Err(error) => fail(error.message()) }
  assert_false(validate(decoded).has_errors())
}

test "semantic validator identifies an out-of-range export" {
  let bytes = empty_module()
  bytes.push(7); bytes.push(5); bytes.push(1); bytes.push(1); bytes.push(0x66); bytes.push(0); bytes.push(1)
  let binary = match parse_module(bytes) { Ok(value) => value; Err(error) => fail(error.message()) }
  let decoded = match decode_module(binary) { Ok(value) => value; Err(error) => fail(error.message()) }
  let report = validate(decoded)
  assert_true(report.has_errors())
  assert_true(report.render().contains("export-index"))
}

test "instruction scanner counts constants locals and calls" {
  let bytes = [0x41, 0x2a, 0x21, 0x00, 0x10, 0x01, 0x0b]
  match scan_instructions(bytes, { start: 0, end: bytes.length() }) {
    Err(error) => fail(error.message())
    Ok(stats) => {
      assert_eq(stats.instruction_count, 4)
      assert_eq(stats.constant_count, 1)
      assert_eq(stats.local_access_count, 1)
      assert_eq(stats.call_count, 1)
    }
  }
}

test "instruction scanner rejects unterminated control flow" {
  let bytes = [0x02, 0x40, 0x01]
  match scan_instructions(bytes, { start: 0, end: bytes.length() }) {
    Ok(_) => fail("expected missing end")
    Err(error) => assert_true(error.message().contains("final end"))
  }
}
