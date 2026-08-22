# Design notes

`moonbit-wasm-inspect` uses three deliberately separate passes:

1. `parse_module` validates the binary envelope and stores spans for every section without decoding all payloads.
2. `decode_module` decodes index-bearing metadata and keeps byte spans for code, constant expressions, and data payloads instead of copying large payloads.
3. `validate` relates the decoded index spaces and returns all independent findings in one report.

This separation keeps a structure-only inspection cheap, prevents one malformed payload from being mistaken for a framing error, and makes the library useful to tools that only need selected sections.

The instruction scanner is intentionally a summary pass, not an interpreter. It validates framing for the supported core operations, records direct `call`/`return_call` targets, and counts control blocks and branches. Indirect calls are counted but cannot create a static direct edge. Proposal instructions are recognized only where their immediate framing is implemented.

The library preserves strict boundaries: unknown section IDs, malformed spans, invalid index references, and unsupported instruction forms are reported rather than guessed. This is preferable for auditing and CI tools, where a false “valid” result is worse than an incomplete report.
