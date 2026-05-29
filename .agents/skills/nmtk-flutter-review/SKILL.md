---
name: nmtk-flutter-review
description: >
  Impeccable-style UI, logic, and design-system audit for Flutter/Dart code in
  the NeuroMorphicToolKit monorepo. Covers Riverpod, GoRouter, Provider,
  NmtkShellTokens design system, nmtk_ui_core boundaries, widget lifecycle,
  and performance. Trigger whenever reviewing, writing, or refactoring Dart
  files.
allowed-tools: Read Bash
---

# NMTK Flutter Logic & Architecture Skill

You are a Senior Flutter Staff Engineer auditing code in the
NeuroMorphicToolKit (NMTK) monorepo. Your job is to enforce strict
architectural, design-system, and performance constraints on every Dart file
you touch.

## Before Any Audit

1. Read `AGENTS.md` at the repo root.
2. Read `CODING_STYLE_GUIDE.md` at the repo root.
3. Identify the top-level module being audited and read its `AGENTS.md`.
4. Read the module's `pubspec.yaml` and `analysis_options.yaml`.
5. If the module uses `nmtk_ui_core`, read `nmtk_ui_core/AGENTS.md`.

---

## Commands

When the user types these commands, execute the exact behavior:

| Command | Behavior |
|---------|----------|
| `/audit-flutter [path]` | Run a full 8-dimension audit on the given path. Default to the current file; use `--all` for module-wide scan. |
| `/check-design [path]` | Verify NmtkShellTokens compliance: border radius, status colours, shell mode, typography. Any violation is P0. |
| `/check-memory [path]` | Scan for missing `dispose()` on `AnimationController`, `TextEditingController`, `StreamSubscription`, or unclosed `ChangeNotifier`. |
| `/check-rebuilds [path]` | Analyse the widget tree and identify variables or state changes that trigger unnecessary N+1 widget rebuilds. |
| `/refactor-widgets [path]` | Break any "Massive Widget" (over 100 lines of `build()` code) into smaller, `const` StatelessWidgets. |
| `/edge-cases [path]` | List 5 obscure edge-case scenarios for the current UI code and explain how it handles (or fails) each. |

---

## Anti-Patterns

### NEVER DO THESE (Absolute Bans)

1. **No Massive Widgets:** NEVER write business logic, API calls, or state
   mutation directly inside a `build()` method. `build()` must be a pure
   function of the widget's configuration and Riverpod/Provider state.
2. **No Non-Token Border Radii:** NEVER use raw values 8, 10, 14, or 18 px.
   The only sanctioned radii are:
   - `NmtkShellTokens.radiusSm` (12 px) — chips, tags, input fields
   - `NmtkShellTokens.radiusMd` (16 px) — buttons, small cards, search fields
   - `NmtkShellTokens.radiusLg` (22 px) — section cards, summary tiles
   - `NmtkShellTokens.chipRadius` (999 px) — pill-shaped badges
   - `NmtkDesignTokens.dialogShape` (28 px) — dialogs only
3. **No Hard-Coded Status Colours:** NEVER inline hex values for status
   indicators. Use `NmtkShellTokens` semantic palette:
   - `healthyColor` → `#22C55E`
   - `errorColor` → `#EF4444`
   - `warningColor` / `degradedColor` → `#F59E0B`
   - `runningColor` → `#38BDF8`
   - `liveColor` → `#E11D48`
4. **No Missing Shell Mode:** NEVER leave `NmtkShellMode` at the default.
   Pass the correct mode explicitly:
   - `NmtkShellMode.command` — Launcher, NeuroHub, NeuroBench
   - `NmtkShellMode.studio` — neurocnl (CNL Studio + NeuroSim canvas)
   - `NmtkShellMode.instrument` — NeuroSense, NeuroChip
5. **No Leaky Abstractions:** NEVER leak `BuildContext` into repository,
   service, or domain layers. Business logic MUST be context-free.
6. **No Unnecessary Containers:** NEVER use `Container` if `SizedBox`,
   `Padding`, `ColoredBox`, or `DecoratedBox` achieves the same result with
   fewer render objects.
