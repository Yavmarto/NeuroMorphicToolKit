# Cross-Module Feature Overlap Analysis

This document compares the major modules in the NeuroMorphicToolKit suite, identifies where features overlap, and recommends whether that overlap should be removed, centralized, or kept.

The analysis distinguishes between:

1. **Current implemented reality** in code and active contracts.
2. **Declared ownership** in `AGENTS.md` and the launcher manifest.
3. **Aspirational scope** described in module README/spec documents.

## Scope

Product modules:

- `neurocnl`
- `Neurosim`
- `Neurochip`
- `Neurobench`
- `Neurosense`
- `Neurohub`
- `Neuro-Dream-Hand`

Platform/support modules:

- `nmtk`
- `nmtk_ui_core`
- `neurocli`

Primary repo sources used:

- `nmtk/neuro_toolkit/assets/modules.json`
- root and module `AGENTS.md`
- module `README.md` and spec docs
- selected routers/services that reveal actual implemented ownership

## Executive conclusion

The suite has a mostly sensible end-to-end workflow, but several overlaps are currently blurred by stale or conflicting module definitions.

The healthiest ownership model is:

| Layer | Best owner |
|---|---|
| CNL grammar, validation, canonical execution semantics | `neurocnl` |
| Visual graph editing and canvas UX | `Neurosim` |
| Hardware feasibility, deployment, firmware/export/runtime artifacts | `Neurochip` |
| Benchmark execution, regression, reporting, target comparison by benchmark outcome | `Neurobench` |
| Biosignal acquisition, encoding, recording, replay, canonical signal/session artifacts | `Neurosense` |
| Registry/distribution of reusable artifacts | `Neurohub` |
| Prosthetic-hand domain simulation and HITL adapters | `Neuro-Dream-Hand` |
| Launcher, install/start/stop, health polling, suite control plane | `nmtk` |
| Shared Flutter shell/widgets/tokens | `nmtk_ui_core` |
| Scriptable CLI front door reusing launcher semantics | `neurocli` |

The main problems are not that modules touch adjacent workflow stages; the main problems are:

1. `Neurohub` has contradictory identities.
2. `Neuro-Dream-Hand` duplicates some generic hardware and EMG capabilities owned elsewhere.
3. `Neurosim` still carries local CNL parsing logic that should not out-own `neurocnl`.

## Module-by-module ownership comparison

| Module | Primary owned responsibility | Evidence of current reality | Overlap risk |
|---|---|---|---|
| `neurocnl` | CNL grammar, parsing, validation, generation, support verdicts, deployment handoff semantics | `neurocnl/AGENTS.md`, `neurocnl/README.md`, `neurocnl/docs/support_matrix.md` | Medium where other modules parse or reinterpret CNL |
| `Neurosim` | Canvas authoring, graph/project persistence, graph-to-CNL UX, preview workflow | `Neurosim/AGENTS.md`, `Neurosim/neurosim_spec.md`, `Neurosim/neurosim/app/services/cnl_to_graph.py` | Medium with `neurocnl` if it owns semantic parsing instead of layout/UI |
| `Neurochip` | Hardware target analysis, quantization, fault analysis, deployment/export, device-facing runtime flows | `Neurochip/AGENTS.md`, `Neurochip/neurochip_spec.md`, `Neurochip/neurochip/app/*` | Medium with `Neurobench` and `Neuro-Dream-Hand` |
| `Neurobench` | Benchmark execution, baseline diffs, reporting, comparison by measured outcomes | `Neurobench/AGENTS.md`, `Neurobench/neurobench_spec.md`, `Neurobench/neurobench/app/services/target_comparator.py` | Medium with `Neurochip` when both compare targets |
| `Neurosense` | Biosignal acquisition, filtering, spike encoding, recording, replay, session artifacts | `Neurosense/AGENTS.md`, `Neurosense/README.md`, `Neurosense/docs/flagship_workflow.md` | High with `Neuro-Dream-Hand` on EMG ingestion/encoding |
| `Neurohub` | Conflicted: manifest says orchestrator, docs say registry, code currently implements project/workflow/asset service | `nmtk/neuro_toolkit/assets/modules.json`, `Neurohub/AGENTS.md`, `Neurohub/README.md`, `Neurohub/neurohub_spec.md`, `Neurohub/neurohub/app/main.py` | Very high with `nmtk` and with its own docs |
| `Neuro-Dream-Hand` | Prosthetic-hand simulation, continual learning, hand-specific HITL bridges and demonstrations | `Neuro-Dream-Hand/AGENTS.md`, `Neuro-Dream-Hand/README.md`, `Neuro-Dream-Hand/SPEC.md` | High where generic EMG, quantization, fault, and export helpers leak into suite-wide ownership |
| `nmtk` | Launcher/control plane, install/start/stop, venv/process management, module health and embedding | `nmtk/AGENTS.md`, `nmtk/neuro_toolkit/assets/modules.json`, `nmtk/neuro_toolkit/lib/services/process_manager.dart` | High only if other modules also claim orchestration |
| `nmtk_ui_core` | Shared UI tokens/widgets/models, state-management-agnostic | `nmtk_ui_core/AGENTS.md`, `nmtk_ui_core/lib/nmtk_ui_core.dart` | Healthy shared infrastructure |
| `neurocli` | Planned scriptable CLI above launcher semantics | `neurocli/AGENTS.md`, `neurocli/README.md` | Low today because it is not implemented |

