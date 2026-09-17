# ADR 0021: Studio To Neurochip Handoff Contract

## Status
Accepted

## Supersedes
- `docs/ADR-claude/0020-studio-owns-deployment-target-selection.md`

## Context
ADR 0020 established the product rule that `CNL Studio` owns deployment target
selection for the canonical operator workflow. The repo now also contains a
versioned `Studio -> Neurochip` handoff payload, extracted target mapping logic
on the producer side, and removed `NeuroSim -> Neurochip` primary-path UI.

What remained open was the authoritative cross-module contract for the handoff
itself. Without that contract, `neurocnl` and `Neurochip` could still drift on:

- which `target_id` belongs to each Studio target
- which `destination_workspace` is canonical for a given imported target
- whether the consumer should trust `destination_workspace` as an independent
  routing input instead of a target-scoped contract field

## Decision
`Studio -> Neurochip` uses a single cross-module handoff contract.

`Studio` remains the only primary owner of deployment target selection. For the
versioned `import_network_handoff` flow, `Neurochip` must treat the imported
target context as the authoritative initial state and must normalize the
workspace from the contract mapping rather than owning separate destination
workspace semantics.

`NeuroSim -> Neurochip` is not a primary operator path.

## Canonical mapping

| Studio target | `target_id` | `target_label` | `destination_workspace` |
|---|---|---|---|
| `teensy` | `teensy41` | `Teensy 4.1` | `teensy` |
| `pynq` | `pynq` | `PYNQ` | `pynq` |
| `akida` | `akida` | `Akida` | `akida` |

This table is the cross-module source of truth until a typed shared package
replaces the duplicated local constants.

## Payload contract
The canonical `Studio -> Neurochip` handoff uses the versioned
`import_network_handoff` query parameter and includes:

- `handoff_version`
- `source`
- `network`
- `target_id`
- `target_label`
- `destination_workspace`
- `readiness_summary`

`import_network` remains a legacy compatibility path only. New callers must use
the versioned handoff.

## Producer obligations
- `neurocnl` must emit `target_id`, `target_label`, and
  `destination_workspace` from the canonical mapping above.
- Producer code must not invent additional destination workspaces for the
  versioned Studio handoff without updating this ADR and the consumer tests in
  the same change.

## Consumer obligations
- `Neurochip` must treat `target_id` as the stronger contract key.
- If a versioned handoff provides a known `target_id`, `Neurochip` must open
  the canonical workspace mapped to that target even if the route or
  `destination_workspace` disagrees.
- If `target_id` is absent but `destination_workspace` maps to one of the
  canonical target workspaces, `Neurochip` may recover the corresponding target
  context.
- `Neurochip` may still expose an explicit `Change Target` action after import,
  but it must not treat target selection as unresolved on first load.

## Consequences
- **Positive:** Phase 1 now has one authoritative, testable contract document.
- **Positive:** Producer and consumer both have a clear rule for target/workspace
  normalization.
- **Positive:** Module docs can link to one contract instead of repeating local
  assumptions.
- **Negative:** The mapping still exists in code on both sides until a shared
  typed contract surface is introduced.
- **Follow-up:** Replace duplicated Dart constants with a shared contract source
  and define the removal trigger for legacy `import_network`.
