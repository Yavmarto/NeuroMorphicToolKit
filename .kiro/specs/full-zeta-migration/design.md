# Design Document: full-zeta-migration

## Overview

This migration eliminates all inconsistencies between raw Material widget usage and the
NMTK Zeta-based design system across five module packages. It is a **pure code-level
refactor** — no new widgets, no new packages, no architecture changes. Every changed line
either replaces a widget call, substitutes a color reference, swaps a font-family string,
or drops a hardcoded radius/gap literal for a `NmtkShellTokens` token lookup.

### Scope

| Package path | Dart frontend root |
|---|---|
| `neurocnl/frontend/` | neurocnl module |
| `Neurohub/frontend/` | Neurohub module |
| `Neurobench/frontend/` | Neurobench module |
| `Neurosense/frontend/` | Neurosense module |
| `nmtk/neuro_toolkit/` | nmtk launcher / toolkit |
| `nmtk_ui_core/` | shared token + widget library (foundation) |

### Design Goals

1. Semantic purity — `Color(0xFF38BDF8)` means **running** everywhere, not "neurocnl primary."
2. Token coverage — every module-level color, font, and radius reference resolves through
   `NmtkShellTokens` or a Zeta widget's own theming layer.
3. Zero build churn — tasks are sequenced so the foundation lands before consumers change.
4. Verifiability — each task ends with a `dart analyze` pass and a documented grep
   absence check; a final CI block re-runs all six canonical grep commands.


---

## Architecture

### Dependency Graph

```
nmtk_ui_core          ← Task 1 (foundation: app_theme + shell_tokens)
    │
    ├── neurocnl/frontend    ← Tasks 2, 3, 4 (must run after Task 1)
    ├── Neurohub/frontend    ← Task 5    (independent of Tasks 2–4)
    ├── Neurobench/frontend  ← Task 6    (independent of Tasks 2–5)
    ├── Neurosense/frontend  ← Task 7    (depends on Task 1 for palette)
    └── nmtk/neuro_toolkit   ← Task 8    (independent)

nmtk_ui_core/lib/widgets  ← Task 9 (radius/gap sweep, no module deps)
```

### Wave Sequencing

The nine tasks are grouped into three ordered waves. Within a wave, tasks with no
cross-task file overlap can be executed in parallel by independent agents.

| Wave | Tasks | Constraint |
|------|-------|-----------|
| **W1 — Foundation** | Task 1 | Must land first; changes theme seed colors and adds `instrumentChannelPalette`. Consumers break without this. |
| **W2 — Module sweeps** | Tasks 2, 3, 4, 5, 6, 7, 8 | All read from the W1 output. Tasks 5–8 are fully independent of each other and of Tasks 2–4. Tasks 2 and 3 within neurocnl touch overlapping files; run sequentially (2 → 3 → 4). |
| **W3 — Core widgets** | Task 9 | Touches only `nmtk_ui_core/lib/widgets/`; no module file overlap. Can run after W1. |

### File Mutation Budget per Task

No task crosses package boundaries except Task 1 (which only writes `nmtk_ui_core`).
Every module task writes only that module's `frontend/lib/` directory tree.


---

## Components and Interfaces

### Token Sources (read-only during migration)

These classes are the **target vocabulary** that migration outputs must reference. No
migration task changes these except Task 1's additions.

#### `NmtkShellTokens` (`nmtk_ui_core/lib/shell_tokens.dart`)

Runtime `ThemeExtension` accessed via `NmtkShellTokens.of(context)`. Key fields used by
migration:

| Field | Type | Semantic |
|---|---|---|
| `healthyColor` | `Color` | `0xFF22C55E` — success / healthy |
| `runningColor` | `Color` | `0xFF38BDF8` — active / in-progress |
| `degradedColor` | `Color` | `0xFFF59E0B` — reduced capability |
| `warningColor` | `Color` | `0xFFF97316` — threshold / caution |
| `errorColor` | `Color` | `0xFFEF4444` — failure |
| `liveColor` | `Color` | `0xFFE11D48` — recording |
| `metadataForeground` | `Color` | dim text / labels |
| `subtleBorder` | `Color` | chart grid lines / axis ticks |
| `chromeBorder` | `Color` | strong borders |
| `radiusSm` | `double` | `12` — inputs, chips, tags |
| `radiusMd` | `double` | `16` — buttons, small cards |
| `radiusLg` | `double` | `22` — section cards |
| `radiusChip` | `double` | `999` — pill badges |
| `sectionGap` | `double` | `16` — section padding |
| `compactGap` | `double` | `8` — tight padding |
| `studioPalette.accent` | `Color` | `0xFF8B5CF6` dark / `0xFF7C3AED` light |
| `instrumentPalette.accent` | `Color` | `0xFF06B6D4` dark / `0xFF0F766E` light |
| `instrumentChannelPalette` | `List<Color>` | **Added by Task 1** — 8-entry channel palette |

**Static accessor pattern (inside `StatelessWidget.build` or `State.build`):**
```dart
final tokens = NmtkShellTokens.of(context);
```

**Static accessor pattern (inside `CustomPainter` — no BuildContext):**
```dart
// Painter receives colors as constructor parameters sourced from NmtkShellTokens
class _MyPainter extends CustomPainter {
  final Color channelColor;
  const _MyPainter({required this.channelColor});
}
// Caller (in build method):
CustomPaint(painter: _MyPainter(channelColor: tokens.healthyColor))
```

#### `NmtkFontFamilies` (`nmtk_ui_core/lib/app_theme.dart`)

```dart
NmtkFontFamilies.monospace  // 'JetBrains Mono'
NmtkFontFamilies.package    // 'nmtk_ui_core'
```