## Overlap matrix

| Overlap area | Modules involved | Assessment | Recommendation |
|---|---|---|---|
| CNL semantics and parsing | `neurocnl`, `Neurosim` | Real overlap | Centralize semantics in `neurocnl`; keep `Neurosim` as visual editor and layout owner |
| Simulation and preview | `neurocnl`, `Neurosim` | Healthy workflow adjacency | Keep |
| Hardware target feasibility vs benchmark comparison | `Neurochip`, `Neurobench` | Adjacent but manageable | Keep split by purpose |
| Quantization, fault, power, export helpers | `Neurochip`, `Neuro-Dream-Hand`, partly `Neurobench` | Partial duplication | Consolidate generic kernels toward `Neurochip` or a shared lower layer; keep domain wrappers in `Neuro-Dream-Hand` |
| EMG acquisition and spike encoding | `Neurosense`, `Neuro-Dream-Hand` | Strong duplication | Move generic EMG/biosignal ownership to `Neurosense`; keep prosthetic adapters in `Neuro-Dream-Hand` |
| Session artifacts, encoding presets, benchmark baselines | `Neurosense`, `Neurobench`, `Neurohub` | Healthy publish/consume overlap if schema ownership stays local | Keep, with `Neurohub` acting as registry only |
| Orchestration and project/workflow control | `nmtk`, `Neurohub` | Most serious boundary conflict | Centralize runtime orchestration in `nmtk`; narrow or rename `Neurohub` responsibility |
| Shared UI | `nmtk_ui_core`, `nmtk`, module frontends | Healthy shared infrastructure | Keep |
| CLI vs launcher lifecycle behavior | `neurocli`, `nmtk` | Healthy alternate interface | Keep, but force one manifest/lifecycle model |

## Detailed overlap findings

### 1. `neurocnl` vs `Neurosim`

**What overlaps**

- `neurocnl` owns grammar, parser semantics, validation, support verdicts, and generated graph semantics per `neurocnl/AGENTS.md`.
- `Neurosim` owns canvas editing and graph/project payloads per `Neurosim/AGENTS.md`.
- `Neurosim/neurosim/app/services/cnl_to_graph.py` still performs regex-based parsing of CNL text into a graph.

**Why this is partly a problem**

The overlap is healthy when `Neurosim` is just a visual surface over canonical `neurocnl` semantics. It becomes unhealthy when `Neurosim` locally decides what CNL means, because that creates semantic drift between text mode and visual mode.

