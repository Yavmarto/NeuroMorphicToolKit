# NeuroMorphicToolKit — UI Audit & Fix Plan

**Date:** 2026-04-26 (Shadcn integration addendum: 2026-04-26)**Reference baseline:** `neurocnl` (CNL Studio) — considered the most mature UI.  
**Scope:** All Flutter/Dart modules — nmtk shell, nmtk_ui_core, neurocnl, Neurosim, Neurochip, Neurohub, Neurobench, Neurosense.

---

## Executive Summary

The suite has a well-structured design system (`nmtk_ui_core`) and a mature reference implementation (`neurocnl`) that the other modules have not consistently caught up to. The core problems cluster into five areas:

1. **Typography split** — neurocnl uses Inter; every other module uses Space Grotesk. This is the most visible cross-module inconsistency.
2. **Colour semantics drift** — success, error, and warning colours are defined in two incompatible sets (NmtkNeurocnlTokens vs NmtkShellTokens). Modules pick different sets.
3. **Breakpoint fragmentation** — six different desktop-breakpoint values across the modules, producing different layout collapses at the same window width.
4. **Hardcoded magic numbers** — layout dimensions that should reference tokens (utility panel width, card heights, tile widths) are scattered as literals.
5. **Button style fragmentation** — four different button patterns in use (ElevatedButton, FilledButton, NmtkPrimaryButton, OutlinedButton) with no clear rule for when to use which.

---

## 1. neurocnl — CNL Studio (Reference)

### What is working well

- Custom purple/lavender dark theme (`NmtkNeurocnlTokens`) is coherent and distinctive.
- Two-pane resizable layout with a drag handle is the correct desktop pattern for an editor studio.
- Pipeline bar with step tabs (Parsed Specs → Validation → Generate → Simulation → Deploy) clearly expresses the workflow.
- File tab strip is intentionally compact (36 px) and IDE-appropriate.
- Syntax token colours (keyword purple, subject cyan, number orange, comment blue-grey) follow a coherent Dracula-derived palette.
- Node/edge colour vocabulary (ensemble, motor, interneuron, input, error-input, excitatory, inhibitory, plastic) is semantically rich and consistent.

### Problems found

#### Typography
- Uses `GoogleFonts.inter` via `_buildInterTextTheme`. Every other module uses `Space Grotesk` via `_buildTextTheme`. This is an intentional split, but the Inter family is applied only partially: the AppBar title is explicitly set to `GoogleFonts.inter(fontSize: 18, fontWeight: w600)`, but the chip labels also call `GoogleFonts.inter(fontSize: 12)`. Elsewhere in widgets, plain `TextStyle()` inherits theme defaults, which _are_ Inter because the theme overrides it — but this fragile coupling means any theme change can silently drop Inter on unlisted widgets.

#### Layout and spacing
- Outer `Padding(EdgeInsets.all(12))` wraps the entire `StudioScreen.build()`. This causes the two workspace frames to sit with only 12 px clearance from all window edges. On large monitors this looks fine; on 1280 × 800 it is noticeably cramped at top and bottom because the top app bar and workspace bar already consume 100 px of vertical space.
- The drag-handle visual element is `width: 4, height: 72` inside a `16px` transparent container. The 72 px height is a magic number. The handle does not span the full height of the pane, so it is hard to discover. VS Code and JupyterLab both use invisible full-height handles — only a cursor change signals draggability. The current implementation falls between two conventions: it draws the handle but makes it easy to miss, and still changes the cursor.
- `_LauncherActionCard` has a hardcoded `SizedBox(width: 220)`. On narrow right-panel widths (< 400 px) this creates overflow. The Wrap container mitigates it somewhat but the fixed card size is an anti-pattern.
- `_DeployStatTile` has `BoxConstraints(minWidth: 150)` but no `maxWidth`. In the Wrap layout, on narrow widths the tiles will expand and the Wrap will still single-column them, which is acceptable, but a `maxWidth: 280` would give the layout better structure.
- `_DurationSlider` uses `fontSize: 11` for the label — the smallest text in the suite. Combined with `color: AppTheme.textSecondary`, this is borderline for readability.
- `_FileTabStrip` is 36 px tall. The `InkWell` targets inside have `padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4)` — a tab only 24–28 px tall after padding, which is below the recommended 44 px touch/click target minimum. On desktop with mouse this is acceptable, but still sub-standard.
- The close button in `_FileTabStrip` is a raw `GestureDetector` wrapping a `16px Icon`. It has no ripple, no visual state, no tooltip. This is inconsistent with every other interactive element in the module.

#### Colour
- `AppTheme.success = NmtkNeurocnlTokens.success = 0xFF4ADE80` (bright Tailwind green-400).  
  `NmtkShellTokens.healthyColor = 0xFF22C55E` (Tailwind green-500).  
  These are close but not identical. The `_RunButton` uses `AppTheme.success` for its enabled background. The workspace switcher bar would use `healthyColor` if it displayed any status. Users won't notice until the two colours appear side-by-side in the deploy workspace.
- `AppTheme.error = NmtkNeurocnlTokens.error = 0xFFFF5C7A` (soft rose-pink).  
  `NmtkShellTokens.errorColor = 0xFFEF4444` (red-500).  
  These are _noticeably different_ — one is warm pink, one is pure red. The SnackBar error background in `_showMessage` uses `AppTheme.error`. If the shell's NmtkShellStatusBadge (which uses `errorColor`) is visible at the same time, users see two different reds for the same semantic state.
- `AppTheme.synNumber` is used as the value text colour in `_DurationSlider`. This re-purposes a syntax-highlight colour for a UI measurement value. It happens to look fine (warm orange), but it breaks the semantic layer — synNumber is for code tokens, not for UI numeric values.

#### Missing
- No empty-state variant for the editor pane when there are no open files.
- No keyboard shortcut indicators on any button in the toolbar.

---

## 2. Neurohub — Orchestration Dashboard

### What is working well

- Uses `NmtkTopAppBar` with destinations (Home/Projects/Workflows/System/Settings) — correct shell pattern.
- `NmtkWorkspaceSwitcherBar` is used correctly.
- `NmtkSurfaceCard`, `NmtkEmptyState`, `NmtkStatusBadge`, `NmtkPrimaryButton`, `NmtkOutlinedButton` all imported and used — the highest adoption of shared components across the suite.
- Activity feed is right-column — correct orchestration UI pattern.
- Responsive breakpoints for the search field (≥ 1100) and status badges (≥ 860) are reasonable.

### Problems found

#### Space used inefficiently
- `_SummaryTile` has a hardcoded `width: 180`. On 1400+ px displays, four tiles at 180 px fill ~780 px of a ~1400 px canvas leaving large unused margins. On ≤ 900 px, the tiles will Wrap to two rows and look undersized. A `Flex`-based approach or `ConstrainedBox(minWidth: 140, maxWidth: 220)` would scale better.
- `ActivityFeed` is constrained to `SizedBox(height: 420)` in `_UtilityPanel`. This is a magic number. If the activity list is short (1–3 items), 420 px is mostly empty. If the list is long, it overflows. `Flexible` or `Expanded` with a min-height is the correct pattern.
- The utility panel is `SizedBox(width: 360)`. The token `NmtkShellTokens.utilityPanelWidth` is 320 px. The code ignores the token and uses 40 px more. This should use `tokens.utilityPanelWidth`.
- `_ProjectGrid` uses `childAspectRatio: 1.02` — nearly square cards for project data. Project cards contain: name, status badge, description, member pills, tags, link indicators. A 1:1 aspect ratio forces long descriptions to truncate aggressively and makes the grid feel cramped vertically. An aspect ratio of 1.4–1.6 is more appropriate.

#### Colour
- `_ShellSearchField` sets `fillColor: Theme.of(context).colorScheme.surfaceContainerHighest` and `borderRadius: BorderRadius.circular(18)`. The 18 px radius is not a token (tokens define 12, 16, 22, 999). It falls between `radiusSm` (12) and `radiusMd` (16) — use 16.
- The dashboard does not apply `NmtkShellMode.studio` or `.instrument` anywhere. Everything is `command` mode. This is fine for NeuroHub (it is a command-mode app), but the token system offers three palette modes and none of the modules that _should_ be in studio or instrument mode are using it in their top app bars.

#### Inconsistencies vs neurocnl
- NeuroHub desktop breakpoint for two-column layout: **1180 px**.  
  neurocnl desktop breakpoint: **1024 px**.  
  NmtkWorkspaceShell (ui_core): **1080 px**.  
  These three values are in use simultaneously across the suite for the same concept ("switch to wide layout"). A user resizing a 1100 px wide window will see neurocnl go wide while NeuroHub stays stacked.
- NeuroHub milestone list in `_ActiveProjectOverview` uses raw `Row(Icon + Text + Text)` with hardcoded `size: 18` icon and no padding abstraction. This pattern is defined from scratch where `NmtkWorkflowCard` from ui_core exists for exactly this purpose.
- The project detail card subtitle reads: _"Project metadata and orchestration state remain separate from shell presentation."_ This is developer language, not user language. It leaked into production text.

---

## 3. Neurosense — Signal Acquisition Console

### What is working well

- Navigation destinations match the instrument workflow (Monitor, Config, Pipeline, Sessions).
- Desktop split between waveform (flex: 8) and controls (flex: 5) correctly prioritises the signal.

### Problems found

#### Space used inefficiently
- `SignalMonitorScreen` desktop layout wraps everything in `SingleChildScrollView > Column`. This means the signal viewer (`LiveSignalViewer(expandedHeight: 320)`) has a hardcoded height of 320 px regardless of available vertical space. On a 1440 × 900 desktop display, after the top bar (52 px), workspace bar (48 px), ReplayStatusSummary, SignalQualityBar, and SizedBox gaps, the waveform gets roughly 320 px. On a 1440 × 2560 monitor in split-screen, it still only gets 320 px. A signal acquisition console should let the waveform `Expand` to fill available space, not be fixed. The column-scroll approach is fundamentally wrong for a realtime instrument surface.
- `RecordingControls` and `SpikeEncodingPanel` both receive `compact: true` even on desktop layouts where there is a dedicated flex: 5 column. The compact flag was likely intended for mobile only, but it is passed unconditionally in the wide layout.

#### Colour / theme
- Neurosense uses `NmtkThemeVariant.neurosense` with seed `0xFFE11D48` (rose). This is also the `liveColor` in `NmtkShellTokens`. Using the module's accent colour as the same semantic colour for "recording/live" means the module's chrome and status indicators will visually bleed into each other — everything looks "live" even when nothing is recording.
- No instrument-mode palette (`NmtkShellMode.instrument`) is applied. Neurosense is the most natural candidate for instrument mode (dark, cyan/teal accent, high contrast), but the top app bar falls back to command mode styling.

#### Desktop guideline violations
- `ReplayStatusSummary` renders before `SignalQualityBar` before the waveform. On a realtime acquisition screen, the dominant element should be the waveform, with status strips as secondary chrome. The current ordering puts metadata (replay status) above signal data — the wrong priority for an instrument.
- The desktop layout has no persistent status strip showing: device connected state, sample rate, dropped frames, recording timer. These are always-visible elements in reference signal acquisition software (OpenBCI GUI, OpenSignals). They are currently absent from the screen chrome.

#### Inconsistency vs suite
- Desktop breakpoint: **1120 px** (unique to Neurosense — no other module uses this value).
- No module-level theme variant switch in the top app bar (`NmtkShellMode.instrument` not used anywhere).

---

## 4. Neurobench — Benchmark Lab

### What is working well

