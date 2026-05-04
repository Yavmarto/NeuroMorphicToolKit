# NeuroMorphicToolKit

NeuroMorphicToolKit is now a consolidated suite:

- one backend: `suite_api` on port `9000`
- one desktop launcher: `nmtk/neuro_toolkit`
- native Flutter feature packages under `nmtk/packages/`
- optional worker processes only for hardware, long-running jobs, or heavy optional dependencies

This is the architecture captured by [ADR 0018](./docs/ADR-claude/0018-suite-api-unified-backend.md), [ADR 0019](./docs/ADR-claude/0019-flutter-feature-packages.md), [ADR 0021](./docs/ADR-claude/0021-studio-neurochip-handoff-contract.md), and [ADR 0023](./docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md).

## Current Product Model

The repo still contains the individual product modules, but they no longer behave like six independently hosted apps.

- [`suite_api/`](./suite_api) is the unified FastAPI backend.
- [`nmtk/neuro_toolkit/`](./nmtk/neuro_toolkit) is the unified Flutter launcher and workspace host.
- [`nmtk/packages/`](./nmtk/packages) contains native feature packages for the module surfaces.
- Optional workers stay isolated when hardware or heavy runtimes are involved.

The six backend domains mounted inside `suite_api` are:

- `neurocnl`
- `neurosim`
- `neurochip`
- `neurobench`
- `neurosense`
- `neurohub`

`Neuro-Dream-Hand` remains in the workspace as a separate Python module and CLI-oriented simulator rather than a launcher-hosted frontend module.

## Module Ownership

- [`neurocnl`](./neurocnl): `NeuroStudio`, the canonical authoring, validation, generation, and deployment-handoff surface.
- [`Neurosim`](./Neurosim): visual graph editing, preview, sweeps, and project workflows. In the launcher, this is reached through the merged Studio/canvas flow rather than a separate install card.
- [`Neurochip`](./Neurochip): execution, packaging, flashing, and hardware diagnostics.
- [`Neurobench`](./Neurobench): benchmarking, comparisons, reports, and robustness analysis.
- [`Neurosense`](./Neurosense): biosignal acquisition, encoding, recording, and replay.
- [`Neurohub`](./Neurohub): registry and metadata layer, not the runtime control plane.
- [`Neuro-Dream-Hand`](./Neuro-Dream-Hand): prosthetic simulation and hardware-in-the-loop research workflows.

Two ownership rules are now central:

- `nmtk` is the only suite control plane.
- `NeuroStudio` owns canonical deployment target selection and hands off to `Neurochip`.

## Runtime Topology

Canonical local development runs:

- `suite_api` on `http://127.0.0.1:9000`
- the native launcher from `nmtk/neuro_toolkit`

Optional workers stay on legacy ports only when needed:

- `neurochip-hw-worker` on `8002`
- `neurobench-runner-worker` on `8003`
- `neurosense-hw-worker` on `8004`
- `neurocnl-physics-worker` on `8006`

Clients should treat `suite_api` as the default API surface and use worker ports only for the worker-specific paths that are intentionally proxied or exposed there.

## Getting Started

Integrated development:

```bash
make dev
```

Manual startup:

```bash
python3 -m pip install -e suite_api/
uvicorn suite_api.main:app --reload --port 9000
cd nmtk/neuro_toolkit
flutter run -d macos
```

The launcher and helper scripts use [`nmtk/neuro_toolkit/assets/modules.json`](./nmtk/neuro_toolkit/assets/modules.json) as the source of truth for module ids, install paths, and launcher-visible metadata.

## Key Docs

- [`SETUP_GUIDE.md`](./SETUP_GUIDE.md)
- [`docs/README.md`](./docs/README.md)
- [`docs/api/README.md`](./docs/api/README.md)
- [`docs/ADR-claude/0018-suite-api-unified-backend.md`](./docs/ADR-claude/0018-suite-api-unified-backend.md)
- [`docs/ADR-claude/0019-flutter-feature-packages.md`](./docs/ADR-claude/0019-flutter-feature-packages.md)
- [`docs/ADR-claude/0021-studio-neurochip-handoff-contract.md`](./docs/ADR-claude/0021-studio-neurochip-handoff-contract.md)
- [`docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md`](./docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md)
