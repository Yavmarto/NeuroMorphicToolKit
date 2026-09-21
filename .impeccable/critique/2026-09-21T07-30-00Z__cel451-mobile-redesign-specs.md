# Impeccable design audit — CEL-451 mobile redesign specs

**Target:** `nmtk/neuro_toolkit/lib/ui_core/docs/mobile_redesign_specs_cel451.md`  
**Design system:** Zeta (`zeta_flutter`, `themeId: "nmtk"`) + `NmtkShellTokens`  
**Date:** 2026-09-21

## P0 — Token compliance

| Rule | Verdict | Evidence |
|---|---|---|
| Border radii | PASS | Spec references only `radiusSm` (12), `radiusMd` (16), `radiusLg` (22), `dialogShape` (28), `radiusChip` |
| Status colours | PASS | No inline hex; uses `healthyColor`, `runningColor`, `errorColor`, etc. |
| Shell mode | PASS | `NmtkShellMode.studio` for neurocnl; `command` for Neurobench |
| Typography | PASS | Space Grotesk scale from `.impeccable/design.json` |
| Spacing | PASS | `sectionGap` (16) and `compactGap` (8) only |

## P1 — Mobile modal standard alignment

| Rule | Verdict | Notes |
|---|---|---|
| 1. No fixed desktop width | PASS | Sheets below 840; `min(screenWidth - 2*sectionGap, 560)` for dialogs |
| 2. Content scrolls | PASS | Required on all sheet bodies |
| 3. SafeArea + keyboard | PASS | Spec mandates `viewInsets.bottom` on text-field sheets |
| 4. Tap targets ≥ 44 | FIX | PlayStopButton, handwriting clear, assistant close called out for engineers |
| 5. Stack 3+ actions | PASS | Hardware form footer + setup action rows |
| 6. Design tokens | PASS | No ad-hoc padding |
| 7. Viewport height cap | PASS | 82% assistant sheet, 80% connect palette, 75% compare panes |

## Breakpoint audit

- Screen compact: 840 px (`NmtkShellTokens.compactBreakpoint`) — canonical
- Deploy inline header: 600 px — documented exception with rationale
- Pane actions: 420 px — documented pane-local threshold

No invented colours, radii, or spacing outside the token set.

**Result: APPROVED for engineer handoff** (implementation fixes for tap targets tracked in spec §6).
