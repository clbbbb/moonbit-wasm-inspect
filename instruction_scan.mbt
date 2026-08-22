///| A conservative scanner for the MVP WebAssembly instruction set. It does
///| not execute instructions; it validates their binary framing and records
///| enough structure for size diagnostics and future control-flow tools.

pub struct InstructionStats {
  instruction_count : Int
  control_depth : Int
  call_count : Int
  memory_access_count : Int
  local_access_count : Int
  constant_count : Int
}

pub fn InstructionStats::summary(self : InstructionStats) -> String {
  "instructions=" + self.instruction_count.to_string() +
  ", calls=" + self.call_count.to_string() +
  ", memory=" + self.memory_access_count.to_string() +
  ", locals=" + self.local_access_count.to_string() +
  ", constants=" + self.constant_count.to_string()
}

fn skip_i64(cursor : Cursor) -> Result[Unit, DecodeError] {
  let start = cursor.position
  let mut count = 0
  let mut done = false
  while !done {
    if count == 10 { return Err(InvalidLeb128(start, "i64 immediate is too long")) }
    match cursor.read_u8() {
      Err(error) => return Err(error)
      Ok(byte) => { count = count + 1; done = (byte & 0x80) == 0 }
    }
  }
  Ok(())
}

fn skip_block_type(cursor : Cursor) -> Result[Unit, DecodeError] {
  let position = cursor.position
  match cursor.peek_u8() {
    Err(error) => Err(error)
    Ok(0x40) | Ok(0x7f) | Ok(0x7e) | Ok(0x7d) | Ok(0x7c) | Ok(0x70) | Ok(0x6f) => cursor.skip(1)
    Ok(_) => match cursor.read_var_i32() {
      Ok(_) => Ok(())
      Err(_) => Err(InvalidLeb128(position, "invalid block type"))
    }
  }
}

fn skip_memory_immediate(cursor : Cursor) -> Result[Unit, DecodeError] {
  match cursor.read_var_u32() {
    Err(error) => Err(error)
    Ok(_) => match cursor.read_var_u32() {
      Ok(_) => Ok(())
      Err(error) => Err(error)
    }
  }
}

fn skip_br_table(cursor : Cursor) -> Result[Unit, DecodeError] {
  let count = match cursor.read_var_u32() { Ok(value) => value; Err(error) => return Err(error) }
  for _ in 0..<(count + 1) {
    match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
  }
  Ok(())
}

fn is_plain_numeric(opcode : Int) -> Bool {
  (opcode >= 0x45 && opcode <= 0xc4) || opcode == 0xd1
}

pub fn scan_instructions(bytes : Array[Int], span : Span) -> Result[InstructionStats, DecodeError] {
  let cursor = Cursor::with_bounds(bytes, span.start, span.end)
  let mut instruction_count = 0
  let mut depth = 0
  let mut calls = 0
  let mut memory = 0
  let mut locals = 0
  let mut constants = 0
  let mut saw_terminal_end = false
  while !cursor.is_finished() {
    let position = cursor.position
    let opcode = match cursor.read_u8() { Ok(value) => value; Err(error) => return Err(error) }
    instruction_count = instruction_count + 1
    match opcode {
      0x00 | 0x01 | 0x0f | 0x1a | 0x1b | 0x1c => ()
      0x02 | 0x03 | 0x04 => {
        match skip_block_type(cursor) { Ok(_) => (); Err(error) => return Err(error) }
        depth = depth + 1
      }
      0x05 => {
        if depth == 0 { return Err(ValidationError(position, "else outside a block")) }
      }
      0x0b => {
        if depth == 0 {
          if !cursor.is_finished() { return Err(ValidationError(position, "bytes follow outer function end")) }
          saw_terminal_end = true
        } else {
          depth = depth - 1
        }
      }
      0x0c | 0x0d | 0x10 | 0x12 | 0x14 => {
        match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
        if opcode == 0x10 || opcode == 0x12 { calls = calls + 1 }
      }
      0x0e => match skip_br_table(cursor) { Ok(_) => (); Err(error) => return Err(error) }
      0x11 | 0x13 => {
        match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
        match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
        calls = calls + 1
      }
      0x20 | 0x21 | 0x22 => {
        match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
        locals = locals + 1
      }
      0x23 | 0x24 | 0x25 | 0x26 => match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
      0x28..=0x3e => {
        match skip_memory_immediate(cursor) { Ok(_) => (); Err(error) => return Err(error) }
        memory = memory + 1
      }
      0x3f | 0x40 => match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
      0x41 => { match cursor.read_var_i32() { Ok(_) => (); Err(error) => return Err(error) }; constants = constants + 1 }
      0x42 => { match skip_i64(cursor) { Ok(_) => (); Err(error) => return Err(error) }; constants = constants + 1 }
      0x43 => { match cursor.skip(4) { Ok(_) => (); Err(error) => return Err(error) }; constants = constants + 1 }
      0x44 => { match cursor.skip(8) { Ok(_) => (); Err(error) => return Err(error) }; constants = constants + 1 }
      0xd0 => match cursor.read_u8() { Ok(_) => (); Err(error) => return Err(error) }
      0xd2 => match cursor.read_var_u32() { Ok(_) => (); Err(error) => return Err(error) }
      0xfc | 0xfd | 0xfe | 0xfb => return Err(UnsupportedFeature("prefixed opcode " + opcode.to_string(), position))
      _ if is_plain_numeric(opcode) => ()
      _ => return Err(UnsupportedFeature("opcode " + opcode.to_string(), position))
    }
  }
  if !saw_terminal_end || depth != 0 {
    Err(ValidationError(span.end, "function instruction sequence is missing its final end"))
  } else {
    Ok({
      instruction_count,
      control_depth: depth,
      call_count: calls,
      memory_access_count: memory,
      local_access_count: locals,
      constant_count: constants,
    })
  }
}

pub fn scan_code_body(binary : Module, body : CodeBody) -> Result[InstructionStats, DecodeError] {
  scan_instructions(binary.bytes, body.instruction_span)
}
