///|
/// Byte-level section comparison complements the size-only structural diff.
pub enum SectionChangeKind {
  SectionChanged
  SectionAdded
  SectionRemoved
}

///|
pub fn SectionChangeKind::label(self : SectionChangeKind) -> String {
  match self {
    SectionChanged => "changed"
    SectionAdded => "added"
    SectionRemoved => "removed"
  }
}

///|
pub struct BinarySectionChange {
  section_label : String
  occurrence : Int32
  kind : SectionChangeKind
  left_index : Int32?
  right_index : Int32?
  left_bytes : Int32
  right_bytes : Int32
  common_prefix_bytes : Int32
  differing_bytes : Int32
}

///|
pub fn BinarySectionChange::description(self : BinarySectionChange) -> String {
  let left_index = match self.left_index {
    Some(index) => index.to_string()
    None => "-"
  }
  let right_index = match self.right_index {
    Some(index) => index.to_string()
    None => "-"
  }
  self.kind.label() +
  " " +
  self.section_label +
  " occurrence=" +
  self.occurrence.to_string() +
  " left#" +
  left_index +
  " right#" +
  right_index +
  " bytes=" +
  self.left_bytes.to_string() +
  "->" +
  self.right_bytes.to_string() +
  ", common-prefix=" +
  self.common_prefix_bytes.to_string() +
  ", differing-bytes=" +
  self.differing_bytes.to_string()
}

///|
fn section_identity(section : Section) -> String {
  match section.custom_name {
    Some(name) => "custom:" + name
    None => "standard:" + section.kind.label()
  }
}

///|
fn occurrence_before(
  sections : Array[Section],
  end : Int32,
  target : Section,
) -> Int32 {
  let identity = section_identity(target)
  let mut count = 0
  for index in 0..<end {
    if section_identity(sections[index]) == identity {
      count = count + 1
    }
  }
  count
}

///|
fn find_section_occurrence(
  sections : Array[Section],
  identity : String,
  occurrence : Int32,
) -> Int32? {
  let mut seen = 0
  let mut index = 0
  while index < sections.length() {
    if section_identity(sections[index]) == identity {
      if seen == occurrence {
        return Some(index)
      }
      seen = seen + 1
    }
    index = index + 1
  }
  None
}

///|
fn compare_section_bytes(
  left : Module,
  left_section : Section,
  right : Module,
  right_section : Section,
) -> (Int32, Int32, Bool) {
  let left_size = left_section.payload.size()
  let right_size = right_section.payload.size()
  let shared_size = if left_size < right_size { left_size } else { right_size }
  let mut prefix = 0
  let mut differences = 0
  let mut equal = left_size == right_size
  while prefix < shared_size &&
        left.bytes[left_section.payload.start + prefix] ==
        right.bytes[right_section.payload.start + prefix] {
    prefix = prefix + 1
  }
  let mut offset = prefix
  while offset < shared_size {
    if left.bytes[left_section.payload.start + offset] !=
      right.bytes[right_section.payload.start + offset] {
      differences = differences + 1
      equal = false
    }
    offset = offset + 1
  }
  if left_size > shared_size {
    differences = differences + left_size - shared_size
  }
  if right_size > shared_size {
    differences = differences + right_size - shared_size
  }
  (prefix, differences, equal)
}

///|
fn removed_section_change(
  left_section : Section,
  left_index : Int32,
  occurrence : Int32,
) -> BinarySectionChange {
  {
    section_label: section_identity(left_section),
    occurrence,
    kind: SectionRemoved,
    left_index: Some(left_index),
    right_index: None,
    left_bytes: left_section.payload.size(),
    right_bytes: 0,
    common_prefix_bytes: 0,
    differing_bytes: left_section.payload.size(),
  }
}

///|
fn added_section_change(
  right_section : Section,
  right_index : Int32,
  occurrence : Int32,
) -> BinarySectionChange {
  {
    section_label: section_identity(right_section),
    occurrence,
    kind: SectionAdded,
    left_index: None,
    right_index: Some(right_index),
    left_bytes: 0,
    right_bytes: right_section.payload.size(),
    common_prefix_bytes: 0,
    differing_bytes: right_section.payload.size(),
  }
}

///|
pub fn diff_binary_sections(
  left : Module,
  right : Module,
) -> Array[BinarySectionChange] {
  let changes : Array[BinarySectionChange] = []
  let left_sections = left.sections()
  let right_sections = right.sections()
  for left_index in 0..<left_sections.length() {
    let left_section = left_sections[left_index]
    let occurrence = occurrence_before(left_sections, left_index, left_section)
    let identity = section_identity(left_section)
    match find_section_occurrence(right_sections, identity, occurrence) {
      None =>
        changes.push(
          removed_section_change(left_section, left_index, occurrence),
        )
      Some(right_index) => {
        let right_section = right_sections[right_index]
        let (prefix, differences, equal) = compare_section_bytes(
          left, left_section, right, right_section,
        )
        if !equal {
          changes.push({
            section_label: identity,
            occurrence,
            kind: SectionChanged,
            left_index: Some(left_index),
            right_index: Some(right_index),
            left_bytes: left_section.payload.size(),
            right_bytes: right_section.payload.size(),
            common_prefix_bytes: prefix,
            differing_bytes: differences,
          })
        }
      }
    }
  }
  for right_index in 0..<right_sections.length() {
    let right_section = right_sections[right_index]
    let occurrence = occurrence_before(
      right_sections, right_index, right_section,
    )
    match
      find_section_occurrence(
        left_sections,
        section_identity(right_section),
        occurrence,
      ) {
      Some(_) => ()
      None =>
        changes.push(
          added_section_change(right_section, right_index, occurrence),
        )
    }
  }
  changes
}

///|
pub fn render_binary_diff(changes : Array[BinarySectionChange]) -> String {
  if changes.length() == 0 {
    return "binary sections are identical\n"
  }
  let mut text = "binary section changes: " +
    changes.length().to_string() +
    "\n"
  for change in changes {
    text = text + "  - " + change.description() + "\n"
  }
  text
}