- Three-panel layout (catalog left / main center / utility right) matches W&B-style experiment tracking.
- `NmtkWorkspaceSwitcherBar` with badge counts on workspace chips is a strong pattern.
- Background run separation from UI (jobs persist across workspace changes) is architecturally sound.
- Uses `NmtkShellTokens.of(context).utilityPanelWidth` for the right utility panel — **correct**.

### Problems found

#### Hardcoded sizes
- Left catalog panel: `SizedBox(width: 300)`. Token `utilityPanelWidth` is 320. The catalog is 20 px narrower than the utility panel on the right — asymmetric without intent.
- Stacked layout catalog: `SizedBox(height: 240)` — magic number. The catalog could be any height.
- Stacked layout utility panel: `SizedBox(height: 700)` or `SizedBox(height: 620)` depending on the workspace — both are magic numbers that will break on shorter displays.
- Content padding: `EdgeInsets.all(20)` — the token `sectionGap` is 16. Other modules use 16. This 20 px inconsistency is small but pervasive.

#### Button style chaos
- `FilledButton.icon` is used for primary actions (Configure and run, Export CSV, Queue benchmark).
- `OutlinedButton.icon` is used for secondary actions.
- `NmtkPrimaryButton` / `NmtkOutlinedButton` from ui_core are NOT used.
This is the opposite of NeuroHub (which uses NmtkPrimaryButton / NmtkOutlinedButton) and the opposite of neurocnl (which uses ElevatedButton styled inline). Three modules, three different button patterns.

#### Colour
- `_BackgroundRunCardContent` uses `Theme.of(context).colorScheme.errorContainer`, `.secondaryContainer`, `.tertiaryContainer` as background colours for the job status container. These are generic Material 3 colours, not the semantic status colours from `NmtkShellTokens` (healthyColor, errorColor, warningColor, runningColor). A failed job uses `errorContainer` (light red in light theme, dark muted red in dark theme), while a running job uses `tertiaryContainer` — neither of which maps to the running colour (0xFF38BDF8 sky blue) the rest of the suite uses for running state.
- SnackBar for job completion: `SnackBar(content: Text(...))` with no `backgroundColor`. Uses default Material theme colour. In neurocnl, SnackBar has explicit `backgroundColor: AppTheme.error / AppTheme.success`. In NeuroBench they are unstyled.

#### Layout inefficiencies
- `_ComparisonWorkspace` has two `SizedBox(width: 260)` dropdowns in a Wrap — the fixed 260 px will truncate long result IDs on narrow right-panel widths.
- `_HeaderMetricChip` shows the latest run ID truncated to 12 characters in a chip-like container. This chip appears as the `trailing` of `NmtkSurfaceCard`, at the top-right of the card. It is easy to miss and the truncated ID (`abc12345678`) gives no useful scan-value. A status badge (passed/failed/score) would be more informative.
- `_PacketRow` displays raw full UUID IDs. A timestamp + short hash would be more scannable.
- `DropdownButton<BenchmarkResult>` (old Material 2 widget) is used in `_ComparisonResultSelector`. All other dropdowns in the codebase use `DropdownButtonFormField` (Material 3). This creates a style gap inside the same dialog.

#### Desktop guideline violations
- In the stacked layout, the utility panel is rendered _after_ the main pane and given a fixed height. This means it is always visible on scroll, not collapsible. On a tablet or small desktop, having a 700 px tall right panel stacked below the main content is unwieldy.

---

## 5. Neurosim — Visual Network Canvas

### What is working well

- Three-panel canvas + library sidebar + property panel is the correct node-editor pattern.
- Draggable panel dividers (14 px handle width) are the right desktop interaction.
- Node width 150 px / height 132 px gives enough room for labels and ports.
- Port hit tolerance 8 px and port radius 6 px are reasonable.

### Problems found

#### Panel sizing
- Library sidebar: `280px` default, min `220px`, max `520px`. Property panel: `320px` default, min `220px`, max `520px`. Min canvas width: `360px`. At minimum everything (220 + 220 + 360 = 800px) the layout is very cramped. At 800px, the canvas would be 360px — barely viable for a graph editor.
- No `NmtkShellTokens.utilityPanelWidth` is used. The 320 px property panel happens to equal the token value, but it's hardcoded.

#### Canvas interaction
- The canvas background, `canvasBackground`, uses the token (`NmtkShellTokens.canvasBackground = 0xFF0A0F1D dark / 0xFFFFFFFF light`). But there is no dot-grid or subtle reference grid visible on the canvas background — all professional node editors (Node-RED, KNIME, ComfyUI, Blender) show a reference grid that makes node placement intuitive. An entirely flat dark background gives no spatial reference.
- Node states are: selected, dragged. There is no visual vocabulary for: valid, warning, error, dirty, simulated. Adding even a 2 px coloured border on the node would bring this in line with the design system's `healthyColor / degradedColor / errorColor / runningColor` palette.

#### Theme
- Neurosim uses `NmtkThemeVariant.neurosim` (indigo seed `0xFF4338CA`). The studio palette accent is `0xFF8B5CF6` (violet). These are close but not the same — the module theme seed and the studio palette are misaligned.
- `themeMode: ThemeMode.dark` — correct.

#### Inconsistency vs suite
- Desktop breakpoint in Neurosim canvas layout: not apparent from surface code (uses LayoutBuilder with panel drag). But the snap behaviour at minimum widths doesn't tie to any suite breakpoint token.

---

## 6. Neurochip — Hardware Deployment

### Unique and critical problem: theme mode

- **Neurochip is the only module using `ThemeMode.system`** — every other module uses `ThemeMode.dark`. On a system with light OS appearance, Neurochip launches in light mode while all other modules (visible in the NMTK shell tabs) are dark. This is a jarring inconsistency when switching between modules.

### What is working well

- Multiple deployment surfaces (Akida / PYNQ / Teensy / Analysis / Compare / Gallery / History) reflect the real complexity of hardware target diversity.
- Deep-link support for Akida handoff from neurocnl is correctly wired.

### Problems found

#### Theme inconsistency
- Amber seed colour (`0xFFD97706`) for hardware deployment is semantically reasonable (amber = caution/hardware), but amber is also `NmtkShellTokens.degradedColor`. Hardware selection flow should not feel like "degraded state".
- Light mode support for Neurochip with amber accent will produce a very different look than the dark purple/indigo of the other modules. Buttons, cards, and borders will all shift.

#### Layout
- `Neurochip` has multiple deploy screens (`akida_deploy_screen`, `pynq_deploy_screen`, `teensy_deploy_screen`) each as separate full-screen routes. There is no persistent active-target chrome showing the currently selected hardware target while navigating between analysis, deploy, and history. The user has to navigate back to the target gallery to change targets.
- `deployment_log_screen.dart` is a standalone screen rather than a bottom-dock panel. Log output in a deployment cockpit should be visible alongside the deploy controls, not behind a route.

#### Space
- `target_gallery_screen` — not fully read, but based on agent findings, target cards in a gallery are separate routes rather than an in-context inspector. A hardware target comparison tool like Arduino IDE 2 would show specs side by side.

---

## 7. nmtk — Launcher Shell

### Problems found

#### Navigation
- The launcher uses `NmtkTopAppBar` + WebView tabs for workspace hosting. This is the weakest UI in the suite. There is no mission-control overview (as described in the existing redesign plan). The shell behaves like a module list + tabbed webview host.
- `module_tab_bar.dart`: 48 px height, module icon + name + close — this is functional but generic. The tab bar gives no visible signal about module health, run state, or active task.

#### Module picker
- `catalog.dart` / `module_picker_panel.dart` — flat install screens with no module detail pages. There is no "module profile" showing purpose, recent outputs, health, dependencies.

#### System diagnostics
- `python_setup.dart` exists but is a gate-screen (shown when Python is not ready), not a persistent diagnostics page. There is no always-accessible system diagnostics surface.

#### Overall
- The launcher is the weakest area of the suite. The other six modules are noticeably more developed. The launcher still behaves like a proof-of-concept wrapper.

---

## 8. nmtk_ui_core — Shared Design System

### What is good

- `NmtkShellTokens` defines a thorough layout metric vocabulary (heights, widths, radii, gaps, durations).
- Three shell mode palettes (command, studio, instrument) are defined and theoretically available.
- `NmtkTopAppBar`, `NmtkWorkspaceSwitcherBar`, `NmtkWorkspaceShell`, buttons, badges, cards, pipeline stepper are all present.
- `NmtkPipelineStepper` covers idle/running/success/error states.

### Problems found

#### Studio and instrument modes unused
- `studioPalette` (violet accent) and `instrumentPalette` (cyan accent) are defined in `NmtkShellTokens` but **no module passes `NmtkShellMode.studio` or `NmtkShellMode.instrument` to `NmtkTopAppBar`**. NeuroBench, Neurosense, and Neurosim all use `NmtkShellMode.command` or omit the parameter entirely. This means the three-mode design concept exists only on paper.

#### Font family gap
- The suite font is `Space Grotesk` applied via `_buildTextTheme`. But `Space Grotesk` is a static embedded font (pubspec.yaml), while `neurocnl` uses `GoogleFonts.inter`. `nmtk_ui_core` never loads `Inter` — if neurocnl's theme propagates into a shared widget from `nmtk_ui_core`, the widget renders in Inter because the context inherits neurocnl's ThemeData. But if a shared widget creates its own sub-theme or uses `Theme.of(context).textTheme` without inheriting the enclosing context's font, it falls back to the default.

#### Radius inconsistency
- Token radii: sm=12, md=16, lg=22, chip=999.
- Actual usage across modules: 8 (chip in neurocnl chipTheme), 10 (file tabs), 12, 14 (launcher action card), 18 (workspace frame, search field), 22 (summary tile), 24 (card), 28 (dialog).
- Values 8, 10, 14, and 18 are not in the token set. The design system defines 5 radii but 8 different values are in production.

#### Missing components
- **No bottom dock / output panel component.** The redesign plan calls for dockable output panes, but there is no `NmtkBottomDock` or `NmtkOutputPanel` in ui_core. Every module implements its own result display.
- **No split-pane component.** neurocnl implements its own `GestureDetector`-based split pane. Neurosim implements its own drag dividers. These are the same pattern but different code.
- **No log viewer component.** Deployment logs, simulation output, and benchmark traces are all custom per-module.
- **No empty state for loading** — `NmtkEmptyState` covers the "no data" case but there is no consistent loading skeleton pattern.

---

## Cross-Suite Inconsistencies (Consolidated)

### Breakpoint fragmentation

| Module | Desktop-layout breakpoint |
|--------|--------------------------|
| nmtk_ui_core `NmtkWorkspaceShell` | **1080 px** |
| neurocnl `StudioScreen` | **1024 px** |
| Neurohub `DashboardScreen` | **1180 px** |
| Neurohub `_ProjectGrid` 3-column | **1360 px** |
| Neurohub `_ProjectGrid` 2-column | **960 px** |
| Neurobench `WorkbenchShellScreen` | **1180 px** |
| Neurosense `SignalMonitorScreen` | **1120 px** |
| Neurosim canvas (panel drag) | N/A (drag-based) |

→ A user with a 1050 px window sees neurocnl wide but every other module stacked.  
→ A user with a 1100 px window sees neurocnl + Neurohub + Neurobench all stacked, but neurocnl is wide.

**Fix:** Define three breakpoints in `NmtkShellTokens`:
```
compactBreakpoint: 600   // mobile/single column  
normalBreakpoint: 1080   // standard desktop  
wideBreakpoint: 1280     // three-panel / full split  
```
All modules adopt these and nothing else.

---

### Typography split

| Module | Font family |
|--------|------------|
| neurocnl | **Inter** (Google Fonts, via `_buildInterTextTheme`) |
| All others | **Space Grotesk** (embedded, via `_buildTextTheme`) |