`Neurosim` can and should own:

- node positioning
- canvas metadata
- graph editing UX
- project persistence

It should not become the authoritative interpreter of the language itself.

**Recommendation**

Keep both modules, but remove duplicated CNL semantic ownership from `Neurosim`.

**Best target state**

- `neurocnl`: canonical parser, validation, support verdicts, generation
- `Neurosim`: visual editing, layout, view-model mapping, project UX

### 2. `Neurochip` vs `Neurobench`

**What overlaps**

- `Neurochip` analyzes whether a design fits hardware constraints and what deployment tradeoffs exist.
- `Neurobench` compares targets using benchmark outcomes, including accuracy, latency, power, memory, and spike fidelity.
- Both specs talk about side-by-side hardware target comparison.

**Why this overlap mostly needs to stay**

These are two different questions:

1. **Can this design fit or deploy on the target?** -> `Neurochip`
2. **How well does it perform on the target under a benchmark?** -> `Neurobench`

That distinction is strong enough to justify both modules keeping comparison-related features.

**Recommendation**

Keep the overlap, but enforce the scope line:

- `Neurochip` owns feasibility and deployability.
- `Neurobench` owns measured or benchmark-derived comparison.

Avoid re-implementing benchmark comparison logic in `Neurochip`.

### 3. `Neurochip` vs `Neuro-Dream-Hand`

**What overlaps**

`Neuro-Dream-Hand` includes:

- quantization helpers
- crossbar export
- fault injection
- hardware bridge code

`Neurochip` also owns:

- quantization
- fault analysis
- deployment/export
- hardware runtime/deployment contracts

**Why this overlap exists**

`Neuro-Dream-Hand` is both an application domain and a proving ground. It naturally developed hardware-oriented helpers for the prosthetic workflow before the suite-wide deployment layer was fully separated.

**Why part of it should be removed**

Generic hardware-analysis kernels should not live permanently in an application-specific module if the suite already has `Neurochip` as the hardware/deployment owner.

**Recommendation**

Split the overlap:

- Keep prosthetic-specific wrappers, experiments, and HITL adapters in `Neuro-Dream-Hand`.
- Move or standardize reusable generic quantization/fault/export logic under `Neurochip` or a future shared hardware library.

### 4. `Neurosense` vs `Neuro-Dream-Hand`

**What overlaps**

This is the clearest duplicated feature area:

- `Neurosense` explicitly narrows itself around `2-channel forearm EMG -> filter -> spike encoding -> record -> replay`.
- `Neuro-Dream-Hand` includes `hardware/emg_streamer.py` and related EMG pipeline support for Ganglion/forearm input.

**Why this should not remain duplicated**

The same generic EMG acquisition and encoding logic should not be owned by both the biosignal toolkit and the prosthetic simulation module. That creates duplicate maintenance of:

- device handling
- channel assumptions
- preprocessing
- encoding
- future artifact contracts

`Neuro-Dream-Hand` should depend on a signal/input contract, not own the generic acquisition stack.

**Recommendation**

Move generic EMG/biosignal ownership to `Neurosense`.

Keep in `Neuro-Dream-Hand` only:

- prosthetic-specific control loop adapters
- task-specific mapping from encoded signal to hand control
- HITL validation logic that is unique to the prosthetic domain

### 5. `Neurosense` vs `Neurobench` vs `Neurohub`

**What overlaps**

- `Neurosense` owns session artifacts and encoding presets.
- `Neurobench` owns benchmark baselines and result/report artifacts.
- `Neurohub` wants to store `encoding_preset` and `benchmark_baseline` as community assets.

**Why this overlap should stay**

This is not duplicated ownership if the roles are separated:

- producer module owns the schema and lifecycle of the artifact
- `Neurohub` owns distribution, search, versioning, and sharing

That is exactly the kind of overlap a registry is supposed to have.

**Recommendation**

