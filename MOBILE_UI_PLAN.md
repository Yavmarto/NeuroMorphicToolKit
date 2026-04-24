# Mobile-Friendly UI Implementation Plan — NeuroMorphicToolKit

> **Scope:** Add a responsive, mobile-friendly UI to all six module frontends while
> preserving 100% visual fidelity with the existing desktop design system.
> The main launcher (`nmtk/neuro_toolkit`) stays desktop-only by design.

---

## Architecture Principles (Binding Constraints)

| # | Principle | What it means |
|---|-----------|---------------|
| P1 | **Single Source of Truth** | All breakpoint logic, adaptive layout helpers, and new mobile-specific widgets live in `nmtk_ui_core`. Modules call shared utilities only — no in-module responsive logic. |
| P2 | **Self-Adapting Widgets** | Every adaptive widget reads `NmtkBreakpoints.of(context)` internally. No `isMobile: bool` props on call sites. |
| P3 | **`NmtkAdaptivePageLayout`** | Each module screen wraps its content in this single widget, which handles the desktop/mobile shell chrome split transparently. |
| P4 | **Phase 0 is a hard gate** | All Phase 1 work depends on a frozen, merged Phase 0. Phase 1 modules are fully parallelisable amongst themselves. |

---

## Phase Map & Dependency Graph

```
Phase 0 — nmtk_ui_core foundation (must complete first)
    P0-T1  NmtkBreakpoints
    P0-T2  NmtkAdaptivePageLayout         ← depends on T1
    P0-T3  NmtkAdaptiveDataTable          ← depends on T1
    P0-T4  NmtkDrawerPanel                ← depends on T1
    P0-T5  NmtkAdaptiveFormLayout         ← depends on T1
    P0-T6  NmtkMobileShellChrome          ← depends on T1
    P0-T7  Updates to existing widgets    ← depends on T1, T6
    P0-T8  Barrel export update           ← depends on T1–T7

Phase 1 — Module adaptations (ALL PARALLEL after Phase 0)
    neurocnl   T1–T4
    Neurochip  T1–T6
    Neurobench T1–T3
    Neurosim   T1–T3
    Neurosense T1–T4
    Neurohub   T1–T4

Phase 2 — Platform scaffolding (parallel to Phase 1)
    P2-T1  flutter create --platforms=android,ios (5 modules)
    P2-T2  AndroidManifest.xml INTERNET permissions
    P2-T3  iOS Info.plist NSAppTransportSecurity
    P2-T4  API_BASE_URL dart-define + warning

Phase 3 — Integration and testing
    P3-T1  nmtk_ui_core widget tests
    P3-T2  Per-module mobile smoke tests
    P3-T3  Manual device checklist
```

---

## New File Map (`nmtk_ui_core/lib/`)

```
nmtk_ui_core/lib/
├── responsive/                          ← NEW directory
│   ├── breakpoints.dart                 (P0-T1)
│   └── adaptive_page_layout.dart        (P0-T2)
├── widgets/
│   ├── adaptive_data_table.dart         (P0-T3)  NEW
│   ├── drawer_panel.dart                (P0-T4)  NEW
│   ├── adaptive_form_layout.dart        (P0-T5)  NEW
│   ├── mobile_shell_chrome.dart         (P0-T6)  NEW
│   ├── surface_card.dart                (P0-T7a) MODIFIED — adaptive padding
│   └── top_app_bar.dart                 (P0-T7b) MODIFIED — testability key
├── app_theme.dart                       (P0-T7c) MODIFIED — use NmtkBreakpoints consts
└── nmtk_ui_core.dart                    (P0-T8)  MODIFIED — add 6 exports
```

---

## Phase 0 — `nmtk_ui_core` Foundation

### P0-T1 — `NmtkBreakpoints` utility class

**File:** `nmtk_ui_core/lib/responsive/breakpoints.dart`
**Dependencies:** None

**Spec:**

```dart
enum NmtkScreenClass { phone, tablet, desktop }

class NmtkBreakpoints {
  static const double phoneMax   = 599;
  static const double tabletMin  = 600;
  static const double tabletMax  = 1239;
  static const double desktopMin = 1240;

  final double width;
  final double height;
  final double devicePixelRatio;
  final Orientation orientation;

  const NmtkBreakpoints._({
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    required this.orientation,
  });

  factory NmtkBreakpoints.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return NmtkBreakpoints._(
      width:            mq.size.width,
      height:           mq.size.height,
      devicePixelRatio: mq.devicePixelRatio,
      orientation:      mq.orientation,
    );
  }

  NmtkScreenClass get screenClass {
    if (width <= phoneMax)  return NmtkScreenClass.phone;
    if (width <= tabletMax) return NmtkScreenClass.tablet;
    return NmtkScreenClass.desktop;
  }

  bool get isPhone   => screenClass == NmtkScreenClass.phone;
  bool get isTablet  => screenClass == NmtkScreenClass.tablet;
  bool get isDesktop => screenClass == NmtkScreenClass.desktop;
  bool get isMobile  => !isDesktop;   // phone OR tablet
  bool get isPortrait => orientation == Orientation.portrait;

  /// Outer page padding:  12 phone / 16 tablet / 20 desktop
  double get pagePadding  => isPhone ? 12.0 : (isTablet ? 16.0 : 20.0);

  /// Card inner padding:  14 phone / 16 tablet / 20 desktop
  double get cardPadding  => isPhone ? 14.0 : (isTablet ? 16.0 : 20.0);
}
```

