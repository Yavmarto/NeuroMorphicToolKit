# CML Studio Pipeline Responsive Plan

## Scope

This plan targets the CML Studio workspace in `neurocnl/frontend`, specifically the right-side pipeline workspace currently implemented in `neurocnl/frontend/lib/screens/studio_screen.dart` and `neurocnl/frontend/lib/widgets/pipeline_bar.dart`.

Primary goal:

- Make the Studio UI fully responsive across desktop, tablet, and mobile widths.
- Show at most one pipeline result pane at a time.
- Keep the pipeline selector at the top.
- When a pane is selected, shift the pipeline row so the active pane label lands at the left edge of the visible strip.

Secondary goal:

- Keep the change local to `neurocnl/frontend` unless the pattern proves reusable enough to justify a shared `nmtk_ui_core` widget.

## Current State

The current Studio screen already has two major responsive modes:

- Desktop: split editor and pipeline panels side by side in `_buildDesktopLayout()`.
- Mobile: editor and pipeline stacked in `_buildMobileLayout()`.

The pipeline workspace already shows only one content pane at a time through `IndexedStack` in `_buildPanelWorkspace()`.

The main gaps are:

- The overall Studio layout is only partially responsive and still behaves like a desktop IDE squeezed into smaller widths.
- The pipeline header is a simple `Row` with a play button and a horizontally scrollable `PipelineBar`.
- The pipeline row scrolls manually, but it does not automatically snap or align the active pane to the left edge.
- Mobile and tablet behavior still keep too much simultaneous structure on screen, especially once the editor, controls, and content panes compete for height.

## Target UX

### 1. Responsive Studio shell

- Large desktop: preserve the two-column IDE layout.
- Tablet: keep the editor and pipeline as separate vertical regions, but rebalance heights and reduce chrome.
- Mobile: move to a single-focus workflow where the user sees one major region at a time with minimal competing surfaces.

### 2. Pipeline workspace

- The pipeline control strip remains at the top of the pipeline workspace.
- Only one pipeline pane is visible at a time.
- Pane switching behaves like a tab view, not a dashboard grid.
- Selecting a pipeline step should animate the selector row so the active item is brought into view and positioned at the left edge when possible.

### 3. Interaction model

- Tap a pipeline step in the top row to switch panes.
- On narrow screens, the pane body transitions horizontally like a paged tab view.
- The selector row follows the active pane and slides to keep orientation obvious.
- The play/stop control remains visible without taking over horizontal space needed by the tabs.

## Proposed Layout Strategy

### Breakpoints

Use three Studio-specific width bands in `StudioScreen`:

- `>= 1200`: full split desktop.
- `768 - 1199`: stacked workspace with editor first and pipeline second, using denser spacing.
- `< 768`: single-focus compact mode.

These values should be validated against the app's existing shell breakpoints before implementation so they align with `nmtk_ui_core` tokens where possible.

### Desktop

- Keep the draggable left-right split in `_buildDesktopLayout()`.
- Keep one active pipeline pane at a time in the right workspace.
- Upgrade the pipeline selector to support programmatic scroll alignment for the active tab.

### Tablet

- Replace the current simple `Expanded(flex: 3/4)` stack with a more deliberate layout:
- Editor workspace on top.
- Pipeline workspace below.
- Reduce internal padding, header height, and secondary control density.
- Ensure each pane body can scroll independently.

### Mobile

- Keep the editor and pipeline as separate sections, but avoid showing multiple dense subregions at once.
- The pipeline workspace becomes an explicit tabbed pane region:
- top toolbar
- horizontally sliding tab strip
- one active pane body
- If vertical space remains too constrained, add a top-level editor/pipeline toggle for mobile only.

## Pipeline Header Refactor

The current `_PipelineWorkspaceHeader` should be refactored into a compact responsive header with these rules:

- Keep play/stop available at all sizes.
- On large widths, show play/stop inline with the pipeline selector.
- On narrow widths, allow the play/stop control to collapse into a fixed leading slot while the selector occupies the remaining width.
- Avoid a second header row unless testing shows the single-row compact header is too cramped.

Implementation direction:

- Convert `PipelineBar` from a passive `SingleChildScrollView` into a stateful, controllable strip that can scroll to the selected item.
- Give each step a measurable key or item anchor.
- When `activeStepId` changes, animate the horizontal scroll offset so the selected tab aligns to the leading edge with a small inset.

## One-Pane Tab View Behavior

Although the pane body is already single-pane from the user's perspective, it is not yet structured as a tab view. The implementation should make that behavior explicit.

