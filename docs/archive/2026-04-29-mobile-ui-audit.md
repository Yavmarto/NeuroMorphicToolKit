# 2026-04-29 Mobile UI Audit

## Scope

This is a static code audit of the Flutter UI surfaces in:

- `nmtk_ui_core`
- `nmtk/neuro_toolkit`
- `neurocnl/frontend`
- `Neurosim/frontend`
- `Neurochip/frontend`
- `Neurobench/frontend`
- `Neurosense/frontend`
- `Neurohub/frontend`

This audit is about actual mobile behavior, not whether Flutter can technically target Android or iOS.

I looked for:

- explicit mobile or narrow-width branches
- mobile navigation patterns such as bottom navigation or stacked layouts
- scroll fallbacks for wide data views
- fixed desktop-only shells that would still render poorly on a phone

I did not run these UIs on a device or emulator in this pass, so the conclusions below are based on implementation structure rather than runtime screenshots.

## Executive Summary

Overall verdict: **partial mobile readiness, not suite-wide mobile readiness**.

- The repo does contain real responsive widgets and a few genuinely mobile-aware module screens.
- The strongest mobile support is in `Neurosense`, followed by parts of `Neurochip`, `Neurobench`, and `neurocnl`.
- The main launcher in `nmtk/neuro_toolkit` is still fundamentally desktop-first. It always uses `NmtkDesktopScaffold`, which is a left-sidebar desktop shell with no mobile branch.
- `nmtk_ui_core` includes a `ResponsiveScaffold`, but it is currently only tested in isolation and is not used by the launcher or the audited module shells.

If the question is "can the current suite UI run on a phone and still feel like it has actual mobile widgets and layout logic?", the answer is:

- **Shared primitives:** yes, partially
- **Several module screens:** yes, partially
- **The launcher experience as a whole:** **no**

## Shared Shell Findings

### 1. The repo has a real mobile scaffold, but it is not wired into production shells

`nmtk_ui_core/lib/app_theme.dart:705-775` defines `ResponsiveScaffold` with a real mobile branch:

- `< 600px`: `NavigationBar`
- `>= 600px`: top app bar layout

This is backed by widget tests in `nmtk_ui_core/test/responsive_scaffold_test.dart:28-87`.

However, `rg` only finds `ResponsiveScaffold` in:

- `nmtk_ui_core/lib/app_theme.dart`
- `nmtk_ui_core/test/responsive_scaffold_test.dart`

There are no production usages elsewhere in the repo.

**Conclusion:** mobile primitives exist, but they are not the shell actually used by the launcher or most module entry points.

### 2. `NmtkDesktopScaffold` is desktop-only by construction

`nmtk_ui_core/lib/widgets/desktop_scaffold.dart:177-292` always renders:

- a left sidebar inside a `Row`
- a desktop header strip
- a content pane to the right

There is no breakpoint logic, drawer mode, bottom navigation mode, or narrow-screen fallback.

**Conclusion:** any screen that uses `NmtkDesktopScaffold` is not meaningfully mobile-adapted.

### 3. `NmtkTopAppBar` is somewhat compression-friendly, but not fully adaptive

`nmtk_ui_core/lib/widgets/top_app_bar.dart:48-150` does a few good things:

- destinations scroll horizontally
- search has a max width
- status badges wrap

But the whole app bar is still a single `Row`, so leading, title, search, badges, and actions can still become crowded on small widths.

**Conclusion:** this helps tablets and narrow desktops more than phones.

### 4. `NmtkWorkspaceShell` is a valid responsive content primitive

`nmtk_ui_core/lib/widgets/workspace_shell.dart:21-78` switches from:

- split two-pane layout at `>= 1080`
- stacked scroll layout below that

**Conclusion:** this is a legitimate mobile/tablet-capable building block. It is one of the better shared patterns in the repo.

## Launcher Findings (`nmtk/neuro_toolkit`)

### Verdict