**Acceptance criteria:**
- 360 px → `isPhone=true`, `isMobile=true`, `isDesktop=false`, `pagePadding=12`
- 768 px → `isTablet=true`, `isMobile=true`
- 1440 px → `isDesktop=true`, `isMobile=false`, `pagePadding=20`

---

### P0-T2 — `NmtkAdaptivePageLayout` widget

**File:** `nmtk_ui_core/lib/responsive/adaptive_page_layout.dart`
**Dependencies:** P0-T1

**Constructor:**

```dart
class NmtkAdaptivePageLayout extends StatefulWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> actions;       // collapsed to ⋮ menu on phone
  final Widget body;
  final Widget? sidePanel;          // null = no FAB
  final String? sidePanelLabel;     // FAB tooltip label
  final double panelWidth;          // persistent panel width on desktop (default 320)

  const NmtkAdaptivePageLayout({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const [],
    required this.body,
    this.sidePanel,
    this.sidePanelLabel,
    this.panelWidth = 320,
  });
}
```

**Behaviour by breakpoint:**

| Breakpoint | Body | Side panel | Actions |
|-----------|------|-----------|---------|
| `isDesktop` | Expanded | Persistent `Container(width: panelWidth)` right of a `VerticalDivider` | `Wrap(spacing:8)` row |
| `isTablet` | Full width | EndDrawer (width 360), opened via FAB `Icons.tune_outlined` | `Wrap(spacing:8)` row |
| `isPhone` | Full width | EndDrawer (width fraction 0.92), opened via FAB | Collapsed into `PopupMenuButton(Icons.more_vert)` |

- Title/subtitle rendered as a `Padding` block at the **top of `body`'s scroll area** (not in AppBar — modules own their AppBar via `NmtkMobileShellChrome`).
- FAB position: `FloatingActionButtonLocation.endFloat`.

**Acceptance criteria:**
- 360 px: no sidePanel column, FAB visible, EndDrawer slides in on tap
- 1440 px: persistent side panel, no FAB
- Rotation portrait↔landscape reflows without crash

---

### P0-T3 — `NmtkAdaptiveDataTable`

**File:** `nmtk_ui_core/lib/widgets/adaptive_data_table.dart`
**Dependencies:** P0-T1

**Spec:** Drop-in for `DataTable`. On `isPhone`/`isTablet`, wraps in `SingleChildScrollView(scrollDirection: Axis.horizontal)`. On desktop, bare `DataTable`.

```dart
class NmtkAdaptiveDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final Color? headingRowColor;
  final Color? dataRowColor;
  final TableBorder? border;
  final double columnSpacing;

  const NmtkAdaptiveDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headingRowColor,
    this.dataRowColor,
    this.border,
    this.columnSpacing = 24,
  });
}
```

**Migration targets:** `NmtkQuantizationTable`, `DeploymentLogTable` (Neurochip), `MetricDiffTable` (Neurobench).

**Acceptance criteria:**
- 360 px: 6-column table is horizontally scrollable
- 1440 px: no wrapping scroll view

---

### P0-T4 — `NmtkDrawerPanel`

**File:** `nmtk_ui_core/lib/widgets/drawer_panel.dart`
**Dependencies:** P0-T1

**Spec:** Standalone panel widget with shell-token-based styling. Used internally by `NmtkAdaptivePageLayout` but also usable by modules managing their own scaffold.

```dart
class NmtkDrawerPanel extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? subtitle;

  const NmtkDrawerPanel({super.key, required this.child, this.title, this.subtitle});
}
```

Renders with:
- Background: `NmtkShellTokens.of(context).utilityPanelBackground`
- Left border (1 px): `NmtkShellTokens.of(context).chromeBorder`
- Padding: 16 px all sides
- Header: `title` in `titleMedium` (bold) + `subtitle` in `bodySmall` (`onSurfaceVariant`)

---

### P0-T5 — `NmtkAdaptiveFormLayout`

