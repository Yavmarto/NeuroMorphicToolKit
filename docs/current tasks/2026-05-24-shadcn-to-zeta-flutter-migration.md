# shadcn_ui → zeta_flutter Migration Plan

**Date**: 2026-05-24
**Status**: ✅ Complete

---

## Current State

The previous execution session started a moon_design migration that is now mid-flight with errors. Before Zeta work begins, `nmtk_ui_core` must be reverted to its clean shadcn baseline.

### Files to revert

```bash
git checkout HEAD -- \
  nmtk_ui_core/pubspec.yaml \
  nmtk_ui_core/lib/app_theme.dart \
  nmtk_ui_core/lib/nmtk_ui_core.dart \
  nmtk_ui_core/lib/shad_theme.dart \
  nmtk_ui_core/lib/widgets/buttons.dart \
  nmtk_ui_core/lib/widgets/toasts.dart \
  nmtk_ui_core/lib/widgets/command_palette.dart \
  nmtk_ui_core/lib/widgets/surface_card.dart \
  nmtk_ui_core/lib/widgets/top_app_bar.dart \
  nmtk_ui_core/lib/widgets/desktop_scaffold.dart
rm nmtk_ui_core/lib/moon_theme.dart
```

---

## Zeta Flutter

- **Package**: `zeta_flutter: ^1.4.5` (pub.dev, published by zebra.com, MIT)
- **Docs**: https://pub.dev/packages/zeta_flutter · https://design.zebra.com

---

## Shadcn → Zeta Component Map

| Shadcn | Zeta |
|--------|------|
| `ShadApp` / `ShadApp.router` | `ZetaProvider` wrapping `MaterialApp` |
| `NmtkShadTheme` / `ShadThemeData` | `ZetaCustomTheme(id:'nmtk', primary: Color(0xFF38BDF8))` |
| `ShadColorScheme` field access | `Zeta.of(context).colors.*` |
| `ShadButton` | `ZetaButton` |
| `ShadButton.outline` | `ZetaButton.outline` |
| `ShadButton.destructive` | `ZetaButton.negative` |
| `ShadButton.secondary` | `ZetaButton.subtle` |
| `ShadButton.ghost` | `ZetaButton.text` |
| `showShadDialog` | `showDialog` (Material) |
| `ShadToaster` / `ShadToast` | `ScaffoldMessenger.showSnackBar` |
| `ShadTheme.of(ctx).colorScheme.primary` | `Zeta.of(ctx).colors.primary` |
| `ShadTheme.of(ctx).colorScheme.destructive` | `Zeta.of(ctx).colors.negative` |
| `ShadTheme.of(ctx).colorScheme.background` | `Zeta.of(ctx).colors.surfacePrimary` |
| `ShadTheme.of(ctx).colorScheme.card` | `Zeta.of(ctx).colors.surfaceSecondary` |
| `ShadTheme.of(ctx).colorScheme.border` | `Zeta.of(ctx).colors.borderDefault` |
| `ShadTheme.of(ctx).colorScheme.foreground` | `Zeta.of(ctx).colors.textDefault` |
| `ShadTheme.of(ctx).colorScheme.muted` | `Zeta.of(ctx).colors.surfaceTertiary` |
| `ShadSeparator.horizontal()` | `ZetaDivider()` |
| `ShadTooltip(builder:..., child:...)` | `ZetaTooltip(content:'...', child:...)` |
| `ShadPopoverController` + `ShadPopover` | `MenuAnchor` (Material) |
| `ShadAvatar` | `ZetaAvatar` |
| `ShadBadge.secondary` | `ZetaBadge` |
| `ShadInput` | `ZetaTextInput` |

---

## Affected Packages

| Package | shadcn_ui dep | uses-material-design |
|---------|--------------|----------------------|
| `nmtk_ui_core` | direct | – |
| `neurocnl/frontend` | direct | true |
| `Neurobench/frontend` | direct | true |
| `nmtk/neuro_toolkit` | direct | true |
| `Neurohub/frontend` | via nmtk_ui_core | true |
| `Neurosense/frontend` | via nmtk_ui_core | true |

---

## Task Breakdown

### T-UI-1 — Revert nmtk_ui_core to pre-moon state

**Status**: ⬜

Run the git revert commands above. Verify `flutter pub get && flutter analyze && flutter test` all pass in `nmtk_ui_core/`.

---

