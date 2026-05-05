# Shell Tokens Top Bars And Status Primitives

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `issues/01-suite-design-contract-and-module-brief.md`

## Unlocks

- All module issue `01` files

## Write scope

- `nmtk_ui_core/lib/**`
- `nmtk_ui_core/test/**`

## Tasks

- Move shell token authority under `DESIGN.md`.
- Implement the top app bar, workspace switcher bar, shell badges, and shell readiness states.
- Add mode-aware tokens for command, studio, and instrument use without fragmenting the suite identity.
- Replace one-off sidebar-era assumptions with desktop shell primitives.

## Done when

- Module repos can consume shared top-bar, status, and token primitives.
- Shared shell chrome no longer requires local theme forks.

## Validation

- `cd nmtk_ui_core && flutter test`
