# Frontend State Management Review

**Date:** 2026-05-31
**Author:** Codex agent review
**Scope:** Flutter/Dart frontends in the NeuroMorphicToolKit monorepo.

## Scope and Surfaces Reviewed

Surfaces with state-bearing UI code:

- `neurocnl/frontend`
- `nmtk/neuro_toolkit` (the launcher / control-plane shell)
- `Neurohub/frontend`
- `Neurosense/frontend`
- `Neurobench/frontend`
- `nmtk_ui_core` (shared presentational widget library)

Surfaces with **zero** `setState` (intentionally thin or non-widget):

- `Neurohub/Neurohub_shell_adapter`
- `Neurosense/Neurosense_shell_adapter`
- `Neurosim/Neurosim_shell_adapter`
- `nmtk_module_contracts`

## Methodology

All numbers below are reproducible with `ripgrep` from the repo root. Counts are
regex-based and therefore approximate; where test code inflates a count it is
reported separately.

- `setState` occurrences (app code only, excluding `test/`):
  `rg -t dart -g '!**/test/**' -c 'setState' <surface>`
- `setState` occurrences including tests:
  `rg -t dart -c 'setState' <surface>`
- Riverpod dependency + version:
  `rg -n 'flutter_riverpod|riverpod_annotation' <surface>/pubspec.yaml`
- Provider definitions:
  `rg -t dart -c 'Provider\(|NotifierProvider|StateNotifierProvider|FutureProvider|StreamProvider|ChangeNotifierProvider|AsyncNotifierProvider|\.autoDispose' <surface>`
- Consumer usage sites:
  `rg -t dart -c 'ConsumerWidget|ConsumerStatefulWidget|ref\.watch|ref\.read|ref\.listen' <surface>`
- Manual sampling of the heaviest `setState` files to classify each usage as
  local UI state vs. business/app state.

## Findings

| Surface | `setState` (app) | Files | incl. tests | Riverpod | Provider defs | Consumer sites |
| --- | ---: | ---: | ---: | --- | ---: | ---: |
| `neurocnl/frontend` | 91 | 21 | 103 | Y — `^2.4.9` + `riverpod_annotation ^2.3.3` | ~80 | ~519 |
| `nmtk/neuro_toolkit` | 42 | 7 | 42 | Y — `^2.6.1` | ~78 | ~76 |
| `Neurohub/frontend` | 15 | 6 | 15 | Y — `^2.6.1` | ~18 | ~42 |
| `nmtk_ui_core` | 14 | 3 | 14 | N — no state-mgmt dep | ~2 | 0 |
| `Neurobench/frontend` | 10 | 2 | 10 | Y — `^2.4.9` | ~9 | ~126 |
| `Neurosense/frontend` | 5 | 4 | 5 | Y — `^2.4.0` | ~8 | ~73 |
| **Total** | **177** | — | **189** | — | — | — |

Key observation: in every product frontend, Riverpod consumer usage vastly
outweighs `setState`. `neurocnl/frontend` alone has ~80 provider definitions and
~519 `ref.watch/read/listen` sites against 91 `setState` calls. Riverpod is the
dominant, established pattern — `setState` is the minority.

`nmtk_ui_core` is the deliberate exception: it is a shared presentational widget
library and has no state-management dependency by design (see
`nmtk_ui_core/AGENTS.md`). Its 14 `setState` calls are local widget state in
self-contained widgets (`validation_chip.dart`, `desktop_scaffold.dart`,
`command_palette.dart`).

## Classification of `setState` Usage

Manual sampling of the heaviest files splits usage into two buckets.

### Appropriate — keep on `setState` (local, ephemeral UI state)

Form inputs, dropdown selections, expansion toggles, and other transient widget
state that already delegates business actions to Riverpod. This is the correct,
idiomatic use of `setState` and should not be migrated.

- `neurocnl/frontend/lib/widgets/simulator_panel.dart` — `setState` only tracks
  local form fields (`_timesteps`, `_seed`, `_dtMs`, `_firingRate`,
  `_selectedBackend`, `_selectedPopulation`) while delegating the actual run /
  reset / refresh work to `ref.read(...notifier)` providers.

### Migration candidates (worth lifting into Riverpod)

Two patterns where `setState` holds state that outlives a single widget's local
concern:

- **Async load / error / loading-flag flows** that map cleanly to `AsyncNotifier`
  or `FutureProvider`:
  - `nmtk/neuro_toolkit/lib/screens/environment_editor.dart`
    (`_loadingPackages`, `_packagesError`, `_packages`, `_body`, `_error`)
  - `nmtk/neuro_toolkit/lib/screens/python_setup.dart`
  - `Neurohub/frontend/lib/screens/login_screen.dart`
  - `Neurohub/frontend/lib/screens/share_model_screen.dart`
  - `neurocnl/frontend/lib/screens/analysis_screen.dart`
  - `neurocnl/frontend/lib/screens/hardware_screen.dart`
- **Cross-widget app/navigation state** that maps to a `Notifier` /
  `NotifierProvider`:
  - `nmtk/neuro_toolkit/lib/screens/tool_view.dart` — `_activeModuleId`
    (active-module navigation), `_moduleLoadFailures` (per-module error map),
    and `_controllers` (per-module webview controllers) are app-level state
    threaded through the launcher shell rather than ephemeral local UI state.

## Verdict

- **Is there a lot of `setState`?** No. Relative to Riverpod usage it is the
  minority pattern in every product frontend. The raw total (177 in app code) is
  concentrated in `neurocnl/frontend` and the launcher, and most of it is
  legitimate local UI state.
- **Should it be replaced with Riverpod?** Not wholesale. Riverpod is already the
  primary pattern, so a blanket rewrite would add churn and risk without
  proportional benefit. A **targeted** migration of the candidates above is
  worthwhile. Legitimate local UI state should stay on `setState`, and
  `nmtk_ui_core` should remain framework-light to preserve its presentational
  library boundary.

## Recommendations (prioritized)

1. **Migrate async load/error screens to `AsyncNotifier` / `FutureProvider`** for
   consistent loading/error handling and testability (the
   `environment_editor.dart`, `python_setup.dart`, `login_screen.dart`,
   `share_model_screen.dart`, `analysis_screen.dart`, `hardware_screen.dart`
   set).
2. **Lift launcher app/navigation state out of `tool_view.dart`** into a Riverpod
   `Notifier` (`_activeModuleId`, `_moduleLoadFailures`, `_controllers`), so the
   shell's active-module and per-module failure state is observable and testable
   outside the widget tree.
3. **Leave local UI `setState` as-is** (form fields, toggles, dropdown selection).
   Migrating these adds boilerplate without benefit.
4. **Do not add Riverpod to `nmtk_ui_core`.** It is a shared presentational
   library; keep it dependency-light per `nmtk_ui_core/AGENTS.md`.

These are recommendations only. Each migration should be its own follow-up task
with its own widget/unit tests; no source code is changed by this report.

## Assumptions

- Counts are regex-based and approximate; test code is reported separately where
  it materially changes a number (notably `neurocnl/frontend`: 91 app vs. 103
  incl. tests).
- This document records findings and recommendations only and performs no
  Riverpod migration. Actual migrations are out of scope and tracked separately.
- Output location follows the existing `docs/assessment/` convention alongside
  the `nmtk-*.md` assessment docs.
