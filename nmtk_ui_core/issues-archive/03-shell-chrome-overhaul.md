# Shell Chrome Overhaul — Top Bar, File Bar, Sidebar, Navigation

## Owner

- `F2` Full-workspace local agent preferred

## Depends on

- `nmtk_ui_core/issues/01-shell-tokens-top-bars-and-status-primitives.md`
- `nmtk_ui_core/issues/02-modules-surface-cards-and-utility-panel-patterns.md`

## Unlocks

- `nmtk_ui_core/issues/04-loading-screen-backend-readiness.md`
- All module-level shell adoption issues (`10-*` in each module)

## Write scope

- `nmtk_ui_core/lib/**`
- `nmtk_ui_core/test/**`
- `nmtk/neuro_toolkit/lib/**` (launcher shell host)

## Background

The current shell has accumulated chrome that conflicts with "it just works" UX goals:
- A top status/info bar that takes vertical space but conveys little user value.
- A right or top file bar that uses custom conventions instead of OS-native file operations.
- A sidebar (module browser / settings drawer) that exposes server internals to the user.
- No persistent back-navigation affordance for deep views (settings, hub, etc.).
- Profile and settings access is buried rather than anchored in a discoverable corner.

This issue reworks all of that as a single coordinated chrome pass.

## Tasks

### Remove the top bar
- Remove the global top bar (the bar above the module content area that shows app-level
  status, breadcrumbs, or module selector chrome).
- Any essential status info (connectivity, background jobs) moves to the bottom-left status
  strip already defined in `shell_tokens.dart`.

### Replace the file action bar with standard file operations
- Remove the current custom top file bar widget.
- Add a minimal file menu (or title-bar menu on macOS) exposing exactly:
  - **New** (`Cmd/Ctrl+N`)
  - **Open…** (`Cmd/Ctrl+O`) — file picker
  - **Save** (`Cmd/Ctrl+S`)
  - **Save As…** (`Cmd/Ctrl+Shift+S`)
- On macOS desktop, use the platform menu bar via `PlatformMenuBar`; on other targets, use
  an icon-button strip in the workspace title area.
- Wire these actions through each module's document provider (neurocnl editor, canvas project,
  bench job, etc.) via a `FileActionDelegate` interface so the chrome layer stays generic.

### Remove the sidebar
- Remove the left or right sidebar that lists installed modules, server status, or settings
  entries. Users should not see or manage module servers.
- Module switching happens via the launcher's navigation rail (already planned in
  `issues/04-launcher-modules-surface-and-install-start-semantics.md`), not an in-app sidebar.

### Add back button in top-left corner
- Add a persistent back-navigation button (`Icons.arrow_back_ios_new_rounded`) anchored to the
  top-left corner of any non-root view (settings page, hub view, bench results, etc.).
- Use `GoRouter`'s `canPop` to show/hide it: visible when there is a route to pop, hidden on
  root destinations.
- The button should animate in/out with a slide+fade so it does not feel abrupt.

### Anchor profile and settings in bottom-left
- Place a compact user avatar / initials chip and a settings gear icon at the bottom-left of
  the navigation rail (below the module destinations).
- Tapping settings navigates to the settings page (back button then returns to origin).
- Tapping the avatar shows a small popover with name, logout (if auth is wired), and theme
  toggle.

## Done when

- No top bar is rendered in the shell host.
- The file bar is replaced by New/Open/Save/Save-As actions with correct keyboard shortcuts.
- The sidebar is absent from the layout; module switching is rail-only.
- A back button appears in the top-left on all non-root pages and disappears on root pages.
- Profile chip and settings gear are visible at the bottom-left of the navigation rail.
- `cd nmtk_ui_core && flutter test` passes.

## Validation

- `cd nmtk_ui_core && flutter test`
- `cd nmtk/neuro_toolkit && flutter test`
- Manual: navigate to settings → back button visible → tap back → return to root → back button
  hidden.
- Manual: `Cmd+S` in neurocnl studio → file save triggered.
