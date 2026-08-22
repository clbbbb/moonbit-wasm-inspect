///| A small native/WASI command line front-end. The library owns parsing and

///|
/// reporting; this package only handles paths, arguments, and exit codes.
#cfg(target="wasm")
fn exit_with(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(target="wasm-gc")
fn exit_with(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn exit_with(code : Int) = "exit"

///|
#cfg(target="js")
extern "js" fn exit_with(code : Int) =
  #| function(code) {
  #|   if (typeof process !== "undefined") process.exit(code);
  #| }

///|
fn usage() -> String {
  "Usage:\n" +
  "  moon run cmd/main inspect [--json] <module.wasm>\n" +
  "  moon run cmd/main validate [--json] <module.wasm>\n" +
  "  moon run cmd/main features [--json] <module.wasm>\n" +
  "  moon run cmd/main diff [--json] <left.wasm> <right.wasm>"
}

///|
fn read_module(path : String) -> Result[@inspect.Module, String] {
  let raw = @fs.read_file_to_bytes(path) catch {
    _ => return Err("cannot read '" + path + "'")
  }
  let bytes : Array[Int] = []
  for byte in raw {
    bytes.push(byte.to_int())
  }
  match @inspect.parse_module(bytes) {
    Ok(binary) => Ok(binary)
    Err(error) => Err("cannot parse '" + path + "': " + error.message())
  }
}

///|
fn single_input(args : ArrayView[String]) -> Result[(Bool, String), String] {
  if args.length() == 1 {
    Ok((false, args[0]))
  } else if args.length() == 2 && args[0] == "--json" {
    Ok((true, args[1]))
  } else {
    Err("expected one module path, optionally preceded by --json")
  }
}

///|
fn two_inputs(
  args : ArrayView[String],
) -> Result[(Bool, String, String), String] {
  if args.length() == 2 {
    Ok((false, args[0], args[1]))
  } else if args.length() == 3 && args[0] == "--json" {
    Ok((true, args[1], args[2]))
  } else {
    Err("expected two module paths, optionally preceded by --json")
  }
}

///|
fn render_features_json(features : Array[@inspect.WasmFeature]) -> String {
  let mut text = "{\"features\":["
  let mut first = true
  for feature in features {
    if !first {
      text = text + ","
    }
    text = text + "\"" + feature.label() + "\""
    first = false
  }
  text + "]}"
}

///|
fn size_json(value : Int?) -> String {
  match value {
    Some(size) => size.to_string()
    None => "null"
  }
}

///|
fn render_diff_json(left : @inspect.Module, right : @inspect.Module) -> String {
  let differences = @inspect.diff_structure(left, right)
  let mut text = "{\"differences\":["
  let mut first = true
  for difference in differences {
    if !first {
      text = text + ","
    }
    text = text +
      "{\"section\":\"" +
      difference.label +
      "\",\"left\":" +
      size_json(difference.left_size) +
      ",\"right\":" +
      size_json(difference.right_size) +
      "}"
    first = false
  }
  text + "]}"
}

///|
fn inspect_command(json : Bool, path : String) -> Int {
  let binary = match read_module(path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  if json {
    println(@inspect.render_structure_json(binary))
    return 0
  }
  match @inspect.decode_module(binary) {
    Ok(decoded) => {
      println(@inspect.render_decoded(decoded))
      0
    }
    Err(error) => {
      println(error.message())
      2
    }
  }
}

///|
fn validate_command(json : Bool, path : String) -> Int {
  let binary = match read_module(path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let decoded = match @inspect.decode_module(binary) {
    Ok(value) => value
    Err(error) => {
      println(error.message())
      return 2
    }
  }
  let report = @inspect.validate(decoded)
  if json {
    println(@inspect.render_validation_json(report))
  } else {
    println(report.render())
  }
  if report.has_errors() {
    1
  } else {
    0
  }
}

///|
fn features_command(json : Bool, path : String) -> Int {
  let binary = match read_module(path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let decoded = match @inspect.decode_module(binary) {
    Ok(value) => value
    Err(error) => {
      println(error.message())
      return 2
    }
  }
  let features = @inspect.detect_features(decoded)
  if json {
    println(render_features_json(features))
  } else {
    println(@inspect.render_features(features))
  }
  0
}

///|
fn diff_command(json : Bool, left_path : String, right_path : String) -> Int {
  let left = match read_module(left_path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  let right = match read_module(right_path) {
    Ok(value) => value
    Err(message) => {
      println(message)
      return 2
    }
  }
  if json {
    println(render_diff_json(left, right))
  } else {
    println(@inspect.render_structure_diff(left, right))
  }
  0
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 2 {
    println(usage())
    exit_with(2)
    return
  }
  let exit_code = match argv[1] {
    "inspect" =>
      match single_input(argv[2:]) {
        Ok((json, path)) => inspect_command(json, path)
        Err(message) => {
          println(message + "\n" + usage())
          2
        }
      }
    "validate" =>
      match single_input(argv[2:]) {
        Ok((json, path)) => validate_command(json, path)
        Err(message) => {
          println(message + "\n" + usage())
          2
        }
      }
    "features" =>
      match single_input(argv[2:]) {
        Ok((json, path)) => features_command(json, path)
        Err(message) => {
          println(message + "\n" + usage())
          2
        }
      }
    "diff" =>
      match two_inputs(argv[2:]) {
        Ok((json, left, right)) => diff_command(json, left, right)
        Err(message) => {
          println(message + "\n" + usage())
          2
        }
      }
    _ => {
      println("unknown command '" + argv[1] + "'\n" + usage())
      2
    }
  }
  if exit_code != 0 {
    exit_with(exit_code)
  }
}
