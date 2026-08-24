# Flutter Audit Report — neuro_toolkit / nmtk/neuro_toolkit

**Date:** 2026-08-21  
**Scope:** All 112 handwritten Dart source and test files in the launcher package  
**Method:** Re-audit after P0 remediation, governance scans, formatter/autofix runs, static analysis, widget tests, launcher doctor, guardrails, integration probes, and a macOS smoke launch

## Design System Score: 4/4 (pass)

- Border radius: pass — the server control uses `radiusChip`; governance rejects numeric launcher radii.
- Status colours: pass — status surfaces resolve through shared NMTK tone tokens.
- Shell mode: pass — both mobile scaffolds explicitly use `NmtkShellMode.command`. The chrome-free wide host is an intentional ADR-0009 design, so the earlier desktop-shell finding was a false positive.
- Typography: pass — SSH keys and requirements content use `NmtkFontFamilies.monospace` and its registered package.
- Layout motion: pass — keyboard inset padding is immediate; no launcher layout-property animation remains.
- Controls: pass — styled launcher controls use Zeta or the shared NMTK wrappers.

## Audit Health Score: 28/32 (Good)

| Dimension | Score | Notes |
|-----------|-------|-------|
| Design System Compliance | 4 | All confirmed token, typography, motion, shell-mode, and control findings are resolved and guarded. |
| Widget Architecture | 3 | Every handwritten file declares at most one widget and build-time reactions were removed; `ToolViewScreen` remains a large rendering coordinator. |
| State Management | 3 | Provider reactions, server resets, workspace initialization, and deployment completion now run through lifecycle listeners; some broad watches and form-local workflow state remain. |
| Performance | 2 | Build-time mutation and layout animation are gone, but broad provider rebuilds and eager launcher collections remain P1 work. |
| Error Handling | 4 | Temporary-file cleanup catches `FileSystemException`, logs only a sanitized message, and stays non-fatal. |
| Lifecycle Safety | 4 | Completion fires once, listeners/timers stop with disposal, and callbacks do not fire after the form unmounts. |
| Type Safety | 4 | `flutter analyze` is clean in both Flutter packages. |
| Testing | 4 | Shared UI and the complete launcher suite are green; unavailable live Suite API services block only the separate root integration probes. |

## P0 Remediation

- [x] Made `ToolViewScreen.build()` side-effect-free by moving provider reactions and reconciliation into `ref.listenManual` lifecycle callbacks.
- [x] Moved deployment completion and heartbeat synchronization out of `BackendSetupForm.build()`.
- [x] Enforced one widget per handwritten Dart file, keeping each state class with its widget.
- [x] Documented the ADR-0009 chrome-free desktop shell and explicitly set command mode on mobile shell instances.
- [x] Replaced raw radii, manual fonts, layout animation, dialogs, multiline fields, icon actions, choices, toggles, selects, progress indicators, and interactive status surfaces.
- [x] Added and exported `NmtkContentDialog` and `NmtkCodeTextArea`; extended `NmtkStatusBadge` with an accessible optional callback.
- [x] Replaced the silent temporary-file cleanup catch with sanitized debug logging.
- [x] Fixed the profile-dialog test with its Riverpod and Neurohub storage dependency boundary.
- [x] Added governance tests for controls, radii, fonts, layout animations, and widget-per-file structure.

## Remaining P1 Work

- Narrow broad Riverpod subscriptions with measured `.select()` projections.
- Split `ToolViewScreen` rendering into smaller pure presentation surfaces.
- Convert unbounded dynamic collections to lazy builders where practical.
- Move more mutable deployment workflow state from the form into its notifier.

## Verification

- `dart fix --apply` → nothing to fix in either Flutter package.
- `dart format .` → clean after formatting both packages.
- `flutter analyze` → clean in `nmtk_ui_core` and `nmtk/neuro_toolkit`.
- `flutter test` in `nmtk_ui_core` → 206 passed.
- Focused launcher remediation/governance tests → passed.
- Launcher guardrail Flutter phase → 196 passed, 1 skipped after synchronizing the concurrent root deployment assets required by the existing bundle contract.
- Launcher doctor → `fatalCount: 0`, `degradedCount: 1` (optional Studio SDK capability).
- Guardrail Python phases → could not start because the local test environment lacks pytest-xdist while `PYTEST_ADDOPTS=-n auto`.
- Required root integration tests → 19 failed because Suite API at `127.0.0.1:9000` was not running.
- An initial standalone launcher run exposed a stale generated deployment bundle; the required guardrail synchronization restored the existing cross-file invariant, after which the complete launcher suite passed.
- `flutter run -d macos` → app built and connected to the Dart VM; macOS could not foreground it automatically, and an existing workspace emitted unrelated CNL parse diagnostics.

## Audit Conclusion

All confirmed P0 Flutter audit findings are remediated in the scoped launcher and shared UI code. The existing stepper, wide layout, mobile filtering, single-surface mounting, and navigation behavior were preserved; no desktop top bar or navigation rail was added.
