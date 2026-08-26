# Flutter Root Frontend Refactor and Merge Order

## Decision

Refactor before the physical merge, but only toward clean, movable feature boundaries—not general cleanup. There is no detected dead Dart code; the real risks are NeuroCNL's size, oversized coordinators, mixed lifecycle ownership, and Neurobench tests currently excluded from analysis.

The target is one root Flutter executable with one root-owned lifecycle. During the refactor, feature code can remain in separate packages until each complete feature is ready to move into the root.

## Refactor Order

1. **Stabilize current work**
   - Finish the ongoing NeuroCNL file splits as a behavior-neutral change.
   - Fix its constructor and public API lints.
   - Keep structural file moves separate from lifecycle or behavior changes.

2. **Restore the safety net**
   - Fix Neurobench's broken test imports.
   - Stop excluding its tests and integration tests from static analysis.
   - Establish green analysis and test baselines for `nmtk`, `nmtk_ui_core`, NeuroCNL, and Neurobench.

3. **Define root contracts**
   - Standardize module IDs and casing.
   - Define typed inputs for the server URL, authentication, deep links, restoration state, navigation callbacks, and error reporting.
   - Make the root responsible for supplying these inputs to every feature.

4. **Clean `nmtk_ui_core`**
   - Keep only typed, reusable, state-management-agnostic UI primitives.
   - Move genuinely shared tokens and shell widgets here before refactoring their consumers.
   - Keep routing, network access, Riverpod, and module-specific business logic out of this package.

5. **Separate application lifecycle from features**
   - Remove feature-owned `MaterialApp`, theme, localization, bootstrap, crash handling, and standalone connection flows.
   - Make the root app the only owner of process-wide lifecycle concerns.
   - Allow temporary feature routers or provider scopes only behind explicit shell adapters.

6. **Refactor API ownership**
   - Make feature API clients accept the root-selected backend and credentials.
   - Remove feature-specific server discovery, hard-coded ports, and duplicate connection storage.
   - Centralize actionable connection and authentication failures at the root boundary.

7. **Refactor state management**
   - Separate domain models and services from Riverpod notifiers and widget state.
   - Move workflow logic and API calls out of `build()` methods.
   - Narrow broad provider watches and keep feature providers namespaced until physical migration.

8. **Break up NeuroCNL by domain**
   - Studio and workspace coordination.
   - Canvas and simulator state.
   - CNL editor and export actions.
   - Setup, run, results, and comparisons.
   - Deployment targets and hardware workflows.

9. **Refactor root coordinators**
   - Split `ToolViewScreen` after the feature contracts stabilize.
   - Then split Backend Setup, deployment services, and the process manager.
   - Keep the root focused on lifecycle, navigation, orchestration, and composition rather than module-specific product logic.

10. **Refactor Neurobench**
    - Remove its nested `MaterialApp.router`.
    - Separate workbench routing, execution state, results, comparison, robustness, and reports.
    - Preserve its command-shell identity while inheriting root lifecycle and connection state.

11. **Physically merge packages**
    - Move one complete feature at a time into `nmtk/neuro_toolkit/lib/features/`.
    - Preserve file history where practical.
    - Move each feature's tests with its implementation and keep the suite green after every slice.

12. **Delete old shells last**
    - Remove package entrypoints, platform runners, web builds, path dependencies, and obsolete adapters only after root integration tests pass.
    - Remove fallback WebView paths only when their native replacements have equivalent behavior and coverage.

## Refactoring Rule Inside Every Feature

Always refactor in this dependency order:

1. Models and contracts.
2. Services and API clients.
3. Providers and notifiers.
4. Routes and shell adapters.
5. Screens and leaf widgets.

Do not manually refactor generated `.g.dart` or `.freezed.dart` files. Do not split tests merely because they exceed 1,000 lines; split them only when fixtures, scenarios, or responsibilities are genuinely independent.

## Migration Order

1. Finish and validate the current NeuroCNL refactor because it is already underway.
2. Complete NeuroCNL's root-owned lifecycle integration.
3. Convert Neurobench to the same adapter contract.
4. Refactor the root coordinators against the stable feature contracts.
5. Move NeuroCNL into the root feature tree.
6. Move Neurobench into the root feature tree.
7. Fold `nmtk_ui_core` into the root only after all consumers use its final public API.
8. Remove the old package and WebView infrastructure.

## Completion Criteria

- One root `runApp()` and one root `MaterialApp`.
- One root-owned theme, localization, accessibility, shortcut, update, crash, and backend lifecycle.
- No module stores or asks for a backend address already known by the root.
- Feature business logic remains separated by domain under `lib/features/`.
- All Dart packages analyze cleanly before their source is moved.
- Root widget and integration tests cover every migrated feature surface.
- The macOS application starts through `flutter run -d macos` and preserves existing workspaces, deep links, and restoration state.

## Related Architecture

- `docs/ADR-claude/0031-root-flutter-app-owns-neurostudio-runtime.md`
- `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart`
- `nmtk/neuro_toolkit/lib/screens/tool_view.dart`
