# Launcher Modules Surface And Install Start Semantics

## Owner

- `F3` Full-workspace local agent

## Depends on

- `issues/01-suite-design-contract-and-module-brief.md`
- `nmtk_ui_core/issues/02-modules-surface-cards-and-utility-panel-patterns.md`

## Can run in parallel with

- `issues/03-launcher-workspace-host-and-persistent-sessions.md`

## Write scope

- `nmtk/**`
- `scripts/**` and root tests that cover launcher semantics

## Tasks

- Merge dashboard and catalog semantics into one stable `Modules` surface.
- Split presence, activity, and health state in the UI model.
- Stop treating `Start` as silent repair or reinstall.
- Surface `repair required`, `preflight failed`, and `degraded optional capability` distinctly.

## Done when

- Cards stay visible during install, repair, and start transitions.
- `Start` means start.
- Repair reasons and launcher provenance are visible and typed.

## Validation

- `bash scripts/run_launcher_guardrails.sh`
- `bash scripts/run_launcher_guardrails.sh --with-integration`
- `python3 scripts/launcher_control_service.py --doctor --json`
