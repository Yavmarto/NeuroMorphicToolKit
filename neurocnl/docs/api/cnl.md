# CNL Parser API

The `neurocnl.cnl` module contains the grammar and parser for Controlled Natural Language.

The parser currently recognizes 18 sentence families. Parser coverage is broader than execution fidelity: some concepts are well-supported in the main Nengo pipeline, while newer concepts are currently best treated as prototyping-oriented or approximate in downstream generation/export.

Support terminology used across the project:

- `parser-recognized`: accepted by the parser
- `faithful`: execution closely preserves intended semantics
- `approximate`: execution or export works with heuristics or backend-specific simplifications
- `unsupported`: runtime or backend support cannot yet be honestly claimed

## CNL Parser

::: neurocnl.cnl.cnl_parser

## CNL Types

::: neurocnl.cnl.types