#### `NmtkNeurocnlTokens` (restricted scope after migration)

Post-migration, `NmtkNeurocnlTokens` fields are **only valid** in:
- CNL editor syntax highlighting (`synKeyword`, `synSubject`, `synNumber`, etc.)
- Network-graph node/edge color assignments
- `NmtkThemeExtension` fields in `app_theme.dart`

Any other use is a violation.


---

## Data Models

### Replacement Pattern Catalogue

This section is the canonical reference for every substitution an implementer must
perform. Each pattern is precise enough to apply mechanically.

---

#### Pattern A — `FilledButton` → `ZetaButton`

**A1. Basic filled button with Text child**
```dart
// BEFORE
FilledButton(
  onPressed: _onPressed,
  child: const Text('Run'),
)

// AFTER
ZetaButton(
  onPressed: _onPressed,
  label: 'Run',
)
```

**A2. Disabled state (onPressed: null)**
```dart
// BEFORE
FilledButton(
  onPressed: null,
  child: const Text('Save'),
)

// AFTER
ZetaButton(
  onPressed: null,  // ZetaButton renders built-in disabled styling
  label: 'Save',
)
```

**A3. Loading state (conditional CircularProgressIndicator child)**
```dart
// BEFORE
FilledButton(
  onPressed: _loading ? null : _doAction,
  child: _loading
      ? const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2))
      : const Text('Run'),
)

// AFTER
ZetaButton(
  onPressed: _loading ? null : _doAction,
  label: 'Run',
  // onPressed: null causes ZetaButton to render its disabled/loading state.
  // Remove the CircularProgressIndicator child entirely.
)
```

**A4. Tonal variant**
```dart
// BEFORE
FilledButton.tonal(
  onPressed: _onPressed,
  child: const Text('Cancel'),
)

// AFTER
ZetaButton(
  onPressed: _onPressed,
  label: 'Cancel',
  type: ZetaButtonType.subtle,
)
```

**A5. Icon variant**
```dart
// BEFORE
FilledButton.icon(
  onPressed: _onPressed,
  icon: const Icon(Icons.upload),
  label: const Text('Import'),
)

// AFTER
ZetaButton(
  onPressed: _onPressed,
  label: 'Import',
  leading: const Icon(Icons.upload),
)
```

**A6. Style override with color — button type mapping**

| `backgroundColor` source | `ZetaButtonType` |
|---|---|
| `NmtkNeurocnlTokens.primary` | `ZetaButtonType.primary` |
| `studioPalette.accent` | `ZetaButtonType.primary` |
| `NmtkShellTokens.errorColor` | `ZetaButtonType.negative` |
| `Colors.grey` / neutral token | `ZetaButtonType.subtle` |
| Unknown raw literal | `ZetaButtonType.primary` + `// ZETA-MIGRATION-TODO: verify button type` |

**A7. Non-Text child — leave a TODO**
```dart
// BEFORE
FilledButton(
  onPressed: _onPressed,
  child: Row(children: [Icon(Icons.add), Text('Add')]),
)

// AFTER — leave untouched with annotation
FilledButton( // ZETA-MIGRATION-TODO: non-Text child, manual migration required
  onPressed: _onPressed,
  child: Row(children: [Icon(Icons.add), Text('Add')]),
)
```


---

#### Pattern B — `TextField` / `TextFormField` → `ZetaTextInput`

**Full parameter mapping table**

| `TextField` / `TextFormField` parameter | `ZetaTextInput` parameter | Notes |
|---|---|---|
| `controller` | `controller` | Direct pass-through |
| `onChanged` | `onChanged` | Direct pass-through |
| `keyboardType` | `keyboardType` | Direct pass-through |
| `obscureText: true` | `obscureText: true` | Direct pass-through |
| `maxLines` | `maxLines` | Direct pass-through |
| `enabled: false` | `disabled: true` | Inverted polarity |
| `focusNode` | `focusNode` | Direct pass-through |
| `validator` | `validator` | `TextFormField` only |
| `decoration: InputDecoration(hintText: ...)` | `hint: ...` | |
| `decoration: InputDecoration(labelText: ...)` | `label: ...` | |
| `decoration: InputDecoration(helperText: ...)` | Append to `hint` with space | e.g. `hint: '$hint $helper'` |
| `decoration: InputDecoration(prefixIcon: ...)` | `leading: ...` | |
| `decoration: InputDecoration(suffixIcon: ...)` | `trailing: ...` | |
| `decoration: InputDecoration(errorText: ...)` | `errorText: ...` | |
| Any other `InputDecoration` param | Drop + `// ZETA-MIGRATION-TODO: <param> has no ZetaTextInput equivalent` | |
| Any other `TextField` param not above | Drop + `// ZETA-MIGRATION-TODO: <param> dropped` | |

**B1. Simple text field**
```dart
// BEFORE
TextField(
  controller: _ctrl,
  decoration: const InputDecoration(
    labelText: 'Project Name',
    hintText: 'Enter a name',
  ),
  onChanged: _onChanged,
)

// AFTER
ZetaTextInput(
  controller: _ctrl,
  label: 'Project Name',
  hint: 'Enter a name',
  onChanged: _onChanged,
)
```

**B2. Form field with validator**
```dart
// BEFORE
TextFormField(
  controller: _ctrl,
  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
  decoration: const InputDecoration(labelText: 'Email'),
)

// AFTER
ZetaTextInput(
  controller: _ctrl,
  label: 'Email',
  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
)
```

