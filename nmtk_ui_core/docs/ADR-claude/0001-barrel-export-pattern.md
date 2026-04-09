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
