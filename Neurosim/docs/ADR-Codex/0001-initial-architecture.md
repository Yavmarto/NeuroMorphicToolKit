# ADR 0001: Initial Architecture of Neurosim

## Status
Accepted

## Context
Many intended users of the toolkit understand systems, signal flow, or control structure, but they do not want to start from handwritten CNL or Python. Neurosim exists to let those users work visually while still staying connected to the formal semantics and simulation behavior used elsewhere in the suite.

The current repo is already structured around that bridge:
- a Flutter frontend in `frontend/` for canvas editing and interactive workflows
- a FastAPI backend in `neurosim/app/`
- project, preview, sweep, export, template, and validation routers
- translation services such as `graph_to_cnl.py`, `cnl_to_graph.py`, and `neurocnl_bridge.py`
- persistence and job support in `project_store.py` and `job_store.py`
- execution helpers in `preview_runner.py` and `sweep_runner.py`
- reusable component definitions in `neurosim/components/`

That structure implies an important architectural constraint: Neurosim is not the canonical owner of SNN semantics. It is the visual design and orchestration layer over those semantics.

## Decision
We will define Neurosim as the visual network design, project, and simulation workbench for the suite.

### Core architectural model

Neurosim is built around three connected representations:
- the interactive canvas graph
- the persisted project model
- the generated or synchronized CNL and simulation-facing representation

The frontend owns interaction and editing. The backend owns translation, orchestration, persistence, and simulation-facing service calls. The authoritative semantics of generated network meaning remain downstream in `neurocnl`.

### Ownership boundaries

Neurosim owns:
- visual composition of networks
- component and template selection
- project persistence
- preview, sweep, export, and simulation workflow orchestration
- graph-to-CNL and CNL-to-graph translation at the application boundary

Neurosim does not own:
- the canonical definition of CNL semantics
- the lowest-level invariant logic
- hardware deployment or benchmarking concerns

If a rule is fundamentally about whether a network is semantically valid, it should normally live in `neurocnl`, not be duplicated as bespoke canvas logic.

### Structural decomposition

Safe changes should preserve the current layering:
- frontend widgets and screens manage the user interaction model
- backend routers define project and simulation workflow endpoints
- services own translation, persistence, and execution orchestration
- schemas define the graph, project, preview, sweep, export, and template contracts
- reusable components remain a distinct library concept rather than hardcoded per screen

The `neurocnl_bridge` is a critical seam. It exists so Neurosim can benefit from `neurocnl` semantics without pulling that logic into every local service.

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not duplicate semantic validation rules in multiple places when they belong in the bridge or upstream semantic layer.
- Do not let the canvas graph drift from the persisted project model or translation schema without updating both directions of synchronization.
- Do not move long-running preview or sweep logic into the UI layer.
- Do not treat visual components as mere cosmetics; their parameter and port definitions are part of the application model.
- Do not bypass the graph/CNL translation boundary with one-off screen-specific hacks for new behaviors.

### Why it is built this way

This architecture gives users a visual entry point without fragmenting the underlying truth of the system. The canvas can stay friendly, the backend can manage workflow and persistence, and the semantic layer can stay centralized instead of being partially reimplemented in the UI.

## Consequences
- Users can construct and iterate on SNN designs through a visual interface without losing access to structured CNL and simulation outputs.
- The module remains maintainable only if graph schema, translation logic, and frontend component definitions stay aligned.
- Preview, sweep, and export features benefit from backend orchestration, but that means asynchronous workflow and persistence logic are part of the architecture, not incidental plumbing.
- The bridge to `neurocnl` reduces semantic duplication, but also means breaking changes in translation or contracts can ripple across multiple Neurosim features.

## Status Update (2026-07-16 audit)
Two structural elements cited in this ADR's Context are no longer accurate: the `graph_to_cnl.py`/`cnl_to_graph.py`/`neurocnl_bridge.py` translation services, and the standalone Flutter `frontend/` directory. Rather than re-verifying and repeating the detail here, see the status updates on `ADR-claude/0002-bidirectional-cnl-conversion.md` (translation services — confirmed removed/replaced by the NIR-native pipeline in `neurocnl/neurosim/app/services/nir_support.py`) and `ADR-Gemini/0003-dynamic-component-manifests.md` (frontend — confirmed there is no `Neurosim/frontend/`, and the canvas UI is embedded in the `neurocnl` frontend at `/canvas`, per `Neurosim/README.md`). The broader ownership-boundary framing in this ADR (Neurosim as visual/orchestration layer, `neurocnl` as canonical semantics owner) still holds.