**File:** `nmtk_ui_core/lib/widgets/adaptive_form_layout.dart`
**Dependencies:** P0-T1

**Spec:** Switches between 2-column grid and single-column list based on available width.

```dart
class NmtkAdaptiveFormLayout extends StatelessWidget {
  final List<Widget> children;
  final double minColumnWidth;   // default 240

  const NmtkAdaptiveFormLayout({
    super.key,
    required this.children,
    this.minColumnWidth = 240,
  });
}

/// Marks a child as spanning full width in both column modes.
class NmtkFormFullWidthRow extends StatelessWidget {
  final Widget child;
  const NmtkFormFullWidthRow({super.key, required this.child});
}
```

Algorithm (via `LayoutBuilder`):
- `maxWidth >= minColumnWidth * 2 + 16`: 2-column `Wrap(spacing:16, runSpacing:16)`, each child `SizedBox(width: (maxWidth-16)/2)`
- Otherwise: single-column `Column(spacing:12)`
- `NmtkFormFullWidthRow` children always span full width

**Acceptance criteria:**
- 360 px: all fields vertical
- 768 px landscape: 2-column grid
- `NmtkFormFullWidthRow` always full-width

---

### P0-T6 — `NmtkMobileShellChrome`

**File:** `nmtk_ui_core/lib/widgets/mobile_shell_chrome.dart`
**Dependencies:** P0-T1

**Spec:** Slim module AppBar for mobile. Delegates to `NmtkTopAppBar` on tablet/desktop.

```dart
class NmtkMobileShellChrome extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final Widget? statusBadge;
  final List<NavigationDestinationData> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final NmtkShellMode mode;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);  // 56px
}
```

**Behaviour:**
- `isPhone`: `AppBar` at 56 px, `title` text, `leading`, `statusBadge` action slot, all destinations collapsed into trailing `PopupMenuButton(Icons.menu_outlined)`
- Selected destination shown with `ListTile.selected: true` using `paletteForMode(mode).accentForeground`
- `isTablet`/`isDesktop`: delegates to `NmtkTopAppBar` unchanged

**Acceptance criteria:**
- `preferredSize.height == 56` on phone
- All destination labels appear in popup
- `onDestinationSelected` fires with correct index
- Correct module accent colour from `NmtkShellMode`

---

### P0-T7 — Updates to existing widgets

#### P0-T7a — `NmtkSurfaceCard` adaptive padding
**File:** `nmtk_ui_core/lib/widgets/surface_card.dart`

Change `padding` from `const EdgeInsets.all(20)` default to `EdgeInsetsGeometry? padding` (nullable). In `build()`:
```dart
final resolvedPadding = padding ?? EdgeInsets.all(NmtkBreakpoints.of(context).cardPadding);
```
**Acceptance criteria:** 360 px → 14 px inner padding; 1440 px → 20 px inner padding.

#### P0-T7b — `NmtkTopAppBar` testability key
**File:** `nmtk_ui_core/lib/widgets/top_app_bar.dart`

Add `key: const ValueKey('nmtk-top-app-bar')` to the outermost `Material` widget. No behaviour change.

#### P0-T7c — `ResponsiveScaffold` canonical breakpoints
**File:** `nmtk_ui_core/lib/app_theme.dart`

Replace hardcoded `< 600` and `< 1240` literals in `ResponsiveScaffold`'s `LayoutBuilder` with `NmtkBreakpoints.phoneMax` and `NmtkBreakpoints.tabletMax`. No behaviour change.

---

### P0-T8 — Barrel export update

**File:** `nmtk_ui_core/lib/nmtk_ui_core.dart`

Add to the existing barrel:
```dart
export 'responsive/breakpoints.dart';
export 'responsive/adaptive_page_layout.dart';
export 'widgets/adaptive_data_table.dart';
export 'widgets/drawer_panel.dart';
export 'widgets/adaptive_form_layout.dart';
export 'widgets/mobile_shell_chrome.dart';
```

**Acceptance criteria:** `import 'package:nmtk_ui_core/nmtk_ui_core.dart'` exposes all new symbols. `flutter analyze` in `nmtk_ui_core/` → zero new errors.

---

## Phase 1 — Module Frontend Adaptations

> All modules are **fully independent** and can be implemented in parallel.
> Every task depends only on **Phase 0 being complete** (P0-T8).

---

### Module 1 — `neurocnl/frontend`
**Theme:** `NmtkThemeVariant.neurocnl` · **Mode:** `NmtkShellMode.studio`

#### P1-neurocnl-T1 — App shell (`app_router.dart`)
**File:** `neurocnl/frontend/lib/routing/app_router.dart`
**Dependencies:** P0-T6, P0-T8

