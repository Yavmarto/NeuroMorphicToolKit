# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Deploy-readiness auto-check: after a passing spec validate, Studio now auto-runs a side-effect-free readiness check (simulator preflight or `previewDeployTarget` for hardware/codegen targets) and surfaces the result in a new Validation panel section, so unsupported-node or codegen failures are visible before the user ever presses Play.
- `PipelineState.deployReadinessStatus` / `deployReadinessResult` (new `DeployReadinessResult` freezed union: `ok` / `unsupported` / `error`).
- `PipelineState.deployStepStatus` / `overallReady` / `deployReadinessFailed` derived getters — single source of truth read by both `pipeline_bar.dart`'s Deploy step and `validation_panel.dart`'s Overall banner, replacing the old independent simulator-vs-hardware branching in each widget.
- Training domain model: TrainingResult, TrainingAvailability, UnavailableReason, TrainingRunSummary in neurocnl.training_registry
- SleepPesAdapter: first concrete training adapter with honest availability checking and deterministic fallback
- SnnTorchAdapter: surrogate-gradient training adapter with honest dependency gating and a deterministic N-MNIST-style toy fixture
- Generic training API: GET /api/training/capabilities, POST /api/training/run, GET /api/training/jobs/{job_id}
- Legacy sleep route rewired through generic training system (backward compatible)
- Flutter training state model and provider (6-state machine, capability-driven)
- Flutter TrainingInspectorPanel widget with elapsed time, success/failure states
- Studio wiring with NEUROCNL_TRAINING_PANEL_ENABLED feature flag
- trainingResultProvider for result reuse across widgets
- Public `fit(...)` helper exported from `neurocnl`
- Shared actionable CNL error payloads across generate/export/simulate/deploy/training-request routes
- `nir_cnl` grammar: `Define a network named <id> with timestep <seconds>.` optional clause propagates the declared timestep into every `nir.LIF` node's `metadata["dt"]` (unless that node already carries its own explicit `dt`) and mirrors it onto the compiled graph's own `metadata["dt"]`; the renderer round-trips it and suppresses the now-redundant per-node clause when it just equals the inherited default.
- `neurocnl/examples/03_generate_and_train_braille.py`: standalone demo that defines a small SNN in CNL, compiles it through nmtk's real notebook-codegen path, and executes the generated snnTorch code end to end against the bundled braille dataset — no FastAPI server, Docker, or Flutter app required.
- `_build_v2_notebook` (snntorch_sim target): a markdown warning cell now appears when a compiled `nir.LIF` node's effective firing threshold looks unreachable for typically-scaled inputs, naming the node and suggesting a network timestep or lower threshold.

### Changed
- sleep_runner.py deprecated — delegates to SleepPesAdapter internally
- POST /api/prosthetic/sleep now delegates via training_service.submit_training_job_forced()
- `NIR_LIF_INVARIANTS` / `NIR_CUBALIF_INVARIANTS` display labels relabeled for readability (e.g. "LIF time constant positive") — no change to `/api/validate` response shape.

### Removed
- Dead hardware-specific Layer 1 invariant groups only reachable through `validate()`'s dead `backend in ("loihi","akida","spinnaker","spinnaker2","teensy")` branches, which no live caller ever exercises on the current NIR-only surface: `LOIHI_INVARIANTS`, `AKIDA_INVARIANTS`, `SPINNAKER_INVARIANTS`, `SPINNAKER2_INVARIANTS`, `TEENSY_INVARIANTS`, plus the `LoihiExportContract` / `AkidaExportContract` / `TeensyExportContract` classes they depended on. `ALL_INVARIANTS` and `validate()` itself are kept — they're still live via the canvas/notebook LIF-population validation path (see `current tasks/2026-07-04/validation-deploy-readiness/audit.md`).

### Fixed
- Frontend: removed stale `'pynq'` entry from `workspace_provider.dart`'s `supportedDeployTargets`, which no longer exists in the deploy-target catalog and was silently causing target resolution to fall back to the first (simulator) entry, hiding hardware-only UI.
- Frontend: `WorkspaceFile`'s `pipelineCache`/`nirArtifactCache`/`pipelineState`/`nirState` fields now round-trip correctly through direct `fromJson(toJson())` calls — added manual `@JsonKey` serializers (previously only worked when the caller went through `jsonEncode`/`jsonDecode`).
- Frontend: `SweepController.runSweep` now guards against continuing after disposal (`ref.mounted` check), matching the stale-request guard pattern used elsewhere.
- Fixed ~120 pre-existing `flutter test` failures across the frontend suite (stale finders/pump-timing, tests stale against already-shipped behavior changes, missing test-binding initialization, and independent mechanical fixes) — see `current tasks/2026-07-04/fix-pre-existing-test-failures/README.md`.
- CNL→snnTorch training notebooks generated from a network with no declared timestep previously used a hardcoded oracle-parity `dt=1e-4` default that, combined with typical `.cnl` template `tau`/`threshold` values, produced an unreachable firing threshold — the LIF neuron never spikes and training loss stays pinned at `ln(num_classes)` forever. All 16 shipped `backend/app/templates/*.cnl` templates now declare an explicit, reachable `with timestep <seconds>` clause.

