# ADR 0001: Barrel Export Pattern

## Status
Accepted

## Context
Multiple NMTK frontends (desktop launcher, module web apps) need to import shared widgets, models, and theming from the UI core library. Scattered imports across many files create a fragile, hard-to-manage dependency surface.

## Decision
Use a single barrel export file (`nmtk_ui_core.dart`) that re-exports all public widgets, models, and the theme configuration. Consumers use a single import statement: `import 'package:nmtk_ui_core/nmtk_ui_core.dart'`. The export ordering follows a convention of theme first, then models, then widgets.

## Consequences
- **Positive:** Single import reduces boilerplate and makes the library's public API explicit; adding new widgets requires updating only the barrel file.
- **Negative:** Barrel exports import everything even when only a subset is needed, potentially increasing compile times; large barrel files can become hard to navigate.

## Status Update (2026-07-16 audit)

Reading `nmtk_ui_core/lib/nmtk_ui_core.dart` confirms the claimed theme→models→widgets export ordering does not actually hold; the real order is a loosely-grouped, organically-grown list with repeated interleaving. Examples: `widgets/responsive_scaffold.dart` (line 2) sits between the two theme exports `app_theme.dart` (line 1) and `zeta_theme.dart` (line 3); `shell_tokens.dart` (a token/theme file, line 13) appears after the models block rather than with the other theme exports; `models/scaffold_models.dart` (line 49) is sandwiched between `widgets/status_badge.dart` (line 48) and `widgets/desktop_scaffold.dart` (line 50); and `motion_tokens.dart` (line 60) and `models/commands.dart` (line 62) appear near the end, interleaved with `widgets/command_palette.dart` and `widgets/shortcut_scope.dart`, long after the main widget block.