Replace the partial `width >= 800` check with `NmtkBreakpoints.of(context)`.
- `isPhone`: replace `NmtkTopAppBar` with `NmtkMobileShellChrome`; hide `NmtkWorkspaceSwitcherBar`
- `isTablet`/`isDesktop`: keep `NmtkTopAppBar` + `NmtkWorkspaceSwitcherBar` unchanged

**Acceptance criteria:**
- 360 px: `NmtkMobileShellChrome` at 56 px; no `WorkspaceSwitcherBar`
- 1440 px: `NmtkTopAppBar` + chips + `WorkspaceSwitcherBar` all visible

---

#### P1-neurocnl-T2 — `StudioScreen` panel as drawer
**File:** `neurocnl/frontend/lib/screens/studio_screen.dart`
**Dependencies:** P0-T2, P0-T8

Existing `_buildMobileLayout` stacks editor + panels vertically. Replace with:
- Wrap in `NmtkAdaptivePageLayout(body: _buildEditorWorkspace(), sidePanel: _buildPanelWorkspace())`
- Desktop two-column resizable split remains via `_buildDesktopLayout` (keep as-is)
- Replace `final isDesktop = width >= 1024` with `final bp = NmtkBreakpoints.of(context); final isDesktop = bp.isDesktop`

**Acceptance criteria:**
- 360 px: CNL editor as primary body; FAB opens panels as right-side drawer
- 1440 px: desktop split layout unchanged

---

#### P1-neurocnl-T3 — `DeployScreen` form layouts
**File:** `neurocnl/frontend/lib/screens/deploy_screen.dart`
**Dependencies:** P0-T5, P0-T8

Wrap form `Row` (label+field pairs) inside `_SimulationTab`, `_LearningTab`, and `_ExportTab` in `NmtkAdaptiveFormLayout`. `DefaultTabController` / `TabBar` already mobile-friendly (no changes needed there).

**Acceptance criteria:**
- 360 px: all form fields stack vertically in all tabs; no `RenderFlex` overflow

---

#### P1-neurocnl-T4 — `HardwareScreen` form + chart height
**File:** `neurocnl/frontend/lib/screens/hardware_screen.dart`
**Dependencies:** P0-T1, P0-T5, P0-T8

- Wrap `_buildConnectionPanel()` `Row` in `NmtkAdaptiveFormLayout`
- Reduce `SensorTimeSeriesChart` height: `SizedBox(height: bp.isPhone ? 140.0 : 240.0)`

**Acceptance criteria:**
- Port selector and baud rate fields stack on phone; chart is 140 px tall on phone

---

### Module 2 — `Neurochip/frontend`
**Theme:** `NmtkThemeVariant.neurochip` · **Mode:** `NmtkShellMode.instrument`

#### P1-neurochip-T1 — Main navigation shell (`app.dart`)
**File:** `Neurochip/frontend/lib/app.dart`
**Dependencies:** P0-T1, P0-T6, P0-T8

- Add `final bp = NmtkBreakpoints.of(context)`
- `isPhone`: `NmtkMobileShellChrome`; remove `NmtkNavigationRail` from body Row; hide `NmtkWorkspaceSwitcherBar`
- `isTablet`: keep rail (non-extended); keep `WorkspaceSwitcherBar`
- `isDesktop`: unchanged
- Reduce headline section padding to `bp.pagePadding` on phone

**Acceptance criteria:** Three breakpoints behave as described; workspace callbacks still work

---

#### P1-neurochip-T2 — `PynqDeployScreen` form
**File:** `Neurochip/frontend/lib/screens/pynq_deploy_screen.dart`
**Dependencies:** P0-T1, P0-T2, P0-T5, P0-T8

1. Wrap all `Row([label, TextField])` pairs in `_buildBoardCard()` with `NmtkAdaptiveFormLayout`
2. `_buildCnlInputCard()`: wrap bit-width dropdown + export button in `NmtkAdaptiveFormLayout` with `NmtkFormFullWidthRow` for the button row
3. `_buildDeployActionCard()`: replace `Row` with `Column(crossAxisAlignment: CrossAxisAlignment.stretch)` on `bp.isPhone`
4. Move `ConstraintReportCard` into `NmtkAdaptivePageLayout`'s `sidePanel`

**Acceptance criteria:** No `RenderFlex` overflow at 360 px; `ConstraintReportCard` accessible via FAB; desktop unchanged

---

#### P1-neurochip-T3 — `AkidaDeployScreen` form
**File:** `Neurochip/frontend/lib/screens/akida_deploy_screen.dart`
**Dependencies:** P0-T1, P0-T5, P0-T8

