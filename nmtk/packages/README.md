# nmtk/packages

This directory contains the launcher-facing native Flutter feature packages.

They are the package-level outcome of the consolidation described in [`../../docs/ADR-claude/0019-flutter-feature-packages.md`](../../docs/ADR-claude/0019-flutter-feature-packages.md): module frontends are integrated as native Flutter surfaces instead of WebView-hosted apps.

## Current Packages

- `neurocnl_feature`
- `neurosim_feature`
- `neurochip_feature`
- `neurobench_feature`
- `neurosense_feature`
- `neurohub_feature`

## What Each Package Does

Each feature package:

- wraps the owning module's shell adapter instead of copying product UI
- depends on `nmtk_ui_core` for shared shell widgets and tokens
- expects `SUITE_API_URL` to point at the unified backend, usually `http://localhost:9000`
- provides the launcher with a native surface that can be routed at `/module/{module}`

The existence of a feature package does not by itself mean the launcher manifest exposes a separate install card or primary nav item for that module. For example, `neurosim_feature` supports the merged Studio/canvas flow even though `NeuroSim` is not treated as a separate top-level catalog module in the current launcher manifest.
