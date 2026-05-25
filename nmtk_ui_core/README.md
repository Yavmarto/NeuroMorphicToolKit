# nmtk_ui_core

Shared Dart/Flutter widget library for the NeuroMorphicToolKit (NMTK) suite. All module frontends (`neurocnl`, `Neurohub`, `Neurobench`, `Neurosense`) depend on this package for design tokens, theming, and reusable UI components.

**Version:** `0.6.0+3` — SDK `^3.11.0`, Flutter `>=3.41.0`

---

## What's in here

### Design tokens
- **Border radius** — Use only the sanctioned token values:
  - `radiusSm` (12 px) — inline chips, tags, input fields
  - `radiusMd` (16 px) — buttons, small cards, search fields
  - `radiusLg` (22 px) — section cards, summary tiles, large containers
  - `chipRadius` (999 px) — pill-shaped badges
  - `dialogShape` (28 px) — dialogs
  - Values of 8, 10, 14, or 18 px are **not sanctioned**; replace with the nearest token.
- **Status colours** — semantic palette used suite-wide:
  - `NmtkShellTokens.healthyColor` (#22C55E) — healthy / success
  - `NmtkShellTokens.errorColor` (#EF4444) — error
  - `NmtkShellTokens.warningColor` (#F59E0B) — warning / degraded
  - `NmtkShellTokens.runningColor` (#38BDF8) — running
  - `NmtkShellTokens.liveColor` (#E11D48) — live / recording
- **Motion tokens** — animation durations and curves in `MotionTokens`.

### Shell modes
Each module frontend must pass the correct shell mode:

| Mode | Colour | Modules |
|------|--------|---------|
| `NmtkShellMode.command` | Navy | Launcher, NeuroHub, NeuroBench |
| `NmtkShellMode.studio` | Violet | neurocnl (CNL Studio + NeuroSim canvas) |
| `NmtkShellMode.instrument` | Cyan | NeuroSense, NeuroChip |

### Theme
- `AppTheme` (800 lines) — suite-wide colour palette, typography scale, spacing, shadow definitions.
- `NmtkZetaTheme` — Zeta Flutter design system integration (`zeta_flutter ^1.4.5`, Zebra Design System, MIT). Provides `ZetaProvider`, `ZetaButton`, `ZetaAvatar`, `ZetaTextInput`, and `Zeta.of(context).colors.*` token access.

### Widgets (40+ components)
- **Scaffolding:** `DesktopScaffold`, `TopAppBar`, `WorkspaceSwitcherBar`
- **Navigation:** `CommandPalette`, `ShortcutScope`
- **Pipeline:** `PipelineStepper`, `ValidationChip`
- **Charts:** `EnergyBarChart`, `QuantizationCurveChart`
- **Modals:** `LoadingScreen`, confirmation dialogs
- **Status:** `StatusDisplay`, badges, chips

### Deployment models
Typed Dart models shared across modules:
- `PynqDeploymentModel` (821 lines) — PYNQ Z2 deployment configuration
- `AkidaDeploymentModel` (770 lines) — Akida NSoC deployment configuration
- `TeensyDeploymentModel` (225 lines) — Teensy board deployment configuration
- `EnergyReport` — energy analysis reporting

---

## Usage

Add to `pubspec.yaml`:

```yaml
dependencies:
  nmtk_ui_core:
    path: ../../nmtk_ui_core   # adjust relative path per module location
```

Import the barrel export:

```dart
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
```

Use tokens directly:

```dart
Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(NmtkShellTokens.radiusMd),
    color: NmtkShellTokens.healthyColor,
  ),
)
```

---

## Rules (enforced by `CODING_STYLE_GUIDE.md`)

- Never use non-token border radius values (8, 10, 14, 18 px). Replace on sight.
- Always pass `NmtkShellMode` to scaffolding widgets — do not leave it at the default.
- Use `NmtkShellTokens` colour constants for all status indicators; do not inline hex values.
