///| Runtime-feature detection is intentionally conservative: a reported

///| feature is definitely required, while an absent report means only that the

///|
/// currently decoded metadata did not require it.
pub enum WasmFeature {
  MultiMemory
  Memory64
  Threads
  BulkMemory
  ReferenceTypes
  ExceptionHandling
  Simd
}

///|
pub fn WasmFeature::label(self : WasmFeature) -> String {
  match self {
    MultiMemory => "multi-memory"
    Memory64 => "memory64"
    Threads => "threads"
    BulkMemory => "bulk-memory"
    ReferenceTypes => "reference-types"
    ExceptionHandling => "exception-handling"
    Simd => "simd"
  }
}

///|
fn contains_feature(values : Array[WasmFeature], target : WasmFeature) -> Bool {
  for value in values {
    if value.label() == target.label() {
      return true
    }
  }
  false
}

///|
fn add_feature(values : Array[WasmFeature], target : WasmFeature) -> Unit {
  if !contains_feature(values, target) {
    values.push(target)
  }
}

///|
pub fn detect_features(decoded : DecodedModule) -> Array[WasmFeature] {
  let features : Array[WasmFeature] = []
  if decoded.memories.length() + imported_count(decoded, MemoryExternal) > 1 {
    add_feature(features, MultiMemory)
  }
  for memory in decoded.memories {
    if memory.limits.memory64 {
      add_feature(features, Memory64)
    }
    if memory.limits.shared {
      add_feature(features, Threads)
    }
  }
  for table in decoded.tables {
    match table.element_type {
      ExternRef => add_feature(features, ReferenceTypes)
      _ => ()
    }
  }
  if decoded.binary().has_section(DataCount) {
    add_feature(features, BulkMemory)
  }
  if decoded.binary().has_section(Tag) {
    add_feature(features, ExceptionHandling)
  }
  for body in decoded.code_bodies {
    match scan_code_body(decoded.binary(), body) {
      Ok(stats) => {
        if stats.bulk_memory_instruction_count > 0 {
          add_feature(features, BulkMemory)
        }
        if stats.simd_instruction_count > 0 {
          add_feature(features, Simd)
        }
      }
      Err(_) => ()
    }
  }
  features
}

///|
pub fn render_features(features : Array[WasmFeature]) -> String {
  if features.length() == 0 {
    return "required features: MVP\n"
  }
  let mut text = "required features:\n"
  for feature in features {
    text = text + "  - " + feature.label() + "\n"
  }
  text
}
