# ADR 0020: CNL Studio Owns Deployment Target Selection

## Status
Accepted

## Context
The suite currently spans `neurocnl`, `Neurosim`, and `Neurochip`, but the
operator workflow is not equally owned by each module. The current frontend
state already shows the intended direction:

- `neurocnl` `Studio` is the primary authoring, validation, generation, and
  handoff surface.
- `Neurosim` is the visual editor and topology inspection surface.
- `Neurochip` is the target-specific execution, packaging, flashing, and
  diagnostics surface.

Recent handoff work introduced a versioned `import_network_handoff` payload
from `Studio` to `Neurochip`, but the contract has not been written down in one
authoritative place. As a result, target ownership, target labels, and
destination workspace mapping can still drift between modules.

## Decision
`CNL Studio` is the only primary surface that selects the deployment target for
the canonical operator workflow.

The canonical workflow is:

1. Author or load a spec in `Studio`.
2. Parse, validate, generate, and optionally simulate in `Studio`.
3. Open `Neurosim` only for visual editing, topology inspection, or
   simulation-oriented refinement.
4. Return to `Studio`.
5. Choose the deployment target once in `Studio`.
6. Open `Neurochip` in the imported target context for execution-specific work.

`Neurosim -> Neurochip` is not a primary operator path. If a direct handoff
exists in the future, it must be explicitly labeled as an advanced shortcut.

`Neurochip` must treat the imported target context as the authoritative initial
state. It may allow an explicit `Change target` override, but it must not ask
the operator to re-answer the same target-selection question by default.

## Shared handoff mapping
The `Studio` target selector owns the following mapping for canonical
`Studio -> Neurochip` handoff:

| Studio target | `target_id` | `target_label` | `destination_workspace` |
|---|---|---|---|
| `teensy` | `teensy41` | `Teensy 4.1` | `teensy` |
| `pynq` | `pynq` | `PYNQ` | `pynq` |
| `akida` | `akida` | `Akida` | `akida` |

All producer and consumer code must treat this table as the cross-module source
of truth until a typed shared contract package replaces it.

## Handoff payload contract
The canonical `Studio -> Neurochip` handoff uses the versioned
`import_network_handoff` query parameter. The payload must include:

- `handoff_version`
- `source`
- `network`
- `target_id`
- `target_label`
- `destination_workspace`
- `readiness_summary`

`import_network` is a legacy compatibility path only. New callers must use the
versioned handoff.

## Consequences
- **Positive:** The suite now has one documented answer to "where do I pick the
  deployment target?"
- **Positive:** `Neurosim` and `Neurochip` can simplify UX because they no
  longer need to behave like competing deployment routers.
- **Positive:** Tests can assert the mapping and payload shape against one
  contract instead of local assumptions.
- **Negative:** Until a typed shared package exists, this ADR still requires
  codebases to manually stay synchronized with the documented mapping.
- **Follow-up:** Move the hardcoded Studio mapping out of
  `studio_screen.dart` into a contract-backed surface and remove stale
  `Neurosim -> Neurochip` handoff wiring.
