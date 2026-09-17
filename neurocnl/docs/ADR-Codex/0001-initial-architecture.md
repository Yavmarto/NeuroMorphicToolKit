# ADR 0001: Initial Architecture of neurocnl

## Status
Accepted

## Context
Programming spiking neural networks usually requires both neuroscience knowledge and simulator- or hardware-specific implementation work. The current `neurocnl` repository exists to make the language of intent the primary authoring surface, then turn that intent into validated, executable, and exportable artifacts without pretending that every backend is equally mature.

This repository is not just a parser. It contains:
- the core Python package in `neurocnl/`, which owns parsing, invariants, IR lowering, backend planning, generation, simulation helpers, exporters, mapping, and handoff logic
- a FastAPI backend in `backend/app/`, which wraps the library for Studio and other API consumers
- a Flutter frontend in `frontend/`, which provides the interactive Studio experience

The library is already organized around a staged pipeline:
- CNL parsing in `neurocnl/cnl/`
- validation layers in `neurocnl/layers/`
- intermediate representation in `neurocnl/ir/`
- generation in `neurocnl/generation/`
- simulation helpers in `neurocnl/simulation/`
- exporters and converters in `neurocnl/export/` and `neurocnl/converter/`
- backend capability metadata and planning in `neurocnl/backends/` and `neurocnl/planner.py`
- downstream toolkit handoff paths in `neurocnl/handoff/`

The code and docs also make an important architectural distinction between:
- parser acceptance
- semantic validation
- execution fidelity
- export availability
- deployment honesty

That distinction is essential because `neurocnl` supports multiple target ecosystems, but the strongest faithful path is still the core Nengo-based flow.

## Decision
We will treat `neurocnl` as the language and semantics authority for the toolkit.

### Core architectural model

`neurocnl` is built around a single staged pipeline:
`parse -> validate -> lower/plan -> generate -> simulate/export/handoff`

That pipeline is the source of truth for behavior. New features should slot into this staged flow rather than bypassing it.

### Ownership boundaries

The core package owns:
- what CNL means
- which sentence families are accepted
- which biological and hardware invariants are enforced
- how parsed specs become IR and generator inputs
- what support level a backend can honestly claim
- the contracts for generated or exported artifacts

The FastAPI backend owns:
- HTTP exposure of library capabilities
- auth, rate limiting, middleware, jobs, and long-running request orchestration
- stable API surfaces for Studio and programmatic consumers

The Flutter frontend owns:
- visual authoring and inspection UX
- API consumption
- presentation of validation, generation, and support-level results

The frontend and backend must not become alternate semantic engines. They are adapters over the library, not replacements for it.

### Structural decomposition

The architecture is intentionally split so that different concerns can evolve without collapsing into one layer:
- `cnl/` parses and types the controlled language
- `layers/` enforces invariants and cross-sentence validation
- `ir/` normalizes parsed meaning into a backend-agnostic representation
- `generation/` turns validated meaning into executable network artifacts
- `backends/` and `planner.py` describe target support and planning constraints
- `export/` and `converter/` produce downstream artifacts and interoperability paths
- `contracts/` define typed boundaries for pipeline and deployment outputs
- `handoff/` integrates `neurocnl` outputs with the wider NMTK ecosystem

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not add parser support without deciding how it is validated, lowered, and surfaced in fidelity metadata.
- Do not treat exporter existence as proof of faithful backend support.
- Do not duplicate semantic rules in API routers or frontend code; semantic truth belongs in the library.
- Do not bypass contracts when adding new export or handoff artifacts.
- Do not change pipeline stage ordering casually; many tests and downstream consumers assume the current staged model.
- Do not collapse backend support labels into a binary supported/unsupported claim. The current architecture depends on nuanced support levels.

### Why it is built this way

This architecture keeps the hardest problem - meaning and validation of CNL specifications - in one place, then allows multiple user surfaces and target backends to consume that same meaning consistently. It also prevents the project from over-promising hardware readiness by making fidelity and support classification explicit first-class outputs of the system.

## Consequences
- Plain-English specifications become a first-class source of truth for SNN behavior instead of backend-specific code.
- Parser work, invariant enforcement, generation, and export can evolve separately because the repository has explicit internal stage boundaries.
- Nengo remains the most trustworthy execution baseline, while additional backends can be exposed with honest caveats instead of inflated claims.
- Cross-cutting changes are more expensive: adding new concepts often requires coordinated updates across parser, validators, IR, planner, generator, contracts, API responses, and tests.
- The architecture is resilient against hand-wavy support claims, but only if maintainers keep fidelity annotations, contracts, and backend metadata current.
