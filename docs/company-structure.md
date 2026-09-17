# Paperclip AI — Company Structure

> Last updated: 2026-09-02

## Org Chart

```
                           [ Board / You ]
                                  │
                               [ CEO ]
                  ┌───────────────┴───────────────┐
               [ CTO ]                          [ PM ]
          ┌──────┴──────┐
    [ Engineer ]   [ Designer ]
```

## Codebase Map

### Frontend — Single App (in progress)

| Location | Description |
|---|---|
| `nmtk/neuro_toolkit/` | **Root Flutter app** — the one frontend. All UI routes through here. |
| `nmtk/neuro_toolkit/lib/features/neurocnl/` | CNL Studio feature module inside the app |
| `nmtk/neuro_toolkit/lib/features/neurobench/` | Neurobench feature module inside the app |
| `nmtk/neuro_toolkit/lib/features/custom_nodes/` | Custom nodes feature module inside the app |
| `nmtk/neuro_toolkit/lib/ui_core/` | Shared design system (Zeta-based, formerly `nmtk_ui_core` package) |
| `nmtk/neuro_toolkit/assets/modules.json` | Source of truth for all module IDs, ports, run paths |

> **Migration status**: The codebase is moving from per-module standalone Flutter frontends to a single unified app. Standalone frontends in `Neurochip/frontend/`, `Neurosense/frontend/`, `Neurohub/frontend/` are legacy — they should eventually be eliminated as their features land in `nmtk/neuro_toolkit/lib/features/`. The `cnlstudio` root is already routed through the unified app.

### Backend — Containerized Per Module

| Container / Service | Module | Notes |
|---|---|---|
| `suite_api` | Orchestration gateway | FastAPI, routes to individual module APIs |
| `neurocnl/backend/` | CNL compiler & trainer | Core neuroscience compute |
| `workers/neurochip_hw/` | BrainChip Akida hardware | Native service on port 8002 on dev host |
| `workers/neurosense_hw/` | Sensor hardware | |
| `workers/neurobench_runner/` | Benchmark execution | |
| `workers/lava_backend/` | Intel Lava runtime | Optional |
| `workers/jupyter_server/` | Notebook server | |
| `workers/snn_mlir_compiler/` | MLIR compiler | |
| `workers/neurocnl_physics/` | Physics simulation | |
| `nmtk/launcher_control/` | Lifecycle control plane | Manages start/stop/health of all services |

### Python Backend Modules (submodules)

| Directory | Role |
|---|---|
| `neurocnl/` | CNL language, compiler, training engine |
| `Neurochip/` | BrainChip Akida deployment |
| `Neurohub/` | Workspace & project management |
| `Neurosense/` | Sensor data ingestion |
| `Neurobench/` | Benchmarking framework |
| `Neurosim/` | Simulation |
| `suite_api/` | API gateway (aggregates all backends) |
| `nmtk_sdk/` | SDK for external integrations |
| `nmtk_module_contracts/` | Shared Pydantic contracts across modules |

### Design System

- **Zeta Flutter** (`zeta_flutter`) is the sole UI kit. No raw Material widgets.
- Color: `Zeta.of(context).colors` — no hardcoded colors.
- Typography: `ZetaTextStyles` — no manual `TextStyle`.
- Spacing: 8px grid. No deeply nested `Container`/`Padding` hacks.
- Border radius: `NmtkShellTokens` / `NmtkDesignTokens` only.

### Dev Topology

- Dev backend host: `<dev-host>` (`dev@<dev-host>`)
- Port 8002 is owned by the native Akida systemd service — **never kill it**.
- `make dev-update` is the daily sync command (not `docker-compose` directly).
- End users never touch a terminal — all lifecycle runs through the Flutter app.
