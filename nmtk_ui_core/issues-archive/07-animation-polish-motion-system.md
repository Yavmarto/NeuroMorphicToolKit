# Animation Polish — More Expressive, Cohesive, and Fun Motion

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `nmtk_ui_core/issues/03-shell-chrome-overhaul.md`

## Can run in parallel with

- `nmtk_ui_core/issues/05-validation-ux-improvements.md`
- `nmtk_ui_core/issues/04-loading-screen-backend-readiness.md`

## Write scope

- `nmtk_ui_core/lib/**`
- `nmtk_ui_core/test/**`

## Background

Current animations are functional but feel generic and flat. The ask is to make the UI feel
more **alive, expressive, and enjoyable** — not gratuitous, but with motion that gives feedback
and personality. Think: VS Code's smooth tab transitions, Linear's spring-animated sidebar,
Vercel's dashboard pulse effects.

## Tasks

### Motion system tokens
- Define a motion token set in `shell_tokens.dart` or a new `motion_tokens.dart`:
  - Duration scale: `durationFast` (120 ms), `durationBase` (220 ms), `durationSlow` (350 ms).
  - Easing curves: `easeEnter` (`Curves.easeOut`), `easeExit` (`Curves.easeIn`),
    `easeStandard` (`Curves.easeInOut`), `easeSpring` (a spring curve for "pop" moments).
  - All existing animations must be updated to use tokens rather than ad-hoc durations.

### Navigation transitions
- Page/route transitions should use a shared-axis slide (horizontal for forward/back, vertical
  for up/down drill-ins) with `durationBase` and `easeStandard`.
- The back button appearance and disappearance (from issue `03`) should use a spring scale
  animation (`easeSpring`, 180 ms).

### Module card interactions
- Module cards in the launcher rail hover state: subtle lift (shadow increase + 1 dp translate
  Y) with `durationFast`.
- Selection: a filled highlight slides in behind the selected item (not a hard swap) — use
  `AnimatedContainer` or a `PositionedTransition`.

### Loading screen entrance / exit
- Loading screen entrance: logo scales from 0.8 → 1.0 with an `easeSpring` curve.
- Loading screen exit: fade + slight upward drift of the entire screen before routing.

### Micro-interactions
- Button press: subtle scale-down (0.96) on tap-down, spring-back on tap-up.
- Validation chip expand/collapse: height animated with `durationBase`, content fades in with
  a 40 ms delay after the container has grown.
- Play button state transitions (idle → running → done): use a `AnimatedSwitcher` with a
  rotating + fading transition between icon states.
- Status indicator dots (healthy/degraded/failed): pulse animation on `degraded` and `failed`
  states using a looping `Curves.easeInOut` scale oscillation.

## Done when

- All motion durations and curves come from `motion_tokens.dart` (no hardcoded `Duration()`
  literals in animation widgets).
- Route transitions use shared-axis slide.
- Play button, module cards, validation chip, and loading screen all use the new motion tokens
  and have the described animation behaviours.
- `cd nmtk_ui_core && flutter test` passes (animation smoke tests).

## Validation

- `cd nmtk_ui_core && flutter test`
- Manual: navigate between all main routes and confirm shared-axis transitions.
- Manual: tap a module card and confirm lift + selection slide effect.
- Manual: toggle play button and confirm icon transition animation.
