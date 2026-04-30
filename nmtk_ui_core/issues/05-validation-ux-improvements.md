# Validation UX Improvements — Friendly Errors, Dropdown, Contrast

## Owner

- `M2` Single-repo cloud agent or local module owner

## Depends on

- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`

## Can run in parallel with

- `nmtk_ui_core/issues/04-loading-screen-backend-readiness.md`
- `neurocnl/issues/13-neurostudio-cnl-canvas-live-sync.md`

## Write scope

- `nmtk_ui_core/lib/widgets/**`
- `nmtk_ui_core/test/**`
- `neurocnl/frontend/lib/widgets/**` (CNL-specific validation surfaces)

## Background

The current validation panel has several UX problems reported by users:
1. **Green text on a green background** — error/success text colour is not legible; token
   contrast ratio fails WCAG AA.
2. **All errors shown at once with no affordance to triage** — a long error list is
   overwhelming; users want to see a summary and expand on demand.
3. **Errors are shown as raw developer messages** (e.g. `ParseError: unexpected token '@' at
   line 4 col 7`) instead of friendly, actionable language.
4. **Default state hides errors** — the validation panel collapses to nothing when there are
   no errors, but shows nothing useful when there is one either.

## Tasks

### Fix colour contrast
- Audit all validation-related colour tokens in `shell_tokens.dart` and `app_theme.dart`.
- Replace any success/error text colours that fail WCAG AA (4.5:1 ratio) against their
  background; use `ColorScheme.onErrorContainer` / `onPrimary` patterns correctly.
- Add a golden test (or accessibility test) that asserts contrast ratio for the validation
  chip widget.

### Change to dropdown / expandable panel
- Replace the flat error list with an expandable summary chip:
  - **Default (collapsed)**: shows a pill with an icon and count, e.g. `✗ 3 errors` (red) or
    `✓ No errors` (green with sufficient contrast on the background colour).
  - **Expanded (tapped/clicked)**: drops down to reveal the full error list with line
    references.
- The "show all" expanded state scrolls independently so it does not push content off screen.
- Keyboard: `Escape` collapses the panel; `F8` / `Cmd+Shift+M` cycles through errors (VS Code
  convention).

### Human-friendly error messages
- In the validation result mapper (in the neurocnl frontend or a shared validation formatter),
  translate raw `ParseError` / `LoweringError` / invariant messages into sentences:
  - Before: `ParseError: unexpected token '@' at line 4 col 7`
  - After: `Line 4: Unexpected character "@". Did you mean to start a comment with "#"?`
- Provide at least one suggestion string per error class (heuristic is fine; need not be
  exhaustive).
- Unknown error types fall back to the raw message in a `monospace` style so developers can
  still read them.

### Standard show-errors default
- When errors exist, the validation panel defaults to **showing** the error count chip (not
  hidden/collapsed to nothing).
- When there are no errors, show a small `✓ Valid` chip that fades out after 3 s so it does
  not permanently occupy space.

## Done when

- All validation text passes WCAG AA contrast against its container colour.
- The panel is collapsed by default and expands on tap/click to reveal the full list.
- At least the 10 most common neurocnl error types have human-friendly messages.
- A `✓ Valid` chip appears briefly after a clean validation pass.
- `cd nmtk_ui_core && flutter test` passes including the new contrast and expand/collapse tests.

## Validation

- `cd nmtk_ui_core && flutter test`
- `cd neurocnl/frontend && flutter test`
- Manual: introduce a CNL syntax error → chip shows error count → tap → list expands → error
  is human readable.
- Manual: fix the error → `✓ Valid` chip appears → fades after 3 s.
