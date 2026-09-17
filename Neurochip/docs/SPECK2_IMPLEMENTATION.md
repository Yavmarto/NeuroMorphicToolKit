# Speck 2 Integration Implementation Plan

This document is the maintained implementation plan and status record for SynSense Speck 2 support in `NeuroMorphicToolKit` (NMTK). It reflects the current `Neurochip` codebase and extends the initial simulator-backed delivery into the remaining hardware bring-up phases.

Source references:
- Speck Dev Kit Manual (`Speck-Dev-Kit-Manual-2025.12-V2.pdf`)
- `Neurochip/neurochip_spec.md`
- `Neurochip/docs/ADR-claude/0001-multi-vendor-hardware-abstraction.md`
- `Neurochip/docs/ADR-claude/0002-contract-driven-development.md`
- `Neurochip/docs/ADR-claude/0005-sitl-verification.md`
- `Neurochip/docs/ADR-Gemini/0002-hardware-profile-manifests.md`

## 1. Hardware Snapshot

| Feature | Specification |
| :--- | :--- |
| **Core Count** | 11 cores (9 CNN, 1 readout, 1 pre-processing) |
| **Neuron Capacity** | ~320,000 spiking neurons |
| **Neuron Model** | LIF |
| **Weight Precision** | 8-bit |
| **Input Resolution** | 128x128 DVS event stream |
| **Execution Model** | Fully asynchronous, event-driven |
| **Power Envelope** | Sub-mW (<1 mW) |

## 2. Current Delivery Status

### Completed now

- `synsense` optional dependency group exists in [Neurochip/pyproject.toml](/NeuroMorphicToolKit/Neurochip/pyproject.toml).
- Hardware profile manifest exists at [Neurochip/neurochip/targets/speck2.json](/NeuroMorphicToolKit/Neurochip/neurochip/targets/speck2.json).
- Speck runtime payload and status contracts exist at [Neurochip/neurochip/contracts/speck_runtime_contract.py](/NeuroMorphicToolKit/Neurochip/neurochip/contracts/speck_runtime_contract.py).
- Simulator-backed execution path exists at [Neurochip/neurochip/app/services/speck_simulator.py](/NeuroMorphicToolKit/Neurochip/neurochip/app/services/speck_simulator.py).
- Backend lifecycle management exists at [Neurochip/neurochip/app/services/speck_backend.py](/NeuroMorphicToolKit/Neurochip/neurochip/app/services/speck_backend.py).
- A Samna-backed hardware adapter now exists at [Neurochip/neurochip/app/services/speck_samna_runtime.py](/NeuroMorphicToolKit/Neurochip/neurochip/app/services/speck_samna_runtime.py).
- A scaffold deployment package generator now emits the required `speck_deploy/*` archive contents from the mapped-network payload, and the package is validated before the hardware adapter accepts it.
- `config.samna` is now a typed Speck Samna payload, and the hardware adapter reconstructs and applies the serialized `SpeckConfiguration` to the opened board model during `map_to_device`.
- The Samna-backed runtime now performs artifact-backed event I/O against the opened board model: it creates Samna source/sink nodes, encodes input spikes, and decodes output events into a numeric response payload.
- Artifact generation now includes a truthful `compile_plan.json` that classifies whether the current mapped network is deployable by the present Speck hardware path, and hardware mapping now rejects unsupported compile plans before touching the board.
- REST router exists at [Neurochip/neurochip/app/routers/speck.py](/NeuroMorphicToolKit/Neurochip/neurochip/app/routers/speck.py).
- `samna`-based device discovery diagnostics now distinguish:
  - SDK missing
  - SDK installed but no Speck device discovered
  - Speck device discovered and the hardware adapter selected
- When a discoverable Speck device is present, `SpeckBackend` now selects the Samna-backed hardware adapter instead of the simulator and opens the device during `map_to_device`.
- Suite exposure exists through the suite proxy and hardware worker wiring already referenced by the backend record.
- Regression coverage exists in:
  - [Neurochip/neurochip/tests/test_speck_backend.py](/NeuroMorphicToolKit/Neurochip/neurochip/tests/test_speck_backend.py)
  - [Neurochip/neurochip/tests/test_speck_runtime_contract.py](/NeuroMorphicToolKit/Neurochip/neurochip/tests/test_speck_runtime_contract.py)
  - [Neurochip/neurochip/tests/test_routers.py](/NeuroMorphicToolKit/Neurochip/neurochip/tests/test_routers.py)

### Not completed yet

- Full Samna-native network mapping output rather than the current normalized compile-plan + `SpeckConfiguration` scaffold
- General on-device inference for arbitrary mapped Speck networks beyond the current deployable linear/readout-compatible path
- Software-in-the-loop verification of generated deployment artifacts
- Cross-module UI and workflow integration for target-specific Speck deployment
- Operator-grade diagnostics for mixed simulator versus local hardware execution

