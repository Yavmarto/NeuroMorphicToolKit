# Changelog

All notable changes to the NeuroMorphicToolkit (NMTK) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-beta.2] - 2026-03-26

### Added

- **Unified Launcher Architecture**: Initial release of the `neuro_toolkit` Flutter-based desktop application for Windows, macOS, and Linux.
- **Module Orchestration**: Background management of Docker containers and Python virtual environments for submodule execution.
- **NMTK UI Core**: Standardized UI component library (`nmtk_ui_core`) for consistent look-and-feel across all modules.
- **Installer Framework**: Scripts for generating standalone macOS `.app`/`.dmg`, Windows `.exe` installers, and Linux AppImages.
- **CI/CD Pipelines**: Automated testing and build workflows for the launcher and core UI library.

### Changed

- **Submodule Integration**: Refactored `neurocnl`, `neurosim`, `neurochip`, `neurobench`, `neurosense`, `neurohub`, and `neuro-dream-hand` to follow the standard service port mapping and unified Docker orchestration.

## [1.0.0-beta.1] - 2026-03-12

### Added

- **NeuroCNL 0.2.0**: Major update to the Conceptual Neuromorphic Language parser and generator.
  - Added inhibitory connections, population coding, and layer 2 cross-sentence validation.
  - See [neurocnl/CHANGELOG.md](./neurocnl/CHANGELOG.md) for details.
- **Unified Dev Pipeline**: Standardized task tracking and issue publishing via `module.json` manifests.
- **Docker Compose Profiles**: Core, physics, and full profiles for flexible local deployment.

---

## Module Changelogs

For detailed changes within specific modules, please refer to their respective changelogs:

- [NeuroCNL](./neurocnl/CHANGELOG.md)
- [NMTK UI Core](./nmtk_ui_core/CHANGELOG.md)
