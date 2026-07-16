# ADR 0007: Hardware Deploy UI Moved to Neurochip Module Frontend

## Status
Accepted

## Context
The launcher dashboard exposed three "Deployment Workflows" buttons (Akida,
PYNQ, Teensy) that opened stepper-based flows for hardware deploy. ADR 0005
established per-target provider classes for those flows; ADR 0006 wired them
into the launcher's Riverpod graph. Over time this placement became
architecturally inconsistent with the monorepo rule stated in
`nmtk/AGENTS.md`:

> Module UIs are embedded web frontends. Keep module-specific product UI in
> the owning module or in `nmtk_ui_core`, not in bespoke launcher-only
> copies.

Akida / PYNQ / Teensy are Neurochip deployment targets (see
`Neurochip/AGENTS.md` — contracts for deployment, runtime-artifact, hardware,
and quantization payloads are all owned by `Neurochip/neurochip/contracts/`).
Housing the UI on the launcher also produced a visible UX inversion: the
Neurochip module frontend's Akida tab was a receive-only handoff screen
("No Akida handoff is loaded. Open this flow from CNL Studio…") while the
full-featured entry point lived in the launcher dashboard.

## Decision
Move the three hardware deploy flows from `nmtk/neuro_toolkit/` into
`Neurochip/frontend/`:

- Screens: `akida_deploy_screen.dart`, `pynq_deploy_screen.dart`,
  `teensy_deploy_screen.dart`.
- Services: `akida_deploy_service.dart`, `pynq_deploy_service.dart`,
  `teensy_deploy_service.dart`.
- Providers (per-target `ChangeNotifierProvider`s from ADR 0005):
  `akida_deploy_provider.dart`, `pynq_deploy_provider.dart`,
  `teensy_deploy_provider.dart`.
- Models: `akida_remote_host.dart`, `pynq_launcher_action_result.dart`,
  and a minimal copy of `module.dart`.
- The five Flutter tests that covered these surfaces move alongside the
  code into `Neurochip/frontend/test/`.

The launcher dashboard loses its "Deployment Workflows" card; its routes
(`/deploy/akida`, `/deploy/pynq`, `/deploy/teensy`) and the three
`ChangeNotifierProvider` overrides in
`nmtk/neuro_toolkit/lib/providers/riverpod_providers.dart` are removed. ADR
0005 still governs the per-target provider shape — it now applies inside
the Neurochip frontend rather than the launcher.

Neurochip's bottom nav becomes (left to right): **Akida · PYNQ · Teensy ·
Analysis · Compare · Gallery · History · Handoff**. The previous "Akida"
tab (a CNL Studio handoff receiver) is renamed `AkidaHandoffScreen` and
relocated to the "Handoff" slot. When Neurochip is opened with an imported
Akida handoff query param (deep-link from CNL Studio) the app still jumps
directly to that tab on startup.

### Adapting the flows to Flutter web
The launcher is a Flutter macOS desktop app; Neurochip's frontend is a
Flutter web app embedded in the launcher's WKWebView. Two desktop-only
patterns needed to change:

1. `AkidaDeployService.downloadPackage(...)` previously wrote
   `akida_deploy.zip` to a caller-supplied `outputDir` using `dart:io`
   `File`. It now returns `Uint8List` and leaves persistence to the
   caller.
2. `AkidaDeployProvider.startDeploy(...)` previously required an
   `outputDir`. It no longer accepts one; on success it exposes
   `savedPackageBytes` and the filename constant
   `AkidaDeployProvider.savedPackageFilename`.
3. `AkidaDeployScreen._startDeploy(...)` previously called
   `getApplicationDocumentsDirectory()` from `path_provider`. It now
   triggers a browser download via the existing Neurochip
   `services/download_bytes.dart` helper (which uses `dart:html` on web
   and a no-op stub elsewhere).

### `ControlApiService` duplication (recognized debt)
`services/control_api_service.dart` is a launcher-control-plane HTTP
client. It is still used by the launcher's `ModuleProvider` for module
lifecycle (install/start/stop/uninstall/update) and by the relocated
deploy providers for PYNQ board / Akida host management and settings.
Extracting it into `nmtk_ui_core` is the correct long-term move; for the
scope of this ADR the file is duplicated in both
`nmtk/neuro_toolkit/lib/services/` and
`Neurochip/frontend/lib/services/`. The two copies share identical
endpoint paths (e.g. `/api/launcher/pynq/boards/*`, `/api/launcher/akida/hosts/*`)
and talk to the same launcher control service port. Follow-up: extract
into `nmtk_ui_core/lib/src/services/` and collapse the copies.

Likewise `models/pynq_launcher_action_result.dart` and the minimal
`models/module.dart` are duplicated for the same reason — both files are
consumed by `control_api_service.dart` on each side.

## Consequences

### Positive
- UX entry point now lives with the module that owns the deployment
  contracts. Discoverability improves: a user who opens Neurochip sees
  the three deploy flows as primary tabs instead of a CNL-Studio-gated
  handoff screen.
- Launcher dashboard has a single concern again: module install / start /
  stop / update lifecycle.
- ADR 0005's per-target provider separation survives the move; only the
  host changes.
- Neurochip's `pubspec.yaml` now declares `flutter: uses-material-design:
  true`, which was missing — that single omission broke every Material
  icon in Neurochip's web build (rendered as tofu boxes). Fixing the
  icons is folded into this ADR because it blocked any meaningful UX
  evaluation of the module.

### Negative / Debt
- `ControlApiService`, `Module`, and `PynqLauncherActionResult` are
  duplicated between launcher and Neurochip until a follow-up extracts
  them into `nmtk_ui_core`. Drift risk is real — any endpoint shape
  change on the launcher control plane must be applied to both copies.
- The launcher copy of `ControlApiService` retains PYNQ-board and Akida-
  host endpoints that no launcher code calls anymore. They compile but
  are dead; a future slim-down should remove them from the launcher
  side.
- Tests previously tagged as launcher coverage
  (`akida_deploy_*_test.dart`, `pynq_deploy_*_test.dart`) now count
  toward Neurochip coverage. `bash scripts/run_launcher_guardrails.sh`
  sees a reduced surface; `cd Neurochip/frontend && flutter test` sees
  the addition. Both still need to pass per their owning `AGENTS.md`.

## Status Update (2026-07-16 audit)

The specific file paths this ADR cites under `Neurochip/frontend/lib/{screens,services,providers,models}/...` no longer exist. Verified with `find /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend -type f`: the directory contains only a single `neurochip.iml` file — no `lib/`, no Dart sources at all.

The actual current architecture is different from what this ADR describes: Neurochip deploy is handled by `NeurocnlShellAdapter` (from `neurocnl_studio`, `neurocnl/frontend`) via a `panel=deploy&target=` query param, wired up in `nmtk/packages/neurochip_feature/lib/src/neurochip_shell_adapter.dart` (`NeurochipShellAdapter`/`normalizeNeurochipDeepLinkForStudio`). This is consistent with the later architecture in ADR 0019 (Flutter Feature Packages) and ADR 0020 (CNL Studio Owns Deployment Target Selection). This ADR is effectively superseded by that later architecture but carries no supersession marker in its `## Status` section.
