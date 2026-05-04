# neuro_toolkit

`neuro_toolkit` is the unified Flutter launcher for NeuroMorphicToolKit.

It is no longer a generic starter app. In the current architecture it is the suite control plane that:

- reads module metadata from `assets/modules.json`
- hosts native module surfaces through feature packages under `nmtk/packages/`
- manages launcher state, installation state, workspace sessions, and runtime health UX
- deep-links into module routes such as `/module/neurocnl`, `/module/neurochip`, and `/module/neurobench`
- preserves the legacy `/workspace?moduleId=` path for compatibility

The control-plane ownership described here matches [`../../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md`](../../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md).

## Current Architecture

- Backend default: `suite_api` on `http://127.0.0.1:9000`
- Frontend integration model: native Flutter feature packages, not WebViews
- Native surfaces: `neurocnl`, `neurosim`, `neurochip`, `neurobench`, `neurosense`, `neurohub`
- Source of truth for launcher-visible module metadata: `assets/modules.json`

## Local Development

From the repo root, the normal integrated path is:

```bash
make dev
```

To run just the launcher against an already running backend:

```bash
cd nmtk/neuro_toolkit
flutter pub get
flutter run -d macos --dart-define=SUITE_API_URL=http://127.0.0.1:9000
```

## Important Files

- `assets/modules.json`: launcher module manifest
- `lib/routing/router.dart`: top-level routes
- `lib/workspace/native_surface_registry.dart`: native surface registry and legacy workspace compatibility
- `lib/services/launcher_control_bootstrap_service.dart`: launcher bootstrap wiring
- `test/`: launcher behavior and manifest-backed regression coverage
