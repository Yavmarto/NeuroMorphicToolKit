# Modules Surface Cards And Utility Panel Patterns

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`

## Unlocks

- `issues/04-launcher-modules-surface-and-install-start-semantics.md`
- Data-heavy module issue `01` files

## Write scope

- `nmtk_ui_core/lib/**`
- `nmtk_ui_core/test/**`

## Tasks

- Build stable module-card patterns for `Installed`, `Available`, and `Needs Attention`.
- Add utility-panel primitives for logs, diagnostics, background jobs, and degraded-state detail.
- Publish compact and desktop variants instead of embedding all behavior in one widget.
- Provide reusable panel, chip, and status patterns for report-heavy and hardware-heavy modules.

## Done when

- The launcher and module repos share the same card and utility-panel vocabulary.
- Module lanes can use shared status and panel patterns instead of custom shells.

## Validation

- `cd nmtk_ui_core && flutter test`