- Wrap all `Row([label, TextField])` pairs in `NmtkAdaptiveFormLayout`
- Replace `Row([RadioListTile, RadioListTile])` Akida version selector with `Column` on phone
- Replace `Row([SegmentedButton])` bit-width selector with `Column` on phone

**Acceptance criteria:** No overflow at 360 px; all selectors usable on phone

---

#### P1-neurochip-T4 — `TeensyDeployScreen` port selector
**File:** `Neurochip/frontend/lib/screens/teensy_deploy_screen.dart`
**Dependencies:** P0-T1, P0-T5, P0-T8

- Wrap `_buildSerialPortCard()` row in `NmtkAdaptiveFormLayout`
- Bit-width selector: same pattern as P1-neurochip-T2
- Verify `FlashProgressIndicator` uses `width: double.infinity` (fix if hardcoded pixel width)

**Acceptance criteria:** Port selector no overflow; flash bar full-width on all screens

---

#### P1-neurochip-T5 — `DeployStatusScreen` grid columns
**File:** `Neurochip/frontend/lib/screens/deploy_status_screen.dart`
**Dependencies:** P0-T1, P0-T8

Replace manual `LayoutBuilder` thresholds (1260/900) with:
```dart
final bp = NmtkBreakpoints.of(context);
final columns = bp.isDesktop ? 3 : (bp.isTablet ? 2 : 1);
```
Apply `bp.pagePadding` to `SingleChildScrollView` padding.

**Acceptance criteria:** 1-col phone, 2-col tablet, 3-col desktop; thresholds match `NmtkBreakpoints`

---

#### P1-neurochip-T6 — `DeploymentLogTable` adaptive scroll
**File:** `Neurochip/frontend/lib/widgets/deployment_log_table.dart`
**Dependencies:** P0-T3, P0-T8

Replace `SingleChildScrollView(horizontal) + DataTable` with `NmtkAdaptiveDataTable`.

**Acceptance criteria:** Phone: horizontal scroll; desktop: no scroll wrapper

---

### Module 3 — `Neurobench/frontend`
**Theme:** `NmtkThemeVariant.neurobench` · **Mode:** `NmtkShellMode.command`

#### P1-neurobench-T1 — `WorkbenchShellScreen` AppBar + stacked layout
**File:** `Neurobench/frontend/lib/screens/workbench_shell.dart`
**Dependencies:** P0-T1, P0-T6, P0-T8

- `isPhone`: `NmtkMobileShellChrome`; hide `_WorkbenchSwitcherBar`
- `isTablet`/`isDesktop`: `NmtkTopAppBar` + `_WorkbenchSwitcherBar` unchanged
- Existing `useStackedLayout` branch (at `< 1180`) already handles phone/tablet — keep it

**Acceptance criteria:** Phone shows slim chrome; stacked layout used at phone/tablet widths

---

#### P1-neurobench-T2 — `MetricDiffTable` adaptive scroll
**File:** `Neurobench/frontend/lib/widgets/metric_diff_table.dart`
**Dependencies:** P0-T3, P0-T8

Replace `SingleChildScrollView(horizontal) + DataTable` with `NmtkAdaptiveDataTable`.

---

#### P1-neurobench-T3 — Stacked layout padding
**File:** `Neurobench/frontend/lib/screens/workbench_shell.dart`
**Dependencies:** P1-neurobench-T1

Change `Padding(const EdgeInsets.all(20), ...)` in the `useStackedLayout` branch to `Padding(EdgeInsets.all(bp.pagePadding), ...)`.

---

### Module 4 — `Neurosim/frontend`
**Theme:** `NmtkThemeVariant.neurosim` · **Mode:** `NmtkShellMode.studio`

#### P1-neurosim-T1 — `CanvasScreen` AppBar + panel visibility
**File:** `Neurosim/frontend/lib/screens/canvas_screen.dart`
**Dependencies:** P0-T1, P0-T2, P0-T6, P0-T8

1. `isPhone`: `NmtkMobileShellChrome`; hide `NmtkWorkspaceSwitcherBar`
2. On phone, force all side panels (`_showLibrary`, `_showCnl`, `_showProperties`) to `false` in `didChangeDependencies`
3. Expose component library only via `NmtkAdaptivePageLayout(sidePanel: ComponentLibrarySidebar())` — CNL and Properties panels are phone-hidden (documented UX trade-off: phone = view/run only, desktop = full edit)
4. Full-width canvas on phone; multi-panel layout unchanged on desktop

**Acceptance criteria:** Full-width canvas on phone; FAB opens library; CNL+properties hidden on phone; desktop unchanged

---

#### P1-neurosim-T2 — `ProjectScreen` master-detail split
**File:** `Neurosim/frontend/lib/screens/project_screen.dart`
**Dependencies:** P0-T1, P0-T8