Keep this overlap.

**Non-negotiable rule**

`Neurohub` should store and version these artifacts, but should not redefine their canonical schema away from the producing module.

### 6. `nmtk` vs `Neurohub`

**What overlaps**

This is the biggest cross-module boundary problem.

`nmtk` clearly owns:

- module registry/manifest
- install/start/stop
- local process and environment management
- health polling
- launcher shell behavior

`Neurohub` was inconsistent before the 2026-04-29 consolidation pass:

- launcher manifest described it as **suite dashboard and project orchestrator**
- `Neurohub/AGENTS.md` described it as **orchestrator and registry**
- `Neurohub/README.md` and `Neurohub/neurohub_spec.md` described it as a registry and metadata layer
- actual code implemented projects, workflows, assets, dashboard, and suite client behavior

**Why this must be resolved**

You cannot do a clean overlap reduction while one module has three different identities:

1. registry
2. orchestrator
3. project/workflow dashboard

That ambiguity encourages duplicated project/workflow/orchestration behavior across the suite.

**Recommendation**

Centralize runtime/module lifecycle orchestration in `nmtk`.

The resolved direction is:

- `nmtk` = launcher/control plane
- `Neurohub` = registry plus project/workflow metadata layer

Project and workflow collaboration can remain in NeuroHub as metadata views, but runtime control must stay in `nmtk`.

### 7. `nmtk_ui_core` shared UI overlap

**What overlaps**

- launcher and module frontends share shell chrome, widgets, tokens, and UI models

**Why it should stay**

This is intentional platform reuse, not unhealthy feature duplication.

**Recommendation**

Keep as-is. The only real issue is documentation drift: `nmtk_ui_core/README.md` still looks like a placeholder despite the package being real and actively used.

### 8. `neurocli` vs `nmtk`

**What overlaps**

- both are intended to expose module lifecycle semantics
- `neurocli` is meant to be the terminal-first front door
- `nmtk` is the GUI/launcher front door

**Why it should stay**

These are alternate interfaces to the same control-plane concepts, not duplicate products.

**Recommendation**

Keep both, but require `neurocli` to reuse:

- the same module ids
- the same manifest
- the same lifecycle semantics

It should never invent a second registry or incompatible command model.

## Contradictions that are driving the overlap

### `Neurohub` has conflicting definitions

| Source | What it says |
|---|---|
| `nmtk/neuro_toolkit/assets/modules.json` | NeuroHub is project registry and workflow metadata |
| `Neurohub/AGENTS.md` | NeuroHub is a registry and metadata layer; `nmtk` owns runtime control |
| `Neurohub/README.md` | NeuroHub is a community registry plus suite metadata layer |
| `Neurohub/neurohub_spec.md` | NeuroHub is a registry and explicitly not the suite launcher |
| `Neurohub/neurohub/app/main.py` | Actual code exposes auth, dashboard, projects, workflows, assets, members, notes, config |

This contradiction must be resolved before long-term overlap cleanup will stick.

### Root README is stale relative to actual module topology

The root `README.md` still lists `NeuroDash` and reports `Neurohub` as `0%` complete, while the launcher manifest does not include `NeuroDash` and the repo contains a working `Neurohub` service.

That mismatch makes ownership analysis harder for anyone reading the repo from the top down.

### `nmtk` docs understate current launcher ownership

`nmtk/neuro_toolkit/SPEC.md` still frames the launcher around a mock-install and simple tool-view phase, while the code already manages venv creation, pip installation, startup, and process control in `lib/services/process_manager.dart`.

### `Neurosense` intentionally narrowed its credible scope, but broader code/spec remains

The README and flagship workflow docs correctly narrow current truth to the EMG record/replay pipeline, while broader spec/code still advertise additional modalities and paths.

This is not inherently wrong, but it matters when deciding what should be centralized and what is still experimental.

### `Neuro-Dream-Hand` has more hardware support code than its SPEC admits