**B3. Disabled field**
```dart
// BEFORE
TextField(
  controller: _ctrl,
  enabled: false,
  decoration: const InputDecoration(labelText: 'Read-only'),
)

// AFTER
ZetaTextInput(
  controller: _ctrl,
  label: 'Read-only',
  disabled: true,
)
```

**B4. Field with prefix and suffix icons**
```dart
// BEFORE
TextField(
  decoration: InputDecoration(
    labelText: 'Search',
    prefixIcon: const Icon(Icons.search),
    suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: _clear),
  ),
)

// AFTER
ZetaTextInput(
  label: 'Search',
  leading: const Icon(Icons.search),
  trailing: IconButton(icon: const Icon(Icons.clear), onPressed: _clear),
)
```

**B5. Monospace-font text field (combined with Pattern D)**
```dart
// BEFORE
TextField(
  style: const TextStyle(fontFamily: 'monospace'),
  ...
)

// AFTER
ZetaTextInput(
  // ZetaTextInput does not expose a style parameter.
  // If monospace font is needed, wrap in a Theme override or use a
  // RawTextField after confirming ZetaTextInput cannot accommodate it.
  // ZETA-MIGRATION-TODO: monospace style — verify ZetaTextInput theming path
  ...
)
```


---

#### Pattern C — `Colors.X` → `NmtkShellTokens` semantic tokens

**C1. Widget build context (most cases)**
```dart
// BEFORE
Container(color: Colors.green)

// AFTER
Container(color: NmtkShellTokens.of(context).healthyColor)
```

**C2. CustomPainter — no BuildContext available**
```dart
// BEFORE
class _StatusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.green;
    // ...
  }
}

// AFTER — pass color as constructor parameter
class _StatusPainter extends CustomPainter {
  final Color healthyColor;
  const _StatusPainter({required this.healthyColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = healthyColor;
    // ...
  }
}

// Caller in build():
CustomPaint(
  painter: _StatusPainter(
    healthyColor: NmtkShellTokens.of(context).healthyColor,
  ),
)
```

**C3. Full color substitution table**

| Raw `Colors.X` | NmtkShellTokens field | Notes |
|---|---|---|
| `Colors.green` / `Colors.green.shadeXXX` | `healthyColor` | |
| `Colors.red` / `Colors.red.shadeXXX` / `Colors.redAccent` | `errorColor` | |
| `Colors.orange` (threshold/warning context) | `warningColor` | |
| `Colors.orange` (reduced-capability context) | `degradedColor` | annotate with TODO if ambiguous |
| `Colors.grey` (text/metadata) | `metadataForeground` | |
| `Colors.grey` (chart grid / axis tick) | `subtleBorder` | |
| `Colors.black54` | `metadataForeground` | |
| `Colors.blue` in `neurocnl/` files | `studioPalette.accent` | |
| `Colors.blue` in `Neurosense/` / `Neurobench/` files | `instrumentPalette.accent` | |
| `Colors.blue` in `Neurohub/` / `nmtk/` files | `commandPalette.accent` | |
| Any other `Colors.X` not in table | Leave unchanged + `// ZETA-MIGRATION-TODO: unrecognized Colors.X usage — review manually` | |


---

#### Pattern D — Bare monospace font string → `NmtkFontFamilies`

```dart
// BEFORE
TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
)

// AFTER
TextStyle(
  fontFamily: NmtkFontFamilies.monospace,
  package: NmtkFontFamilies.package,
  fontSize: 13,
)
```

The same substitution applies for `'Courier'` and `'Consolas'`. Both `fontFamily` and
`package` must be set together; setting only `fontFamily` without `package` will cause
Flutter to fall back to the platform monospace font.

---

#### Pattern E — `BorderRadius.circular(N)` → token

**Radius token selection table**

| Literal value `N` | Token | Semantic |
|---|---|---|
| `< 12` (e.g., 6, 8, 10) | `tokens.radiusSm` (12) | Input fields, inline chips, tags |
| `12` | `tokens.radiusSm` (12) | Same |
| `16` or `14`–`18` (non-dialog) | `tokens.radiusMd` (16) | Buttons, small cards |
| `> 18` and `≤ 20` (dialog/sheet) | `tokens.radiusMd` (16) | Modal surfaces |
| `> 20` (dialog/sheet) | `tokens.radiusLg` (22) | Large modal surfaces |
| `999` | `tokens.radiusChip` (999) | Pill badges |
| Intentional platform override | Unchanged + `// ZETA-MIGRATION-EXEMPT: <reason>` | |

```dart
// BEFORE
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(6),
  ),
)

// AFTER
final tokens = NmtkShellTokens.of(context);
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(tokens.radiusSm),
  ),
)
```

**Removing `const` when a token lookup is introduced:**
```dart
// BEFORE (const context)
const DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
  ),
)

// AFTER — const must be removed because token lookup is runtime
DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(tokens.radiusSm),
  ),
)
```

---

#### Pattern F — `instrumentChannelPalette` for signal channels

```dart
// BEFORE — inline color list
final _channelColors = [
  Colors.cyan,
  Colors.teal,
  Colors.blue,
  // ...
];

// AFTER — reference canonical palette
// In build():
final channelColor = NmtkShellTokens.instrumentChannelPalette[
    channelIndex % NmtkShellTokens.instrumentChannelPalette.length];
```

For `CustomPainter`:
```dart
// Pass the resolved List<Color> to the painter constructor
CustomPaint(
  painter: _SignalPainter(
    channelColors: NmtkShellTokens.instrumentChannelPalette,
  ),
)

class _SignalPainter extends CustomPainter {
  final List<Color> channelColors;
  const _SignalPainter({required this.channelColors});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < channelCount; i++) {
      final color = channelColors[i % channelColors.length];
      // ...
    }
  }
}
```


