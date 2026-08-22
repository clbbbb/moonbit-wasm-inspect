# moonbit-wasm-inspect

MoonBit 原生的 WebAssembly 二进制检查与分析库，并提供可直接运行的命令行工具。

仓库：<https://github.com/clbbbb/moonbit-wasm-inspect>

它面向需要读取、审计或比较 `.wasm` 文件结构的工具作者：输入 WASM 二进制字节，得到 section、导入导出、函数元数据、数据/元素段、名称元数据、特性需求与校验结果。它不是 WebAssembly 运行时、编译器、反编译器，也不是其他语言 WASM 库的薄封装。

## 适用场景

- CI 中检查交付物是否为结构合法的 WASM v1 模块；
- 分析插件、合约或边缘函数的导入导出和所需 proposal；
- 比较两个构建产物的 section 结构；
- 为 MoonBit 编辑器工具、审计器和教学工具提供轻量二进制读取能力。

## 安装与构建

先按 [MoonBit 安装说明](https://www.moonbitlang.com/download/) 安装工具链，然后：

```bash
git clone https://github.com/clbbbb/moonbit-wasm-inspect.git
cd moonbit-wasm-inspect
moon check --deny-warn
moon test --deny-warn
```

作为依赖使用时，在你的 `moon.pkg` 中导入：

```moonbit nocheck
///|
import {
  "clbbbb/moonbit-wasm-inspect" @inspect,
}
```

发布到 mooncakes.io 后可通过 `moon add clbbbb/moonbit-wasm-inspect` 安装。

## CLI 使用

命令以源码方式运行，不需要预先安装可执行文件：

```bash
moon run cmd/main inspect path/to/module.wasm
moon run cmd/main inspect --json path/to/module.wasm
moon run cmd/main validate path/to/module.wasm
moon run cmd/main validate --json path/to/module.wasm
moon run cmd/main features path/to/module.wasm
moon run cmd/main diff left.wasm right.wasm
```

`inspect` 输出结构或已解码元数据；`validate` 发现语义问题时返回退出码 `1`；路径、格式或参数错误返回 `2`。四个命令均可加 `--json` 获取机器可读输出。

## 可运行示例

示例不依赖外部 fixture，在内存中构造一个真实的 WASM v1 模块并输出检查报告：

```bash
moon run examples/basic
```

最小 API 调用如下：

```moonbit nocheck
match @inspect.parse_module(bytes) {
  Err(error) => println(error.message())
  Ok(binary) => match @inspect.decode_module(binary) {
    Err(error) => println(error.message())
    Ok(decoded) => println(@inspect.render_decoded(decoded))
  }
}
```

## 已实现功能

- 有边界检查的字节游标、u32/i32 LEB128、magic/version、section 大小与顺序验证；
- Type、Import、Function、Table、Memory、Global、Export、Start、Code、Data、DataCount、Tag 与基础 Element section 解码；
- 标准 `name` custom section 的模块名和函数名映射；
- 数据/元素段、函数/标签类型、导出、start、memory/table/function 索引空间的交叉校验；
- 指令流摘要：控制块、分支、直接调用边、局部变量、常量、内存访问，以及常见 bulk-memory/SIMD immediate；
- 调用图摘要、文本/JSON 结构报告、校验报告、结构 diff 与保守特性识别。

## 功能边界

本项目当前不执行模块、不生成或优化 WASM，也不实现完整的验证器或反汇编器。Element 的 expression-based 形式、非 ASCII 名称、完整 SIMD 指令语义、异常处理指令流、GC/component model 与全部 proposal 仍不支持；遇到无法安全解码的格式会返回明确错误。特性报告是保守的“确定需要”，不承诺未报告的 proposal 一定未出现。

设计取舍见 [docs/DESIGN.md](docs/DESIGN.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 来源与许可证

项目实现为原创 MoonBit 代码；二进制格式依据 [WebAssembly Core Specification](https://webassembly.github.io/spec/core/binary/index.html) 编写，没有移植或复制其他 WASM 解析器的实现。CLI 文件读取使用 [moonbitlang/x/fs](https://github.com/moonbitlang/x) 0.5.1（Apache-2.0），作为正常依赖而非复制代码。测试 fixture 是项目内手工构造的最小 WASM 二进制。

本项目采用 [Apache-2.0](LICENSE) 许可证。
