# CEL-451 — Mobile redesign design specs (Zeta + Impeccable)

**Parent:** [CEL-450](CEL-450) Complete redesign — mobile  
**Audience:** Engineer child issues under CEL-450  
**Validated against:** `.impeccable/design.json`, `nmtk-flutter-review` P0 rules, `mobile_modal_standard.md`  
**Test widths:** 375×667 (iPhone SE), 390×844 (iPhone 14)

---

## 0. Global rules (all five areas)

### Breakpoints

| Name | Value | When to use |
|---|---|---|
| **Screen compact** | `NmtkShellTokens.compactBreakpoint` (**840 px**) | Canonical mobile gate: assistant, studio shell, neurobench wizard, connect palette, modal/sheet vs dialog |
| **Step inline header** | **600 px** | Deploy-review inline header row only (`deploy_review_step.dart`, `studio_layout_metrics.dart`) — keeps target dropdown + compare chip on one row on small tablets |
| **Pane action stack** | **420 px** | Within a setup pane, stack action buttons vertically when the pane body is narrower than 420 px (`_stackableActionRow` in Akida/Pynq/advanced panes) |

Do **not** invent new breakpoints. If a surface needs a third threshold, document it in this file first.

### Spacing & radii (token-only)

| Token | Value | Use |
|---|---|---|
| `tokens.sectionGap` | 16 px | Screen padding, section separation, FAB inset |
| `tokens.compactGap` | 8 px | Between chips, inline controls, stacked action gaps |
| `tokens.radiusSm` | 12 px | Input borders, chips |
| `tokens.radiusMd` | 16 px | Buttons, small cards |
| `tokens.radiusLg` | 22 px | Section cards, bottom-sheet top corners, floating canvas bar |
| `NmtkDesignTokens.dialogShape` | 28 px | Centered dialogs (desktop only below 840) |

### Typography

| Role | Flutter | Size / weight |
|---|---|---|
| Screen title | `titleLarge` | 20 / 500 |
| Section title | `titleMedium` | 16 / 500 |
| Body | `bodyMedium` | 16 / 400 |
| Metadata / caption | `bodySmall` + `metadataForeground` | 14 / 400 |
| Mono values | `JetBrains Mono` via theme | 13 / 400 |

Font family: **Space Grotesk** for all UI chrome (Zeta `themeId: "nmtk"`).

### Status colours (never inline hex)

Use `NmtkShellTokens`: `healthyColor`, `runningColor`, `degradedColor`, `warningColor`, `errorColor`, `liveColor`.

### Shell mode

| Surface | Mode |
|---|---|
| neurocnl Studio (setup, canvas, deploy review) | `NmtkShellMode.studio` |
| Neurobench run/compare | `NmtkShellMode.command` |