- `isPhone`: show list only; tap → `Navigator.push` to detail page
- `isTablet`/`isDesktop`: keep `Row([list, divider, detail])` split
- Wrap action button row in `Wrap(spacing:8, runSpacing:8)` instead of `Row`

**Acceptance criteria:** Phone: 2-page master-detail; desktop: 2-column; buttons wrap without overflow

---

#### P1-neurosim-T3 — `SweepScreen` config panel as drawer
**File:** `Neurosim/frontend/lib/screens/sweep_screen.dart`
**Dependencies:** P0-T1, P0-T2, P0-T8

- Wrap in `NmtkAdaptivePageLayout(body: _buildResults(), sidePanel: _SweepForm())`
- On phone: results body shown first; FAB opens sweep config
- On desktop: two-column `Row` split kept

**Acceptance criteria:** Phone: results + FAB opens config drawer; desktop: split layout unchanged

---

### Module 5 — `Neurosense/frontend`
**Theme:** `NmtkThemeVariant.neurosense` · **Mode:** `NmtkShellMode.instrument`

#### P1-neurosense-T1 — App shell (`app.dart`)
**File:** `Neurosense/frontend/lib/app.dart`
**Dependencies:** P0-T1, P0-T6, P0-T8

- `isPhone`: `NmtkMobileShellChrome` with condensed status badge; hide `NmtkWorkspaceSwitcherBar`
- Remove `ConstrainedBox(maxWidth:1480)` on phone: `child: bp.isPhone ? _buildScreen() : ConstrainedBox(...)`
- `isTablet`/`isDesktop`: unchanged

---

#### P1-neurosense-T2 — `SignalMonitorScreen` chart sizing
**File:** `Neurosense/frontend/lib/screens/signal_monitor_screen.dart`
**Dependencies:** P0-T1, P0-T8

- Replace hardcoded `1120` threshold with `NmtkBreakpoints.of(context).isDesktop`
- `isPhone`: `SizedBox(height: 200, child: LiveSignalViewer())` (vs default ~300)
- `RecordingControls(compact: true)` and `SpikeEncodingPanel(compact: true)` already have compact mode — apply on all mobile widths

---

#### P1-neurosense-T3 — `DeviceConfigScreen` form
**File:** `Neurosense/frontend/lib/screens/device_config_screen.dart`
**Dependencies:** P0-T1, P0-T5, P0-T8

- Wrap device selector + sampling rate fields in `NmtkAdaptiveFormLayout`
- Apply `bp.pagePadding` to `ListView` padding

---

#### P1-neurosense-T4 — `FilterPipelineScreen` overflow fix
**File:** `Neurosense/frontend/lib/screens/filter_pipeline_screen.dart`
**Dependencies:** P0-T1, P0-T8

- If filter stages rendered in a `Row`: wrap in `SingleChildScrollView(scrollDirection: Axis.horizontal)` on phone
- Replace any action button `Row` with `Wrap(spacing:8, runSpacing:8)`

**Acceptance criteria:** No `RenderFlex` overflow at 360 px

---

### Module 6 — `Neurohub/frontend`
**Theme:** `NmtkThemeVariant.neurohub` · **Mode:** `NmtkShellMode.command`

#### P1-neurohub-T1 — `DashboardScreen` AppBar adaptive
**File:** `Neurohub/frontend/lib/screens/dashboard_screen.dart`
**Dependencies:** P0-T1, P0-T6, P0-T8

- Unify existing `width`-based conditionals under `NmtkBreakpoints`
- `isPhone`: `NmtkMobileShellChrome`; hide `NmtkWorkspaceSwitcherBar`
- Change outer `Padding(const EdgeInsets.all(16))` to `EdgeInsets.all(bp.pagePadding)`

---

#### P1-neurohub-T2 — `ProjectDetailScreen` action row
**File:** `Neurohub/frontend/lib/screens/project_detail_screen.dart`
**Dependencies:** P0-T1, P0-T8

- Replace `Row([ElevatedButton, ...])` action group with `Wrap(spacing:8, runSpacing:8)`
- Apply `bp.pagePadding` to content `Padding`

---

#### P1-neurohub-T3 — `WorkflowEditorScreen` + `WorkflowRunScreen` AppBar
**Files:**
- `Neurohub/frontend/lib/screens/workflow_editor_screen.dart`
- `Neurohub/frontend/lib/screens/workflow_run_screen.dart`

**Dependencies:** P0-T1, P0-T6, P0-T8

- `isPhone`: `NmtkMobileShellChrome` for both screens
- Change body `Padding(const EdgeInsets.all(24))` to `bp.pagePadding`

---