---

## Task Decomposition

Each task below maps to an implementation unit. File lists are the **known mutation set**;
implementers must grep for additional instances before declaring a task complete.

---

### Task 1 — nmtk_ui_core Foundation Changes (P0, Wave 1)

**Touches:** `nmtk_ui_core/lib/app_theme.dart`, `nmtk_ui_core/lib/shell_tokens.dart`

Must land before any module task. Consumers cannot compile without the
`instrumentChannelPalette` constant and will produce wrong theme seeds if the
`_seedForVariant` change is absent.

#### 1a. `app_theme.dart` — Fix `_seedForVariant` for neurocnl

```dart
// BEFORE
case NmtkThemeVariant.neurocnl:
  return NmtkNeurocnlTokens.primary;   // returns 0xFF38BDF8 — WRONG

// AFTER
case NmtkThemeVariant.neurocnl:
  return const Color(0xFF8B5CF6);      // Studio Violet (dark default)
```

#### 1b. `app_theme.dart` — Fix `_neurocnlDarkTheme()` seed and button themes

Change the `ColorScheme.fromSeed(seedColor:)` call:
```dart
// BEFORE
seedColor: NmtkNeurocnlTokens.primary,

// AFTER
seedColor: const Color(0xFF8B5CF6),  // NmtkShellTokens.dark.studioPalette.accent
```

Change `elevatedButtonTheme` and `outlinedButtonTheme` in `_neurocnlDarkTheme()`:
```dart
// BEFORE — ElevatedButtonThemeData
backgroundColor: NmtkNeurocnlTokens.primary,
foregroundColor: Colors.white,

// AFTER
backgroundColor: const Color(0xFF8B5CF6),
foregroundColor: Colors.white,

// BEFORE — OutlinedButtonThemeData
foregroundColor: NmtkNeurocnlTokens.primary,
side: const BorderSide(color: NmtkNeurocnlTokens.primary),

// AFTER
foregroundColor: const Color(0xFF8B5CF6),
side: const BorderSide(color: Color(0xFF8B5CF6)),
```

#### 1c. `app_theme.dart` — Fix `_neurocnlLightTheme()` seed and button themes

```dart
// BEFORE
seedColor: NmtkNeurocnlTokens.primary,  // in ColorScheme.fromSeed

// AFTER
seedColor: const Color(0xFF7C3AED),  // NmtkShellTokens.light.studioPalette.accent

// ElevatedButtonThemeData
// BEFORE
backgroundColor: NmtkNeurocnlTokens.primary,
// AFTER
backgroundColor: const Color(0xFF7C3AED),
```

#### 1d. `app_theme.dart` — Add doc comments to `NmtkNeurocnlTokens` status fields

```dart
/// Restricted to CNL-editor syntax diagnostics and network-graph canvas
/// elements only. For module-level status UI, use [NmtkShellTokens] instead.
static const Color success = Color(0xFF4ADE80);

/// Restricted to CNL-editor syntax diagnostics and network-graph canvas
/// elements only. For module-level status UI, use [NmtkShellTokens] instead.
static const Color error = Color(0xFFFF5C7A);

/// Restricted to CNL-editor syntax diagnostics and network-graph canvas
/// elements only. For module-level status UI, use [NmtkShellTokens] instead.
static const Color warning = Color(0xFFFFB347);
```

#### 1e. `shell_tokens.dart` — Add `instrumentChannelPalette`

Add as a `static const` field directly on `NmtkShellTokens` (not inside
`fromColorScheme`; it is a constant, not a theme-brightness-dependent value):

```dart
/// Canonical 8-color palette for multi-channel instrument signal visualizations.
///
/// Colors are drawn from the instrument-mode teal/cyan family and are indexed
/// by channel number modulo 8. See DESIGN.md §5.3 Instrument Channel Palette.
static const List<Color> instrumentChannelPalette = [
  Color(0xFF06B6D4), // cyan-500
  Color(0xFF65C4C4), // cyan-400 muted
  Color(0xFF91E1E1), // cyan-300 muted
  Color(0xFFBCFBFB), // cyan-200 muted
  Color(0xFF0F766E), // teal-700
  Color(0xFF1A8080), // teal-600 muted
  Color(0xFF003535), // teal-900
  Color(0xFF0A1616), // teal-950
];
```

**Verification after Task 1:**
```bash
dart analyze nmtk_ui_core/
grep -c 'NmtkNeurocnlTokens\.primary' nmtk_ui_core/lib/app_theme.dart
# Expected: 0 matches inside ColorScheme.fromSeed and button theme calls
```


---

### Task 2 — neurocnl FilledButton Sweep (Wave 2)

**Package:** `neurocnl/frontend/`  
**Apply Pattern A** to all instances below. Run `dart analyze neurocnl/frontend/` after
each file.

| File | Instance count | Notes |
|---|---|---|
| `lib/screens/studio_screen.dart` | 8 | Mix of basic + disabled; check for loading-state guards |
| `lib/widgets/cnl_sentence_builder_dialog.dart` | 1 | Basic |
| `lib/widgets/cnl_editor.dart` | 1 | Basic |
| `lib/widgets/simulator_panel.dart` | 2 | May include disabled state |
| `lib/widgets/nir_importer_tab.dart` | 2 | May include `FilledButton.icon` |
| `lib/widgets/training_inspector_panel.dart` | 1 | Basic |
| `lib/widgets/template_load_guard.dart` | 1 | Basic |

**Import to add if not present:**
```dart
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
```

