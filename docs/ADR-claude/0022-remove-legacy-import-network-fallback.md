# ADR 0022: Remove Legacy `import_network` Fallback

## Status
Accepted

## Supersedes
- The legacy compatibility note in `docs/ADR-claude/0021-studio-neurochip-handoff-contract.md`

## Context
ADR 0021 established `import_network_handoff` as the canonical
`Studio -> Neurochip` query parameter and kept legacy `import_network` only as
temporary compatibility while callers migrated.

As of 2026-04-28, the repo no longer contains any active producer that emits
`import_network` for the `Studio -> Neurochip` path:

- `neurocnl` emits only `import_network_handoff`
- `Neurochip` already consumes the versioned handoff contract
- remaining `import_network` references are test fixtures or generic shell deep
  link pass-through coverage, not active Studio handoff producers

That satisfies the original removal trigger: all known callers have migrated to
the versioned handoff contract.

## Decision
The deprecation window for legacy `import_network` closes on 2026-04-28.

`Neurochip/frontend/lib/services/import_network_payload.dart` must no longer
parse `import_network` for the `Studio -> Neurochip` handoff. Only
`import_network_handoff` is supported for imported-network bootstrapping.

The shared target mapping also moves out of duplicated module-local constants
and into the typed `nmtk_module_contracts` package so producer and consumer read
the same contract surface.

## Consequences
- **Positive:** the handoff path has one canonical entrypoint and one typed
  target/workspace contract source.
- **Positive:** future target additions require one contract update instead of
  parallel constant edits in `neurocnl` and `Neurochip`.
- **Positive:** the consumer contract is easier to reason about because legacy
  fallback rules no longer mask stale callers.
- **Negative:** any external caller still using `import_network` must migrate to
  `import_network_handoff` before this repo version is adopted.

## Status Update (2026-07-16 audit)

The cited file `Neurochip/frontend/lib/services/import_network_payload.dart` no longer exists — `Neurochip/frontend` is now an empty stub (only `neurochip.iml` remains) since the ADR-0019 Flutter feature-package migration superseded it.

The underlying decision (no bare `import_network` fallback) still holds. The versioned-handoff parsing logic now lives in `nmtk/packages/neurochip_feature/lib/src/neurochip_shell_adapter.dart` (around line 68, the `import_network_handoff` query-parameter check). Readers should look there instead of the deleted path.
