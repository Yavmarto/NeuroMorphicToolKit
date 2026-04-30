# Launcher Workspace Host And Persistent Sessions

## Owner

- `F3` Full-workspace local agent

## Depends on

- `issues/01-suite-design-contract-and-module-brief.md`
- `issues/02-shell-adapter-contract-and-package-conventions.md`
- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`

## Can run in parallel with

- `issues/04-launcher-modules-surface-and-install-start-semantics.md`

## Write scope

- `nmtk/**`
- Root launcher verification surfaces in `scripts/` and `tests/` when needed

## Tasks

- Replace route-per-module with a stable `/workspace` host.
- Remove left-primary-nav assumptions and adopt the top-bar shell layout.
- Keep opened module surfaces alive across switches.
- Add adapter loading, lifecycle, and restoration hooks for mixed native and embedded coexistence.

## Done when

- The workspace host preserves warm sessions.
- Module switching no longer rebuilds the shell like a page navigation flow.
- Native module entrypoints have an integration surface in the launcher.

## Validation

- `bash scripts/run_launcher_guardrails.sh`
- `python3 scripts/launcher_control_service.py --doctor --json`