Accent: `studioPalette.accent` (#8B5CF6 dark / #7C3AED light) on studio surfaces; `instrumentPalette` on Neurobench.

### Tap targets

Minimum **44×44 logical px** on every interactive control (mobile modal standard rule 4). Prefer `ZetaIconButton`, `ZetaButton`, `ZetaListItem` (48 px built-in).

### Bottom chrome coordination

Multiple steps anchor controls near the bottom. Z-order (bottom → top):

1. Step content (scrollable)
2. Step-specific bar: `MobileCanvasChrome`, `RunActionBar`, `MobileDeployActionDock`, `ActiveJobsBar`
3. Assistant FAB (`StudioAssistantHost`) — **never** bottom-anchored on mobile; use `bottom: height * 0.38`, `right: sectionGap`
4. Modal bottom sheets (assistant, connect palette, hardware form) — above everything when open

Engineers must not add a second bottom-anchored FAB without updating this contract.

### Modal / sheet standard

All popups below 840 px follow [`mobile_modal_standard.md`](mobile_modal_standard.md) (7 rules). Canonical patterns:

- Action sheet: `mobile_scaffold.dart` → `_showFileActionsSheet`
- Adaptive dialog ↔ sheet: `server_access_popup.dart`
- Tall sheet: `canvas_screen.dart` → `_showMobileNodeSheet`
- List picker: `canvas_connect_palette.dart`

---

## 1. Setup step flow

**Files:** `akida_setup_pane.dart`, `pynq_setup_pane.dart`, `akida_advanced_scaffold_pane.dart`, `add_hardware_target_form.dart`, `mobile_deploy_action_dock.dart`

### 1.1 Screen layout (mobile, width < 840)

```
┌─────────────────────────────────────┐
│ Studio stepper (overlay, top)       │
├─────────────────────────────────────┤
│ ▼ SingleChildScrollView body        │
│   • Phase banner (StudioPhaseBanner)│
│   • Title (titleLarge)              │
│   • Key-value rows (NmtkKeyValueRow)│
│   • Capability chips (Wrap)         │
│   • Action group (_stackableActionRow)│
│   • Divider                         │
│   • Bundle / board section          │
│   • ZetaAccordion → Advanced pane   │
├─────────────────────────────────────┤
│ MobileDeployActionDock (sticky)     │  ← primary Deploy CTA only
└─────────────────────────────────────┘
        [Assistant FAB @ 38% height]
```

### 1.2 Hierarchy

| Block | Typography | Spacing |
|---|---|---|
| Phase banner | `labelMedium`, status colour | `sectionGap` below stepper |
| Pane title | `titleLarge` | `compactGap` after banner |
| Key-value rows | `bodyMedium` label + value | `compactGap` between rows |
| Capability chips | `labelSmall` in `radiusSm` chips | `compactGap` wrap spacing |
| Action buttons | `ZetaButton` / `NmtkOutlinedButton` | `compactGap` when stacked |
| Bundle section | `titleMedium` header | `sectionGap` above divider |
| Advanced accordion | `ZetaAccordion` title `titleMedium` | collapsed by default on mobile |

### 1.3 Action row rules

- **Pane width < 420 px:** full-width `Column` of buttons (`_stackableActionRow`).
- **Pane width ≥ 420 px, screen < 840:** `Wrap` with `spacing/runSpacing: compactGap`.
- **3+ actions on screen < 840:** always stack vertically (mobile modal standard rule 5). Reference: `akida_setup_pane.dart:290`.
- Replace remaining `FilledButton.icon` with `ZetaButton` for token consistency.

### 1.4 Primary deploy CTA

When `isCompact`:

- Hide inline `NmtkPrimaryButton` in pane body.
- Report label/state via `MobileDeployActionReporter` → `MobileDeployActionDock`.
- Dock: full-width `ZetaButton` (primary), `sectionGap` horizontal padding, safe-area bottom inset.

### 1.5 Akida advanced scaffold (inside accordion)

| Control | Mobile layout |
|---|---|
| Version selector | Label **above** `ZetaSegmentedControl` (not inline) |
| Bit-width selector | Label above control |
| Action row (4 buttons) | Stack below 420 px pane width |
| Topology preview | `SingleChildScrollView` horizontal if graph wider than viewport |

### 1.6 Pynq setup

Same structure as Akida. Up to 5 conditional actions — **must** use `_stackableActionRow`; never a single horizontal `Row` on mobile.

### 1.7 Add hardware target form

**Entry:** bottom sheet below 840 px (`isScrollControlled`, `useSafeArea`, `radiusLg` top corners, keyboard `viewInsets.bottom`).

```
┌─────────────────────────────────────┐
│ Handle + title (titleLarge)           │
├─────────────────────────────────────┤
│ SingleChildScrollView               │
│   • Target type segmented control   │
│   • Label-above-field text inputs   │
│   • Deployment mode (label above)   │
├─────────────────────────────────────┤
│ Footer actions (Column, full-width) │
│   [Cancel]  [Test connection]       │
│   [Save]                            │
└─────────────────────────────────────┘
```

**Footer (rule 5 fix — required):** below 840 px, use `Column` of full-width `ZetaButton`s, not `Wrap`. Order: Cancel (text), Test (outline), Save (primary). Cancel stays enabled during save (CEL-452 regression).

Padding: `sectionGap` on all sides; `compactGap` between stacked buttons.

### 1.8 Acceptance criteria

- [ ] No overflow at 375×667 and 390×844 (`mobile_step_audit_cel452_test.dart`)
- [ ] Deploy CTA visible without scrolling past accordion
- [ ] All actions ≥ 44 px tap target
- [ ] Hardware form footer stacked vertically on mobile

---

## 2. Assistant button placement

**Files:** `studio_assistant_host.dart`, `studio_assistant_panel.dart`

### 2.1 Launcher (FAB)

| Viewport | Control | Position |
|---|---|---|
| < 840 px | Icon-only `FloatingActionButton` + `Tooltip("Studio assistant")` | `right: sectionGap`, `bottom: height * 0.38` |
| ≥ 840 px | `FloatingActionButton.extended` with label | `right: 16`, `bottom: 16` |

Icon: `ZetaIcons.chat`, colour `colorScheme.onPrimary`.  
`heroTag: 'studio-assistant-fab'` (single instance per scaffold).

**Do not** move FAB to bottom-right on mobile — it collides with step bars (see host comment at `studio_assistant_host.dart:88-94`).

### 2.2 Panel — mobile sheet

| Property | Value |
|---|---|
| Entry | `showModalBottomSheet` |
| `isScrollControlled` | `true` |
| `useSafeArea` | `true` |
| Top radius | `tokens.radiusLg` (22 px) |
| Height | `82%` of screen (`height * 0.82`) |
| Keyboard | `Padding(bottom: viewInsets.bottom)` on sheet root |

### 2.3 Panel — internal layout

```
┌─────────────────────────────────────┐
│ Header: title + ZetaIconButton close│  ← replace raw IconButton
├─────────────────────────────────────┤
│ Setup context bar (if applicable)   │
├─────────────────────────────────────┤
│ Expanded: message timeline (scroll) │
├─────────────────────────────────────┤
│ Input row: ZetaTextInput + send     │  ← full-width field, 44px send
└─────────────────────────────────────┘
```

- Close control: **`ZetaIconButton`** (48 px), not raw `IconButton`.
- Input border: `radiusSm`; send button: `ZetaButton` icon variant, min 44 px.
- Header padding: `sectionGap` horizontal, `compactGap` vertical.

### 2.4 Panel — desktop

`endDrawer` width **380 px**; same `StudioAssistantPanel` body.

### 2.5 Acceptance criteria

- [ ] FAB does not overlap `MobileCanvasChrome`, `RunActionBar`, or `MobileDeployActionDock`
- [ ] Sheet passes mobile modal rules 2, 3, 7
- [ ] Close + send controls ≥ 44 px

---

## 3. Canvas bottom bar

**Files:** `mobile_canvas_chrome.dart`, `canvas_connect_palette.dart`, `canvas_handwriting_overlay.dart`, `component_library_sidebar.dart`, `canvas_screen.dart`

### 3.1 Floating chrome bar (`MobileCanvasChrome`)

```
        ┌──────────────────────────────┐
        │ ↩ ↪ │ ⊞ │ ＋ │ 🗑 │ extras │
        └──────────────────────────────┘
              ↑ centered, floating
```

| Property | Token / value |
|---|---|
| Position | `bottom: safeArea.bottom + sectionGap`, horizontally centered |
| Bar shape | `radiusLg` pill, `surfaceDefault` or branded Obsidian Flow (pipeline canvas) |
| Icon buttons | **44×44** (`CanvasChromeIconButton`) |
| Overflow | `SingleChildScrollView` horizontal — bar never clips off-screen |
| Shadow | `Colors.black @ 22%`, blur 16 — ZETA-MIGRATION-EXEMPT |

**Button groups (left → right):** Undo/Redo | Auto-layout | Add (optional) | Clear (optional) | `extraLeftActions` / `extraRightActions`

### 3.2 Add primitive flow (mobile)

Use `canvas_screen.dart` → `_showPaletteSheet` (4-column grid), **not** `component_library_sidebar.dart` (desktop-only collapsible sidebar; no mobile references).

Sheet spec:

| Property | Value |
|---|---|
| `maxHeight` | `height * 0.8` |
| Grid | 4 columns mobile, `compactGap` spacing |
| Tile | min 44 px, `radiusMd`, icon + `labelSmall` |

### 3.3 Connect palette (`canvas_connect_palette.dart`)

Canonical mobile pattern (listed in `mobile_modal_standard.md`):

- Bottom sheet, `useSafeArea`, keyboard-aware `maxHeight`
- Port list rows: **minHeight 44**
- Grid: 2 columns mobile, 3 desktop
- Scrollable body (`SingleChildScrollView`)

### 3.4 Handwriting overlay (`canvas_handwriting_overlay.dart`)

| Property | Current | Spec |
|---|---|---|
| Popup width | 220 px fixed | `min(220, screenWidth - 2 * sectionGap)` |
| Clear button | 24×24 | **44×44** `ZetaIconButton` |
| Suggestion chips | `Wrap` below field | `compactGap`; chips use `radiusSm` |
| Position clamp | none | Clamp popup so it stays on-screen |

### 3.5 Pipeline settings / export dialogs

Below 840 px: bottom sheet or full-width `NmtkDialogSurface` with `min(screenWidth - 2*sectionGap, 560)`. Body scrolls. Actions stack vertically when 3+.

### 3.6 Acceptance criteria

- [ ] Chrome bar icons 44×44 (`mobile_canvas_chrome_contrast_test.dart`)
- [ ] Connect palette passes all 7 modal rules
- [ ] Handwriting clear button 44×44
- [ ] No collision between chrome bar and assistant FAB at 38% offset

---

## 4. Execute Run page (Neurobench)

**Files:** `active_jobs_bar.dart`, `benchmark_workbench_tabs.dart`, `comparison_workspace.dart`, `regression_trends_screen.dart`, `play_stop_button.dart`, `workbench_shell.dart`, `run_action_bar.dart`

### 4.1 Workbench shell (mobile)

Below 840 px: `NeurobenchMobileWizard` — stacked catalog → workbench (no side-by-side split).

```
┌─────────────────────────────────────┐
│ App bar / wizard header             │
├─────────────────────────────────────┤
│ TabBar (isScrollable: true)         │  ← 6 tabs, icon + label
├─────────────────────────────────────┤
│ Tab body (SingleChildScrollView)    │
├─────────────────────────────────────┤
│ ActiveJobsBar (bottomNavigationBar) │
└─────────────────────────────────────┘
```

### 4.2 Active jobs bar

| Viewport | Layout |
|---|---|
| < 840 px | Title + status badge **stacked** vertically; `sectionGap` padding; 44 px min touch on tap targets |
| ≥ 840 px | Single horizontal row |

Status badge: semantic `NmtkShellTokens` colour + `labelSmall`.

### 4.3 Benchmark workbench tabs

- `TabBar(isScrollable: true)` — do not shrink tabs below readable width on phone.
- Tab icon colour: `onSurfaceVariant` (theme-relative).
- Each tab body: `SingleChildScrollView` wrapper.

### 4.4 Comparison workspace (mobile)

Below 840 px:

```
┌─────────────────────────────────────┐
│ Baseline dropdown (full width)      │
│        ⇅ compare icon               │
│ Current dropdown (full width)       │
│ Selection badges (stacked)          │
├─────────────────────────────────────┤
│ Chart / table content (scroll)      │
├─────────────────────────────────────┤
│ Export actions (Column, full-width) │
│   [Export CSV]                      │
│   [Export PDF]                      │
└─────────────────────────────────────┘
```

Export buttons: `Column` of full-width `ZetaButton`s on compact (not horizontal `Row`).

### 4.5 Regression trends screen

| Element | Mobile spec |
|---|---|
| Back button | `leadingWidth: 96`, label "Back" (not "Back to Workbench") |
| Title | `ellipsis` overflow |
| Chart area | `sectionGap` padding; scroll if needed |

### 4.6 Play / stop control (`play_stop_button.dart`)

| Property | Current | Spec |
|---|---|---|
| Size | 36×36 | **44×44** circle |
| Running colour | `runningColor` | keep |
| Idle | primary / studio accent | keep |
| Compact retry | `ZetaIconButton` in `RunActionBar` | 48 px built-in |

`RunActionBar`: horizontally scrollable safety net on narrow widths; primary play/stop centred.

### 4.7 neurocnl run step

`play_stop_button.dart` is shared. `RunActionBar` floats above content (similar z-order to canvas chrome). Do not duplicate bottom bars.

### 4.8 Acceptance criteria

- [ ] `mobile_qa_cel432_test.dart` — contrast pass at 390×844
- [ ] `mobile_screen_audit_cel431_test.dart` — no overflow
- [ ] Play/stop ≥ 44 px
- [ ] Comparison export buttons stacked on mobile

---

## 5. Execute Deploy page

**Files:** `deploy_review_step.dart`, `deploy_review_target_dropdown.dart`, `deploy_review_compare_chip.dart`, `deploy_review_compare_body.dart`, `deploy_review_empty_state.dart`, `compare_targets_dialog.dart`

### 5.1 Step chrome

| Viewport | Header location |
|---|---|
| < 600 px | Inline row inside step body |
| ≥ 600 px | Studio top bar (`showBelowStepperHeaderRow`) |

Inline row contents (single horizontal row, wraps only as last resort):

`DeployReviewTargetDropdown` | `DeployReviewCompareChip` | provenance label | `ReviewPublishAction`

Padding: `sectionGap` horizontal (reduce overcrowding — consider `compactGap` between inline controls on 375 px).

### 5.2 Target dropdown

- `LayoutBuilder` → `isExpanded: true` when parent width bounded.
- Long names: `ellipsis` + `Tooltip`.
- Min height 44 px.

### 5.3 Compare mode body

| Viewport | Layout |
|---|---|
| < 600 px | Vertical `ListView` of compare panes |
| ≥ 600 px | Horizontal `Row` of `Expanded` panes |

Each pane height on mobile: `clamp(320, maxHeight * 0.75, 640)`. Internal content scrolls.

### 5.4 Compare targets dialog

- `NmtkDialogSurface.constraints(context)` — no fixed 360 px box on mobile.
- `CheckboxListTile`: **not** `dense: true` (44 px rows).
- Actions: two `ZetaButton.text` in dialog footer (OK for ≤2 actions).

Below 840 px prefer bottom sheet with same body + stacked actions if a third action is added later.

### 5.5 Empty state

No in-content back button — shell AppBar provides back (documented in `deploy_review_empty_state.dart`). Centered `NmtkEmptyState` with `sectionGap` padding.

### 5.6 Single-target results

Scrollable column of deployment cards. Cards use `radiusLg`, `sectionGap` margin, status colours from tokens.

### 5.7 Acceptance criteria

- [ ] Inline header fits 375 px without overflow (dropdown + chip)
- [ ] Compare panes scroll independently on SE-class height
- [ ] Dialog/sheet passes modal standard at 375×667
- [ ] Publish action reachable without scrolling past compare panes

---

## 6. Impeccable token audit (pre-handoff)

Validated against `.impeccable/design.json` and `nmtk-flutter-review` P0 rules:

| Check | Result | Notes |
|---|---|---|
| Border radii | **PASS** | Spec uses only `radiusSm/Md/Lg`, `dialogShape`, `radiusChip` |
| Status colours | **PASS** | No inline hex; semantic tokens named |
| Shell mode | **PASS** | studio vs command assigned per surface |
| Typography | **PASS** | Space Grotesk scale from design.json |
| Spacing | **PASS** | `sectionGap` + `compactGap` only; no ad-hoc <8 px |
| Tap targets | **FIX REQUIRED** | PlayStopButton 36px, handwriting clear 24px, assistant close IconButton — called out in specs above |
| Breakpoint consistency | **DOCUMENTED** | 840 / 600 / 420 px roles defined in §0 |
| Modal standard | **PASS** | All sheet/dialog patterns reference 7-rule checklist |

---

## 7. Engineer child issue map

| Child issue focus | Primary files | Key spec sections |
|---|---|---|
| Setup step | `akida_setup_pane`, `pynq_setup_pane`, `akida_advanced_scaffold_pane`, `add_hardware_target_form` | §1 |
| Assistant | `studio_assistant_host`, `studio_assistant_panel` | §2 |
| Canvas bar | `mobile_canvas_chrome`, `canvas_connect_palette`, `canvas_handwriting_overlay` | §3 |
| Execute Run | `active_jobs_bar`, `benchmark_workbench_tabs`, `comparison_workspace`, `play_stop_button` | §4 |
| Execute Deploy | `deploy_review_step/*` | §5 |

### Shared prerequisites (apply before area-specific work)

1. Read `mobile_modal_standard.md` and run relevant audit tests after each area.
2. Build on in-progress uncommitted changes in the working tree — do not revert.
3. Fix tap-target gaps (§6) in the same PR as layout changes for that file.

### Test commands

```bash
cd nmtk/neuro_toolkit
flutter test test/mobile_step_audit_cel452_test.dart
flutter test test/mobile_qa_cel432_test.dart
flutter test test/mobile_screen_audit_cel431_test.dart
flutter test test/mobile_modal_audit_cel421_test.dart
```

---

## 8. In-progress work to preserve

The current working tree already implements partial fixes. **Build on these; do not revert:**

- `_stackableActionRow` (420 px) in Akida/Pynq/advanced setup panes
- Assistant breakpoint 900 → 840; compact FAB at 38% height; mobile bottom sheet
- `MobileCanvasChrome` 44×44 icon buttons
- Connect palette safe area + keyboard insets + 44 px port rows
- Comparison workspace stacked selectors + vertical export buttons
- Deploy review stacked compare panes + adaptive dropdown
- `studio_layout_metrics` mobile gate 600 → 840
- Hardware form: deployment mode label above control; Cancel enabled during save

Remaining gaps are explicitly listed in §§1.7, 2.3, 3.4, 4.6, and §6.