**Verification after Task 2:**
```bash
dart analyze neurocnl/frontend/
grep -r 'FilledButton\b' neurocnl/frontend/lib --include='*.dart' | \
  grep -v 'ZETA-MIGRATION-TODO'
# Expected: 0 lines
```

---

### Task 3 — neurocnl TextField/TextFormField + Monospace Sweep (Wave 2)

**Package:** `neurocnl/frontend/`  
**Apply Pattern B** for text inputs. **Apply Pattern D** for monospace font strings.

| File | TextField count | Monospace |
|---|---|---|
| `lib/screens/studio_screen.dart` | 4 | No |
| `lib/widgets/cnl_editor.dart` | 2 | No |
| `lib/widgets/simulator_panel.dart` | 2 | No |
| `lib/screens/server_setup_screen.dart` | 1 | No |
| `lib/screens/project_screen.dart` | 2 | No |
| `lib/screens/sweep_screen.dart` | 4 | No |
| `lib/widgets/learning_config_panel.dart` | 1 | No |
| `lib/widgets/akida_deploy_panel.dart` | 1 | No |
| `lib/screens/export_screen.dart` | 0 | Yes (1) |
| `lib/widgets/nir_importer_tab.dart` | 0 | Yes (1) |
| `lib/screens/export_dialog.dart` | 0 | Yes (1) |
| `lib/screens/simulation_dashboard.dart` | 0 | Yes (1) |

**Verification after Task 3:**
```bash
dart analyze neurocnl/frontend/
grep -r '\bTextField\(' neurocnl/frontend/lib --include='*.dart'
grep -r '\bTextFormField\(' neurocnl/frontend/lib --include='*.dart'
grep -r "fontFamily:.*'monospace'" neurocnl/frontend/lib --include='*.dart'
# All three: expected 0 lines
```

---

### Task 4 — neurocnl Colors.X + Channel Palette Sweep (Wave 2)

**Package:** `neurocnl/frontend/`  
**Apply Pattern C** for semantic color replacement.  
**Apply Pattern F** for `sensor_time_series_chart.dart` channel palette.

| File | Colors.X refs | Notes |
|---|---|---|
| `lib/widgets/simulator_panel.dart` | Yes | Colors.X status signals |
| `lib/widgets/training_inspector_panel.dart` | `Colors.grey` | Metadata text |
| `lib/widgets/sensor_time_series_chart.dart` | Channel list | Pattern F — replace with `instrumentChannelPalette` |

Also review `NmtkNeurocnlTokens.success` / `.error` references in any status-indicator
widget. Check:
- `lib/widgets/training_inspector_panel.dart` — `NmtkNeurocnlTokens.success` / `.error`
  in health-badge contexts must become `NmtkShellTokens.of(context).healthyColor` /
  `.errorColor`.

**Verification after Task 4:**
```bash
dart analyze neurocnl/frontend/
grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" \
  neurocnl/frontend/lib --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'
grep -r "Colors\.\(blue\|cyan\|teal\)" \
  neurocnl/frontend/lib/widgets/sensor_time_series_chart.dart
# Expected: 0 lines
```


---

### Task 5 — Neurohub Sweep (Wave 2, parallel with Tasks 3–4)

**Package:** `Neurohub/frontend/`  
**Apply Patterns A, B, C** as indicated.

| File | FilledButton | TextField | Colors.X | Notes |
|---|---|---|---|---|
| `lib/screens/login_screen.dart` | 0 | 6 | `Colors.red` | Pattern B (6x) + C for Colors.red |
| `lib/screens/new_project_screen.dart` | 0 | 2 | — | Pattern B |
| `lib/screens/share_model_screen.dart` | 0 | 3 | — | Pattern B |
| `lib/screens/asset_library_screen.dart` | 0 | 1 | — | Pattern B |
| `lib/screens/dashboard_screen.dart` | 0 | 1 | — | Pattern B |
| `lib/widgets/onboarding_tour.dart` | 0 | 0 | `Colors.black54` | Pattern C → metadataForeground |

**Verification after Task 5:**
```bash
dart analyze Neurohub/frontend/
grep -r '\bTextField\(' Neurohub/frontend/lib --include='*.dart'
grep -r '\bTextFormField\(' Neurohub/frontend/lib --include='*.dart'
grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" \
  Neurohub/frontend/lib --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'
# All: expected 0 lines
```

---

### Task 6 — Neurobench Sweep (Wave 2, parallel)

**Package:** `Neurobench/frontend/`  
**Apply Patterns A, B, C** as indicated.

| File | FilledButton | TextField | Colors.X | Notes |
|---|---|---|---|---|
| `lib/screens/workbench_shell.dart` | 2 | 3 | — | Patterns A + B |
| `lib/screens/report_builder.dart` | 0 | 1 | — | Pattern B |
| `lib/widgets/metric_diff_table.dart` | 0 | 0 | `Colors.green`, `Colors.red`, `Colors.grey` | Pattern C — may need CustomPainter variant |
| `lib/widgets/robustness_curve_chart.dart` | 0 | 0 | `Colors.X` | Pattern C — chart painter; use constructor param |
| `lib/widgets/target_comparison_grid.dart` | 0 | 0 | `Colors.X` | Pattern C |
| `lib/widgets/run_history_timeline.dart` | 0 | 0 | `Colors.green` | Pattern C → healthyColor |
| `lib/widgets/trend_chart.dart` | 0 | 0 | `Colors.grey` | Pattern C; check grid vs. text context |

**Note on chart painters:** `robustness_curve_chart.dart` and `trend_chart.dart` likely
contain `CustomPainter` subclasses. Apply the constructor-parameter pattern (Pattern C2)
for all color references inside `paint()` methods.

