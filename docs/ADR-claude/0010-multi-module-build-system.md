# ADR 0010: Multi-Module Build System

## Status
Accepted

## Context
Building the full NMTK suite requires compiling 6 Flutter web frontends (each with different `API_BASE_URL` dart-defines), installing Python dependencies for 6+ backends, and linking the shared `nmtk_ui_core` package. Full rebuilds are slow, so incremental builds are essential for developer productivity.

## Decision
The Makefile uses file-based dependency tracking: each frontend target depends on `$(1)/frontend/build/web/index.html`, which is rebuilt only when source files are newer than the build output. `build_all_frontends.sh` iterates modules and passes `--dart-define=API_BASE_URL="http://localhost:{port}"` per module. `scripts/build_module.sh` handles single-module rebuilds with `FLUTTER_DEVICE` selection. `scripts/deep_clean.sh` removes all build artifacts (build/, venv/, .dart_tool/) for clean rebuilds.

## Consequences
- **Positive:** File-based dependency tracking avoids unnecessary rebuilds; per-module build scripts enable focused development on a single module.
- **Negative:** Modification-time-based tracking can miss changes in transitive dependencies (e.g., nmtk_ui_core changes not triggering module frontend rebuilds); no content-hash-based caching.

## Amendment — Consolidation Phase 3 (2026)
The per-module `flutter build web` pipeline described above is superseded
after Phase 3 of the consolidation plan. The new build system is a single
`flutter build macos` of `nmtk/neuro_toolkit/` which includes all six domain
feature packages as path dependencies. See ADR 0019 and the implementation
plan at `docs/implementation-plan-consolidation.md`.
