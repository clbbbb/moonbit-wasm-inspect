///|
/// Minimal in-memory inspection example. Run with `moon run examples/basic`.
fn sample_module() -> Array[Int] {
  [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    // type: one () -> () function
     1, 4, 1, 0x60, 0, 0,
    // function: type 0
     3, 2, 1, 0,
    // export function 0 as "run"
     7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 0,
    // code: one empty body
     10, 4, 1, 2, 0, 0x0b,
  ]
}

///|
fn main {
  match @inspect.parse_module(sample_module()) {
    Err(error) => println(error.message())
    Ok(binary) =>
      match @inspect.decode_module(binary) {
        Err(error) => println(error.message())
        Ok(decoded) => {
          println(@inspect.render_decoded(decoded))
          println(@inspect.validate(decoded).render())
        }
      }
  }
}