**Not mobile-ready as a launcher experience.**

### Evidence

1. `ToolViewScreen` always uses `NmtkDesktopScaffold`

`nmtk/neuro_toolkit/lib/screens/tool_view.dart:614-673` and `:655-673` return `NmtkDesktopScaffold` in both the empty and normal workspace paths.

That means the primary launcher shell always depends on the desktop-only left sidebar.

2. The module picker is not truly responsive for phone widths

`nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart:65-83` hardcodes `crossAxisCount = 3` and then computes card width with a floor of `240`.

That avoids tiny cards, but it does not switch to 1-column or 2-column layouts by breakpoint.

On a phone-width viewport, this will force oversized cards into a wrapping layout that is more "desktop cards squeezed smaller" than a real mobile card list.

3. Settings has several desktop-style `Row` layouts without narrow fallback

`nmtk/neuro_toolkit/lib/screens/settings.dart:64-119` uses `Row(mainAxisAlignment: spaceBetween)` for settings fields such as Theme and Log Level.

`nmtk/neuro_toolkit/lib/screens/settings.dart:131-154` also uses a row for the telemetry description plus switch.

These sections may survive on medium widths, but there is no explicit stacked mobile branch.

### Important nuance

Many native module surfaces are embedded without their own shell chrome:

- `neurocnl/frontend/lib/shell_adapter.dart:18-33`
- `Neurosim/frontend/lib/shell_adapter.dart:22-31`
- `Neurochip/frontend/lib/shell_adapter.dart:68-82`
- `Neurobench/frontend/lib/shell_adapter.dart:14-21`
- `Neurosense/frontend/lib/shell_adapter.dart:22-30`

Those adapters typically set `showShellChrome: false`, so the module content can be more responsive than the launcher around it. But the outer launcher frame is still desktop-only.

## Module-by-Module Findings

## `Neurosense`

### Verdict

**Best mobile readiness in the suite.**

### Evidence

1. Screen-level mobile branches exist

`Neurosense/frontend/lib/screens/signal_monitor_screen.dart:15-74` explicitly switches on width:

- narrow: stacked `SingleChildScrollView`
- wide: split `Row` with `Expanded`

`Neurosense/frontend/lib/screens/device_config_screen.dart:23-69` also has:

- narrow: `ListView` with stacked sections
- wide: `Row` with side-by-side panels

2. Viewer uses available space instead of fixed heights

`Neurosense/frontend/lib/widgets/live_signal_viewer.dart:252-264` sizes the plot from `LayoutBuilder` constraints rather than hardcoded pixel height.

3. The shell is still top-bar based, not phone-native navigation

`Neurosense/frontend/lib/app.dart:123-186` uses `NmtkTopAppBar` and `NmtkWorkspaceSwitcherBar`, not bottom navigation.

So even here, the content is mobile-aware, but the app-level navigation is closer to compact desktop/tablet than native phone UI.

### Assessment

If a single module had to run on mobile first, `Neurosense` is the closest to acceptable.

## `Neurochip`

### Verdict

**Good responsive content patterns, weak app-shell mobile story.**

### Evidence

1. Standalone mode uses the desktop scaffold

`Neurochip/frontend/lib/app.dart:141-173` returns `NmtkDesktopScaffold` when `showShellChrome` is true.

That makes the standalone shell desktop-first.

2. Embedded mode strips shell chrome

`Neurochip/frontend/lib/app.dart:134-139` falls back to a plain `Scaffold` with `SafeArea` when shell chrome is disabled, which is better for embedding.

3. Several core screens use `NmtkWorkspaceShell`

Example: `Neurochip/frontend/lib/screens/akida_deploy_screen.dart:151-156` uses `NmtkWorkspaceShell`, which gives split-on-wide and stacked-on-narrow behavior.

4. Form helpers adapt to available width

`Neurochip/frontend/lib/widgets/deploy_form_helpers.dart:94-113` turns two-column fields into single-column fields below a computed threshold.

