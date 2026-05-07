# Impeccable Audit - 2026-05-07

I ran an `impeccable audit` on the launcher shell and shared UI layer, scoped to `/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit` and `/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core`. No fixes yet, just the audit.

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|---|---:|---|
| 1 | Accessibility | 2/4 | Recovery UI can overflow badly enough to hide the retry action |
| 2 | Performance | 3/4 | No obvious heavy-motion/layout-thrash patterns |
| 3 | Responsive Design | 2/4 | Some shared widgets still assume roomy widths |
| 4 | Theming | 2/4 | Token system exists, but many shared widgets bypass it |
| 5 | Anti-Patterns | 3/4 | Mostly intentional, not AI-slop, but visually inconsistent in spots |
| **Total** |  | **12/20** | **Acceptable** |

## Anti-Patterns Verdict

Pass, mostly. This does not read like generic AI-generated SaaS chrome. The shell has a real point of view. The weaker part is not "AI slop", it is token drift: some shared widgets still fall back to raw Material colors and ad hoc status palettes, which makes the system feel less unified than the design docs promise.

## Executive Summary

- Audit Health Score: **12/20** (`Acceptable`)
- Test verification:
  - `nmtk_ui_core`: `rtk flutter test` failed with a real overflow in the readiness state view
  - `nmtk/neuro_toolkit`: `rtk flutter test` also failed, including `tool_view_test.dart` nav fallback coverage
- Top issues:
  1. Broken degraded/error readiness card can hide recovery controls
  2. Shared widgets bypass semantic/theme tokens in several places
  3. Some interactive targets are below WCAG touch size minimum
  4. Data-heavy widgets are not adapted for narrow layouts

## Detailed Findings

- **[P1] Readiness/recovery card can overflow and lose its action**
  - Location: `nmtk_ui_core/lib/widgets/shell_readiness_state_view.dart:62`, `nmtk_ui_core/test/shell_primitives_test.dart:168`
  - Category: Accessibility / Responsive
  - Impact: In degraded startup states, the recovery affordance can disappear, which is exactly when the user most needs it.
  - WCAG/Standard: `1.4.10 Reflow`, `2.1.1 Keyboard`
  - Recommendation: Stack the action below the message at constrained widths, or make the action row wrap instead of forcing a single horizontal row.
  - Suggested command: `$impeccable adapt`

- **[P1] Theme/token drift is systemic across shared UI**
  - Location: `nmtk_ui_core/lib/widgets/progress_card.dart:37`, `nmtk_ui_core/lib/widgets/workflow_card.dart:57`, `nmtk_ui_core/lib/widgets/quantization_table.dart:93`, `nmtk_ui_core/lib/models/akida_deployment_model.dart:286`, `nmtk_ui_core/lib/models/pynq_deployment_model.dart:70`
  - Category: Theming
  - Impact: Dark mode, high contrast, and semantic status mapping can diverge across modules even when the shell is themed correctly.
  - Recommendation: Route status colors through `NmtkShellTokens` or a single semantic palette API instead of `Colors.*` and per-model literals.
  - Suggested command: `$impeccable harden`

- **[P1] Launcher shell test coverage is already red**
  - Location: `nmtk/neuro_toolkit/test/tool_view_test.dart:525`
  - Category: Responsive / Technical quality
  - Impact: The suite shell currently has failing UI regression coverage, including launcher-nav fallback behavior. That lowers confidence in further visual work.
  - Recommendation: Stabilize the failing shell tests before piling on UI changes.
  - Suggested command: `$impeccable harden`

- **[P2] Module close affordance is under minimum touch target size**
  - Location: `nmtk/neuro_toolkit/lib/widgets/module_tab_bar.dart:117`
  - Category: Accessibility / Responsive
  - Impact: The close button is constrained to `18x18`, which is too small for touch and uncomfortable even on desktop at scale.
  - WCAG/Standard: `2.5.8 Target Size (Minimum)` in WCAG 2.2
  - Recommendation: Keep the icon small if you like, but give the button a `44x44` tappable box.
  - Suggested command: `$impeccable adapt`

- **[P2] Quantization table is desktop-biased**
  - Location: `nmtk_ui_core/lib/widgets/quantization_table.dart:22`
  - Category: Responsive
  - Impact: Bare `DataTable` plus fixed spacing is likely to overflow on compact widths and larger text scales.
  - WCAG/Standard: `1.4.10 Reflow`
  - Recommendation: Wrap in horizontal scroll or switch to a stacked mobile presentation below a breakpoint.
  - Suggested command: `$impeccable adapt`

- **[P3] Theme layers are thoughtful, but not yet fully harmonized**
  - Location: `nmtk_ui_core/lib/app_theme.dart:678`, `nmtk_ui_core/lib/shad_theme.dart:97`
  - Category: Anti-Pattern / Theming
  - Impact: The system has good bones, but multiple palette sources make it easy for future surfaces to drift.
  - Recommendation: Document one source of truth for semantic colors across Material, Shad, and shell tokens.
  - Suggested command: `$impeccable document`

## Patterns & Systemic Issues

- Hard-coded status colors appear in shared widgets and models instead of one semantic source.
- Responsive intent exists in the shell, but some content widgets still assume wide layouts.
- Tests are already catching real UI regressions, which is good, but they are not green right now.

## Positive Findings

- The shell register is strong and specific. It does not feel like generic SaaS chrome.
- Shared shell primitives already include good semantic hooks, especially in the workspace switcher and top app bar.
- Motion/perf discipline looks solid. I did not find blur-heavy, shadow-heavy, or layout-thrashing UI patterns in the audited surfaces.

## Recommended Actions

1. **[P1] `$impeccable adapt`**: Fix the readiness/recovery card layout so degraded and error states always keep the action reachable.
2. **[P1] `$impeccable harden`**: Unify semantic/status color usage and clean up the red launcher/shared-UI test failures.
3. **[P2] `$impeccable adapt`**: Bring module tabs and data tables up to mobile and text-scale-safe behavior.
4. **[P3] `$impeccable document`**: Lock down the palette/token source of truth for Material, Shad, and shell layers.
5. **[P2] `$impeccable polish`**: Final consistency pass after the structural fixes land.

You can ask me to run these one at a time, all at once, or in any order you prefer.

Re-run `$impeccable audit` after fixes to see your score improve.