The two fonts are not interchangeable. Inter is a text-optimised font; Space Grotesk is geometric and display-oriented. In a desktop suite, mixing them in adjacent panels produces visible inconsistency.

**Fix:** Standardise on one font. The existing redesign plan recommends Space Grotesk for UI chrome + IBM Plex Mono / JetBrains Mono for code/data. neurocnl should use Space Grotesk for chrome and fall back to the monospace family only for the CNL editor area. Alternatively, standardise on Inter across the suite and deprecate Space Grotesk.

---

### Colour semantic split

Two incompatible success/error/warning colour sets exist:

| Semantic | NmtkNeurocnlTokens | NmtkShellTokens |
|----------|--------------------|-----------------|
| Success/Healthy | `0xFF4ADE80` (green-400) | `0xFF22C55E` (green-500) |
| Error | `0xFFFF5C7A` (rose-pink) | `0xFFEF4444` (red-500) |
| Warning | `0xFFFFB347` (amber-light) | `0xFFF59E0B` (amber-500) and `0xFFF97316` (orange-500) |
| Degraded | — (absent) | `0xFFF59E0B` |
| Running | — (absent) | `0xFF38BDF8` (sky-400) |
| Live/Recording | — (absent) | `0xFFE11D48` (rose-600) |

neurocnl uses the first set; every other module uses the second. In the NMTK shell with multiple modules running simultaneously, status signals use different colours for the same state.

**Fix:** neurocnl should adopt the `NmtkShellTokens` semantic colours for status (success, error, warning). Its purple identity only needs to be expressed in the accent, background, and syntax colours — not in the semantic status palette.

---

### Button pattern fragmentation

| Module | Primary action | Secondary action |
|--------|---------------|-----------------|
| neurocnl | `ElevatedButton` (styled inline) | `OutlinedButton` (styled inline) |
| Neurohub | `NmtkPrimaryButton` | `NmtkOutlinedButton` |
| Neurobench | `FilledButton` | `OutlinedButton` (unstyled) |
| Neurosense | (not seen in main screens) | — |
| Neurochip | (custom per screen) | — |

