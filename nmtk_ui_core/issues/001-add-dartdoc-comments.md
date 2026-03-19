# Add Dartdoc Comments to All Public Widgets and Classes

**Priority:** Medium  
**Type:** Code Quality  
**Date:** 2026-03-19  

## Description

Per the CODING_STYLE_GUIDE.md §Flutter §4, all public members should have `///` dartdoc comments. Currently, the widget classes (`NmtkPrimaryButton`, `NmtkOutlinedButton`, `NmtkEnergyBarChart`, etc.) and model classes have **zero dartdoc comments** despite being a shared UI library.

## Tasks

- [ ] Add `///` dartdoc to `NmtkPrimaryButton` and its parameters
- [ ] Add `///` dartdoc to `NmtkOutlinedButton` and its parameters
- [ ] Add `///` dartdoc to all widgets in `widgets/`
- [ ] Add `///` dartdoc to all model classes in `models/`
- [ ] Add `///` dartdoc to `AppTheme` and `NmtkNavigationRail`
