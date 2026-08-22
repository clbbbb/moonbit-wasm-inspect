// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "clbbbb/moonbit-wasm-inspect"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/clbbbb/moonbit-wasm-inspect"

license = "Apache-2.0"

keywords = [ "wasm", "webassembly", "binary", "inspection", "analysis" ]

preferred_target = "wasm"

description = "A MoonBit-native WebAssembly binary inspection and analysis library."

import {
  "moonbitlang/x@0.5.1",
}