### T-UI-2 — Add zeta_flutter to nmtk_ui_core; create NmtkZetaTheme

**Status**: ⬜

- Add `zeta_flutter: ^1.4.5` to `pubspec.yaml`
- Create `lib/zeta_theme.dart` with `ZetaCustomTheme(id:'nmtk', primary: Color(0xFF38BDF8))`
- Keep `shadcn_ui` temporarily until T-UI-4

---

### T-UI-3 — Replace all Shadcn components in nmtk_ui_core/lib/

**Status**: ⬜

- `widgets/buttons.dart`: `ShadButton.*` → `ZetaButton.*`
- `widgets/toasts.dart`: `ShadToaster`/`ShadToast` → `ScaffoldMessenger.showSnackBar`
- `widgets/command_palette.dart`: `showShadDialog` → `showDialog`, `ShadInput` → `ZetaTextInput`
- `widgets/surface_card.dart`: remove unused shadcn import
- `widgets/top_app_bar.dart`: `ShadButton.outline` → `ZetaButton.outline`
- `widgets/desktop_scaffold.dart`: `ShadTheme`/`ShadColorScheme`/`ShadSeparator`/`ShadTooltip`/`ShadPopover`/`ShadAvatar`/`ShadBadge` → Zeta equivalents
- `flutter analyze nmtk_ui_core` must reach 0 errors

---

### T-UI-4 — Delete shad_theme.dart; remove shadcn_ui from nmtk_ui_core pubspec

**Status**: ⬜

- Delete `lib/shad_theme.dart`
- Update barrel: `export 'zeta_theme.dart'` replaces `export 'shad_theme.dart'`
- Remove `shadcn_ui: ^0.54.0` from `pubspec.yaml`
- `flutter pub get && flutter test nmtk_ui_core` green

---

### T-UI-5 — Migrate neurocnl/frontend

**Status**: ⬜

- Remove `shadcn_ui` from pubspec; set `uses-material-design: false`
- `lib/app.dart`: remove `ShadTheme` wrapper (inner `MaterialApp.router` stays)
- `routing/canvas/neurosim_app.dart`: `ShadApp` → `ZetaProvider` wrapping `MaterialApp`
- Replace `ShadButton.*` in `canvas_screen`, `project_screen`, `simulation_control_panel`, `export_dialog`
- Update test pumps: `ShadApp`/`ShadTheme` → `ZetaProvider`/`MaterialApp`
- `flutter test neurocnl/frontend` green

---

### T-UI-6 — Migrate Neurobench/frontend

**Status**: ⬜

- Remove `shadcn_ui`; set `uses-material-design: false`
- Check for direct Shadcn calls; replace if found
- `flutter test Neurobench/frontend` green

---

### T-UI-7 — Migrate nmtk/neuro_toolkit

**Status**: ⬜

- `main.dart`: `ShadApp`/`ShadApp.router` → `ZetaProvider` wrapping `MaterialApp`/`MaterialApp.router`
- `settings.dart`: `showShadDialog`/`ShadDialog`/`ShadButton.ghost` → `showDialog`/`AlertDialog`/`ZetaButton.text`
- `router.dart`: same dialog replacements
- `tool_view_header_actions.dart`: `ShadTheme.of(ctx).colorScheme.*` → `Zeta.of(ctx).colors.*`
- Update test pumps
- `flutter test nmtk/neuro_toolkit` green

---

### T-UI-8 — Migrate Neurohub/frontend and Neurosense/frontend

**Status**: ⬜

- `Neurohub/frontend/lib/app.dart`: remove `ShadTheme(data: NmtkShadTheme.dark, ...)` wrapper
- `Neurosense/frontend/lib/widgets/replay_controls.dart`: `ShadButton.*` → `ZetaButton.*`
- Both pubspecs: `uses-material-design: false`; add `zeta_flutter: ^1.4.5` where needed
- Update test pumps in both
- `flutter test` green for both

---

### T-UI-9 — Full suite verification

**Status**: ⬜

- `grep -r "shadcn_ui" --include="*.dart" --include="*.yaml" .` → empty
- All 6 packages pass `flutter analyze` and `flutter test`
- Update `nmtk_ui_core/README.md` to reference `zeta_flutter`

---

## Exit Criteria

`grep -r "shadcn_ui" --include="*.dart" --include="*.yaml" .` returns nothing; all 6 Flutter packages pass `flutter analyze` and `flutter test`.
