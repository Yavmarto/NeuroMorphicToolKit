# Flutter Audit Report — NMTK / last 7 days + working tree

**Scope:** 180 `lib/` Dart files in parent repo (committed last 7d + uncommitted on `dev`); Neurohub submodule 7 files; no Dart changes in Neurochip, Neurobench, neurocnl, Neurosense, Neurosim submodules.

**Audit Health Score: 26/32 (Good)** — approve with minor fix list; no merge blockers in neuro_toolkit analyze.

| Dimension | Score | Notes |
|-----------|-------|-------|
| Design System Compliance | 3 | Token radii respected; brainviz still uses legacy `AppTheme` colours; Neurohub connect has nested cards |
| Widget Architecture | 3 | `studio_screen` shell extraction is a clear win; `workspace_repos_screen` hosts two public widgets |
| State Management | 3 | Riverpod + `ref.listen`/`select` used correctly; GoRouter migration for Neurohub routes |
| Performance | 3 | Brainviz ticker gated on dirty frames; results panel avoids redundant `setState` |
| Error Handling | 2 | `ConnectNotifier` surfaces raw `error.toString()`; most paths use typed exceptions |
| Lifecycle Safety | 4 | Controllers/tickers disposed in changed surfaces |
| Type Safety | 3 | `flutter analyze` → 11 infos/warnings, 0 errors |
| Testing | 4 | Strong coverage on connect, brainviz, studio mobile, navigation |

## Verification Commands Run
- `flutter analyze` (neuro_toolkit) → exit 0, 11 issues (unused/unnecessary imports)
- `flutter analyze` (Neurohub/frontend) → exit 0, clean
- `flutter test` connect_notifier, server_connect_screen, brainviz_force_3d_view, dev_offline_navigation → **24 passed**

---

## Blocking Issues (P0)

_None in neuro_toolkit committed/uncommitted diff. Neurohub submodule below is pre-merge polish, not a runtime crash._

- [ ] **Nested cards** — `Neurohub/frontend/lib/src/github_connect_screen.dart:248` outer `Card` wraps `_buildCodeCard` which returns another `Card` at `:354`. Violates layout rule (card-in-card). Flatten to a single surface or use `NmtkSurfaceCard`-style border only.

## Major Issues (P1)

- [ ] **Raw exception text shown to users** — `nmtk/neuro_toolkit/lib/features/server/connect/connect_notifier.dart:153-159` — generic `on Object catch` sets `failureCause: error.toString()`, which can expose socket/stack details in the sign-in banner (`server_connect_screen.dart:174-178`). Map to a friendly message like the `ConnectException` branch at `:146-151`.
- [ ] **Two public widgets in one file** — `nmtk/neuro_toolkit/lib/features/neurocnl/screens/hub/workspace_repos_screen.dart:16` (`WorkspaceRepoCard`) and `:105` (`WorkspaceReposScreen`). Split per one-widget-per-file rule.
- [ ] **Imperative routing still present** — `nmtk/neuro_toolkit/lib/features/neurocnl/widgets/canvas/custom_node_source_editor.dart:61-62` uses `Navigator.push` + `MaterialPageRoute` for the custom-node editor (touched in 7d window). Migrate to a declared GoRouter route.
- [ ] **Imperative routing (run step)** — `nmtk/neuro_toolkit/lib/features/neurocnl/features/studio/workflow/steps/run_step/support.dart:7-8` — same `MaterialPageRoute` pattern for notebook preview navigation.
- [ ] **Neurohub cancel uses Navigator** — `Neurohub/frontend/lib/src/github_connect_screen.dart:326` — `Navigator.maybePop()` instead of host GoRouter when embedded in launcher webview (acceptable standalone; inconsistent when shell-hosted).

## Suggestions (P2)

- [ ] **Legacy theme colours in new brainviz files** — `brainviz_force_3d_view.dart:340-342`, `brainviz_reset_camera_button.dart:23-39` use `AppTheme.*` instead of `NmtkShellTokens` / `Zeta.of(context).colors` for surface/border/text. Not status colours, but weakens dark/light parity.
- [ ] **Magic padding** — `share_workspace_screen.dart:158`, `workspace_repos_screen.dart:200` use `EdgeInsets.all(24)`; prefer `NmtkSpacingTokens` where available.
- [ ] **Analyzer hygiene** — unused import `custom_node_editor_panel.dart:4`; unnecessary zeta imports in several touched files (see analyze output).
- [ ] **Neurohub token duplication** — `github_connect_theme.dart` copies `NmtkShellTokens` values; add a cross-package invariant test or shared re-export to prevent drift.

## Positive Highlights

- **Studio decomposition** — `studio_screen.dart` slimmed via `studio_screen_shell/*` (desktop/mobile shells, keyboard shortcuts, pipeline content). Improves maintainability without behaviour change.
- **GoRouter Neurohub routes** — `neurohub_routes.dart` + `workspace_repos_screen.dart:119` / `share_workspace_screen.dart:115` replace `MaterialPageRoute` pushes for workspace share flow.
- **Connect auth restoration** — `connect_notifier.dart` + `server_connect_screen.dart` restore prefilled host/username, embedded mode, and dev-offline path with tests.
- **Brainviz performance** — `results_brainviz_panel.dart` dirty-flag `setState`; `brainviz_force_3d_view.dart` ticker lifecycle + repaint caching.
- **Error-handling fix** — `run_step.dart:157-165` replaces empty `catch (_) {}` with typed debug logging.

## Submodule Delta Summary

| Module | Dart files (7d) | Verdict |
|--------|-----------------|---------|
| nmtk/neuro_toolkit | ~180 lib + tests | Good; P1 items above |
| Neurohub/frontend | 7 | Clean analyze; P0 nested card |
| Neurochip, Neurobench, neurocnl, Neurosense, Neurosim | 0 | No audit surface |