Recommended approach:

- Replace the content `IndexedStack` in `_buildPanelWorkspace()` with a `PageView` or `TabBarView`-style interaction layer.
- Keep state persistence for heavy panes so switching tabs does not reset results or editors.
- Synchronize the selected pipeline step, page index, and route-backed `workspace.activePanel`.

Preferred implementation:

- Use `PageController` in `StudioScreen` because the parent already owns the panel selection state.
- Disable free-swipe navigation on desktop if that feels too loose for the IDE model.
- Allow animated page changes on tablet and mobile.

## Active Tab Left-Edge Alignment

This is the key interaction you requested.

Behavior:

- When the user selects a pane, the selector row animates horizontally.
- The selected pane label should land at the left edge of the visible row when enough trailing space exists.
- If the selected tab is near the end, clamp the scroll so the row does not overshoot.

Implementation detail:

- Track the `ScrollController` inside `PipelineBar`.
- Give each step container a `GlobalKey`.
- After layout, compute the selected tab's x-offset relative to the scrollable content.
- Animate the controller to `max(0, tabOffset - leadingInset)`, clamped to `maxScrollExtent`.

Fallback:

- If precise measurement becomes brittle, use `Scrollable.ensureVisible` with leading-edge alignment semantics, then refine only if needed.

## Pane Content Responsiveness

Each pipeline pane should be reviewed under the one-pane model:

- `ParseResultsTable`
- `ValidationPanel`
- `_GenerateWorkspacePanel`
- `SimulationDashboard`
- `_DeployWorkspacePanel`

Audit goals:

- No horizontal overflow at mobile widths.
- Internal headers and chip rows wrap or scroll intentionally.
- Long forms and metrics stack cleanly.
- Charts and tables degrade to single-column presentation where needed.

The generate pane already has a horizontally scrolling metrics row. Similar treatment should be applied consistently rather than relying on overflow tolerance.

## Visual Consistency and Token Cleanup

While implementing, normalize the Studio surfaces to repo rules:

- Replace non-token border radii such as `18` with sanctioned token values from `NmtkShellTokens`.
- Preserve the documented `// studio-compact` outer padding exception.
- Keep `NmtkShellMode.studio` behavior intact.

This is not a separate redesign. It is a cleanup pass required by the repo style guide while touching these surfaces.

## File-Level Plan

Expected write set for implementation:

- `neurocnl/frontend/lib/screens/studio_screen.dart`
- `neurocnl/frontend/lib/widgets/pipeline_bar.dart`

Possible follow-on write set if shared extraction is justified:

- `nmtk_ui_core/lib/widgets/...`
- `nmtk_ui_core/lib/nmtk_ui_core.dart`

The default path should stay inside `neurocnl/frontend` first.

## Delivery Phases

### Phase 1: Responsive shell pass

- Introduce explicit desktop, tablet, and mobile layout branches in `StudioScreen`.
- Rebalance editor versus pipeline space usage.
- Remove obvious overflow and cramped header behavior.

### Phase 2: Pipeline selector upgrade

- Make the selector row programmatically scrollable.
- Add active-tab left-edge alignment animation.
- Keep route and provider state synchronized.

### Phase 3: True tab-view pane behavior

- Convert pane switching to a controlled paged view.
- Keep pane state alive across switches.
- Tune animation duration and gesture behavior by breakpoint.

### Phase 4: Pane-by-pane responsive cleanup

- Audit each pipeline pane for narrow-width layout problems.
- Fix wrapping, spacing, and scrolling behavior.
- Add tests for the most failure-prone widths.

## Verification

Implementation should be accepted only after:

- `cd neurocnl/frontend && flutter test`
- Manual resizing checks at desktop, tablet, and mobile widths.
- Verification that selecting each pipeline tab keeps only one pane visible.
- Verification that the active tab scrolls to the left edge on narrow and medium widths.
- Verification that switching tabs does not clear generated or simulated results unexpectedly.

Recommended manual widths:

- 1440 px
- 1024 px
- 768 px
- 600 px
- 390 px

## Risks

- `PageView` plus provider-backed panel state can create double sources of truth if page index and `activePanel` are not synchronized carefully.
- Automatic tab alignment can feel jumpy if it fires before layout settles; this needs post-frame scheduling and change guards.
- Some pane widgets may currently assume desktop height or width and will need local refactors once the shell gets stricter.

## Recommendation

Implement this as a focused `neurocnl/frontend` change first. Only extract a shared tab-strip primitive into `nmtk_ui_core` if the pattern is proven reusable after the Studio behavior is stable.