**Verification after Task 6:**
```bash
dart analyze Neurobench/frontend/
grep -r 'FilledButton\b' Neurobench/frontend/lib --include='*.dart' | \
  grep -v 'ZETA-MIGRATION-TODO'
grep -r '\bTextField\(' Neurobench/frontend/lib --include='*.dart'
grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" \
  Neurobench/frontend/lib --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'
# All: expected 0 lines
```


---

### Task 7 — Neurosense Sweep (Wave 2, parallel; depends on Task 1)

**Package:** `Neurosense/frontend/`  
**Apply Patterns B, C, D, F** as indicated. Task 1 must land first because
`instrumentChannelPalette` is referenced here.

| File | TextField | Monospace | Colors.X | Channel palette | Notes |
|---|---|---|---|---|---|
| `lib/screens/recording_controls.dart` | 2 | Yes (1) | — | — | Patterns B + D |
| `lib/screens/replay_controls.dart` | 1 | — | — | — | Pattern B |
| `lib/widgets/support_level_badge.dart` | 0 | — | `Colors.X` status | — | Pattern C |
| `lib/widgets/live_signal_viewer.dart` | 0 | — | — | Yes | Pattern F — update widget + painter |
| `lib/widgets/spike_encoding_panel.dart` | 0 | — | — | Yes | Pattern F — update widget + painter |

**Verification after Task 7:**
```bash
dart analyze Neurosense/frontend/
grep -r '\bTextField\(' Neurosense/frontend/lib --include='*.dart'
grep -r "fontFamily:.*'monospace'" Neurosense/frontend/lib --include='*.dart'
grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" \
  Neurosense/frontend/lib --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'
grep -r "Colors\.\(blue\|cyan\|teal\)" \
  Neurosense/frontend/lib/widgets/live_signal_viewer.dart \
  Neurosense/frontend/lib/widgets/spike_encoding_panel.dart
# All: expected 0 lines
```

---

### Task 8 — nmtk/neuro_toolkit Sweep (Wave 2, parallel)

**Package:** `nmtk/neuro_toolkit/`  
**Apply Patterns A, B, D** as indicated.

| File | FilledButton | TextField | Monospace | Notes |
|---|---|---|---|---|
| `lib/screens/server_setup.dart` | 0 | 1 | — | Pattern B |
| `lib/screens/backend_setup.dart` | 2 | 1 | — | Pattern A (2x, includes FilledButton.tonal) + B |
| `lib/screens/settings.dart` | 0 | 4 | — | Pattern B |
| `lib/screens/python_setup.dart` | 0 | 0 | Yes (1) | Pattern D |

**Verification after Task 8:**
```bash
dart analyze nmtk/neuro_toolkit/
grep -r 'FilledButton\b' nmtk/neuro_toolkit/lib --include='*.dart' | \
  grep -v 'ZETA-MIGRATION-TODO'
grep -r '\bTextField\(' nmtk/neuro_toolkit/lib --include='*.dart'
grep -r "fontFamily:.*'monospace'" nmtk/neuro_toolkit/lib --include='*.dart'
# All: expected 0 lines
```

---

### Task 9 — nmtk_ui_core Widgets Radius/Gap Sweep (Wave 3)

**Package:** `nmtk_ui_core/lib/widgets/`  
**Apply Pattern E** to all instances.

| File | Literal | Replacement | Notes |
|---|---|---|---|
| `desktop_scaffold.dart` | `BorderRadius.circular(6)` | `tokens.radiusSm` | Remove `const` if needed |
| `surface_card.dart` | `BorderRadius.circular(12)` | `tokens.radiusSm` | Remove `const` if needed |
| `summary_card.dart` | `BorderRadius.circular(12)` | `tokens.radiusSm` | Remove `const` if needed |
| `pipeline_stepper.dart` | `BorderRadius.circular(12)` | `tokens.radiusSm` | Remove `const` if needed |
| `validation_chip.dart` | `BorderRadius.circular(999)` | `tokens.radiusChip` | Remove `const` if needed |
| `workflow_step_row.dart` | `BorderRadius.circular(999)` | `tokens.radiusChip` | Remove `const` if needed |
| `info_chip.dart` | `BorderRadius.circular(999)` | `tokens.radiusChip` | Remove `const` if needed |
| `workspace_shell.dart` | `EdgeInsets.fromLTRB(20, 20, 10, 20)` | `EdgeInsets.all(tokens.sectionGap)` | Annotate if asymmetry was intentional |

**Const removal procedure:** When a `BorderRadius.circular(tokens.xxx)` call is inside a
`const` constructor, change the enclosing widget from `const WidgetName(...)` to
`WidgetName(...)`. The radius token lookup (`tokens.radiusSm`) is a runtime field access
and cannot be `const`.

**Verification after Task 9:**
```bash
dart analyze nmtk_ui_core/
grep -r 'BorderRadius\.circular([0-9]' nmtk_ui_core/lib/widgets --include='*.dart' | \
  grep -v 'ZETA-MIGRATION-EXEMPT'
grep -r 'EdgeInsets\.fromLTRB' \
  nmtk_ui_core/lib/widgets/workspace_shell.dart
# Both: expected 0 lines
```


---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid
executions of a system — essentially, a formal statement about what the system should do.
Properties serve as the bridge between human-readable specifications and
machine-verifiable correctness guarantees.*

This migration is primarily a code-shape transformation (absence invariants, constant
checks, grep-verifiable rules). Most acceptance criteria are best verified by static
analysis and CI grep assertions rather than property-based testing. However, three
genuine universal properties emerge from the requirements where input variation materially
affects correctness.

