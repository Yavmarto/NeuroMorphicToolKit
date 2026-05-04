# Module-Facing Desktop Shell Brief

## Purpose

This brief is the downstream handoff for module teams and repo-limited agents
working on the desktop migration.

Use this document when you need the suite-shell contract without reading the
full redesign plans.

## Canonical sources

- `DESIGN.md`: authoritative shell contract
- `docs/2026-04-23-desktop-ui-modernization-and-module-embedding-plan.md`:
  shell architecture and migration direction
- `docs/2026-04-24-desktop-module-migration-subplans.md`: module-lane
  migration guidance

If these docs conflict, `DESIGN.md` wins for shell behavior and status language.

## Shell contract you must target

- The shell is mission control. Modules are specialized workbenches inside one
  desktop suite.
- Primary app navigation lives in the top app bar.
- Open-module switching lives in a separate top workspace bar.
- The workspace canvas is the dominant surface.
- The utility panel is contextual support chrome for logs, diagnostics,
  background jobs, contextual inspectors, degraded-state detail, and recovery
  actions. It is not primary navigation.
- Workspace sessions stay alive until explicitly closed or intentionally
  restarted.
- Switching between already-open modules should feel like warm-session
  switching, not startup.

## Mode assignments

- `command`: shell chrome and `Neurohub`
- `studio`: `neurocnl` and `Neurosim`
- `instrument`: `Neurosense`, `Neurochip`, `Neurobench`, and
  `Neuro-Dream-Hand`

These modes are visual and behavioral variants within one suite identity. Do
not create module-local shell brands.

## Status and readiness language

Required shell-visible readiness states:

- `opening`
- `warming up`
- `ready`
- `degraded`
- `error`

Allowed module-specific substates include:

- `probing hardware`
- `restoring session`
- `indexing assets`
- `loading model`

Required wording distinctions:

- `preflight failed`: required dependency or startup condition is blocking use
- `degraded optional capability`: optional runtime, hardware path, or advanced
  feature is unavailable, but the module or suite can still run

Do not collapse those two cases into one generic startup error.

## Desktop-first and mobile-portable rules

- Keep business logic, capability reporting, and readiness/state contracts out
  of desktop widget trees where practical.
- Treat mobile as a future composition target, not the primary shell
  optimization target.
- Hardware-heavy workflows may degrade on mobile to monitoring, review, setup,
  or companion flows instead of full local control.
- Dense authoring, deployment, and live instrument surfaces may remain
  desktop-primary.

## What module teams own

- Module-local feature surfaces
- Module application services and typed contracts
- Shell adapter entrypoints, deep links, restoration hooks, and
  capability/degradation reporting
- Module-specific use of shared suite primitives from `nmtk_ui_core`

## What module teams should not redefine locally

- Top app bar structure
- Top workspace bar responsibilities
- Shell readiness vocabulary
- `preflight failed` versus `degraded optional capability` wording
- Utility-panel purpose
- Mode assignments