5. Dashboard-like screens use actual breakpoint logic

`Neurochip/frontend/lib/screens/deploy_status_screen.dart:65-86` switches capability cards between 3, 2, or 1 columns based on width.

### Assessment

The inner workflow screens are reasonably mobile-aware. The shell around them is not.

## `neurocnl`

### Verdict

**Partial mobile support, but the product remains desktop-heavy.**

### Evidence

1. The shell does react to width

`neurocnl/frontend/lib/screens/studio_screen.dart:404-426` chooses:

- desktop layout above `NmtkShellTokens.normalBreakpoint`
- mobile layout below it

2. The mobile layout is a stacked split, not a dedicated mobile UI

`neurocnl/frontend/lib/screens/studio_screen.dart:483-496` turns the editor and panel areas into vertical `Expanded` sections.

That is a real responsive branch, but it still preserves the same complex workstation model on a phone.

3. Desktop mode has a draggable split-pane editor

`neurocnl/frontend/lib/screens/studio_screen.dart:429-480` uses a classic resizable desktop workspace. That is appropriate on desktop, but it highlights how desktop-centric the feature set is.

4. Some subpanels collapse well

`neurocnl/frontend/lib/screens/studio_screen.dart:978-995` adjusts padding based on width.

`neurocnl/frontend/lib/screens/studio_screen.dart:1030-1032` uses horizontal scrolling for compact header metrics.

5. The graph view has compact handling, but still relies on dense canvas interaction

`neurocnl/frontend/lib/widgets/network_graph_view.dart:111-209` uses `LayoutBuilder`, condensed preview logic, and bounded detail panels.

That is responsive work, but it is still a graph-and-inspector tool rather than a mobile-first experience.

6. Shell navigation is still top-app-bar based

`neurocnl/frontend/lib/routing/app_router.dart:180-215` uses `NmtkTopAppBar`, not bottom navigation or drawer behavior.

### Assessment

`neurocnl` has genuine responsive effort, but the studio metaphor remains too dense to call the overall experience mobile-ready.

## `Neurosim`

### Verdict

**Responsive in places, but still fundamentally desktop/canvas oriented.**

### Evidence

1. The canvas screen is desktop-structured

`Neurosim/frontend/lib/screens/canvas_screen.dart:91-156` builds around a wide `Row` with optional side panels and a central canvas.

2. The canvas itself is large-scale and interaction-heavy

`Neurosim/frontend/lib/widgets/network_canvas.dart:84-92` uses `InteractiveViewer` over a `10000 x 10000` canvas.

That can technically work on mobile, but it is a desktop interaction model. Pinch-zoom exists, yet precision editing on a phone will be hard.

3. Some control panels do narrow-width fallback correctly

`Neurosim/frontend/lib/widgets/simulation_control_panel.dart:26-97` switches to a narrow layout with horizontally scrollable controls and compact backend status.

4. Shell adapters suppress chrome when embedded

`Neurosim/frontend/lib/shell_adapter.dart:22-31` sets `showShellChrome: false`, which avoids one layer of desktop shell when hosted.

### Assessment

This is responsive enough to avoid immediate breakage, but not designed for comfortable mobile authoring.

## `Neurobench`

### Verdict

**Moderate responsive support, but several data views remain desktop-biased.**

### Evidence

1. The workbench has a real stacked mobile layout

`Neurobench/frontend/lib/screens/workbench_shell.dart:239-287` switches below `NmtkShellTokens.normalBreakpoint` into a vertically stacked scroll layout for catalog, main pane, and utility panel.

2. The shell still uses top app bar plus workspace switcher

`Neurobench/frontend/lib/screens/workbench_shell.dart:177-235` uses `NmtkTopAppBar` and `NmtkWorkspaceSwitcherBar`, not a mobile navigation pattern.

3. Some widgets still hardcode desktop-ish structure

`Neurobench/frontend/lib/widgets/target_comparison_grid.dart:23-31` always uses a 2-column grid.