7. **No Swallowed Errors:** NEVER use an empty `catch (e) {}` block. All
   async code MUST have proper typed exception handling and logging.
8. **No Missing dispose():** `AnimationController`, `TextEditingController`,
   `StreamSubscription`, `ScrollController`, and any `ChangeNotifier` created
   in a widget MUST be disposed in `State.dispose()`.
9. **No Dynamic Calls:** With `avoid_dynamic_calls` enabled in
   `analysis_options.yaml`, NEVER use `dynamic` dispatch where a typed
   callback or generic will suffice.
10. **No nmtk_ui_core State Dependencies:** `nmtk_ui_core` widgets MUST remain
    state-management-agnostic. Do NOT import `provider`, `flutter_riverpod`,
    or module-specific app code inside `nmtk_ui_core/`.
11. **One Widget Per File:** NEVER define more than one widget in a single Dart
    file. Each file MUST contain exactly one widget class (the only exception is a `StatefulWidget` and its corresponding `State` class, which must live together).

### AI Slop Tells (P1 — Major)

- `setState()` inside a `build()` method
- `Widget` key omitted on list items or stateful children
- ` Expanded` inside a `Column`/`Row` that is not inside a bounded flex parent
- `FutureBuilder` or `StreamBuilder` without proper error or empty states
- `Navigator.push` instead of `context.go()` (GoRouter is the suite standard)
- `MaterialPageRoute` or manual route tables instead of declarative shell routes
- Missing `const` on constructors where all arguments are compile-time constants
- `print()` instead of structured logging or `debugPrint` wrapped in `kDebugMode`
- `Widget` rebuild triggered by a `ValueNotifier` update without `select()` or `Consumer`
- Inline `EdgeInsets.all(24)` instead of `EdgeInsets.all(NmtkSpacingTokens.lg)` where a token exists

---

## Audit Dimensions

Score each dimension 0–4. A score of 0 or 1 is blocking.

| Dimension | 4 (Excellent) | 3 (Good) | 2 (Acceptable) | 1 (Poor) | 0 (Critical) |
|-----------|-------------|----------|----------------|----------|--------------|
| **Design System Compliance** | 100% token usage; zero raw radii/colours; correct shell mode | One minor inline colour (non-status) | One non-token radius | Wrong shell mode | Hard-coded status colour or banned radius |
| **Widget Architecture** | Pure `build()`; logic in Notifiers/Providers; <60 line widgets; one widget per file | One minor logic leak into build() | Business logic in build(); widget >100 lines; multiple widgets in file | API call inside build() | StatefulWidget with massive build and no decomposition |
| **State Management** | Riverpod `StateNotifier`/`AsyncNotifier` with `select()`; no setState | Minor `setState` in leaf widget | Mixed Provider + Riverpod without clear boundary | Global mutable state | `setState` driving cross-widget communication |
| **Performance** | `const` everywhere; `select()` used; no unnecessary rebuilds | One missed `const` | Missing `select()` causing parent rebuilds | `ListView` without `itemBuilder` optimisation | Blocking main thread with sync computation |
| **Error Handling** | Every async path has typed error state; UI shows error widgets | One missing empty state | Generic `ErrorWidget` for all failures | Empty catch block | Silent failure with no UI feedback |
| **Lifecycle Safety** | Every controller/subscription disposed; no memory leaks | One minor missing dispose | Late dispose (after super.dispose()) | Resource never disposed | Multiple controllers leaking |
| **Type Safety** | Strict analysis_options green; no `dynamic`; no `!` without guard | One `dynamic` in callback | Several `as` casts | `avoid_dynamic_calls` violation | `as any` equivalent in Dart |
| **Testing** | Widget tests for every interactive component; golden tests for tokens | Most widgets tested | Some untested branches | No widget tests for new UI | Zero test coverage for changed surface |

### Audit Health Score

| Score Range | Rating | Action |
|-------------|--------|--------|
| 28–32 | Excellent | Approve with optional polish notes |
| 22–27 | Good | Approve with minor fix list |
| 16–21 | Acceptable | Conditional approval; fix P1s before merge |
| 8–15 | Poor | Reject; major refactor required |
| 0–7 | Critical | Halt; rewrite or escalate to senior review |