## [0.6.0] — 2026-04-08

### Added
- Pre-beta gate hardening across all hardware backends
- Hardware-aware constraint validation for SpiNNaker targets (topological drift mitigation, Akida sequential invariants)
- Akida validator invariant expansion; real graph traversal replaces stub capability checker
- NeuroCNL → Neurochip PYNQ handoff connector (NeuroCNL-12)

### Fixed
- Critical syntax errors in backend capability profiles
- Ruff lint violations (NR-20)
- Lazy-load Rockpool capabilities to prevent import errors on core installs

## [0.5.0] — 2026-03-28

### Added
- SynSense sinabs framework integration; sinabs.Network export via NIR bridge
- Rockpool converter integrated via NIR (SynSense DYNAP-CNN / Speck targets)
- SpiNNaker2 backend export (projection scaling + hardware constraints)
- Lava simulation-path testing and validation
- Loihi layer-1 validator results integrated into planner verdict

## [0.4.0] — 2026-03-20

### Added
- PYNQ Z2 FINN compilation target integration
- Direct overlay config export for PYNQ Z2
- PYNQ runtime artifact contract (NeuroCNL-09)
- PYNQ support semantics (NeuroCNL-08)

## [0.3.0] — 2026-03-15

### Added
- Teensy deployment contract (NeuroCNL-01)
- Teensy validator enforcement (NeuroCNL-02)
- Teensy runtime verification and handoff (NeuroCNL-06)
- Docs refreshed for backend fidelity (CNL-056)

## [0.2.0] — 2026-03-12

### Added

- **Inhibitory connections** (CNL concept #7) — `The connection from X to Y MUST be inhibitory`
- **Population coding** (CNL concept #8) — `The population MUST encode input using N neurons`
- **Layer 2 cross-sentence validation** — dangling connection detection, contradictory parameter detection
- **Structured logging** — Python `logging` module replaces all `print()` statements
- **CLI flags** — `--verbose`/`-v`, `--quiet`/`-q`, `--format json|table`
- **Batch validation** — `neurocnl --validate-only *.cnl` validates multiple specs with summary table
- **Table report format** — `--format table` shows colored ✓/✗ per invariant
- 4 new Layer 1 invariants: `inhibitory_weight_negative`, `population_neuron_count_positive`, `population_dimensions_positive`, `population_radius_positive`
- Nengo generator supports configurable ensemble size, dimensions, radius, and inhibitory connections
- 46 new tests (190 total, all passing)

## [0.1.0] — 2026-03-12

### Added

- **CNL Parser** with 6 neuromorphic concepts:
  - Threshold firing
  - Refractory period
  - Membrane potential decay
  - Synaptic weight
  - Axonal delay (new)
  - STDP learning rules (new)
- **Layer 1 validation** — 8 physical invariants enforcing biologically plausible parameters
- **Loihi-specific invariants** — 3 hardware constraints (weight quantization, core limits, delay range)
- **Nengo code generation** — automatic network generation from parsed specs, including:
  - Lowpass synapse for axonal delays
  - PES learning rule for STDP approximation
  - Dynamic max_rates based on refractory period
- **Loihi emulator backend** — `--backend loihi` flag using NengoLoihi emulator (no Intel hardware required)
- **4 demo CNL specs** — EMG gripper, slip reflex, EEG attention, audio wake-word
- **Simulation prototypes** — all 4 demos run with synthetic inputs
- **Auto-generated assertions** — Layer 3 pytest assertions from CNL specs
- **CI/CD** — GitHub Actions workflow (Python 3.11 + 3.12 matrix)
- **Proper packaging** — pyproject.toml with metadata, dependencies, CLI entry point
- **Public API** — `from neurocnl import parse, validate, generate`
- **CLI** — `neurocnl spec.cnl [--backend loihi]`
- 144 passing tests

## [0.0.0] — 2025-12-01

### Added

- Initial MVP with 4 CNL concepts (threshold, refractory, decay, weight)
- 3-layer pipeline: invariants → specification → validation assertions
- Basic Nengo code generation for reflex arc
- 74 passing tests