The property-based testing library for this project's Dart/Flutter context is
[`dart_test`](https://pub.dev/packages/test) together with
[`test_randomize_ordering_seed`](https://pub.dev/packages/test) for iteration seeding, or
the `fast_check` / `dart_quickcheck` package if available in the project's dependency
graph. Each property test must run a minimum of **100 iterations**.

---

### Property 1: TextField/ZetaTextInput parameter mapping completeness

*For any* combination of supported `TextField` / `TextFormField` parameters
(from the canonical mapping table: `controller`, `onChanged`, `keyboardType`,
`obscureText`, `maxLines`, `enabled`/`disabled`, `focusNode`, `hintText`, `labelText`,
`helperText`, `prefixIcon`, `suffixIcon`, `errorText`, `validator`), the migration
function that produces a `ZetaTextInput` SHALL have every mapped field set to the
corresponding value, and every unmapped field SHALL be absent from the output.

*For any* randomly generated `TextFieldConfig` struct (a bag of optional parameter
values drawn from the supported set), applying `migrateToZetaTextInput(config)` SHALL
return a `ZetaTextInput` where:
- `hint` equals `config.hintText` (or the concatenation of `hintText` and `helperText`
  when both are non-null)
- `label` equals `config.labelText` when present
- `disabled` equals `!config.enabled` when `enabled` is explicitly set
- `leading` equals `config.prefixIcon` when present
- `trailing` equals `config.suffixIcon` when present

**Validates: Requirements 3.3, 3.4**

---

### Property 2: Validator round-trip — validator return propagates to `errorText`

*For any* validator function `v: String? → String?` and any input string `s`, if the
migrated `ZetaTextInput` is evaluated with `validator(s)`:
- WHEN `v(s)` returns a non-null, non-empty string `e`, THEN `errorText` SHALL equal `e`
- WHEN `v(s)` returns `null`, THEN `errorText` SHALL be `null`

This ensures the `TextFormField` → `ZetaTextInput` migration does not silently discard
validation state.

*For any* randomly generated (validator function, input string) pair, the
`errorText` field of the resulting `ZetaTextInput` SHALL match the validator's return
value exactly.

**Validates: Requirements 3.6**

---

### Property 3: Channel color index modulo wrap — no RangeError, correct color

*For any* channel count `N` (where `N ≥ 1`) and any channel index `i` (where
`i ≥ 0`), the color assigned to channel `i` SHALL equal
`NmtkShellTokens.instrumentChannelPalette[i % 8]` and SHALL NOT throw a `RangeError`.

This property holds regardless of whether `N > 8`, `i > 7`, or `i > N`, ensuring the
modulo-wrap overflow behavior is correct for all signal channel counts.

*For any* randomly generated `(N, i)` pair with `N` in `[1, 1000]` and `i` in
`[0, 9999]`:
- `palette[i % palette.length]` SHALL return a valid `Color`
- No exception SHALL be thrown
- The returned color SHALL be a member of the 8-element canonical instrument palette set

**Validates: Requirements 6.3, 6.7**


---

## Error Handling

### Build-time violations

Per Requirement 1.6, any `Color` literal whose value equals `0xFF38BDF8` appearing
outside a CNL/graph context shall trigger a build-time analysis error. This is
implemented as a custom `dart analyze` lint rule (or a pre-commit grep check) rather
than a runtime assertion.

**Implementation note:** Until a custom lint plugin is in place, enforce via CI:
```bash
# In CI, before build step:
VIOLATIONS=$(grep -rn 'Color(0xFF38BDF8)' neurocnl/frontend/lib --include='*.dart' | \
  grep -v -E '(nodeEnsemble|nodeMotor|edgeExcitatory|nodeGenericEnsemble|synSubject|runningColor)')
if [ -n "$VIOLATIONS" ]; then
  echo "[NMTK-MIGRATION-VIOLATION] 0xFF38BDF8 used as accent outside allowed contexts:"
  echo "$VIOLATIONS"
  exit 1
fi
```

### Migration TODO annotations

When an automated pattern cannot be applied cleanly, the migration leaves an annotated
comment rather than an incorrect substitution. These annotations are the error-recovery
path:

| Annotation | Meaning |
|---|---|
| `// ZETA-MIGRATION-TODO: non-Text child, manual migration required` | FilledButton child is not a Text widget |
| `// ZETA-MIGRATION-TODO: verify button type` | Unknown backgroundColor literal in FilledButton style |
| `// ZETA-MIGRATION-TODO: <param> has no ZetaTextInput equivalent` | InputDecoration parameter dropped |
| `// ZETA-MIGRATION-TODO: <param> dropped` | TextField behavioral parameter dropped |
| `// ZETA-MIGRATION-TODO: unrecognized Colors.X usage — review manually` | Colors.X not in substitution table |
| `// ZETA-MIGRATION-TODO: asymmetric padding replaced with symmetric; verify visually` | EdgeInsets.fromLTRB replaced with symmetric |
| `// ZETA-MIGRATION-EXEMPT: <reason>` | BorderRadius literal intentionally retained |

All `ZETA-MIGRATION-TODO` annotations become post-migration backlog items. A non-zero
count of TODO annotations does not block merging the migration PR, but each must be
resolved before the feature is considered fully closed.

### `dart analyze` gate

After every individual file migration, the implementer must run:
```bash
dart analyze <package_root>/ 2>&1 | grep -E '(error|warning)' | grep -v 'info'
```
Any `undefined_identifier` or `argument_type_not_assignable` error in a migrated file
is a blocker. Fix before moving to the next file.


---

## Testing Strategy

### Dual Testing Approach

This migration is primarily a **static-analysis + absence-invariant** verification
problem. The testing strategy combines:

1. **CI grep assertions** — six canonical grep commands that must return zero matches
   (the primary correctness gate)
2. **`dart analyze` pass** — run after every file and after each task completes
3. **Property-based tests** — three properties where input variation reveals bugs
4. **Unit/example tests** — specific constant-value and code-shape assertions

---

### CI Verification: Six Canonical Grep Commands

These commands are the **final acceptance gate** and must be added to the CI pipeline
as a required step that runs after all migration tasks complete:

```bash
# 1. Zero FilledButton references (excluding explicit TODO lines)
grep -r 'FilledButton\b' neurocnl Neurohub Neurobench Neurosense nmtk \
  --include='*.dart' | grep -v 'ZETA-MIGRATION-TODO'

# 2. Zero bare TextField widget instantiations
grep -r '\bTextField\(' neurocnl Neurohub Neurobench Neurosense nmtk \
  --include='*.dart'

# 3. Zero bare TextFormField widget instantiations
grep -r '\bTextFormField\(' neurocnl Neurohub Neurobench Neurosense nmtk \
  --include='*.dart'

# 4. Zero raw status color references in module files (excluding TODO lines)
grep -r "Colors\.\(green\|red\|redAccent\|orange\|grey\|black54\)" \
  Neurobench Neurosense Neurohub neurocnl --include='*.dart' | \
  grep -v 'ZETA-MIGRATION-TODO'

# 5. Zero bare monospace font-family strings
grep -r "fontFamily:.*'monospace'" neurocnl Neurosense nmtk --include='*.dart'

# 6. Zero bare numeric radius literals in nmtk_ui_core widgets (excluding EXEMPT)
grep -r "BorderRadius\.circular([0-9]" nmtk_ui_core/lib/widgets \
  --include='*.dart' | grep -v 'ZETA-MIGRATION-EXEMPT'
```

Each command that returns any output causes CI to fail with a descriptive message
identifying the file and line.

---

### Property-Based Tests

Configure property tests in `nmtk_ui_core/test/migration_properties_test.dart`.

**Property 1 — TextField mapping completeness**
```dart
// Tag: Feature: full-zeta-migration, Property 1: TextField/ZetaTextInput parameter mapping completeness
// Minimum iterations: 100
test('migrateToZetaTextInput maps all supported parameters correctly', () {
  // Generate random TextFieldConfig structs with random subsets of parameters
  // Assert each ZetaTextInput field matches the mapped TextField parameter
  // Run with test randomize_ordering_seed for reproducibility
});
```

**Property 2 — Validator round-trip**
```dart
// Tag: Feature: full-zeta-migration, Property 2: Validator round-trip
// Minimum iterations: 100
test('validator return value propagates to errorText correctly', () {
  // Generate (validator, inputString) pairs
  // Assert ZetaTextInput errorText equals validator(inputString)
});
```

**Property 3 — Channel color modulo wrap**
```dart
// Tag: Feature: full-zeta-migration, Property 3: Channel color index modulo wrap
// Minimum iterations: 100
test('instrumentChannelPalette[i % 8] never throws and returns valid color', () {
  // Generate (N: 1..1000, i: 0..9999) pairs
  // Assert palette[i % palette.length] is valid Color, no RangeError
  // Assert returned color is in the canonical 8-color set
});
```

---

### Unit and Example Tests

Add to `nmtk_ui_core/test/`:

```dart
// Palette length invariant
test('instrumentChannelPalette has exactly 8 entries', () {
  expect(NmtkShellTokens.instrumentChannelPalette.length, equals(8));
});

// Palette membership invariant
test('all instrumentChannelPalette entries are from the canonical set', () {
  const canonicalSet = {
    Color(0xFF06B6D4), Color(0xFF65C4C4), Color(0xFF91E1E1), Color(0xFFBCFBFB),
    Color(0xFF0F766E), Color(0xFF1A8080), Color(0xFF003535), Color(0xFF0A1616),
  };
  for (final color in NmtkShellTokens.instrumentChannelPalette) {
    expect(canonicalSet.contains(color), isTrue,
        reason: 'Color $color is not in the canonical instrument palette');
  }
});

// Font constant consistency
test('NmtkFontFamilies constants have expected values', () {
  expect(NmtkFontFamilies.monospace, equals('JetBrains Mono'));
  expect(NmtkFontFamilies.package, equals('nmtk_ui_core'));
});

// Theme seed color (neurocnl dark)
test('neurocnl dark theme seed is Studio Violet', () {
  final theme = AppTheme.darkThemeForVariant(NmtkThemeVariant.neurocnl);
  // The seed color drives ColorScheme.fromSeed; primary will be derived from it.
  // Assert primary is NOT 0xFF38BDF8 (the old wrong value)
  expect(theme.colorScheme.primary.value, isNot(equals(0xFF38BDF8)));
});
```

---

### Manual Review Checklist

Before closing each task, perform a visual diff review for:

- [ ] `CustomPainter` subclasses: confirm all color parameters are sourced from
  constructor args (not internal `Colors.X` refs)
- [ ] Loading-state FilledButton patterns: confirm `CircularProgressIndicator` children
  are removed and `onPressed: null` correctly disables `ZetaButton`
- [ ] `Colors.orange` usages: confirm degraded vs. warning intent is annotated
- [ ] `const` removal completeness: confirm no `const` keyword remains on widgets that
  contain a runtime token lookup
- [ ] Import deduplication: confirm no file has duplicate `nmtk_ui_core` imports after
  import addition