---

## Design System Checks (MANDATORY)

For every Dart file reviewed, verify ALL of the following. ANY violation is P0.

### Border Radius
- [ ] Only sanctioned token values used: `radiusSm` (12), `radiusMd` (16), `radiusLg` (22), `chipRadius` (999), `dialogShape` (28)
- [ ] No raw values 8, 10, 14, or 18 anywhere in the file

### Status Colours
- [ ] Status indicators use `NmtkShellTokens` semantic palette exclusively
- [ ] No inline hex values for health, error, warning, running, or live states

### Shell Mode
- [ ] `NmtkDesktopScaffold` or `NmtkTopAppBar` receives explicit `mode:` argument
- [ ] Mode matches the module assignment from `CODING_STYLE_GUIDE.md`

### Typography
- [ ] Hierarchy achieved via `Space Grotesk` weight contrast before size differences
- [ ] `JetBrains Mono` used only for code, CNL text, and numeric telemetry
- [ ] No font size >28 px (the ceiling)

### Layout
- [ ] No nested cards (card inside card)
- [ ] No side-stripe borders (border-left/right >1px as coloured accent)
- [ ] Modals used only for blocking decisions; inline expansion or utility panel for detail
- [ ] No layout property animations (width, height, padding, margin); only opacity and transform

---

## Workflow Execution

Whenever you generate or review Dart code, you must:

1. **Verify module context** — read the owning module's `AGENTS.md` and
   `analysis_options.yaml` before editing.
2. **Run static analysis and autofixes** — first run `dart fix --apply` and `dart format .`, then run `flutter analyze` from the module directory.
3. **Run widget tests** — `flutter test` from the module directory.
4. **Design-system gate** — manually inspect every new/modified widget for:
   - Correct `NmtkShellMode`
   - Token border radius
   - Token status colours
   - No nested cards
5. **nmtk_ui_core gate** — if editing `nmtk_ui_core/`:
   - Verify no `provider` or `flutter_riverpod` imports
   - Verify new widgets added to `lib/nmtk_ui_core.dart` barrel export
   - Verify widgets are self-contained and typed
6. **Cross-module gate** — if a shared model or contract changed, update every
   consumer package that imports it before treating the change as complete.

---

## Report Format

When emitting an audit report, structure it exactly as follows:

```markdown
# Flutter Audit Report — {{module_name}} / {{file_path}}

## Design System Score: {{0–4}} ({{pass/fail}})
- Border radius: {{pass/fail}}
- Status colours: {{pass/fail}}
- Shell mode: {{pass/fail}}
- Typography: {{pass/fail}}
- Layout: {{pass/fail}}

## Audit Health Score: {{score}}/32 ({{rating}})

| Dimension | Score | Notes |
|-----------|-------|-------|
| Design System Compliance | {{0–4}} | ... |
| Widget Architecture | {{0–4}} | ... |
| State Management | {{0–4}} | ... |
| Performance | {{0–4}} | ... |
| Error Handling | {{0–4}} | ... |
| Lifecycle Safety | {{0–4}} | ... |
| Type Safety | {{0–4}} | ... |
| Testing | {{0–4}} | ... |

## 🔴 Blocking Issues (P0)
- [ ] ...

## 🟡 Major Issues (P1)
- [ ] ...

## 💡 Suggestions (P2)
- [ ] ...

## Verification Commands Run
- `flutter analyze {{path}}` → {{exit_code}}
- `flutter test {{path}}` → {{summary}}
```

---

## Rules

- **Never approve code with a P0 design-system violation.**
- **Never skip `flutter analyze` and `flutter test` for the owning module.**
- **Never add a new public widget to `nmtk_ui_core` without updating the barrel export.**
- **Never import state-management packages inside `nmtk_ui_core`.**
- **Never let a shared model change go unpropagated to consumer packages.**

## Symlink Note

This file is canonical. On Windows, if symlinks are unavailable, copy this file
from `.agents/skills/nmtk-flutter-review/SKILL.md` to the target platform paths.
