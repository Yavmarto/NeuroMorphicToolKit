# Suite Design Contract And Module Brief

## Owner

- `F1` Full-workspace local agent

## Depends on

- None

## Can overlap with

- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`

## Write scope

- Root `DESIGN.md`
- Root migration docs under `docs/`
- Module-facing design brief material used by later issue packets

## Tasks

- Finalize the mission-control, studio, and instrument mode guidance.
- Freeze the top app bar, top workspace bar, utility panel, and desktop-first/mobile-portable rules.
- Define shell-visible readiness states, degraded states, and status language.
- Publish a short module-facing brief that downstream repo agents can consume without reinterpreting the whole plan.

## Done when

- `DESIGN.md` is implementation-ready.
- Module teams have a stable design brief.
- The design language for shared shell chrome is no longer an open question.

## Validation

- Design review across `DESIGN.md`, `docs/2026-04-23-desktop-ui-modernization-and-module-embedding-plan.md`, and `docs/2026-04-24-desktop-module-migration-subplans.md`