#### P1-neurohub-T4 — `BundleInspectionScreen` + `OrchestrationControlsScreen`
**Files:**
- `Neurohub/frontend/lib/screens/bundle_inspection_screen.dart`
- `Neurohub/frontend/lib/screens/orchestration_controls_screen.dart`

**Dependencies:** P0-T1, P0-T6, P0-T8

- `isPhone`: `NmtkMobileShellChrome`
- Replace `Row([button...])` groups with `Wrap(spacing:8, runSpacing:8)`
- Apply `bp.pagePadding`

---

## Phase 2 — iOS/Android Platform Scaffolding

### Current platform folder status

| Module | `android/` | `ios/` |
|--------|-----------|--------|
| `neurocnl/frontend` | ✅ Exists | ✅ Exists |
| `Neurochip/frontend` | ❌ Missing | ❌ Missing |
| `Neurobench/frontend` | ❌ Missing | ❌ Missing |
| `Neurosim/frontend` | ❌ Missing | ❌ Missing |
| `Neurosense/frontend` | ❌ Missing | ❌ Missing |
| `Neurohub/frontend` | ❌ Missing | ❌ Missing |

---

### P2-T1 — Flutter platform scaffolding (5 modules)

Run inside each of the 5 missing-platform module directories:
```bash
flutter create --platforms=android,ios --org com.nmtk .
```

This generates `android/` and `ios/` with bundle IDs `com.nmtk.<module>`.

**Modules:**
- `Neurochip/frontend/` → bundle ID `com.nmtk.neurochip`
- `Neurobench/frontend/` → `com.nmtk.neurobench`
- `Neurosim/frontend/` → `com.nmtk.neurosim`
- `Neurosense/frontend/` → `com.nmtk.neurosense`
- `Neurohub/frontend/` → `com.nmtk.neurohub`

---

### P2-T2 — Android `AndroidManifest.xml` internet permissions

**Files:** `<module>/frontend/android/app/src/main/AndroidManifest.xml` (all 6 modules)

Add inside `<manifest>` (before `<application>`):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Add to `<application>` element:
```xml
android:usesCleartextTraffic="true"
```

> **Note:** `neurocnl/frontend` is also missing `INTERNET` permission — fix all 6.

---

### P2-T3 — iOS `Info.plist` ATS settings

**Files:** `<module>/frontend/ios/Runner/Info.plist` (all 6 modules)

Add:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <!-- TODO-PROD: restrict to API_BASE_URL domain only before App Store submission -->
</dict>
```

---

### P2-T4 — `API_BASE_URL` dart-define warning

**Files:** `<module>/frontend/lib/main.dart` (all 6 modules)

Add at the top of `main()`:
```dart
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
if (apiBaseUrl.isEmpty) {
  debugPrint('[NMTK] WARNING: API_BASE_URL is not set. '
      'Pass --dart-define=API_BASE_URL=https://your-server.example.com');
}
```

**Build commands (for documentation):**
```bash
# Android
flutter build apk --dart-define=API_BASE_URL=https://api.nmtk.example.com

# iOS
flutter build ipa --dart-define=API_BASE_URL=https://api.nmtk.example.com
```

---

## Phase 3 — Integration and Testing

### P3-T1 — `nmtk_ui_core` widget tests

**New test files:** `nmtk_ui_core/test/responsive/`

| File | What it tests |
|------|---------------|
| `breakpoints_test.dart` | `isPhone/isTablet/isDesktop` at 360/768/1440 px; `pagePadding`, `cardPadding` values |
| `adaptive_page_layout_test.dart` | FAB present on phone/tablet; persistent panel on desktop; EndDrawer opens on FAB tap |
| `adaptive_data_table_test.dart` | Horizontal `SingleChildScrollView` wrapping at 360 px; none at 1440 px |
| `adaptive_form_layout_test.dart` | Single column at 360 px; 2-column at 800 px; `NmtkFormFullWidthRow` always full-width |
| `mobile_shell_chrome_test.dart` | `preferredSize.height == 56`; all destinations in popup; `onDestinationSelected` fires correctly |

**Test pattern:**
```dart
await tester.pumpWidget(MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(360, 800)),
    child: widget,
  ),
));
```

---

### P3-T2 — Per-module mobile smoke tests

**New test files:** `<module>/frontend/test/mobile_smoke_test.dart` (all 6 modules)

Each smoke test validates at 360 × 800 px:
1. App launches without `RenderFlex` overflow
2. Bottom navigation bar is visible (from `ResponsiveScaffold`)
3. FAB is visible if the screen has a `sidePanel`
4. Tapping the FAB opens a drawer without crash

---

### P3-T3 — Manual device checklist

| Check | Platforms | Pass condition |
|-------|-----------|----------------|
| AppBar height | iOS + Android | `NmtkMobileShellChrome` at 56 px, no clipping |
| Bottom navigation | iOS + Android | `NavigationBar` visible at bottom |
| Forms fit screen | iOS + Android | No horizontal overflow, no clipped fields |
| DataTables scroll | iOS + Android | 5+ column tables horizontally scrollable |
| FAB panel opens | iOS + Android | EndDrawer slides in without crash |
| Theme colours match | iOS + Android | `#1337EC` primary, module seeds, dark surface identical to desktop |
| Landscape reflow | iOS + Android | Rotation adapts layout without errors |
| HTTP API connectivity | Physical device on LAN | API requests reach server at `API_BASE_URL` |

