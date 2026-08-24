# nmtk_ui_core

Shared Dart/Flutter widget library for the NeuroMorphicToolKit (NMTK) suite — design tokens, theming, and reusable UI components.

Three projects depend on it: the launcher app (`nmtk/neuro_toolkit`), the Studio (`neurocnl/frontend`), and the Neurobench surface (`Neurobench/frontend`). Those are the only three Flutter projects in the suite; Neurosense, Neurohub, Neurochip, and Neurosim have no frontends of their own, so their UI reaches this package indirectly through the Studio. See the [root README](../README.md#architecture).

**Version:** `0.7.0+0` — SDK `^3.11.0`, Flutter `>=3.41.0`

---

## What's in here

### Design tokens

`NmtkShellTokens` is a `ThemeExtension`, so its values are **instance** fields reached through `NmtkShellTokens.of(context)` — never static access.

- **Border radius** — use only the sanctioned token values:
  - `radiusSm` (12 px) — inline chips, tags, input fields
  - `radiusMd` (16 px) — buttons, small cards, search fields
  - `radiusLg` (22 px) — section cards, summary tiles, large containers
  - `radiusChip` (999 px) — pill-shaped badges
  - Values of 8, 10, 14, or 18 px are **not sanctioned**; replace with the nearest token.
  - `NmtkDesignTokens.dialogShape` (28 px) — dialogs. Note this lives on `NmtkDesignTokens` in `app_theme.dart`, not on `NmtkShellTokens`, and is a `BorderRadius` rather than a `double`.
- **Status colours** — semantic palette used suite-wide, all on `NmtkShellTokens`:
  - `healthyColor` (#22C55E) — healthy / success
  - `errorColor` (#EF4444) — error
  - `warningColor` (#F97316) — warning
  - `degradedColor` (#F59E0B) — degraded. A distinct token from `warningColor`
  - `runningColor` (#38BDF8) — running
  - `liveColor` (#E11D48) — live / recording
- **Motion tokens** — durations and curves in `NmtkMotionTokens` (`durationFast/Base/Slow/Spring`, `easeEnter/Exit/Standard/Spring`).

### Shell modes

Each mounted surface passes a shell mode, which selects the accent palette:

| Mode | Colour | Used by |
|------|--------|---------|
| `NmtkShellMode.command` | Navy (#1337EC) | The launcher, and Neurobench |
| `NmtkShellMode.studio` | Violet (#8B5CF6) | neurocnl (the Studio, including the canvas) |
| `NmtkShellMode.instrument` | Cyan (#06B6D4) | Reserved; no current consumer |

The mode is genuinely wired, not decorative — `paletteForMode` is read by `top_app_bar.dart`, `workspace_chip.dart`, and the desktop rail.

> `CODING_STYLE_GUIDE.md`'s shell-mode table still lists NeuroSense and NeuroChip under `instrument`. Neither has a frontend, so that row has no consumer; the style guide is the side to correct.

### Theme
- `NmtkZetaTheme` — Zeta Flutter design system integration (`zeta_flutter ^1.4.5`, Zebra Design System, MIT-licensed). Provides `ZetaProvider`, `ZetaButton`, `ZetaAvatar`, `ZetaTextInput`, and `Zeta.of(context).colors.*` token access.
- `AppTheme` — the older suite-wide palette, typography, spacing, and shadow definitions. It is **scheduled for removal**: the barrel marks it `TODO(T-DEBT): migrate test harnesses to NmtkZetaTheme, then delete`. Prefer `NmtkZetaTheme` in new code.

### Widgets

Over a hundred exported components. Every public widget carries the `Nmtk` prefix.

- **Scaffolding:** `NmtkDesktopScaffold`, `NmtkMobileScaffold`, `NmtkResponsiveScaffold`, `NmtkAdaptiveLayout`, `NmtkTopAppBar`, `NmtkWorkspaceSwitcherBar`
- **Navigation:** `NmtkCommandPalette`, `NmtkShortcutScope`
- **Pipeline:** `NmtkPipelineStepper`, `NmtkSnnWorkflowStepper`, `NmtkValidationChip`
- **Charts:** `NmtkEnergyBarChart`, `NmtkSparklineChart`, `NmtkQuantizationTable`
- **Modals:** `NmtkLoadingScreen`, confirmation dialogs
- **Status:** `NmtkStatusBadge`, `NmtkShellStatusBadge`, badges, chips

Check the barrel at `lib/nmtk_ui_core.dart` for the authoritative export list.

### Shared models

Typed Dart models used across modules, in `lib/models/`:

- `pynq_deployment_model.dart` — PYNQ Z2 deployment types (`PynqDeployConfig`, `PynqRegisterMap`, `PynqLayerDescriptor`, `PynqDeployPayload`, `PynqPairedBoard`, `PynqDeployJob`, and others)
- `akida_deployment_model.dart` — Akida types (`AkidaPairedHost`, `AkidaDeployJob`, `AkidaSupportState`, and others)
- `teensy_deployment_model.dart` — Teensy types (`FlashJob`, `SerialPortInfo`, `VerificationReport`, and others)
- `energy_report.dart` — `EnergyReport`

Each file exports several types; there is no single class matching a file's name.

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

Read tokens from the context:

```dart
final tokens = NmtkShellTokens.of(context);

Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(tokens.radiusMd),
    color: tokens.healthyColor,
  ),
)
```

---

## Rules (enforced by `CODING_STYLE_GUIDE.md`)

- Never use non-token border radius values (8, 10, 14, 18 px). Replace on sight.
- Always pass `NmtkShellMode` to scaffolding widgets — the default is `command`, so leaving it unset silently yields Navy.
- Use `NmtkShellTokens` colours for all status indicators; do not inline hex values.
- Reach tokens through `NmtkShellTokens.of(context)`. Static field access does not compile.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