That is a real mobile weakness because there is no 1-column narrow fallback.

4. Wide tables fall back to horizontal scrolling rather than reflow

`Neurobench/frontend/lib/widgets/metric_diff_table.dart:26-40` wraps `DataTable` in a horizontal `SingleChildScrollView`.

That is a valid containment strategy, but it is not a mobile-optimized presentation.

### Assessment

`Neurobench` is usable on narrower screens better than the launcher, but some of its analytical widgets are still essentially desktop tables and grids.

## `Neurohub`

### Verdict

**Responsive dashboard layout, but still not strongly mobile-native.**

### Evidence

1. The dashboard hides optional chrome based on width

`Neurohub/frontend/lib/screens/dashboard_screen.dart:98-123` conditionally removes search, create action, status badge, and even one destination on smaller widths.

That is a strong sign of intentional responsive behavior.

2. Main content switches between one-column and two-column density

`Neurohub/frontend/lib/screens/dashboard_screen.dart:192-239` determines whether to use a two-column layout based on breakpoint.

3. Project cards collapse to a single column on narrow widths

`Neurohub/frontend/lib/screens/dashboard_screen.dart:554-602` uses 3, 2, or 1 columns depending on width.

4. Some widgets bound their own height defensively

`Neurohub/frontend/lib/widgets/activity_feed.dart:35-41` clamps height to a reasonable range instead of assuming a large desktop panel.

5. The shell is still top-bar oriented, including when embedded

`Neurohub/frontend/lib/app.dart:64-75` and `Neurohub/frontend/lib/shell_adapter.dart:22-29` show no shell-chrome-off path comparable to some other modules.

### Assessment

`Neurohub` has solid responsive dashboard work, but it still reads more like a compact desktop dashboard than a phone-first app.

## Overall Ranking

From strongest to weakest mobile behavior in the audited surfaces:

1. `Neurosense`
2. `Neurochip`
3. `Neurohub`
4. `Neurobench`
5. `neurocnl`
6. `Neurosim`
7. `nmtk/neuro_toolkit` launcher

The bottom slot is the most important one operationally, because the launcher is the suite entry point.

## Key Gaps Preventing a "Yes, this has a mobile UI" Answer

1. The suite entry shell is desktop-only.
2. The shared mobile scaffold exists but is unused in production paths.
3. Most apps use top app bars and workspace switcher bars rather than phone navigation patterns.
4. Several analytical surfaces rely on horizontal scrolling or fixed multi-column grids instead of mobile-specific representations.
5. Canvas-heavy apps (`neurocnl`, `Neurosim`) have responsive containment, but not simplified mobile workflows.

## Bottom-Line Answer

If the standard is "does this codebase contain any actual responsive widgets and mobile-specific layout behavior?", the answer is **yes**.

If the standard is "can the suite UI, as users would realistically experience it, be considered mobile-ready with proper mobile widgets and responsive flows?", the answer is **no**.

The repo currently looks like:

- a desktop-first launcher
- several partially responsive module UIs
- one notably better mobile-aware module (`Neurosense`)
- a shared responsive shell that has not yet been adopted where it matters most

## Recommended Next Focus Areas

1. Replace launcher use of `NmtkDesktopScaffold` with an actually deployed adaptive shell based on `ResponsiveScaffold` behavior.
2. Add explicit narrow-screen variants for launcher settings and module picker.
3. Standardize module shell navigation on a phone mode:
   either bottom navigation, drawer + compact top bar, or per-module tab collapse.
4. Fix known fixed-layout offenders first:
   `Neurobench/frontend/lib/widgets/target_comparison_grid.dart`
   `nmtk/neuro_toolkit/lib/widgets/module_picker_panel.dart`
   `nmtk/neuro_toolkit/lib/screens/settings.dart`
5. For canvas products, define a reduced-scope mobile mode instead of trying to fit the full desktop authoring model into a narrow viewport.
