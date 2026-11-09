///| WebAssembly module model. The model deliberately keeps raw section spans:

///| callers can inspect a module cheaply and opt in to detailed decoding only

///|
/// for the sections they need.
#derive(Eq)
pub enum SectionKind {
  Custom
  Type
  Import
  Function
  Table
  Memory
  Global
  Export
  Start
  Element
  Code
  Data
  DataCount
  Tag
}

///|
pub extend SectionKind with Eq::{not_equal, equal}

///|
pub fn SectionKind::id(self : SectionKind) -> Int32 {
  match self {
    Custom => 0
    Type => 1
    Import => 2
    Function => 3
    Table => 4
    Memory => 5
    Global => 6
    Export => 7
    Start => 8
    Element => 9
    Code => 10
    Data => 11
    DataCount => 12
    Tag => 13
  }
}

///|
pub fn SectionKind::label(self : SectionKind) -> String {
  match self {
    Custom => "custom"
    Type => "type"
    Import => "import"
    Function => "function"
    Table => "table"
    Memory => "memory"
    Global => "global"
    Export => "export"
    Start => "start"
    Element => "element"
    Code => "code"
    Data => "data"
    DataCount => "data-count"
    Tag => "tag"
  }
}

///|
pub fn section_kind_from_id(id : Int32) -> SectionKind? {
  match id {
    0 => Some(Custom)
    1 => Some(Type)
    2 => Some(Import)
    3 => Some(Function)
    4 => Some(Table)
    5 => Some(Memory)
    6 => Some(Global)
    7 => Some(Export)
    8 => Some(Start)
    9 => Some(Element)
    10 => Some(Code)
    11 => Some(Data)
    12 => Some(DataCount)
    13 => Some(Tag)
    _ => None
  }
}

///|
pub struct Section {
  id : Int32
  kind : SectionKind
  payload : Span
  full : Span
  custom_name : String?
}

///|
pub fn Section::payload_size(self : Section) -> Int32 {
  self.payload.size()
}

///|
pub fn Section::is_named(self : Section, name : String) -> Bool {
  match self.custom_name {
    Some(value) => value == name
    None => false
  }
}

///|
pub struct Module {
  bytes : Array[Int32]
  sections : Array[Section]
  version : Int32
}

///|
pub fn Module::version(self : Module) -> Int32 {
  self.version
}

///|
pub fn Module::byte_length(self : Module) -> Int32 {
  self.bytes.length()
}

///|
pub fn Module::sections(self : Module) -> Array[Section] {
  self.sections
}

///|
pub fn Module::section_count(self : Module) -> Int32 {
  self.sections.length()
}

///|
pub fn Module::find_section(self : Module, kind : SectionKind) -> Section? {
  for section in self.sections {
    if section.kind == kind {
      return Some(section)
    }
  }
  None
}

///|
pub fn Module::custom_sections(self : Module, name : String) -> Array[Section] {
  let found : Array[Section] = []
  for section in self.sections {
    if section.is_named(name) {
      found.push(section)
    }
  }
  found
}

///|
pub fn Module::section_bytes(self : Module, section : Section) -> Array[Int32] {
  let output : Array[Int32] = []
  let mut position = section.payload.start
  while position < section.payload.end {
    output.push(self.bytes[position])
    position = position + 1
  }
  output
}

///|
pub enum ValueType {
  I32
  I64
  F32
  F64
  V128
  FuncRef
  ExternRef
}

///|
pub fn ValueType::label(self : ValueType) -> String {
  match self {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    FuncRef => "funcref"
    ExternRef => "externref"
  }
}

///|
fn value_type_from_byte(byte : Int32) -> ValueType? {
  match byte {
    0x7f => Some(I32)
    0x7e => Some(I64)
    0x7d => Some(F32)
    0x7c => Some(F64)
    0x7b => Some(V128)
    0x70 => Some(FuncRef)
    0x6f => Some(ExternRef)
    _ => None
  }
}