---

## Design Decisions

**Why `NmtkBreakpoints` as a plain class, not `InheritedWidget`?**
It's a value object constructed from `MediaQuery.of(context)` on demand. `MediaQuery` already provides rebuild semantics. This is the same pattern as `NmtkShellTokens.of(context)` — zero new tree overhead.

**Why `NmtkAdaptivePageLayout` owns the side panel FAB?**
Consistent animation curves, FAB placement, and keyboard-avoidance behaviour across all 6 modules. Without this, each module would implement slightly different drawer behaviour.

**Why is `NmtkWorkspaceSwitcherBar` hidden on phone (not replaced)?**
Its function is surfaced via `NmtkMobileShellChrome`'s popup. Building a dedicated mobile workspace switcher bar would require a Phase 0 slot that isn't justified for the first mobile pass. It can be added as a Phase 1.5 enhancement.

**Why does `NmtkMobileShellChrome` delegate to `NmtkTopAppBar` on tablet/desktop?**
Module `app.dart` files can unconditionally use `NmtkMobileShellChrome` — the switching is internal. This matches Principle P2: no `isMobile` props at call sites.

**Why is `CanvasScreen` (Neurosim) phone-limited to view/run only?**
The CNL editor + multi-panel network canvas is inherently a large-screen tool. Surfacing 4 side panels on a 360 px phone would be unusable. The explicit UX trade-off: phone = view and run simulations; tablet/desktop = full editing.

---

## Quick Reference — Task Summary

### Phase 0 (Sequential, nmtk_ui_core)
| Task | File | Dep |
|------|------|-----|
| P0-T1 | `responsive/breakpoints.dart` | — |
| P0-T2 | `responsive/adaptive_page_layout.dart` | T1 |
| P0-T3 | `widgets/adaptive_data_table.dart` | T1 |
| P0-T4 | `widgets/drawer_panel.dart` | T1 |
| P0-T5 | `widgets/adaptive_form_layout.dart` | T1 |
| P0-T6 | `widgets/mobile_shell_chrome.dart` | T1 |
| P0-T7a | `widgets/surface_card.dart` (adaptive padding) | T1 |
| P0-T7b | `widgets/top_app_bar.dart` (key) | T6 |
| P0-T7c | `app_theme.dart` (canonical consts) | T1 |
| P0-T8 | `nmtk_ui_core.dart` (exports) | T1–T7 |

### Phase 1 (Parallel per module, all depend on P0-T8)
| Module | Tasks |
|--------|-------|
| neurocnl | T1 shell · T2 StudioScreen · T3 DeployScreen · T4 HardwareScreen |
| Neurochip | T1 shell · T2 PynqDeploy · T3 AkidaDeploy · T4 TeensyDeploy · T5 DeployStatus · T6 LogTable |
| Neurobench | T1 shell · T2 MetricDiffTable · T3 padding |
| Neurosim | T1 CanvasScreen · T2 ProjectScreen · T3 SweepScreen |
| Neurosense | T1 shell · T2 SignalMonitor · T3 DeviceConfig · T4 FilterPipeline |
| Neurohub | T1 Dashboard · T2 ProjectDetail · T3 Workflow screens · T4 Bundle+Orchestration |

### Phase 2 (Parallel to Phase 1)
| Task | Action |
|------|--------|
| P2-T1 | `flutter create --platforms=android,ios` for 5 modules |
| P2-T2 | `INTERNET` permission + `usesCleartextTraffic` in all 6 `AndroidManifest.xml` |
| P2-T3 | `NSAllowsArbitraryLoads` in all 6 `Info.plist` |
| P2-T4 | `API_BASE_URL` warning in all 6 `main.dart` |

### Phase 3 (After Phase 1+2)
| Task | Output |
|------|--------|
| P3-T1 | 5 widget test files in `nmtk_ui_core/test/responsive/` |
| P3-T2 | 6 `mobile_smoke_test.dart` files across modules |
| P3-T3 | Manual device verification checklist |