### Current runtime truth

The shipped implementation is still simulation-first. Installing `samna` and `sinabs` changes runtime diagnostics and recommended mode, but does not yet switch execution from `SpeckSimulator` to a real Speck device path.

## 3. Current Architecture

The present implementation follows the accepted `Neurochip` architecture:

- Hardware constraints are modeled as a static target profile, consistent with the multi-vendor manifest ADR.
- service-to-router payloads are validated by Pydantic contracts, consistent with the contract-driven-development ADR.
- CI-safe execution is provided by an in-process simulator, which is the first step toward the SITL verification ADR.

Current backend surfaces:

| Layer | File | Responsibility |
| :--- | :--- | :--- |
| Target profile | `Neurochip/neurochip/targets/speck2.json` | Declares device limits and target metadata |
| Contracts | `Neurochip/neurochip/contracts/speck_runtime_contract.py` | Validates mapped-network payloads, status payloads, and expected artifact names |
| Simulator | `Neurochip/neurochip/app/services/speck_simulator.py` | In-process state machine for construct, map, run, reset |
| Backend | `Neurochip/neurochip/app/services/speck_backend.py` | Lifecycle orchestration and environment diagnostics |
| Router | `Neurochip/neurochip/app/routers/speck.py` | `/status`, `/configure`, `/run`, `/reset` API surface |

Current API prefix:

- Direct module: `/api/neurochip/hardware/speck`
- Suite proxy: same routed path through the suite control plane

## 4. Remaining Implementation Plan

### Phase 1. Samna runtime adapter

Objective: add a real hardware adapter without breaking the simulator default path.

Planned work:
- Introduce a dedicated Samna-backed runtime service behind the existing `SpeckBackend` lifecycle.
- Keep `samna` and `sinabs` imports optional and isolated to hardware-only code paths.
- Add explicit runtime selection: `simulator`, `local_hw`, `not_available`.
- Extend the capability probe from package presence to actual device discovery and selected execution-backend reporting.
- Preserve the current REST contract so suite consumers do not need a path change.

Phase 1 progress:
- Done: SDK availability is no longer the only signal; the backend now probes `samna` for discoverable Speck devices and reports structured status fields for discovery support, discovery result, and device count.
- Done: discovered hardware now binds to a real Samna-backed adapter, and `map_to_device` opens the first discoverable Speck device through `samna.device.open_device(...)`.
- Remaining: replace the current `HARDWARE_INFERENCE_NOT_IMPLEMENTED` guard with real artifact-backed on-device execution.

Definition of done:
- `SpeckBackend` can bind either `SpeckSimulator` or a Samna adapter.
- `/status` reports truthful device discovery, not only package presence.
- Default test runs still pass on hosts without Speck hardware or SDKs installed.

### Phase 2. Artifact generation and mapping contracts

Objective: turn mapped-network payloads into an actual Speck deployment package.

Planned work:
- Implement a deployment artifact builder that emits the files already declared in `REQUIRED_ARTIFACT_FILES`:
  - `speck_deploy/model.json`
  - `speck_deploy/config.samna`
  - `speck_deploy/manifest.json`
  - `speck_deploy/README.md`
- Extend the runtime contract only if the emitted artifacts require additional metadata such as:
  - target firmware or SDK version
  - device topology summary
  - checksum and schema version fields
- Validate artifact structure before mapping starts.
- Keep contract updates synchronized with all router, service, and test consumers.

Phase 2 progress:
- Done: the backend now generates a truthful scaffold Speck archive containing `model.json`, `config.samna`, `manifest.json`, and `README.md`.
- Done: the Speck contract now includes a typed deployment-manifest model and archive validator, and the Samna runtime adapter loads validated artifacts before mapping hardware.
- Done: `config.samna` is now a typed Samna configuration payload, and the runtime applies the serialized `SpeckConfiguration` to the opened device model before marking the hardware mapped.
- Done: the runtime now uses Samna source/sink nodes to perform artifact-backed event I/O on hardware. For small output populations, it routes input spikes through the documented readout path and decodes `ReadoutPinValue` events into the returned output vector.
- Done: the archive now includes `compile_plan.json`, and the hardware path refuses unsupported mapped-network topologies at compile-plan load time instead of pretending they are deployable.
- Remaining: replace the normalized configuration scaffold with real Samna-native mapped-network output and broaden execution beyond the current deployable linear/readout-compatible path.

Definition of done:
- Artifact emission is reproducible from the current mapped-network payload.
- Contract tests cover missing files, invalid bit widths, checksum mismatches, and schema drift.
- Simulator mode can consume the same generated package or an equivalent normalized model representation.

### Phase 3. SITL verification

