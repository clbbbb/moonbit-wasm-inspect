///| Instruction scanning validates the binary framing of core operations and

///|
/// returns compact call-graph and control-flow facts without executing code.
pub struct InstructionStats {
  instruction_count : Int32
  control_depth : Int32
  control_block_count : Int32
  branch_count : Int32
  call_count : Int32
  called_functions : Array[Int32]
  memory_access_count : Int32
  local_access_count : Int32
  constant_count : Int32
  bulk_memory_instruction_count : Int32
  simd_instruction_count : Int32
}

///|
pub fn InstructionStats::summary(self : InstructionStats) -> String {
  "instructions=" +
  self.instruction_count.to_string() +
  ", blocks=" +
  self.control_block_count.to_string() +
  ", branches=" +
  self.branch_count.to_string() +
  ", calls=" +
  self.call_count.to_string() +
  ", memory=" +
  self.memory_access_count.to_string() +
  ", locals=" +
  self.local_access_count.to_string() +
  ", constants=" +
  self.constant_count.to_string() +
  ", bulk-memory=" +
  self.bulk_memory_instruction_count.to_string() +
  ", simd=" +
  self.simd_instruction_count.to_string()
}

///|
fn skip_i64(cursor : Cursor) -> Result[Unit, DecodeError] {
  let start = cursor.position
  let mut count = 0
  let mut done = false
  while !done {
    if count == 10 {
      return Err(InvalidLeb128(start, "i64 immediate is too long"))
    }
    match cursor.read_u8() {
      Err(error) => return Err(error)
      Ok(byte) => {
        count = count + 1
        done = (byte & 0x80) == 0
      }
    }
  }
  Ok(())
}

///|
fn skip_block_type(cursor : Cursor) -> Result[Unit, DecodeError] {
  let position = cursor.position
  match cursor.peek_u8() {
    Err(error) => Err(error)
    Ok(0x40)
    | Ok(0x7f)
    | Ok(0x7e)
    | Ok(0x7d)
    | Ok(0x7c)
    | Ok(0x70)
    | Ok(0x6f) => cursor.skip(1)
    Ok(_) =>
      match cursor.read_var_i32() {
        Ok(_) => Ok(())
        Err(_) => Err(InvalidLeb128(position, "invalid block type"))
      }
  }
}

///|
fn skip_memory_immediate(cursor : Cursor) -> Result[Unit, DecodeError] {
  match cursor.read_var_u32() {
    Err(error) => Err(error)
    Ok(_) =>
      match cursor.read_var_u32() {
        Ok(_) => Ok(())
        Err(error) => Err(error)
      }
  }
}

