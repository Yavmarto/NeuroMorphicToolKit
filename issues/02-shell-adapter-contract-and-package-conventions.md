# Shell Adapter Contract And Package Conventions

## Owner

- `F4` Full-workspace local agent

## Depends on

- `issues/01-suite-design-contract-and-module-brief.md`

## Unlocks

- Every module-local migration issue in this backlog

## Write scope

- Root docs for adapter contracts and integration examples
- Cross-module package naming and restoration conventions

## Tasks

- Define the adapter interface shape for native desktop module entrypoints.
- Define deep-link targets, restoration hooks, and capability/degradation reporting contracts.
- Define package naming conventions such as `<module>_shell_adapter`.
- Publish one concrete example packet that a single-repo cloud agent can execute safely.

## Done when

- Module lanes can consume one stable adapter contract instead of inventing local variants.
- Deep links, restoration, and degraded capability semantics are specified once at the root.

## Validation

- Contract review against `nmtk`, `nmtk_ui_core`, `neurocli`, and the module subplan doc