Objective: verify Speck deployment artifacts in CI without depending on physical hardware.

Planned work:
- Add a Speck-focused SITL verifier aligned with ADR 0005.
- Feed deterministic event vectors into generated artifacts and compare outputs against expected traces.
- Record correctness metrics and timing summaries that can be asserted in tests.
- Keep the simulator and verifier separate:
  - simulator for runtime fallback and developer workflows
  - SITL verifier for artifact validation and regression detection

Definition of done:
- CI can fail on broken Speck artifacts even when no hardware is attached.
- Verification fixtures are deterministic and small enough for default test runs.
- The verification surface is documented for future hardware targets to reuse.

### Phase 4. Device bring-up and operator diagnostics

Objective: make local hardware execution debuggable by non-experts.

Planned work:
- Add structured hardware discovery errors for:
  - SDK missing
  - host unsupported
  - no device found
  - mapping failed
  - inference failed
- Return human-readable diagnostics plus machine-readable error codes.
- Capture runtime target metadata such as connected board id, firmware details if available, and selected backend.
- Ensure reset semantics are identical between simulator and hardware modes.

Definition of done:
- Local operators can distinguish `preflight unavailable` from `device mapping failure`.
- Router responses remain contract-valid in both simulator and hardware paths.
- Tests cover the main negative paths with mocked Samna interactions.

### Phase 5. Cross-module workflow integration

Objective: connect Speck deployment cleanly to the broader suite workflow.

Planned work:
- Confirm the producer and consumer contract for target-selected deployment flows with `neurocnl` and any suite control-plane surfaces that invoke `Neurochip`.
- Expose Speck runtime status in whatever UI or orchestration surface already reflects active hardware targets.
- Keep target metadata aligned with any launcher or suite-visible manifests if Speck becomes a selectable deployment target outside `Neurochip`.

Definition of done:
- The selected Speck target can be carried from the originating workflow into `Neurochip`.
- Suite-visible status messaging does not imply physical hardware support before it exists.
- Any cross-module contract change ships with the required integration tests.

## 5. Implementation Order

Recommended order:

1. Finish the Samna runtime adapter behind the existing backend interface.
2. Implement package generation for the runtime artifact files already declared by contract.
3. Add SITL verification for artifact correctness.
4. Add hardware discovery and operator diagnostics.
5. Wire cross-module UX and orchestration updates only after the backend semantics are stable.

This order keeps the existing API surface stable, preserves optional hardware dependencies, and avoids leaking incomplete hardware support into suite-visible workflows.

## 6. Risks and Guardrails

### Main risks

- `samna` and `sinabs` imports could leak into default startup or test paths.
- The current contract may be too small for full artifact generation, causing downstream schema churn.
- SITL may diverge from hardware behavior if fixtures are not regularly compared against real-device runs.
- Suite surfaces may overstate support if they key only off SDK availability instead of actual device discovery.

### Guardrails

- Keep simulator mode as the default fallback until real hardware execution is proven.
- Isolate optional dependencies in hardware-only modules and mock them in tests.
- Treat artifact contracts as the source of truth for router and service payloads.
- Do not change path names, checksum semantics, or target metadata in one layer only.

## 7. Verification Checklist

For backend changes in this plan, use the module-required checks:

```bash
cd Neurochip && PYTHONPATH=.. poetry run pytest tests/
cd Neurochip && poetry run ruff check .
cd Neurochip && poetry run mypy .
cd Neurochip/frontend && flutter test
```

Speck-specific verification should also include:

- router tests for `/status`, `/configure`, `/run`, and `/reset`
- contract tests for runtime payload validation and artifact manifests
- mocked Samna hardware-path tests
- SITL regression fixtures once Phase 3 lands

If a future Speck change crosses module contracts, also run:

```bash
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```

## 8. Status Update

As of 2026-05-04:

- Initial simulator-backed Speck integration is complete.
- The document has been updated from a static implementation record into a live execution plan.
- Phase 1 has started: truthful `samna` device discovery and runtime-status reporting are now implemented.
- Phase 1 has advanced: runtime selection now chooses a Samna-backed hardware adapter when a discoverable Speck device is present, and the adapter opens and closes the hardware device through `samna`.
- Phase 2 has started: artifact generation and archive validation now exist, and hardware mapping consumes that validated package before opening the device.
- Phase 2 has advanced: generated `config.samna` payloads are now parsed and applied to the board model during hardware mapping.
- Phase 2 has advanced again: `run_inference()` now performs artifact-backed Samna event I/O against the mapped board model.
- Phase 2 has advanced again: the hardware path now has a truthful compile/deployability gate in the artifact and at map time.
- The next recommended implementation slice is still the real compiler problem: replace the normalized compile-plan/config scaffold with true Samna-native mapped-network deployment output for general Speck workloads, then add SITL coverage for that path.
