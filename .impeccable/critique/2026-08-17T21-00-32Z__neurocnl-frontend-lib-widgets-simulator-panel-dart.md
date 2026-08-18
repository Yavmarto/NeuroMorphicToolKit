---
timestamp: 2026-08-17T21-00-32Z
slug: neurocnl-frontend-lib-widgets-simulator-panel-dart
---
Method: dual-agent (A: design review · B: mechanical audit). Detector substitution: this project has no web DOM (Flutter/Dart macOS app) — the toolkit's browser-injection detector is HTML/CSS-pattern based and gives no signal on Dart source, so Assessment B ran a literal line-by-line audit against this repo's own CODING_STYLE_GUIDE.md instead.

Target: `_DeployRunStatus`/`_DeployRunStatusPane`/`_DeployRunIdleView`/`_DeployRunRunningView`/`_DeployRunDoneView` and their wiring in `neurocnl/frontend/lib/widgets/simulator_panel.dart` (~line 1150-1460).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Idle/Running/Done are distinct; running shows no progress toward completion (no %, no timestep count) |
| 2 | Match System / Real World | 3 | Plain domain terms, no jargon |
| 3 | User Control and Freedom | 2 | No cancel affordance while running; no link back to the Setup pane driving it |
| 4 | Consistency and Standards | 1 | Breaks its own file's conventions — checkmark used for Failed too; centered void next to the compact, left-aligned banner above it |
| 5 | Error Prevention | n/a | Read-only status view, nothing to input |
| 6 | Recognition Rather Than Recall | 3 | State always visible |
| 7 | Flexibility and Efficiency | 1 | "Review step" pointer is static prose, not a shortcut |
| 8 | Aesthetic and Minimalist Design | 1 | Confuses minimalism with emptiness — 3 lines of unstyled text in a 520-600px pane |
| 9 | Error Recovery | 1 | Same checkmark glyph for Completed/Failed/Caveats — color-only distinction |
| 10 | Help and Documentation | 2 | Points at Review but gives no way to get there |
| **Total** | | **17/36** | Bottom third — "unfinished," not "polished" |

## Design Specificity Verdict

Not authored for this product. `_DeployRunIdleView` is a near-verbatim clone of the file's pre-existing `_EmptyResultsPlaceholder` — same icon, same size, same `ZETA-MIGRATION-EXEMPT` comment, only the string changed. The done state — the only one with real content — reads as a generic "success toast" template: centered icon, label, key/value list. Nothing anchors it to this being a spiking-network simulator run.

The mechanical audit backs this up with a concrete cause: the status pill and the key/value rows were both **hand-rolled from scratch** instead of reusing widgets this exact app already ships (`NmtkStatusBadge`, `NmtkKeyValueRow` in `nmtk_ui_core`). That's *why* it feels generic — it isn't drawing on this app's own visual language, it's improvising a new one inline.

## Overall Impression

The information is right; the construction is not. Every number the user actually wants (backend, duration, spike count) is typeset identically to a disclaimer caption, wrapped in `Center` inside a pane sized for the old charts, so three lines of text float in a void — which is exactly what "exceptionally horrible" describes. Underneath that, the code reinvents two shared widgets, ships a factually false "no Zeta equivalent" comment next to an icon that does have one, and mutates state outside `setState` in two of three transition branches (works today only by an undocumented coincidence).

## What's Working

- Status **colors** are correct — `NmtkShellTokens.healthyColor/errorColor/warningColor`, no hardcoded values, matches the style guide's semantics table exactly.
- The state model is clean, exhaustive Dart: a sealed `_DeployRunStatus` with `idle`/`running`/`done` factories, not a loose set of nullable flags.
- Copy is honest and unpretentious ("Ran with caveats," "Press Run to simulate this network here") — no marketing voice creeping into a status readout.

## Priority Issues

**[P0] The status icon lies for 2 of 3 outcomes.** `_DeployRunDoneView` computes the right color per outcome but renders one fixed `ZetaIcons.check_circle` regardless — a checkmark shows even when the label says "Failed" or "Ran with caveats," just tinted red or amber. A user scanning for a checkmark reads "confirmed" before they read the color. The file already has the correct three-icon pattern elsewhere (`check_circle_outline`/`warning_outline`/`cancel_outline` in `_PreflightBadge`) — switch on the same three icons here instead of one glyph.
*Fix:* icon = `switch (result.status) { completed => check_circle, failed => cancel_outline, _ => warning_outline }`.

