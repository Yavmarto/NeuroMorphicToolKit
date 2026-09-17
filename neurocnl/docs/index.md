# neurocnl

Controlled Natural Language (CNL) specifications for neuromorphic computing — parse, validate, and compile plain-English specifications directly to NIR graphs (`nir.NIRGraph`).

## Overview

`neurocnl` allows you to define spiking neural networks using human-readable English sentences. This approach bridges the gap between high-level behavioral specifications and lower-level neuromorphic implementation details. The primary execution path compiles CNL directly to NIR (`CNL → IR → NIR`) without constructing a Nengo network.

## Key Features

- **Natural Language Parsing**: Define models using a structured subset of English with **21 parser-recognized sentence families**.
- **Automated Validation**: Multi-layer validation ensures your specifications are biologically plausible and consistent.
- **Direct NIR Compilation**: `compile_to_nir()` compiles CNL directly to a `nir.NIRGraph` in five stages (parse → exportability gate → IR lowering → materialization → optional write). Nengo is never constructed.
- **Hardware Export**: Export your models to NIR, Loihi (via Lava), SpiNNaker, Akida, PYNQ, Sinabs, and Rockpool. Export availability improves portability, but backend fidelity varies by target. Exporter presence does not imply production-ready hardware support.
- **Interactive Studio**: A Flutter-based web interface for designing, simulating, and analyzing your neuromorphic models.

## Fidelity Terms

`neurocnl` uses these support labels consistently:

- `parser-recognized`: the parser accepts the sentence family
- `faithful`: execution closely preserves intended semantics
- `approximate`: execution or export works with heuristics or backend-specific simplifications
- `unsupported`: runtime or backend support cannot be honestly claimed yet

## Backend Support In Product Flows

Studio and the backend API now surface backend support directly during validation:

- `backend_support.verdict` summarizes whether the selected backend is `faithful`, `approximate`, or `unsupported`
- `backend_support.warnings` lists timing, mapping, or hardware-limit caveats that do not necessarily fail validation
- `generator_fidelity.annotations` describes advanced generated concepts that are currently heuristic or placeholder implementations

Use these results to separate parser success from deployment confidence. A spec can parse and validate successfully while still being only `approximate` for a target backend. Exporter availability does not by itself imply faithful or production-ready deployment on every target.

## Getting Started

New to CNL or NIR? Start with the plain English overview:
[**CNL and NIR Explained in Plain English**](cnl_and_nir_explained.md) —
covers what CNL is, how it becomes a NIR graph, and how NIR converts back to
CNL, with no code required.

For writing your first CNL specification, see the [User Guide](user_guide.md).

For a deep-dive into the full `CNL → IR → NIR` pipeline (stages, fidelity table, error codes, worked examples), see the
[**CNL → NIR Developer Guide**](cnl_to_nir_developer_guide.md).