///|
pub struct FunctionType {
  params : Array[ValueType]
  results : Array[ValueType]
}

///|
pub fn FunctionType::params(self : FunctionType) -> Array[ValueType] {
  self.params
}

///|
pub fn FunctionType::results(self : FunctionType) -> Array[ValueType] {
  self.results
}

///|
pub fn FunctionType::signature(self : FunctionType) -> String {
  let mut text = "("
  let mut first = true
  for value in self.params {
    if !first {
      text = text + ", "
    }
    text = text + value.label()
    first = false
  }
  text = text + ") -> ("
  first = true
  for value in self.results {
    if !first {
      text = text + ", "
    }
    text = text + value.label()
    first = false
  }
  text + ")"
}

///|
#derive(Eq)
pub enum ExternalKind {
  FunctionExternal
  TableExternal
  MemoryExternal
  GlobalExternal
  TagExternal
}

///|
pub extend ExternalKind with Eq::{not_equal, equal}

///|
pub fn ExternalKind::label(self : ExternalKind) -> String {
  match self {
    FunctionExternal => "function"
    TableExternal => "table"
    MemoryExternal => "memory"
    GlobalExternal => "global"
    TagExternal => "tag"
  }
}

///|
pub struct Import {
  module_name : String
  name : String
  kind : ExternalKind
  type_index : Int32?
}

///|
pub struct Export {
  name : String
  kind : ExternalKind
  index : Int32
}

///|
pub struct Limits {
  minimum : Int32
  maximum : Int32?
  shared : Bool
  memory64 : Bool
}

///|
pub fn Limits::description(self : Limits) -> String {
  let text = "min=" + self.minimum.to_string()
  match self.maximum {
    Some(maximum) => text + ", max=" + maximum.to_string()
    None => text + ", max=unbounded"
  }
}

///|
pub struct TableInfo {
  element_type : ValueType
  limits : Limits
}

///|
pub struct MemoryInfo {
  limits : Limits
}

///|
pub struct GlobalInfo {
  value_type : ValueType
  mutable : Bool
  init_span : Span
}

///|
pub struct TagInfo {
  type_index : Int32
}

///|
pub struct CodeBody {
  locals : Array[ValueType]
  instruction_span : Span
  byte_length : Int32
}

///|
pub struct DecodedModule {
  binary : Module
  types : Array[FunctionType]
  imports : Array[Import]
  function_types : Array[Int32]
  tables : Array[TableInfo]
  memories : Array[MemoryInfo]
  globals : Array[GlobalInfo]
  exports : Array[Export]
  start_function : Int32?
  code_bodies : Array[CodeBody]
  element_segments : Array[ElementSegment]
  data_segments : Array[DataSegment]
  data_count : Int32?
  tags : Array[TagInfo]
  warnings : Array[String]
}

///|
pub fn DecodedModule::binary(self : DecodedModule) -> Module {
  self.binary
}

///|
pub fn DecodedModule::types(self : DecodedModule) -> Array[FunctionType] {
  self.types
}

///|
pub fn DecodedModule::imports(self : DecodedModule) -> Array[Import] {
  self.imports
}

///|
pub fn DecodedModule::exports(self : DecodedModule) -> Array[Export] {
  self.exports
}

///|
pub fn DecodedModule::warnings(self : DecodedModule) -> Array[String] {
  self.warnings
}

///|
pub fn DecodedModule::defined_function_count(self : DecodedModule) -> Int32 {
  self.function_types.length()
}

///|
pub fn DecodedModule::defined_tag_count(self : DecodedModule) -> Int32 {
  self.tags.length()
}

///|
pub fn DecodedModule::imported_function_count(self : DecodedModule) -> Int32 {
  let mut count = 0
  for item in self.imports {
    if item.kind == FunctionExternal {
      count = count + 1
    }
  }
  count
}