**Fix:** All modules should use `NmtkPrimaryButton` and `NmtkOutlinedButton` from ui_core for all standard CTA and secondary actions. Module-specific button styling (e.g. neurocnl's green run button) is the one legitimate exception and should be documented as such.

---

### Shell mode palette (unused)

`NmtkShellMode` defines three values (`.command`, `.studio`, `.instrument`) with associated accent/frame-tint palettes. No module actually uses `.studio` or `.instrument` when constructing its `NmtkTopAppBar`. The shell therefore looks identical across all modules when it should feel different between the launcher shell (command), CNL Studio (studio), and NeuroSense (instrument).

**Intended mapping:**
| Module | Correct mode |
|--------|-------------|
| nmtk launcher | `.command` |
| NeuroHub | `.command` |
| neurocnl | `.studio` |
| Neurosim | `.studio` |
| NeuroSense | `.instrument` |
| NeuroChip | `.instrument` |
| NeuroBench | `.command` |

---

### Theme mode split

| Module | ThemeMode |
|--------|----------|
| Neurochip | `ThemeMode.system` |
| All others | `ThemeMode.dark` |

Neurochip is the only module that respects OS appearance. On a light-mode macOS installation, Neurochip launches light while all tabs in the NMTK shell are dark.

---

### Utility panel width

| Location | Value |
|----------|-------|
| `NmtkShellTokens.utilityPanelWidth` | **320 px** |
| Neurohub `_UtilityPanel` | **360 px** (hardcoded — 40 px over token) |
| Neurobench utility panel | **320 px** (uses token correctly) |
| Neurobench catalog panel | **300 px** (hardcoded — 20 px under token) |

---

## Fix Plan

### Priority 1 — Critical consistency fixes (do these first)

These are small code changes with large visible impact.

#### P1-A: Standardise ThemeMode to dark
- Neurochip: change `ThemeMode.system` → `ThemeMode.dark`.
- Add a global settings preference for light/dark/system with a single switch in the nmtk launcher settings screen.
- **Effort:** 1 hour.

#### P1-B: Adopt NmtkShellMode in all top app bars
- neurocnl `StudioScreen`: pass `mode: NmtkShellMode.studio` to `NmtkTopAppBar`.
- Neurosim canvas screen: pass `mode: NmtkShellMode.studio`.
- Neurosense signal monitor: pass `mode: NmtkShellMode.instrument`.
- Neurochip deploy screens: pass `mode: NmtkShellMode.instrument`.
- NeuroBench workbench shell: current `NmtkShellMode.command` is correct. No change.
- **Effort:** 2 hours.

#### P1-C: Fix utility panel widths
- Neurohub `_UtilityPanel`: change `SizedBox(width: 360)` → `SizedBox(width: tokens.utilityPanelWidth)`.
- Neurobench catalog panel: change `SizedBox(width: 300)` → `SizedBox(width: tokens.utilityPanelWidth)`.
- **Effort:** 30 minutes.

#### P1-D: Unify status colours in neurocnl
- Replace `NmtkNeurocnlTokens.success` (0xFF4ADE80) in neurocnl UI widgets with `NmtkShellTokens.of(context).healthyColor`.
- Replace `NmtkNeurocnlTokens.error` (0xFFFF5C7A) in neurocnl UI status with `NmtkShellTokens.of(context).errorColor`.
- Keep the Dracula-inspired error pink only for the CNL editor diagnostics and the node/edge colour system — that is syntactic context, not status context.
- **Effort:** 2 hours.

#### P1-E: Standardise SnackBar styling
- Create a shared helper `NmtkSnackBars.success(context, message)` and `NmtkSnackBars.error(context, message)` in `nmtk_ui_core/lib/widgets/snack_bars.dart`.
- Both set the `backgroundColor` to `tokens.healthyColor` / `tokens.errorColor` respectively.
- Migrate neurocnl, Neurobench, and Neurohub to use these helpers.
- **Effort:** 2 hours.

---

### Priority 2 — Layout metric standardisation

#### P2-A: Define breakpoint tokens in NmtkShellTokens
Add to `NmtkShellTokens`:
```dart
static const double compactBreakpoint = 600;
static const double normalBreakpoint = 1080;
static const double wideBreakpoint = 1280;
```
Migrate all modules to these three values. Remove the scattered 1024, 1100, 1120, 1180, 1360 values.
- **Effort:** 4 hours (one module at a time).

#### P2-B: Fix Neurohub project grid aspect ratio
Change `childAspectRatio: 1.02` → `childAspectRatio: 1.5` or use `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 320, childAspectRatio: 1.5)`.
- **Effort:** 30 minutes.

#### P2-C: Fix ActivityFeed hardcoded height
Replace `SizedBox(height: 420, child: ActivityFeed())` with `Flexible(child: ActivityFeed())` inside a constrained parent, or `ConstrainedBox(constraints: BoxConstraints(minHeight: 240, maxHeight: 480))`.
- **Effort:** 1 hour.

#### P2-D: Fix Neurobench stacked-layout magic heights
Replace `SizedBox(height: 240)` for catalog and `SizedBox(height: 700/620)` for utility panel with `Flexible` or `ConstrainedBox` with sensible min/max.
- **Effort:** 1 hour.

#### P2-E: Fix Neurobench content padding
Change `EdgeInsets.all(20)` → `EdgeInsets.all(tokens.sectionGap)` (16 px).
- **Effort:** 15 minutes.

#### P2-F: Fix neurocnl drag handle
Replace the fixed `height: 72` visual indicator with a full-height transparent drag region (`expanded: true`) plus a subtle hover-state highlight (no persistent visible pill). Follow the JupyterLab pattern: invisible by default, shows a 2 px accent line on hover.
- **Effort:** 2 hours.

#### P2-G: Fix neurocnl file tab close button
Replace the raw `GestureDetector(Icon(Icons.close))` with `IconButton(icon: Icon(Icons.close), iconSize: 14, tooltip: 'Close', ...)`. Apply 32 px minimum touch target via `ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap)`.
- **Effort:** 30 minutes.

#### P2-H: Neurosense waveform expansion
Replace the fixed-height `Column` with an `Expanded` layout that gives the `LiveSignalViewer` a flex priority. Remove the `expandedHeight: 320` parameter from the desktop layout and let the viewer fill available space.
- **Effort:** 2 hours.

---

### Priority 3 — Typography unification

#### P3-A: Choose one body font family
**Option A (recommended):** Switch neurocnl from Inter to Space Grotesk. Update `_neurocnlDarkTheme` and `_neurocnlLightTheme` to use `_buildTextTheme` instead of `_buildInterTextTheme`. The CNL editor area still uses monospace (independent of theme).  
**Option B:** Switch all other modules to Inter by replacing `_buildTextTheme` with `_buildInterTextTheme` suite-wide.

The existing redesign plan already recommends Space Grotesk for headings/UI and IBM Plex Mono for code. Option A is consistent with that plan.

- **Effort:** 2 hours (Option A).

#### P3-B: Add monospace font asset
Add `JetBrains Mono` or `IBM Plex Mono` as a bundled font asset. Update `neurocnl`'s editor text style and any other code/numeric display areas to reference `fontFamily: 'JetBrainsMono'` (or similar) instead of the generic `'monospace'` fallback.
- **Effort:** 1 hour.

#### P3-C: Fix synNumber misuse
Replace `AppTheme.synNumber` as the colour for the duration slider value in `_DurationSlider` with `theme.colorScheme.primary` or a dedicated data-value colour token. `synNumber` should only appear in the CNL syntax highlighting layer.
- **Effort:** 15 minutes.

---

### Priority 4 — Button pattern unification

#### P4-A: Migrate neurocnl to NmtkPrimaryButton / NmtkOutlinedButton
The `OutlinedButton.icon` calls in `_buildHeaderActions` (Templates, Export) should become `NmtkOutlinedButton`. The `ElevatedButton.icon` run button is a special case (it uses success green) and is the one legitimate exception to the pattern — document it with a comment.
- **Effort:** 2 hours.

#### P4-B: Migrate Neurobench to NmtkPrimaryButton / NmtkOutlinedButton
Replace `FilledButton.icon` and `OutlinedButton.icon` in the workbench utility panel with `NmtkPrimaryButton` and `NmtkOutlinedButton`.
- **Effort:** 2 hours.

#### P4-C: Fix Neurobench DropdownButton
Replace `DropdownButton<BenchmarkResult>` in `_ComparisonResultSelector` with `DropdownButtonFormField<BenchmarkResult>` to match the Material 3 style used everywhere else.
- **Effort:** 30 minutes.

#### P4-D: Fix Neurobench background run card colours
Replace `Theme.of(context).colorScheme.errorContainer/secondaryContainer/tertiaryContainer` with `tokens.errorColor/healthyColor/runningColor` as container background colours (with appropriate alpha).
- **Effort:** 1 hour.

---

### Priority 5 — Component additions to nmtk_ui_core

These are larger additions that enable future consistency.

#### P5-A: Add NmtkSplitPane
A reusable horizontal split pane with draggable divider. Parameterised by initial ratio, min/max constraints, and divider appearance. Replace neurocnl's bespoke split implementation and Neurosim's drag dividers with this component.
- **Effort:** 4 hours.

#### P5-B: Add NmtkBottomDock
A resizable bottom panel that can be toggled (collapsed/partial/full). Used for simulation output, deployment logs, benchmark traces. This is the most impactful architectural addition for the studio and instrument modules.
- **Effort:** 6 hours.

#### P5-C: Add NmtkLogViewer
A scrollable log output widget with timestamp, level (info/warning/error), source, and message columns. Shared by neurocnl simulation output, Neurochip deployment logs, and NeuroBench background run output.
- **Effort:** 4 hours.

#### P5-D: Add NmtkStatusStrip
A persistent horizontal strip (40 px) for live instrument state: connected device, recording state, sample rate, elapsed time, frame drop count. Used by Neurosense above the waveform. Mirrors the Arduino IDE 2 bottom bar pattern.
- **Effort:** 3 hours.

---

### Priority 6 — Missing design system rules (document and enforce)

#### P6-A: Add radius usage table to CODING_STYLE_GUIDE.md
Document which radius to use where:
- `radiusSm (12)` — inline chips, tags, input fields
- `radiusMd (16)` — buttons, small cards, search fields
- `radiusLg (22)` — section cards, summary tiles, large containers
- `chip (999)` — pill-shaped status badges, info chips
- `28` — dialogs only (matches Material 3 default)
- No other radius values.

Eliminate current non-token radii: 8, 10, 14, 18 from production.

#### P6-B: Add NmtkShellMode assignment table to AGENTS.md
Each module AGENTS.md should specify the correct `NmtkShellMode` for its primary screen.

#### P6-C: Mark NmtkNeurocnlTokens status colours as syntax-only
Add documentation comment to `NmtkNeurocnlTokens.success/error/warning`:
```dart
/// Semantic status for CNL syntax diagnostics only.
/// For module-level status UI, use NmtkShellTokens.healthyColor / errorColor / warningColor.
```

---

## Neurochip-Specific Recommendations (Beyond Priority 1)

1. Add a persistent active-target chrome strip (40 px, below the top app bar) showing the currently selected hardware target name, compatibility icon, and change-target button. This is visible on all Neurochip screens, not just the gallery.
2. Move the deployment log from a standalone `deployment_log_screen.dart` route into an `NmtkBottomDock` panel visible on the deploy screens.
3. Change the module theme seed from amber (`0xFFD97706`) to something that doesn't collide with `degradedColor`. Cyan/teal (`0xFF0891B2`) would work for a hardware/instrument identity.

---

## Neurosense-Specific Recommendations (Beyond Priority 2-H)

1. Add `NmtkStatusStrip` at the top of `SignalMonitorScreen`, showing: device name, connection state dot, sample rate, recording duration timer, drop frame counter.
2. Change top app bar `mode` to `NmtkShellMode.instrument`.
3. Order screen content: status strip → waveform (Expanded) → controls row (fixed bottom). Remove `ReplayStatusSummary` from above the waveform; relocate it to a collapsible side panel or the status strip.
4. Change Neurosense theme seed from `0xFFE11D48` (rose/live) to `0xFF0891B2` (cyan — instrument mode accent) to avoid semantic collision with `liveColor`.

---

## Summary Table

| Issue | Module(s) | Severity | Fix Priority |
|-------|-----------|----------|-------------|
| ThemeMode.system vs dark | Neurochip | Critical | P1-A |
| Shell mode not applied | All | High | P1-B |
| Utility panel width ignores token | Neurohub | Medium | P1-C |
| Status colour split (success/error) | neurocnl vs suite | High | P1-D |
| SnackBar unstyled | Neurobench, Neurohub | Medium | P1-E |
| Breakpoint fragmentation (6 values) | All | High | P2-A |
| Project card aspect ratio ~1:1 | Neurohub | Medium | P2-B |
| ActivityFeed fixed height | Neurohub | Medium | P2-C |
| Stacked layout magic heights | Neurobench | Medium | P2-D |
| 20px content padding vs 16px token | Neurobench | Low | P2-E |
| Drag handle fixed height | neurocnl | Low | P2-F |
| File tab close button (no ripple, tiny) | neurocnl | Low | P2-G |
| Waveform fixed height 320px | Neurosense | High | P2-H |
| Inter vs Space Grotesk split | neurocnl vs all | High | P3-A |
| Generic monospace fallback in editor | neurocnl | Low | P3-B |
| synNumber used as UI value colour | neurocnl | Low | P3-C |
| Button pattern chaos (4 patterns) | All | High | P4-A–C |
| DropdownButton (M2) in M3 app | Neurobench | Medium | P4-C |
| Run card uses generic M3 tones | Neurobench | Medium | P4-D |
| No NmtkSplitPane shared component | All | Medium | P5-A |
| No NmtkBottomDock shared component | neurocnl, Neurochip | High | P5-B |
| No NmtkLogViewer shared component | neurocnl, Neurochip, Neurobench | Medium | P5-C |
| No NmtkStatusStrip shared component | Neurosense | High | P5-D |
| Non-token radii in production | All | Low | P6-A |
| Shell mode canvas background (no grid) | Neurosim | Medium | — |
| Neurochip theme seed = degraded colour | Neurochip | Medium | recommendation |
| Neurosense theme seed = live colour | Neurosense | Medium | recommendation |
| Persistent target chrome absent | Neurochip | High | recommendation |
| Launcher no mission-control view | nmtk | High | P5 (future) |
| Shadcn theme not defined | All | — | **Done — see §Shadcn** |

---

## Shadcn/UI Integration (addendum 2026-04-26)

### What was delivered

A new file `nmtk_ui_core/lib/shad_theme.dart` defines `NmtkShadTheme`, the
central Shadcn/UI theme for the entire suite. It is exported through the barrel
(`nmtk_ui_core.dart`) so every module accesses it via its existing
`nmtk_ui_core` import — no extra dependency in consumer pubspecs for the theme
types themselves.

`nmtk_ui_core/pubspec.yaml` gains `shadcn_ui: ^0.21.0`.

### Palette — "Indigo & Teal"

Zero `Colors.*` material-class references appear in `shad_theme.dart`. Every
colour is a plain `Color(0xFFRRGGBB)` hex literal expressed in the Shadcn
colour-token vocabulary (`background`, `foreground`, `primary`, `accent`, …).

| Token | Light value | Dark value | Rationale |
|-------|-------------|------------|-----------|
| `background` | `#FAFAFB` | `#0F0D1A` | Near-white / CNL studio surface |
| `foreground` | `#11052C` | `#F1EEF9` | Violet-tinted near-black / CNL textPrimary |
| `primary` | `#4F46E5` | `#818CF8` | Indigo-600 / Indigo-400 lifted for dark bg |
| `primaryForeground` | `#F5F3FF` | `#0F0D1A` | Pale indigo / dark for contrast |
| `secondary` | `#EEF2FF` | `#231E35` | Indigo-50 / CNL surfaceVariant |
| `accent` | `#14B8A6` | `#2DD4BF` | Teal-500 / Teal-400 — the "playful" pole |
| `accentForeground` | `#FFFFFF` | `#0F172A` | White / near-black on teal |
| `destructive` | `#DC2626` | `#EF4444` | Red-600 / matches `NmtkShellTokens.errorColor` |
| `border` | `#DDD6FE` | `#3D3560` | Violet-200 / CNL border |
| `ring` | `#4F46E5` | `#818CF8` | Focus ring = primary |

**Why indigo + teal?**
Indigo reads as "technical authority" without the generic quality of blue.
Teal is its warm-cool complement — different enough to pop as an accent, close
enough to remain harmonious. Together they express "playfessional": precise
and capable with a spark of personality.

### Border-radius override

`NmtkShadTheme` sets `radius: BorderRadius.circular(12)` on both light and dark
`ShadThemeData`.  The shadcn default is 8 px (matching the shadcn/web CSS
variable `--radius: 0.5rem`).  Our 12 px matches `NmtkDesignTokens.buttonShape`
and bridges the gap to the 16 px `NmtkShellTokens.radiusMd` used on most cards.

### How it relates to the existing Material 3 theme

`NmtkShadTheme` does not replace `AppTheme` (Material 3). Both coexist:

- **Material 3** (`AppTheme`) drives: Scaffold, AppBar, NavigationRail, every
  widget that calls `Theme.of(context)` — the bulk of the current UI.
- **Shadcn** (`NmtkShadTheme`) drives: Shadcn-specific components imported from
  `shadcn_ui` — buttons, inputs, dropdowns, command palette, etc. as they are
  adopted to replace the current raw Material widgets.

The two layers are wired together by switching from `MaterialApp` to
`ShadApp.material` in each module's `main.dart`.

### Module integration checklist

Each module needs two changes to activate Shadcn components:

**Step 1 — add `shadcn_ui` to the module's own pubspec:**
```yaml
# In <module>/frontend/pubspec.yaml
dependencies:
  shadcn_ui: ^0.21.0   # same version as nmtk_ui_core
```

**Step 2 — switch `MaterialApp` → `ShadApp.material` in `main.dart`:**
```dart
import 'package:nmtk_ui_core/nmtk_ui_core.dart'; // exports NmtkShadTheme, ShadApp

// Before
MaterialApp(
  themeMode: ThemeMode.dark,
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  ...
)

// After
ShadApp.material(
  themeMode: ThemeMode.dark,
  theme: NmtkShadTheme.light,
  darkTheme: NmtkShadTheme.dark,
  // Keep the Material 3 layer so existing widgets remain styled.
  materialThemeBuilder: (context, _) =>
      AppTheme.darkThemeForVariant(NmtkThemeVariant.neurocnl),
  ...
)
```

> **Module-specific variants:** Each module calls `materialThemeBuilder` with
> its own `NmtkThemeVariant`. The Shadcn palette is **shared across all
> modules** (the "Indigo & Teal" brand). Only the Material 3 layer carries
> per-module identity (indigo for neurocnl, teal for Neurohub, amber for
> Neurochip, etc.). This is the intended separation: Shadcn components look
> consistent suite-wide; native Material chrome reflects the module accent.

### Integration order recommendation

Migrate in the same order as the P4 button fixes so the first Shadcn components
introduced are the buttons — which fixes the button-pattern chaos (audit item
P4-A through P4-C) at the same time:

1. **nmtk_ui_core** — replace `NmtkPrimaryButton` / `NmtkOutlinedButton`
   internals to wrap `ShadButton` instead of `ElevatedButton` / `OutlinedButton`.
   This immediately propagates consistent button styling to every module that
   already uses `NmtkPrimaryButton`.
2. **Neurohub** — switch `main.dart` to `ShadApp.material`; already uses
   `NmtkPrimaryButton` / `NmtkOutlinedButton` so gains Shadcn buttons for free.
3. **neurocnl** — switch `main.dart`; replace inline `OutlinedButton` calls in
   `StudioScreen` with `NmtkOutlinedButton` (P4-A).
4. **Neurobench** — switch `main.dart`; replace `FilledButton` with
   `NmtkPrimaryButton` (P4-B).
5. **Neurosense / Neurochip / Neurosim** — switch `main.dart` each.
6. **nmtk launcher** — switch last; it has the most complex app setup.

### How Shadcn fixes specific audit issues

| Audit item | How Shadcn resolves it |
|------------|------------------------|
| Button pattern chaos (P4-A–C) | `ShadButton` via `NmtkPrimaryButton` wrapper unifies all 4 patterns behind one component |
| DropdownButton (M2) in Neurobench (P4-C) | Replace with `ShadSelect` — native Shadcn picker with M3-compatible styling |
| Non-token radii scattered across code (P6-A) | `NmtkShadTheme._kRadius` (12 px) propagates to all Shadcn components automatically; no per-widget radius overrides needed |
| Snackbar unstyled (P1-E) | Replace `ScaffoldMessenger.showSnackBar` with `ShadToast` for non-critical feedback; keep SnackBar only for persistent alerts |
| No command palette / search | `ShadCommand` provides a keyboard-accessible command palette — directly addresses the shell's missing quick-action surface |

### What Shadcn does NOT resolve (still needs explicit fixes)

These items from the original audit are not addressed by adopting Shadcn alone:

- ThemeMode inconsistency (P1-A) — Neurochip must still be changed to `.dark`.
- Shell mode palette usage (P1-B) — `NmtkShellMode.studio/.instrument` must still be passed to `NmtkTopAppBar`.
- Breakpoint fragmentation (P2-A) — layout breakpoints are not Shadcn concerns; still requires `NmtkShellTokens` additions.
- Typography split (P3-A) — `NmtkShadTheme` does not set a font family; that is still on the Material `AppTheme` layer.
- `NmtkBottomDock`, `NmtkSplitPane`, `NmtkLogViewer`, `NmtkStatusStrip` (P5) — structural layout components that must be built regardless of the component library.

### Files changed by this addendum

| File | Change |
|------|--------|
| `nmtk_ui_core/pubspec.yaml` | `shadcn_ui: ^0.21.0` added to `dependencies` |
| `nmtk_ui_core/lib/shad_theme.dart` | **New file** — `NmtkShadTheme` class |
| `nmtk_ui_core/lib/nmtk_ui_core.dart` | `shad_theme.dart` added to barrel export |
| `UI_AUDIT_AND_FIX_PLAN.md` | This addendum section |

---

## NmtkDesktopScaffold (addendum 2026-04-26)

### What was delivered

`nmtk_ui_core/lib/widgets/desktop_scaffold.dart` — a new shared layout widget
that gives every submodule the same structural chrome without duplicating code.
It is exported through the barrel alongside all other shared widgets.

### What the audit problem it directly solves

The audit identified that the suite uses **top-tab routing** (chip-based
destinations in `NmtkTopAppBar`) as the primary navigation pattern. This is a
web-first pattern that costs horizontal space on a desktop window and forces
module destinations to compete with each other across a single cramped row.

`NmtkDesktopScaffold` replaces that with a **left-hand sidebar** — the standard
desktop application navigation convention used by VS Code, Linear, Figma,
Docker Desktop, and every reference app cited in the audit.

### Layout anatomy

```
┌──────────────────────────────────────────────────────────────┐
│  [Brand]  │  [Page title]                [actions] [profile] │ 52 px header
├───────────┼──────────────────────────────────────────────────┤
│           │                                                  │
│  Sidebar  │   Content area (scheme.background)              │
│  scheme.  │                                                  │
│  card bg  │   ← child widget injected here →                │
│           │                                                  │
│  [nav 1]  │                                                  │
│  [nav 2]  │                                                  │
│  ───────  │                                                  │
│  [foot 1] │                                                  │
│  [toggle] │                                                  │
└───────────┴──────────────────────────────────────────────────┘
```

The sidebar animates between 220 px (expanded, icon + label) and 56 px
(collapsed, icon only) at 200 ms / `Curves.easeInOut`.

### Colour contract (all from `ShadTheme.of(context).colorScheme`)

| Surface | Token |
|---------|-------|
| Sidebar background | `scheme.card` — crisp white in light mode |
| Sidebar border | `scheme.border` — violet-200 tint |
| Header background | `scheme.card` |
| Header border | `scheme.border` |
| Content area | `scheme.background` — near-white, subtly darker than card |
| Active nav item fill | `scheme.primary` at 10 % alpha |
| Active nav icon/text | `scheme.primary` |
| Nav item hover | `scheme.muted` |
| Collapsed tooltip | `ShadTooltip` |
| Destructive profile actions | `scheme.destructive` |
| Avatar fallback background | `scheme.primary` / `scheme.primaryForeground` |

Zero `Colors.*` references appear in the file.

### Shadcn components used

| Component | Where |
|-----------|-------|
| `ShadTooltip` | Collapsed sidebar nav items; collapse-toggle button |
| `ShadBadge.secondary` | Nav item badge counts (unread / run count) |
| `ShadSeparator.horizontal` | Sidebar section dividers |
| `ShadAvatar` | User profile avatar in header |
| `ShadPopover` + `ShadPopoverController` | User profile dropdown |

### Public API surface

```dart
// Data models (all const-constructible)
NmtkSidebarItem({ id, label, icon, selectedIcon?, badgeCount? })
NmtkUserProfile({ displayName, email?, avatarUrl?, avatarFallback?, actions })
NmtkUserProfileAction({ label, icon?, onPressed?, isDestructive? })
NmtkUserProfileAction.divider()

// The scaffold
NmtkDesktopScaffold({
  pageTitle,
  navItems,           // List<NmtkSidebarItem>
  selectedIndex,
  child,              // ← page content injected here
  onNavItemSelected?,
  footerNavItems?,
  onFooterNavItemSelected?,
  headerActions?,     // Widget? (e.g. status badges, search field)
  userProfile?,       // NmtkUserProfile?
  sidebarBrand?,      // Widget? (custom logo)
  mode?,              // NmtkShellMode (default: command)
  initiallyExpanded?, // bool (default: true)
})
```

### Integration pattern for each module

Replace the module's top-level `Scaffold + NmtkTopAppBar` combination with
`NmtkDesktopScaffold`. The existing `NmtkShellMode` value passes through
unchanged (the scaffold carries it for consumers but doesn't use it internally
for colour decisions — those come from `NmtkShadTheme`).

```dart
// Before (in e.g. Neurohub DashboardScreen)
Scaffold(
  backgroundColor: NmtkShellTokens.of(context).shellBackground,
  appBar: NmtkTopAppBar(
    destinations: _destinations,
    selectedIndex: _index,
    onDestinationSelected: _onNav,
    mode: NmtkShellMode.command,
  ),
  body: Column(
    children: [
      NmtkWorkspaceSwitcherBar(...),
      Expanded(child: _body),
    ],
  ),
)

// After
NmtkDesktopScaffold(
  pageTitle: 'Command Center',
  navItems: const [
    NmtkSidebarItem(id: 'home',      label: 'Home',      icon: Icons.home_outlined,        selectedIcon: Icons.home_rounded),
    NmtkSidebarItem(id: 'projects',  label: 'Projects',  icon: Icons.folder_open_outlined, selectedIcon: Icons.folder_open_rounded),
    NmtkSidebarItem(id: 'workflows', label: 'Workflows', icon: Icons.alt_route_outlined),
    NmtkSidebarItem(id: 'system',    label: 'System',    icon: Icons.memory_outlined,      selectedIcon: Icons.memory_rounded),
  ],
  selectedIndex: _index,
  onNavItemSelected: (i) => setState(() => _index = i),
  mode: NmtkShellMode.command,
  userProfile: NmtkUserProfile(
    displayName: 'Yoshi M.',
    email: 'yoshi@response.nl',
    actions: [
      NmtkUserProfileAction(label: 'Settings', icon: Icons.settings_outlined, onPressed: _openSettings),
      const NmtkUserProfileAction.divider(),
      NmtkUserProfileAction(label: 'Sign out', icon: Icons.logout, isDestructive: true, onPressed: _signOut),
    ],
  ),
  child: _body,   // ← same body as before, no changes needed
)
```

The `NmtkWorkspaceSwitcherBar` can be placed inside `child` as a sticky top
element of the content area when workspace-level tab switching is still needed
within a module (e.g. NeuroBench's Summary / Comparison / Reports tabs become
workspace chips inside the content area, not the top nav).

### Sidebar vs NmtkTopAppBar coexistence

`NmtkTopAppBar` is **not removed** — it remains available for modules that embed
inside the NMTK launcher WebView (where the launcher shell provides the outer
chrome). `NmtkDesktopScaffold` is used when a module runs as a standalone
desktop app or is the top-level screen of a module opened from the launcher.

### Files changed by this addendum

| File | Change |
|------|--------|
| `nmtk_ui_core/lib/widgets/desktop_scaffold.dart` | **New file** — `NmtkDesktopScaffold` and all supporting types |
| `nmtk_ui_core/lib/nmtk_ui_core.dart` | `desktop_scaffold.dart` added to barrel export |
| `UI_AUDIT_AND_FIX_PLAN.md` | This addendum section |

---

## Phase M: Playfessional Material Migration (addendum 2026-04-26)

> **Integrates with audit priorities:** This phase supersedes P4-A through P4-D
> (button chaos, dropdown style, run card tones) and P1-E (SnackBar styling).
> It complements but does not replace P1-A (ThemeMode), P1-B (ShellMode),
> P1-C/D (token colour fixes), P2-A (breakpoints), P3-A (typography), and
> P5 (missing shared components) — those remain as independent tasks.

### What this phase covers

Strip default Flutter Material shell widgets from every module and replace them
with Shadcn-native equivalents sourced from the shared `nmtk_ui_core` package.
Goal: a unified "playfessional" desktop experience — every module uses the same
scaffold, the same interaction components, and the same generous spacing rules.

---

### §M.1 — Widget replacement dictionary

This table is the canonical reference. Every developer executing a wave follows
it without exception. Any deviation requires a new ADR.

#### Replace

| Remove | Replace with | Notes |
|--------|-------------|-------|
| `MaterialApp(...)` | `ShadApp.material(...)` | Keep all existing params; add `theme:` / `darkTheme:` from `NmtkShadTheme` |
| `MaterialApp.router(...)` | `ShadApp.material.router(...)` | Same; pass `routerConfig:` through unchanged |
| `Scaffold(appBar: ..., body: ...)` (root) | `NmtkDesktopScaffold(...)` | Per-screen Scaffolds that are root views only |
| `Scaffold(body: ...)` (sub-view) | Remove scaffold; content becomes bare widget | Sub-views are passed as `child` to the app-level `NmtkDesktopScaffold` |
| `AppBar(...)` | Remove | `NmtkDesktopScaffold` header replaces it |
| `NmtkTopAppBar(...)` (in app.dart) | `NmtkDesktopScaffold` sidebar + headerActions | The destination chips become `navItems:` |
| `ElevatedButton(...)` | `ShadButton(...)` | Default filled variant |
| `ElevatedButton.icon(...)` | `ShadButton(icon: Icon(...), child: Text(...))` | |
| `FilledButton(...)` | `ShadButton(...)` | |
| `FilledButton.icon(...)` | `ShadButton(icon: Icon(...), child: Text(...))` | |
| `OutlinedButton(...)` | `ShadButton.outline(...)` | |
| `OutlinedButton.icon(...)` | `ShadButton.outline(icon: Icon(...), child: Text(...))` | |
| `TextButton(...)` | `ShadButton.ghost(...)` | |
| `TextField(...)` | `ShadInput(...)` | Wrap in `Column(crossAxisAlignment: start, [ShadLabel(...), ShadInput(...)])` for labels |
| `TextFormField(...)` | `ShadInput(...)` inside `ShadFormBuilderField` | Or keep `Form` key; replace widget only |
| `Card(...)` | `ShadCard(...)` | |
| `NmtkSurfaceCard(...)` | `ShadCard(...)` | Migrate gradually; NmtkSurfaceCard wrapper logic can move into content |
| `ListTile(...)` | Inline `Row` inside `ShadCard` | No direct shadcn equivalent |
| `DropdownButtonFormField(...)` | `ShadSelect(...)` + `ShadOption(...)` items | |
| `DropdownButton(...)` | `ShadSelect(...)` | |
| `AlertDialog(...)` | `ShadDialog(...)` | |
| `showDialog(builder: AlertDialog)` | `showShadDialog(context, builder: ShadDialog)` | |
| `SnackBar(...)` via `ScaffoldMessenger` | `ShadToast(...)` via `ShadToaster.of(context)` | Requires `ShadToaster()` in app widget tree |
| `Chip(...)` | `ShadBadge(...)` | |
| `Divider()` / `VerticalDivider()` | `ShadSeparator.horizontal()` / `ShadSeparator.vertical()` | |
| `Tooltip(message: ..., child: ...)` | `ShadTooltip(builder: (ctx) => Text(...), child: ...)` | |
| `LinearProgressIndicator(...)` | `ShadProgress(...)` | |
| `CircularProgressIndicator()` (full-page) | `ShadProgress(...)` or `ShadSkeleton()` | |
| `Checkbox(...)` | `ShadCheckbox(...)` | |
| `Switch(...)` | `ShadSwitch(...)` | |
| `Slider(...)` | `ShadSlider(...)` | |

#### Do NOT replace

These widgets are layout/animation primitives or have no Shadcn equivalent.
Leave them exactly as-is.

| Keep | Reason |
|------|--------|
| `Row`, `Column`, `Stack`, `Expanded`, `Flexible`, `Spacer` | Flutter layout — no Shadcn equivalent |
| `SizedBox`, `Padding`, `Center`, `Align`, `ConstrainedBox` | Spacing/layout — no Shadcn equivalent |
| `SingleChildScrollView`, `ListView`, `GridView`, `CustomScrollView` | Scrolling — no Shadcn equivalent |
| `LayoutBuilder`, `Builder`, `AnimatedBuilder` | Build helpers |
| `AnimatedContainer`, `AnimatedOpacity`, `TweenAnimationBuilder` | Animation — no Shadcn equivalent |
| `GestureDetector`, `MouseRegion`, `InkWell` (complex gestures) | Custom interaction handling |
| `CustomPaint` | Charts, canvases, spike rasters, network graphs — untouchable |
| `NavigationRail` | Replaced by `NmtkDesktopScaffold` sidebar, not directly by a Shadcn widget |
| `SafeArea` | Platform safety — keep where present |
| `Form` + `GlobalKey<FormState>` | Validation infrastructure; replace only the leaf widgets |
| `WebView`, `HtmlElementView` | No Shadcn equivalent |
| `NmtkPipelineStepper` | Complex shared component; no Shadcn equivalent |
| `NmtkWorkspaceSwitcherBar` | Keep; moves to content area inside `child` |
| `NmtkStatusBadge`, `NmtkShellStatusBadge` | Keep; use for live status signals |
| `NmtkEmptyState` | Keep |
| `NmtkPrimaryButton`, `NmtkOutlinedButton` | Phase out gradually; direct callers use `ShadButton` |
| `CircularProgressIndicator` (inline spinner) | Keep for button loading states |

---

### §M.2 — Padding standardisation

All padding values in migrated screens follow this rule set:

| Context | Value | Dart constant |
|---------|-------|---------------|
| Page-level content area (the `child` of `NmtkDesktopScaffold`) | `EdgeInsets.all(24)` | `_kPagePad` |
| Major section gap (between `ShadCard` blocks) | `SizedBox(height: 24)` | — |
| Within a `ShadCard` (content padding) | `EdgeInsets.all(24)` or `EdgeInsets.all(32)` for prominent cards | `ShadCard(padding: ...)` |
| Dense instrument panels (NeuroSense monitor, neurocnl editor chrome) | `EdgeInsets.all(16)` | exception, document in code comment |
| Inline element gap (icon → label, badge → text) | `8` or `12` | unchanged |
| Form field gap | `SizedBox(height: 16)` | — |

> **Exception:** neurocnl `StudioScreen` uses 12 px outer padding intentionally
> (IDE-style compactness). Mark with `// studio-compact` comment and do not
> upgrade to 24 px.

---

### §M.3 — App-level integration pattern

Every module `app.dart` follows this template after migration.

```dart
// ── Before (all modules) ──────────────────────────────────────────────────
MaterialApp(
  theme:     AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: ThemeMode.dark,
  home:      _buildHome(...),
)

// ── After ────────────────────────────────────────────────────────────────────
ShadApp.material(
  // Shadcn layer — controls Shadcn components
  theme:     NmtkShadTheme.light,
  darkTheme: NmtkShadTheme.dark,
  // Material layer — controls native Flutter widgets  
  materialThemeBuilder: (_, __) =>
      AppTheme.darkThemeForVariant(NmtkThemeVariant.myVariant),
  themeMode: ThemeMode.dark,
  home: _buildHome(...),   // unchanged
)
```

The `_buildHome()` method itself changes: screens no longer return a `Scaffold`.
Instead, the app wraps the entire home in `NmtkDesktopScaffold` once:

```dart
// Pattern A — workspace controller apps (NeuroHub, NeuroSense, Neurochip)
// app.dart _buildHome returns:
NmtkDesktopScaffold(
  pageTitle:    _pageTitle(routeState),     // computed from current route target
  navItems:     _kNavItems,                 // const list defined at top of file
  selectedIndex: _indexForTarget(routeState.target),
  onNavItemSelected: _selectIndex,
  headerActions: _buildStatusBadges(...),   // live badges from provider state
  userProfile:   _kUserProfile,
  mode:          NmtkShellMode.instrument,  // or .command, .studio per module
  child:         _buildScreen(routeState.target),  // content widget — no Scaffold
)

// Pattern B — GoRouter apps (NeuroBench)
// GoRouter routes return content-only widgets; the NmtkDesktopScaffold lives
// at the app level wrapping the router's Navigator:
ShadApp.material.router(
  routerConfig: router,
  builder: (context, child) => NmtkDesktopScaffold(
    pageTitle:     _pageTitle(context),
    navItems:      _kNavItems,
    selectedIndex: _selectedIndex(context),
    onNavItemSelected: (i) => context.go(_routeForIndex(i)),
    child: child ?? const SizedBox.shrink(),
  ),
)
```

**`showShellChrome: false` handling** (NeuroBench, NeuroSense — embedded mode):

```dart
// When the module is embedded in the NMTK launcher WebView, showShellChrome
// is false. The scaffold is skipped entirely.
showShellChrome
  ? NmtkDesktopScaffold(navItems: ..., child: content)
  : content   // bare content widget, no chrome
```

**ShadToaster placement** — add once at the outermost app level:

```dart
ShadApp.material(
  ...
  home: Stack(
    children: [
      _buildHome(...),
      const Align(
        alignment: Alignment.bottomRight,
        child: ShadToaster(),
      ),
    ],
  ),
)
```

---

### §M.4 — Module migration order and rationale

Modules are migrated in waves. Each wave is independently shippable and tested
before the next begins. Later waves benefit from patterns established earlier.

| Wave | Module | Rationale |
|------|--------|-----------|
| 0 | `nmtk_ui_core` | Shared prep — enables all subsequent waves |
| 1 | `Neurohub` | Highest shared-component adoption; simplest app.dart to migrate |
| 2 | `Neurobench` | GoRouter pattern establishes Pattern B for later modules |
| 3 | `Neurosense` | Instrument-mode pattern; live-status-badge integration into headerActions |
| 4 | `Neurochip` | Similar to NeuroSense; hardware-deployment context |
| 5 | `neurocnl` | Most mature module; most custom widgets; studio-mode exception rules |
| 6 | `Neurosim` | Canvas is untouchable; only chrome migrates |
| 7 | `nmtk` launcher | Last; most complex WebView/embedding integration |

---

### §M.5 — Wave 0: Shared package preparation

**Owner:** `nmtk_ui_core`  
**Read first:** `nmtk_ui_core/AGENTS.md`  
**Unlock:** All subsequent waves depend on this being merged first.

#### Tasks

**W0-1 · Upgrade `NmtkPrimaryButton` / `NmtkOutlinedButton` internals**

In `nmtk_ui_core/lib/widgets/buttons.dart`, replace the `ElevatedButton` /
`OutlinedButton` internals with `ShadButton` / `ShadButton.outline`.
The public API stays identical — callers require no changes.

```dart
// buttons.dart — NmtkPrimaryButton.build() after
import 'package:shadcn_ui/shadcn_ui.dart';

@override
Widget build(BuildContext context) {
  final shadScheme = ShadTheme.of(context).colorScheme;
  // tone → Shadcn colour mapping  ...
  return icon != null
      ? ShadButton(icon: Icon(icon, size: 18), child: Text(label), onPressed: onPressed)
      : ShadButton(child: Text(label), onPressed: onPressed);
}
```

This immediately propagates consistent button styling to NeuroHub (the only
current module that already uses `NmtkPrimaryButton`) before Wave 1 begins.

**W0-2 · Add `NmtkSnackBars` → `NmtkToasts` helper**

Replace the `NmtkSnackBars` spec from audit P1-E with a `NmtkToasts` helper
that wraps `ShadToaster`:

```dart
// nmtk_ui_core/lib/widgets/toasts.dart
import 'package:shadcn_ui/shadcn_ui.dart';

abstract class NmtkToasts {
  static void success(BuildContext context, String message) {
    ShadToaster.of(context).show(
      ShadToast(description: Text(message)),
    );
  }
  static void error(BuildContext context, String message) {
    ShadToaster.of(context).show(
      ShadToast.destructive(description: Text(message)),
    );
  }
}
```

Export `toasts.dart` from the barrel.

**W0-3 · Add `shadcn_ui` to all module pubspecs**

Add `shadcn_ui: ^0.21.0` to:
- `Neurohub/frontend/pubspec.yaml`
- `Neurobench/frontend/pubspec.yaml`
- `Neurosense/frontend/pubspec.yaml`
- `Neurochip/frontend/pubspec.yaml`
- `neurocnl/frontend/pubspec.yaml`
- `Neurosim/frontend/pubspec.yaml`
- `nmtk/neuro_toolkit/pubspec.yaml`

**W0-4 · Run `flutter test` in `nmtk_ui_core`**

Ensure all existing widget tests pass before any module work begins.

---

### §M.6 — Wave 1: NeuroHub

**Owner:** `Neurohub/frontend/`  
**Read first:** `Neurohub/AGENTS.md`  
**Depends on:** Wave 0 merged.

#### Architecture change

NeuroHub uses `MaterialApp` with a workspace controller. The `NmtkDesktopScaffold`
lives in `app.dart`, wrapping the return value of `_buildHome()`.
Individual screens (`DashboardScreen`, `ProjectDetailScreen`, etc.) strip their
`Scaffold` + `NmtkTopAppBar` and become pure content widgets.

#### File-by-file tasks

**`Neurohub/frontend/lib/app.dart`**

1. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme.light` / `.dark`.
2. Add `ShadToaster()` to the widget tree (wrap `_buildHome` in a `Stack`).
3. Introduce `NmtkDesktopScaffold` wrapping the result of `_buildHome()`:
   - `navItems:` replaces the `_destinations` list in `DashboardScreen`.
   - `selectedIndex:` derived from `routeState.section` → integer mapping.
   - `onNavItemSelected:` calls `_workspaceController.selectShellSection(...)`.
   - `pageTitle:` derived from current route target (e.g. `'Projects'`, `'${project.name}'`).
   - `userProfile:` optional; wire to auth provider if available.

**`Neurohub/frontend/lib/screens/dashboard_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`, `NmtkWorkspaceSwitcherBar`.
- Remove nav destination list (moved to `app.dart`).
- Keep `Column([_OverviewStrip, SizedBox(16), NmtkSurfaceCard, ...])` content intact.
- Replace `_SummaryTile` container with `ShadCard`.
- `_ShellSearchField` `TextField` → `ShadInput`.
- Padding on `Padding(EdgeInsets.all(16))` → `EdgeInsets.all(24)`.
- `_UtilityPanel` `SizedBox(width: 360)` → `SizedBox(width: tokens.utilityPanelWidth)` (fixes audit P1-C).

**`Neurohub/frontend/lib/screens/project_detail_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar` (app-level scaffold handles chrome).
- The back-navigation chip is replaced: `pageTitle` in the app-level scaffold
  shows `'${project.name}'`; `headerActions` slot receives a back button:
  `ShadButton.ghost(onPressed: onBack, child: Row([Icon(Icons.chevron_left), Text('Projects')]))`.
- Content becomes a `SingleChildScrollView(padding: EdgeInsets.all(24), ...)` returning the existing card stack.
- `NmtkSurfaceCard` blocks → migrate innermost manually-built containers to `ShadCard`; keep shared `NmtkSurfaceCard` for now.

**`Neurohub/frontend/lib/screens/new_project_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- `TextFormField(controller: _nameController, ...)` → `ShadInput(controller: _nameController, placeholder: Text('Project name'), ...)`.
- `TextFormField(controller: _descriptionController, ...)` → `ShadInput(controller: _descriptionController, maxLines: 4, ...)`.
- Wrap each `ShadInput` in `Column([ShadLabel(child: Text('Project Name')), ShadInput(...)])`.
- `ElevatedButton('Create Project')` → `ShadButton(child: Text('Create Project'))`.
- `OutlinedButton('Cancel')` → `ShadButton.outline(child: Text('Cancel'))`.
- `ScaffoldMessenger.showSnackBar(SnackBar(...))` → `NmtkToasts.success(context, 'Project created')` / `NmtkToasts.error(context, ...)`.
- Padding: `EdgeInsets.all(24)` on content container.
- `Form` + `GlobalKey<FormState>` — keep; validation stays.

**`Neurohub/frontend/lib/screens/workflow_editor_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Any `ElevatedButton` / `OutlinedButton` → `ShadButton` / `ShadButton.outline`.
- Any `SnackBar` → `NmtkToasts`.
- Content padding → 24 px.

**`Neurohub/frontend/lib/screens/workflow_run_screen.dart`**

- Same pattern as workflow_editor_screen.

**`Neurohub/frontend/lib/screens/bundle_inspection_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Content padding → 24 px.

**`Neurohub/frontend/lib/screens/orchestration_controls_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Content padding → 24 px.

**`Neurohub/frontend/lib/screens/settings_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- `TextField` inputs → `ShadInput`.
- `Switch` → `ShadSwitch` (if present).
- Content padding → 24 px.

**`Neurohub/frontend/lib/screens/login_screen.dart`**

- Login is a special case: shown before `NmtkDesktopScaffold`. Keep its own
  `Scaffold` but migrate to `ShadCard` + `ShadInput` + `ShadButton` visually.
- This screen is fullscreen before auth — it doesn't need the sidebar.

**`Neurohub/frontend/lib/widgets/project_card.dart`**

- `NmtkSurfaceCard` — keep for now.
- If any inline `Container` / `Card` → `ShadCard`.

**`Neurohub/frontend/lib/widgets/activity_feed.dart`**

- `SizedBox(height: 420)` → `Flexible(child: ...)` or `ConstrainedBox(constraints: BoxConstraints(minHeight: 240, maxHeight: 480))` (fixes audit P2-C).

#### Verify

```
flutter test Neurohub/frontend/
flutter analyze Neurohub/frontend/
```

Manually verify in running app: sidebar visible, page title updates on nav, profile dropdown works, project form validates and toasts on success/error.

---

### §M.7 — Wave 2: NeuroBench

**Owner:** `Neurobench/frontend/`  
**Read first:** `Neurobench/AGENTS.md`  
**Depends on:** Wave 0 merged.

#### Architecture change

NeuroBench uses `MaterialApp.router` + GoRouter. Apply Pattern B:
`NmtkDesktopScaffold` wraps the router's output via `ShadApp.material.router`'s
`builder:` parameter.

#### File-by-file tasks

**`Neurobench/frontend/lib/app.dart`**

1. `MaterialApp.router(routerConfig: router)` → `ShadApp.material.router(routerConfig: router, builder: (context, child) => ...)`.
2. Add `NmtkDesktopScaffold` in the `builder:` callback.
3. Sidebar items: Summary / Comparison / Reports / Robustness.
4. `selectedIndex` reads current `GoRouterState.of(context).uri` → maps to index.
5. `onNavItemSelected` calls `context.go(_routeForIndex(i))`.
6. Add `ShadToaster()` in the stack.

**`Neurobench/frontend/lib/screens/workbench_shell.dart`**

- Remove `Scaffold`, `NmtkTopAppBar` (the scaffold now lives in `app.dart`).
- Remove `_WorkbenchSwitcherBar` from the `body:` Column — move it to the
  top of `_buildMainPane()` as a sticky strip inside the content area.
- Remove `showShellChrome` guard around `NmtkTopAppBar` / `NmtkWorkspaceSwitcherBar`
  (the guard now lives in `app.dart`'s `builder:` callback).
- Content: keep `Padding(EdgeInsets.all(20))` → upgrade to `EdgeInsets.all(24)` (fixes audit P2-E).
- The content structure (three-column `Row`) stays intact.

**Widget replacements within `workbench_shell.dart`**

- `FilledButton.icon(onPressed: ..., child: Text('Configure and run'))` → `ShadButton(icon: ..., child: Text('Configure and run'))`.
- `OutlinedButton.icon` (Cancel, Compare, Reports, Sweeps) → `ShadButton.outline(icon: ..., child: ...)`.
- `DropdownButton<BenchmarkResult>` in `_ComparisonResultSelector` → `ShadSelect<BenchmarkResult>(...)` + `ShadOption` items (fixes audit P4-C).
- `AlertDialog` in `_BenchmarkRunSetupDialog` → `ShadDialog(...)`.
- `SnackBar` (3 occurrences) → `NmtkToasts.success` / `NmtkToasts.error`.
- `LinearProgressIndicator()` in `_ComparisonResultSelector` → `ShadProgress()`.
- `_BackgroundRunCardContent` job status container: replace `Theme.of(context).colorScheme.errorContainer/.secondaryContainer/.tertiaryContainer` with `ShadTheme.of(context).colorScheme.destructive / primary / accent` at 15% alpha (fixes audit P4-D).
- `TextField` in `_BenchmarkRunSetupDialog` (`NetworkPath`, `Seed`, `Params JSON`) → `ShadInput`.
- `DropdownButtonFormField<String>` (Target dropdown) → `ShadSelect<String>`.
- `_SelectionBadge` inline container → `ShadCard(padding: EdgeInsets.all(12), ...)`.
- Padding on `_WorkbenchUtilityPanel` card gap: `SizedBox(height: 16)` → `SizedBox(height: 24)`.

**`Neurobench/frontend/lib/screens/comparison_screen.dart`** / **`report_screen.dart`** / **`robustness_screen.dart`** / **`regression_trends_screen.dart`**

- Remove any per-screen `Scaffold` / `AppBar` if present.
- Apply 24 px page padding.
- Any `ElevatedButton` / `OutlinedButton` → `ShadButton`.

#### Verify

```
flutter test Neurobench/frontend/
```

Manually verify: sidebar routes between workspaces, benchmark setup dialog opens as `ShadDialog`, comparison dropdown uses `ShadSelect`, job status card uses theme colours.

---

### §M.8 — Wave 3: NeuroSense

**Owner:** `Neurosense/frontend/`  
**Read first:** `Neurosense/AGENTS.md`  
**Depends on:** Wave 0 merged.

#### Architecture change

NeuroSense's `app.dart` is the most complex in the suite — it builds the entire
layout including a `Scaffold > Column[NmtkTopAppBar, NmtkWorkspaceSwitcherBar, Expanded(content)]`
**with live status badges computed from provider state**. The migration extracts
this layout into `NmtkDesktopScaffold`.

The live status badges (`connectedDevice`, `isRecording`, `streamState`,
`replayingSessionId`) move to `headerActions` of `NmtkDesktopScaffold`, since
they are computed in `app.dart` where providers are already watched.

#### File-by-file tasks

**`Neurosense/frontend/lib/app.dart`**

1. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme`.
2. Remove inner `Scaffold > SafeArea > Column[NmtkTopAppBar, NmtkWorkspaceSwitcherBar, Expanded]` block.
3. Replace with `NmtkDesktopScaffold`:
   - `navItems:` = the 4 `_destinations` items as `NmtkSidebarItem` list.
   - `selectedIndex:` = `_indexForTarget(_workspaceController.routeState.target)`.
   - `onNavItemSelected:` = `_selectIndex`.
   - `mode:` = `NmtkShellMode.instrument` (fixes audit P1-B).
   - `headerActions:` = `_buildStatusBadges(deviceState, recordingState, streamState, sessionsState)` — a `Wrap(spacing: 8, ...)` of `NmtkStatusBadge` / `NmtkShellStatusBadge` widgets.
   - `child:` = `_buildScreen(routeState.target)` — no Scaffold inside.
4. The `showShellChrome: false` guard: `showShellChrome ? NmtkDesktopScaffold(...) : _buildScreen(routeState.target)`.
5. The `ConstrainedBox(maxWidth: 1480)` + `Container(padding: EdgeInsets.all(20))` wrapping the screen content: upgrade padding to `EdgeInsets.all(24)` (fixes audit P2-E).
6. Add `ShadToaster()` to widget tree.

**`Neurosense/frontend/lib/screens/signal_monitor_screen.dart`**

- No Scaffold to remove (it had none — it's already a content widget).
- Replace `SingleChildScrollView > Column` root with `Expanded`-based layout
  so `LiveSignalViewer` fills available height (fixes audit P2-H).
  New structure: `Column(children: [ReplayStatusSummary, SignalQualityBar, Expanded(child: LiveSignalViewer()), RecordingControls, SpikeEncodingPanel])`.
- The `expandedHeight: 320` param on `LiveSignalViewer` is removed; it expands via `Expanded`.
- Compact flags removed from the desktop layout; `RecordingControls(compact: false)` etc.

**`Neurosense/frontend/lib/screens/device_config_screen.dart`**

- No Scaffold.
- Wrap content in `Padding(EdgeInsets.all(24))`.
- Any `ElevatedButton` / `OutlinedButton` → `ShadButton`.

**`Neurosense/frontend/lib/screens/filter_pipeline_screen.dart`**

- No Scaffold.
- Content padding → 24 px.

**`Neurosense/frontend/lib/screens/sessions_screen.dart`**

- No Scaffold.
- Content padding → 24 px.
- Any `ElevatedButton` / `OutlinedButton` → `ShadButton`.
- `SnackBar` → `NmtkToasts`.

**`Neurosense/frontend/lib/widgets/export_dialog.dart`**

- `AlertDialog` → `ShadDialog`.

#### Verify

```
flutter test Neurosense/frontend/
```

Manually verify: live status badges appear in header, sidebar navigates correctly, waveform `Expanded` fills screen height, `showShellChrome: false` path shows bare screen with no sidebar.

---

### §M.9 — Wave 4: NeuroChip

**Owner:** `Neurochip/frontend/`  
**Read first:** `Neurochip/AGENTS.md`  
**Depends on:** Wave 0, Wave 3 (instrument-mode pattern established).

#### Architecture change

Similar to NeuroSense (workspace controller). Apply Pattern A from §M.3.  
The active-target chrome (currently absent — audit recommendation) is introduced
here as a `headerActions` strip showing the currently selected hardware target.

#### File-by-file tasks

**`Neurochip/frontend/lib/app.dart`**

1. `ThemeMode.system` → `ThemeMode.dark` (fixes critical audit item P1-A).
2. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme`.
3. Add `NmtkDesktopScaffold`:
   - `navItems:` = deployStatus / artifacts / targets / analysis / compare / history items.
   - `mode:` = `NmtkShellMode.instrument`.
   - `headerActions:` = active-target badge `NmtkStatusBadge(label: _activeTargetName, icon: ...)`.
   - `footerNavItems:` = troubleshooting / settings items.
4. Add `ShadToaster()`.

**All screens**

- Remove `Scaffold` + `AppBar` / `NmtkTopAppBar`.
- Content padding → 24 px.
- `ElevatedButton` → `ShadButton`.
- `OutlinedButton` → `ShadButton.outline`.
- `AlertDialog` → `ShadDialog`.
- `SnackBar` → `NmtkToasts`.
- Deployment log: wrap log output in `ShadCard` with `SizedBox(height: X)` capped via `ConstrainedBox` rather than hardcoded heights.

**Theme seed** (audit recommendation)

Change `NmtkThemeVariant.neurochip` seed from amber `0xFFD97706` to
`0xFF0891B2` (cyan) to avoid collision with the semantic `degradedColor`. Update
`nmtk_ui_core/lib/app_theme.dart`'s `_seedForVariant` switch case.

#### Verify

```
flutter test Neurochip/frontend/
```

Manually verify: app opens in dark mode, active target appears in header, deployment log shows in content area.

---

### §M.10 — Wave 5: neurocnl (CNL Studio)

**Owner:** `neurocnl/frontend/`  
**Read first:** `neurocnl/AGENTS.md`  
**Depends on:** Waves 0–4 merged and patterns proven.

#### Architecture change

neurocnl is an editor-first studio. `NmtkDesktopScaffold` provides the outer
chrome (brand, pipeline nav, header) while the `StudioScreen` content fills the
`child` with its own split-pane layout. The 12 px outer padding on `StudioScreen`
is the one explicit exception to the 24 px rule — it is IDE-compact by design.

#### File-by-file tasks

**`neurocnl/frontend/lib/app.dart` or `main.dart`**

1. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme`.
2. `NmtkDesktopScaffold`:
   - `navItems:` = Author / Analyze / Deploy (the three studio modes).
   - `mode:` = `NmtkShellMode.studio` (fixes audit P1-B).
   - `sidebarBrand:` = CNL Studio brand mark.
   - `headerActions:` = `PipelineBar` widget (persists across mode switches).

**`neurocnl/frontend/lib/screens/studio_screen.dart`**

- Keep the 12 px outer `Padding` — add `// studio-compact` comment.
- `_buildWorkspaceFrame` `DecoratedBox` → `ShadCard` (removes hardcoded `Color(Colors.black.withValues(alpha: 0.12))` shadow — Shadcn card handles elevation token).
- `_LauncherActionCard` `SizedBox(width: 220)` → `ShadCard` with `ConstrainedBox(constraints: BoxConstraints(minWidth: 180, maxWidth: 280))` (fixes audit §1 layout item).
- `OutlinedButton.icon` (Templates, Export) → `ShadButton.outline`.
- `_RunButton` `ElevatedButton.icon` — this is the green run button, a legitimate brand exception.
  Keep as `ShadButton` but override background: `ShadButton(backgroundColor: ShadTheme.of(context).colorScheme.accent, child: ...)`.
- `_FileTabStrip` close `GestureDetector(Icon(close))` → `ShadButton.ghost(padding: EdgeInsets.zero, child: Icon(Icons.close, size: 14))` (fixes audit tab close button P2-G).
- `ScaffoldMessenger.showSnackBar` → `NmtkToasts`.
- `AppTheme.success` / `AppTheme.error` in `_showMessage` → `NmtkToasts` (fixes audit P1-D).

**`neurocnl/frontend/lib/screens/analysis_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Content padding → 24 px.

**`neurocnl/frontend/lib/screens/deploy_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Content padding → 24 px.
- `ElevatedButton` → `ShadButton`.

**`neurocnl/frontend/lib/screens/hardware_screen.dart`**

- Remove `Scaffold`, `NmtkTopAppBar`.
- Content padding → 24 px.

**`neurocnl/frontend/lib/screens/server_setup_screen.dart`**

- Keep own Scaffold if it is a pre-connection gate screen (like NeuroHub's LoginScreen).
- `TextField` → `ShadInput`.
- `ElevatedButton` → `ShadButton`.

**Status colour fix** (audit P1-D)

In `neurocnl/frontend/lib/widgets/` — any widget using `AppTheme.success` /
`AppTheme.error` as a UI status colour: replace with
`ShadTheme.of(context).colorScheme.destructive` for errors and a positive tint
for success (no direct success token in Shadcn — use `NmtkShellTokens.of(context).healthyColor`).

#### Verify

```
flutter test neurocnl/frontend/
```

Manually verify: studio sidebar shows Author/Analyze/Deploy, pipeline bar visible in header, editor split-pane works, run button is accent-coloured, toasts appear instead of SnackBars.

---

### §M.11 — Wave 6: NeuroSim

**Owner:** `Neurosim/frontend/`  
**Read first:** `Neurosim/AGENTS.md`  
**Depends on:** Wave 5 (studio-mode pattern proven).

#### Architecture change

The canvas is **untouchable** — `CustomPaint`, `TransformationController`, node
drag/connect/select logic, port rendering, edge drawing. These stay as-is.
Only the chrome around the canvas changes.

#### File-by-file tasks

**`Neurosim/frontend/lib/app.dart`**

1. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme`.
2. `NmtkDesktopScaffold`:
   - `navItems:` = Canvas / CNL / Simulate / Sweep / Export.
   - `mode:` = `NmtkShellMode.studio`.

**`Neurosim/frontend/lib/screens/canvas_screen.dart`**

- Remove `Scaffold` / `AppBar`.
- The canvas itself (`InteractiveViewer` + `CustomPaint`) stays.
- Sidebar panels (`ComponentLibrarySidebar`, `PropertyPanel`) stay.
- Panel drag handles: keep `GestureDetector`; update `Container` → `ShadCard` for panel surfaces.
- Any `ElevatedButton` in the canvas toolbar → `ShadButton`.
- Content padding on panel sections → 16 px (instrument-compact, not 24 px, because panel space is premium in a canvas IDE).

**`Neurosim/frontend/lib/screens/project_screen.dart`**

- Remove `Scaffold`.
- Content padding → 24 px.

**`Neurosim/frontend/lib/screens/sweep_screen.dart`**

- Remove `Scaffold`.
- `ElevatedButton` / `OutlinedButton` → `ShadButton`.

**`Neurosim/frontend/lib/screens/export_screen.dart`**

- Remove `Scaffold`.
- `ElevatedButton` → `ShadButton`.
- `AlertDialog` → `ShadDialog`.

#### Verify

```
flutter test Neurosim/frontend/
```

Manually verify: canvas renders correctly, sidebar panels snap/resize, node drag/connect works.

---

### §M.12 — Wave 7: NMTK Launcher

**Owner:** `nmtk/neuro_toolkit/`  
**Read first:** `nmtk/AGENTS.md`  
**Depends on:** All waves 0–6 merged.

#### Architecture change

The launcher is the most complex integration because it hosts other modules as
WebViews and manages the suite's module lifecycle. Run launcher doctor before
and after this wave:

```bash
python3 scripts/launcher_control_service.py --doctor --json
bash scripts/run_launcher_guardrails.sh
```

#### File-by-file tasks

**`nmtk/neuro_toolkit/lib/main.dart`**

1. `MaterialApp(...)` → `ShadApp.material(...)` with `NmtkShadTheme`.

**`nmtk/neuro_toolkit/lib/screens/tool_view.dart`**

- Current: `Scaffold + module tab bar` housing WebViews.
- Apply `NmtkDesktopScaffold`:
  - `navItems:` = installed module list (dynamic, from module manifest).
  - Sidebar replaces the top tab bar (`module_tab_bar.dart`).
  - `child:` = the WebView area unchanged.

**`nmtk/neuro_toolkit/lib/screens/catalog.dart`**

- Remove `Scaffold`, `AppBar`.
- `ElevatedButton` / `OutlinedButton` → `ShadButton`.
- Cards → `ShadCard`.

**`nmtk/neuro_toolkit/lib/screens/settings.dart`**

- Remove `Scaffold`.
- `TextField` → `ShadInput`.
- `Switch` → `ShadSwitch`.

**`nmtk/neuro_toolkit/lib/screens/python_setup.dart`**

- Keep as a gate-screen Scaffold (pre-setup, no sidebar context needed).
- Migrate interactive elements: `ElevatedButton` → `ShadButton`.

#### Verify

```
flutter test nmtk/neuro_toolkit/
bash scripts/run_launcher_guardrails.sh
python3 scripts/launcher_control_service.py --doctor --json
```

Launcher doctor must report `fatalCount: 0`.

---

### §M.13 — Definition of done

#### Per-module done

A wave is complete when ALL of these pass:

- [ ] No `Scaffold` + `AppBar` combination exists at the root of any screen that is shown as the module's `home`.
- [ ] All `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton` replaced with the correct `ShadButton` variant.
- [ ] All `TextField`, `TextFormField` replaced with `ShadInput`.
- [ ] All `Card` replaced with `ShadCard`.
- [ ] All `AlertDialog` / `showDialog` replaced with `ShadDialog` / `showShadDialog`.
- [ ] All `SnackBar` / `ScaffoldMessenger` replaced with `NmtkToasts`.
- [ ] All `Divider` / `VerticalDivider` replaced with `ShadSeparator`.
- [ ] All `Tooltip` replaced with `ShadTooltip`.
- [ ] Page-level padding is 24 px (with documented exceptions).
- [ ] No custom `Color(0xFF...)` literals appear in migrated files (only Shadcn token reads).
- [ ] `flutter test <module>/frontend/` passes with no regressions.
- [ ] `flutter analyze <module>/frontend/` reports zero errors.

#### Suite-level done

- [ ] All 7 modules complete their per-module checklist.
- [ ] `flutter test nmtk_ui_core/` passes.
- [ ] Launcher doctor `fatalCount: 0`.
- [ ] Cross-module integration tests pass: `python3 -m pytest tests/integration/test_cross_module.py`.
- [ ] Manual walkthrough: open each module, verify sidebar, header, profile dropdown, toasts, form validation.

---

### §M.14 — Risk register

| Risk | Affected waves | Mitigation |
|------|---------------|------------|
| `shadcn_ui ^0.21.0` API mismatch — specific component doesn't exist or has different constructor | All | Pin version; run `flutter pub upgrade shadcn_ui` and fix compile errors before wave begins |
| `ShadApp.material.router` does not accept `builder:` param | Wave 2 (NeuroBench) | If missing, wrap `GoRouter`'s `navigatorBuilder` instead |
| `ShadForm` / `ShadFormBuilderField` not available in package version | Waves 1, 2, 5 | Fall back to `Form` + `GlobalKey<FormState>`; replace only the leaf `TextFormField` with `ShadInput` |
| `ShadToaster.of(context)` unavailable — toast API changed | All | Fall back to `NmtkSnackBars` helper from audit P1-E as temporary bridge |
| Canvas performance regression in NeuroSim after `ShadCard` wrapping | Wave 6 | Profile with Flutter DevTools before/after; revert panel surfaces to `DecoratedBox` if fps drops |
| NeuroSense live-status-badge rebuild rate — `headerActions` rebuilds whole scaffold on each frame | Wave 3 | Extract badge builder into `Consumer` widget to isolate rebuilds |
| Login screen (NeuroHub) still needs `Scaffold` | Wave 1 | Explicitly excluded from the "remove Scaffold" rule; document exception in code comment |
| NeuroSim panel drag handles break after widget wrapping | Wave 6 | Test drag resize before marking wave complete |
| `showShellChrome: false` path in NeuroSense/NeuroBench — embedded mode shows no chrome | Waves 2, 3 | Conditional in `app.dart` `builder:` must pass `child` directly without `NmtkDesktopScaffold` |
| Launcher doctor failure after Wave 7 | Wave 7 | Run `--doctor --json` after each file change, not just at the end |