///|
fn skip_br_table(cursor : Cursor) -> Result[Unit, DecodeError] {
  let count = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for _ in 0..<(count + 1) {
    match cursor.read_var_u32() {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn read_two_u32(cursor : Cursor) -> Result[Unit, DecodeError] {
  match cursor.read_var_u32() {
    Err(error) => Err(error)
    Ok(_) =>
      match cursor.read_var_u32() {
        Ok(_) => Ok(())
        Err(error) => Err(error)
      }
  }
}

///|
fn skip_bulk_memory_immediate(cursor : Cursor) -> Result[Bool, DecodeError] {
  let position = cursor.position
  let subopcode = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match subopcode {
    0..<=7 => Ok(false)
    8 | 10 | 12 | 14 =>
      match read_two_u32(cursor) {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    9 | 11 | 13 | 15..<=17 =>
      match cursor.read_var_u32() {
        Ok(_) => Ok(true)
        Err(error) => Err(error)
      }
    _ =>
      Err(
        UnsupportedFeature("0xfc subopcode " + subopcode.to_string(), position),
      )
  }
}

///|
fn skip_simd_immediate(cursor : Cursor) -> Result[Unit, DecodeError] {
  let position = cursor.position
  let subopcode = match cursor.read_var_u32() {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  match subopcode {
    0..<=11 => skip_memory_immediate(cursor)
    12 | 13 => cursor.skip(16)
    21..<=34 => cursor.skip(1)
    14..<=20 | 35..<=255 => Ok(())
    _ =>
      Err(
        UnsupportedFeature("0xfd subopcode " + subopcode.to_string(), position),
      )
  }
}

///|
fn is_plain_numeric(opcode : Int32) -> Bool {
  (opcode >= 0x45 && opcode <= 0xc4) || opcode == 0xd1
}

///|
pub fn scan_instructions(
  bytes : Array[Int32],
  span : Span,
) -> Result[InstructionStats, DecodeError] {
  let cursor = Cursor::with_bounds(bytes, span.start, span.end)
  let mut instruction_count = 0
  let mut depth = 0
  let mut blocks = 0
  let mut branches = 0
  let mut calls = 0
  let called_functions : Array[Int32] = []
  let mut memory = 0
  let mut locals = 0
  let mut constants = 0
  let mut bulk_memory = 0
  let mut simd = 0
  let mut saw_terminal_end = false
  while !cursor.is_finished() {
    let position = cursor.position
    let opcode = match cursor.read_u8() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    instruction_count = instruction_count + 1
    match opcode {
      0x00 | 0x01 | 0x0f | 0x1a | 0x1b | 0x1c => ()
      0x02 | 0x03 | 0x04 => {
        match skip_block_type(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        depth = depth + 1
        blocks = blocks + 1
      }
      0x05 =>
        if depth == 0 {
          return Err(ValidationError(position, "else outside a block"))
        }
      0x0b =>
        if depth == 0 {
          if !cursor.is_finished() {
            return Err(
              ValidationError(position, "bytes follow outer function end"),
            )
          }
          saw_terminal_end = true
        } else {
          depth = depth - 1
        }
      0x0c | 0x0d | 0x14 => {
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        if opcode == 0x0c || opcode == 0x0d {
          branches = branches + 1
        }
      }
      0x10 | 0x12 => {
        let callee = match cursor.read_var_u32() {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        called_functions.push(callee)
        calls = calls + 1
      }
      0x0e =>
        match skip_br_table(cursor) {
          Ok(_) => branches = branches + 1
          Err(error) => return Err(error)
        }
      0x11 | 0x13 => {
        match read_two_u32(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        calls = calls + 1
      }
      0x20 | 0x21 | 0x22 => {
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        locals = locals + 1
      }
      0x23 | 0x24 | 0x25 | 0x26 =>
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      0x28..<=0x3e => {
        match skip_memory_immediate(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        memory = memory + 1
      }
      0x3f | 0x40 =>
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      0x41 => {
        match cursor.read_var_i32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        constants = constants + 1
      }
      0x42 => {
        match skip_i64(cursor) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        constants = constants + 1
      }
      0x43 => {
        match cursor.skip(4) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        constants = constants + 1
      }
      0x44 => {
        match cursor.skip(8) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        constants = constants + 1
      }
      0xd0 =>
        match cursor.read_u8() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      0xd2 =>
        match cursor.read_var_u32() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      0xfc =>
        match skip_bulk_memory_immediate(cursor) {
          Ok(true) => bulk_memory = bulk_memory + 1
          Ok(false) => ()
          Err(error) => return Err(error)
        }
      0xfd =>
        match skip_simd_immediate(cursor) {
          Ok(_) => simd = simd + 1
          Err(error) => return Err(error)
        }
      0xfe | 0xfb =>
        return Err(
          UnsupportedFeature("prefixed opcode " + opcode.to_string(), position),
        )
      _ if is_plain_numeric(opcode) => ()
      _ =>
        return Err(UnsupportedFeature("opcode " + opcode.to_string(), position))
    }
  }
  if !saw_terminal_end || depth != 0 {
    Err(
      ValidationError(
        span.end,
        "function instruction sequence is missing its final end",
      ),
    )
  } else {
    Ok({
      instruction_count,
      control_depth: depth,
      control_block_count: blocks,
      branch_count: branches,
      call_count: calls,
      called_functions,
      memory_access_count: memory,
      local_access_count: locals,
      constant_count: constants,
      bulk_memory_instruction_count: bulk_memory,
      simd_instruction_count: simd,
    })
  }
}

///|
pub fn scan_code_body(
  binary : Module,
  body : CodeBody,
) -> Result[InstructionStats, DecodeError] {
  scan_instructions(binary.bytes, body.instruction_span)
}

///|
pub struct FunctionCallSummary {
  function_index : Int32
  callees : Array[Int32]
}

///|
pub fn build_call_graph(
  decoded : DecodedModule,
) -> Result[Array[FunctionCallSummary], DecodeError] {
  let summaries : Array[FunctionCallSummary] = []
  let mut function_index = decoded.imported_function_count()
  for body in decoded.code_bodies {
    let stats = match scan_code_body(decoded.binary(), body) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    summaries.push({ function_index, callees: stats.called_functions, })
    function_index = function_index + 1
  }
  Ok(summaries)
}