**[P0] Two shared widgets got reinvented instead of reused.** The status pill is a hand-rolled `Row(Icon, SizedBox, Text)` when `nmtk_ui_core` already ships `NmtkStatusBadge` (label + `NmtkTone` → themed pill, correct radius/spacing built in). The `_kv` label/value helper is a third near-duplicate of a pattern the same file already has twice (`_ReportTab._kv`), when `NmtkKeyValueRow` already exists and additionally routes its value color through the theme correctly. This is the direct, mechanical explanation for the "not authored for this product" verdict above — it's not reusing the app's own components.
*Fix:* map `result.status` → `NmtkTone`, render `NmtkStatusBadge(label:, tone:)`; replace both `_kv` bodies with `NmtkKeyValueRow`.

**[P1] `Center` everywhere is what produces the void.** Idle, Running, and Done all wrap their content in `Center` inside a fixed 520-600px `Expanded` region sitting directly under the compact, left-aligned `_PreflightResultWidget` banner. Dense-then-empty is the actual visual complaint. The file has the right precedent two hundred lines up: `_SimulatorErrorDetails` gives its content an actual tinted surface (`Container(color: tokens.errorColor.withValues(alpha: 0.08))`). Give the Done card the same treatment — a real surface, top-anchored, not floating dead-center in blank space.

**[P1] `ref.listen` mutates state without `setState` in 2 of 3 branches.** `_onRunStateChanged` sets `_runStartedAt`/`_completedAt` directly on lines that don't call `setState` — only the `Timer.periodic` tick does. It renders correctly today only because `build()` also calls `ref.watch` on the same provider and happens to rebuild on the same transition. That's an implicit, undocumented coupling and the literal anti-pattern this repo's own style guide names by name. *Fix:* wrap all three branches' field writes in `setState(() { ... })`.

**[P1] No hierarchy on the numbers that matter.** Backend, duration, and spike count are the actual answer to "what happened," typeset at the same `bodySmall` weight as the surrounding captions, differentiated only by bold. Step the values up to `titleSmall`/`titleMedium`.

**[P2] Idle and Running are content-free.** Neither shows the backend name this pane is already scoped to (`widget.backend`) or anything about what's about to run — both were lifted near-verbatim from the pre-existing generic placeholder. Since this pane is per-backend, say which backend.

## Minor Observations

- False exemption comment: `Icon(Icons.bolt_outlined, ...) // ZETA-MIGRATION-EXEMPT: no Zeta equivalent` — `ZetaIcons.flash_on` exists and this file already uses `ZetaIcons.analytics`/`.check_circle` two lines away. Delete the comment, use the real icon.
- `CircularProgressIndicator` (Material, no exemption comment) — probably legitimate (Zeta's progress circle is determinate-only), but undocumented, unlike this file's own convention of commenting every exemption.
- Elapsed-time formatting (`_formatElapsed`) duplicates logic already in `akida_execution_pane.dart` — with a visible inconsistency: Akida zero-pads seconds ("5m 03s"), this one doesn't ("5m 3s"). Same concept, two outputs, in the same module.
- Several spacings sit off the mandated 8px grid: `SizedBox(width: 20, height: 20)`, two `SizedBox(height: 12)`s, `width: 6`, `vertical: 2`.
- `BoxConstraints(maxWidth: 260)` is a bare magic number with no name and no attempt to use the pane's actual width — the pane is roughly half the screen; nothing here adapts to that.
- Three view classes (Idle/Running/Done) are near-duplicate `Center > Column` trees with inconsistent outer padding/width between them — worth collapsing into one parameterized card so switching states doesn't visibly jump in size.

## Persona Red Flags

**Alex (power user, running many targets back-to-back):** no way to jump to Review from here, no shortcut, no copy-to-clipboard on the numbers — every completed run is a dead end that requires manually clicking to the next step.

**Jordan (new to the tool):** a green checkmark centered in an otherwise-empty half-screen pane reads like an unfinished feature, not a trustworthy result — the emptiness itself undermines confidence that this really ran their network on `snntorch_sim`, independent of whether the numbers are correct.

## Questions to Consider

- The Setup pane already has Ready/Exact status chips and Run/Clear — does Deploy need a second, competing "Completed" state at all, or could one line fold into that existing chip row and free this whole pane for something the user can't get anywhere else?
- That pane's fixed height (520-600px) was sized for the old raster charts. Was centering three lines of text in it a decision, or just what happens when nobody revisits a height after the content that justified it moves away?

## Run Notes

Target: `simulator_panel.dart` (slug `neurocnl-frontend-lib-widgets-simulator-panel-dart`). Assessments A and B ran as two isolated parallel sub-agents, no shared context. No `ignore.md` present. CLI detector (`detect.mjs`) ran but is web/CSS-pattern-based and returns no real signal on Dart source — treated as N/A, not as a clean bill of health; Assessment B's manual audit is the substitute. No browser visualization — this is a native macOS desktop app, not a web surface, so live-server/injection don't apply. No PRODUCT.md/DESIGN.md in this repo — `$impeccable init` would let future critiques score against a written product brief instead of inferring one; not required to act on now.