The SPEC still frames hardware/chip phases as planned, while the repo already contains significant bridge/export/fault/quantization code.

That gap makes the module look less overlapping on paper than it is in practice.

## Recommended keep/remove decisions

| Overlap | Decision | Why |
|---|---|---|
| `neurocnl` parsing vs `Neurosim` parsing | **Remove duplicate semantic ownership from `Neurosim`** | One canonical language owner is required |
| `neurocnl` runtime vs `Neurosim` preview | **Keep** | UX wrapper over execution is a valid split |
| `Neurochip` feasibility vs `Neurobench` benchmark comparison | **Keep** | Different decision layers |
| Generic quantization/fault/export in `Neuro-Dream-Hand` | **Reduce / centralize** | Those are suite-wide hardware concerns, not prosthetic-only concerns |
| EMG acquisition in `Neuro-Dream-Hand` | **Move generic parts to `Neurosense`** | `Neurosense` is the explicit biosignal owner |
| `Neurohub` storing presets/baselines from producers | **Keep** | Registry behavior is correct here |
| Runtime/module orchestration in both `nmtk` and `Neurohub` | **Remove from one side; centralize in `nmtk`** | Control plane needs a single authority |
| Shared UI in `nmtk_ui_core` | **Keep** | Intended infrastructure reuse |
| `neurocli` mirroring launcher lifecycle | **Keep** | Same system, different interface |

## Suggested cleanup order

1. Resolve the `Neurohub` identity conflict across manifest, README/spec, and code.
2. Make `neurocnl` the undisputed owner of CNL semantic parsing used by `Neurosim`.
3. Move generic EMG/biosignal acquisition ownership from `Neuro-Dream-Hand` toward `Neurosense`.
4. Consolidate reusable hardware-analysis kernels out of `Neuro-Dream-Hand` toward `Neurochip` or a shared lower layer.
5. Refresh stale top-level docs so the suite architecture described to contributors matches the actual codebase.

## Source references

- Root architecture and stale suite status: `README.md`
- Launcher module registry: `nmtk/neuro_toolkit/assets/modules.json`
- Repo-wide module routing constraints: `AGENTS.md`
- `neurocnl` ownership and support claims: `neurocnl/AGENTS.md`, `neurocnl/README.md`, `neurocnl/docs/support_matrix.md`
- `Neurosim` ownership and local CNL parsing: `Neurosim/AGENTS.md`, `Neurosim/neurosim_spec.md`, `Neurosim/neurosim/app/services/cnl_to_graph.py`
- `Neurochip` ownership and deployment/analysis surface: `Neurochip/AGENTS.md`, `Neurochip/neurochip_spec.md`, `Neurochip/neurochip/app/`
- `Neurobench` benchmark and comparison surface: `Neurobench/AGENTS.md`, `Neurobench/neurobench_spec.md`, `Neurobench/neurobench/app/services/target_comparator.py`
- `Neurosense` flagship scope: `Neurosense/AGENTS.md`, `Neurosense/README.md`, `Neurosense/docs/flagship_workflow.md`
- `Neurohub` conflict sources: `Neurohub/AGENTS.md`, `Neurohub/README.md`, `Neurohub/neurohub_spec.md`, `Neurohub/neurohub/app/main.py`
- `Neuro-Dream-Hand` domain scope and hardware overlap: `Neuro-Dream-Hand/AGENTS.md`, `Neuro-Dream-Hand/README.md`, `Neuro-Dream-Hand/SPEC.md`, `Neuro-Dream-Hand/neurodreamhand/hardware/`
- Launcher control ownership: `nmtk/AGENTS.md`, `nmtk/neuro_toolkit/lib/services/process_manager.dart`
- Shared UI ownership: `nmtk_ui_core/AGENTS.md`, `nmtk_ui_core/lib/nmtk_ui_core.dart`
- Planned CLI scope: `neurocli/AGENTS.md`, `neurocli/README.md`
