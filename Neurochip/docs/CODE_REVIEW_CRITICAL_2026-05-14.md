# NeuroChip Critical Code Review and Implementation Plan

Date: 2026-05-14
Reviewer: Codex
Scope: `Neurochip/**`, with contract/context checks against `neurocnl`, `nmtk`, `nmtk_ui_core`, and the PYNQ ADRs where relevant.

## Bottom Line

The logic and implementation do **not** currently hold up end to end.

There is a real, useful core here: the PYNQ word-MMIO contract has mostly been pulled into Neurochip, NeuroCNL, launcher metadata, staged manifests, and tests; the PYNQ provisioning work also reflects hard-won runtime isolation lessons. However, the module as a product is still fragile. A clean backend import fails in the current Poetry environment, NeuroChip's local documentation still describes a retired standalone frontend even though the user-facing hardware UI is integrated into CNL Studio, important user-story endpoints are placeholders, several estimator/analysis paths ignore target-specific hard limits, and multiple deployment routes can return confident-looking success for simulator, scaffold, or invalid-artifact paths.

The riskiest theme is **truthfulness**. NeuroChip is supposed to be the hardware-facing layer. It must never blur "artifact generated", "simulated", "compiled", "mapped to SDK simulator", and "deployed to real hardware". Several current APIs still do.

## Review Methodology

Read first:

- `AGENTS.md`
- `/.codex/RTK.md`
- `CODING_STYLE_GUIDE.md`
- `Neurochip/AGENTS.md`
- `Neurochip/neurochip_spec.md`
- `Neurochip/docs/ADR-Gemini/*`
- `Neurochip/docs/ADR-Codex/*`
- `Neurochip/docs/ADR-claude/*`

Additional context:

- Open Brain context for NeuroChip/PYNQ troubleshooting and follow-ups.
- `semble search` for NeuroChip deployment, runtime, hardware, quantization, PYNQ, Akida, and Lava surfaces.
- Targeted source inspection across routers, contracts, services, target manifests, provisioning, overlay manifests, workers, and tests.

Verification attempted:

```text
cd Neurochip
rtk poetry run pytest neurochip/tests -q
rtk env PYTHONPATH=. poetry run pytest neurochip/tests -q
rtk poetry run ruff check .
rtk poetry run mypy .
```

Results:

- `ruff check .`: passed.
- `mypy .`: failed with 28 errors in 5 files, mostly Lava router/backend typing plus test typing.
- `poetry run pytest neurochip/tests -q`: failed collection with 44 `ModuleNotFoundError: No module named 'neurochip'` errors because the nested test path is not import-safe under that invocation.
- `PYTHONPATH=. poetry run pytest neurochip/tests -q`: still failed collection with 19 errors because importing `neurochip.app.main` imports Lava, and `lava_backend.py` imports `numpy` even when Lava is unavailable.
- `PYTHONPATH=. poetry run python -c "import neurochip.app.main"`: failed with `ModuleNotFoundError: No module named 'numpy'`.

## Positive Findings

These parts are directionally sound:

- The PYNQ overlay v1.0.1 constants now match ADR 0010: `MAX_SYNAPSES = 15360`, `weight_base_offset = 0x1000`, stride 4, and `int8_dense_row_major_word_mmio`.
- `Neurochip/hardware/pynq_z2/overlay_manifest.json`, `Neurochip/overlay_staging/pynq_z2/overlay_manifest.json`, `neurocnl`, `nmtk`, and `nmtk_ui_core` appear aligned on the 15,360-synapse word-MMIO contract.
- PYNQ provisioning now records canonical PYNQ runtime selection and includes XRT/BOARD/LD_LIBRARY_PATH/PATH in the generated systemd unit.
- PYNQ worker errors preserve structured error codes better than older behavior.
- Contracts exist for PYNQ, Teensy, Akida, Speck, hardware profiles, quantization, estimation, faults, and deployment manifests.
- Serial flashing uses subprocess argument lists rather than shell strings.
- SQLite queries in deployment storage are parameterized.

## Findings

### P0: The backend does not import in the current clean Poetry environment

Evidence:

- `Neurochip/neurochip/app/main.py:25-38` unconditionally imports every router, including Lava.
- `Neurochip/neurochip/app/routers/lava.py` imports `LavaBackend`.
- `Neurochip/neurochip/app/services/lava_backend.py:14-24` catches missing Lava SDK dependencies, then imports `numpy` again in the exception path.
- `Neurochip/pyproject.toml:7-23` does not declare `numpy` as an unconditional dependency.

Observed failure:

```text
ModuleNotFoundError: No module named 'numpy'
```

Impact:

Default server startup and most app-level tests fail without `numpy`, despite the module rule that Lava is optional and missing optional runtimes must degrade rather than crash startup.

Recommendation:

- Make `numpy` an explicit dependency if the fallback requires it, or remove NumPy from the import-time fallback path.
- Guard optional routers at app startup or move optional imports inside operations.
- Add a test that `import neurochip.app.main` succeeds with Lava, PYNQ, Akida, Speck SDKs absent.

### P0: The module's own verification suite is currently red

Evidence:

- `rtk poetry run pytest neurochip/tests -q` failed at collection with 44 import errors.
- `rtk env PYTHONPATH=. poetry run pytest neurochip/tests -q` failed at collection with 19 Lava/NumPy import errors.
- `rtk poetry run mypy .` failed with 28 errors.
- `ruff check .` passed.

Impact:

The module cannot currently prove its own contracts, routers, and hardware fallbacks in the checked environment. This is especially serious for a hardware-facing module because regressions are expensive to discover on real boards.

Recommendation:

- Fix the test invocation/path layout. The current `neurochip/tests` nested test directory is brittle when invoked from the repository root as documented.
- Fix optional-runtime import failures before evaluating individual test failures.
- Bring `mypy` back to green or update the stated verification contract if strict mypy is no longer intended.

### P0: PYNQ export can return an artifact that its own contract validator rejects

Evidence:

- `Neurochip/neurochip/app/routers/export.py:266-273` validates PYNQ limits using `network.num_synapses`.
- `Neurochip/neurochip/app/services/pynq_generator.py:67-86` expands actual connections from `connection["weight_count"]` and population sizes.
- `Neurochip/neurochip/app/services/pynq_generator.py:180-259` packages the artifact without validating `overlay_config.json` against `PynqOverlayConfigArtifactContract`.
- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py:302-350` contains the contract that would catch the invalid artifact, but the generator does not call it.

Reproduction:

```text
NetworkInput(num_neurons=256, num_synapses=1, populations=[128, 128],
connections=[{"weight_count": 16384}])
```

The route-side `PynqNetworkPayloadContract` passes because `num_synapses` is 1. `generate_pynq_package` then emits 16,384 actual connections. `validate_pynq_compile_artifact` rejects the returned zip:

```text
ValidationError: Total synapses (16384) exceeds overlay-v1 max (15360)
```

Impact:

NeuroChip can return a PYNQ artifact that cannot be compiled/deployed under its own fixed overlay contract. This breaks the "defense in depth" contract model and can move failures later into compilation or hardware workflows.

Recommendation:

- Derive `num_synapses` from actual connections before validation, or require the payload count to match generated topology.
- Validate the generated `overlay_config`, `register_map`, and final ZIP before returning it.
- Add a regression test where declared and generated synapse counts disagree.

### P1: Constraint analysis ignores target-specific synapse capacity

Evidence:

- `Neurochip/neurochip/targets/pynq_z2.json:10` declares `synapse_capacity: 15360`.
- `Neurochip/neurochip/contracts/hardware_contracts.py:4-57` does not model `synapse_capacity`, `max_populations`, overlay id/version, or other PYNQ-specific profile fields.
- Pydantic's default behavior ignores unknown fields, so the target-specific fields are discarded.
- `Neurochip/neurochip/app/services/constraint_analyzer.py:35-65` checks neuron capacity, bit width, and estimated memory only. It does not check synapse capacity.

Observed behavior:

A PYNQ network with 20,000 synapses returns `memory_fit: "pass"` and no recommendation, even though the overlay contract caps deployable synapses at 15,360.

Impact:

The compatibility report can tell users a network is acceptable for PYNQ when the deploy/export contract will reject it. That is exactly the late-stage hardware failure the module is supposed to prevent.

Recommendation:

- Add optional target profile fields such as `synapse_capacity`, `max_populations`, `overlay_id`, `overlay_version`, and `supported_topologies` to a typed profile extension or discriminated target model.
- Fail or warn in `analyze()` when `network.num_synapses` exceeds the target's hard synapse capacity.
- Add PYNQ-specific analyzer tests for the 15,360 boundary.

### P1: Hardware deploy endpoints can report success while running only simulator fallback

Evidence:

- `Neurochip/neurochip/app/services/pynq_backend.py:257-258` creates a `PynqSimulator` when no configured PYNQ interpreter and no in-process PYNQ runtime exist.
- `Neurochip/neurochip/app/services/pynq_backend.py:381-385` treats simulator `load_overlay()` as successful.
- `Neurochip/neurochip/app/routers/pynq.py:483-499` returns `"Overlay loaded and configured successfully."` without including `runtime_mode`.
- `Neurochip/neurochip/app/routers/pynq.py:704-707` has a preflight endpoint that can report degraded simulator state, but `/deploy` does not require that gate.

Impact:

Callers can receive a successful response from `/hardware/pynq/deploy` without real board readiness. That is useful for local testing but dangerous for product semantics unless the response explicitly says "simulator".

Recommendation:

- Include `runtime_mode` and `preflight_status` in deploy responses.
- Consider `require_hardware=true` for hardware deployment paths, defaulting to fail-closed in launcher-visible flows.
- Keep simulator deploy endpoints separate or clearly labelled.

### P1: PYNQ error taxonomy is still too coarse at the HTTP boundary

Evidence:

- `Neurochip/neurochip/app/services/pynq_worker.py:140-150` distinguishes `PYNQ_DEVICE_PROBE_FAILED` and `PYNQ_DEVICE_NOT_FOUND`.
- `Neurochip/neurochip/app/services/pynq_backend.py:332-342` preserves many worker error codes.
- `Neurochip/neurochip/app/routers/pynq.py:231-246` maps all `OverlayLoadError` to HTTP 500 and all `MmioWriteError` to HTTP 500.

Impact:

Operators cannot reliably distinguish missing board, stale zocl, invalid manifest, overflow, worker timeout, and internal failures from the HTTP status alone. This loses the troubleshooting clarity captured in the April PYNQ incident.

Recommendation:

- Map `PYNQ_DEVICE_NOT_FOUND` and probe failures to 503.
- Map overlay/register-map mismatches to 422.
- Map `MMIO_WEIGHT_OVERFLOW` to 413 or 422.
- Preserve structured `error_code` and a remediation hint in all PYNQ endpoint responses.

### P1: NeuroChip frontend documentation is stale now that the UI lives in CNL Studio

Evidence:

- `Neurochip/AGENTS.md:5-16` requires reading and verifying `frontend/pubspec.yaml`, `frontend/analysis_options.yaml`, and `cd frontend && flutter test`.
- `Neurochip/neurochip_spec.md:332-390` specifies a full Flutter UX.
- `Neurochip/neurochip_spec.md:444-467` specifies `frontend/lib`, `frontend/pubspec.yaml`, and `frontend/test`.
- Actual `Neurochip/frontend` contains only `neurochip.iml`.
- Product ownership clarification after the initial review: the promised user-facing frontend is integrated into CNL Studio, not expected to exist as a standalone NeuroChip Flutter app.

Impact:

This is not evidence that the deployment UX is missing. It is evidence that NeuroChip's local docs and agent instructions are stale. Contributors are still directed to nonexistent standalone frontend files and checks, and the spec does not clearly describe the current CNL Studio -> NeuroChip ownership boundary.

Recommendation:

- Update `Neurochip/AGENTS.md`, `README.md`, `neurochip_spec.md`, and relevant ADR/spec references to state that the frontend is integrated into CNL Studio.
- Replace `cd frontend && flutter test` with the owning CNL Studio/frontend verification command.
- Keep NeuroChip documentation focused on the backend/hardware contract: artifact generation, compile/deploy APIs, provisioning, target profiles, and diagnostics.

### P1: User-story endpoints are still placeholders or synthetic models

Evidence:

- `Neurochip/neurochip/app/routers/analysis.py:20-29` returns placeholder messages for `/partition` and `/compare`.
- `Neurochip/neurochip/app/services/partitioner.py:28-115` implements a basic partitioner, but the router does not use it.
- `Neurochip/neurochip/app/services/quantizer.py:13-65` uses a seeded mathematical simulation, not real task accuracy or spike fidelity.
- `Neurochip/neurochip/app/services/fault_runner.py:10-67` uses synthetic degradation curves.
- `Neurochip/neurochip/app/services/power_estimator.py:17-70` and `:73-106` use coarse heuristics only.

Impact:

Several advertised core features can produce polished-looking numbers that are not grounded in the actual network/task/hardware. For a deployment tool, synthetic estimates must be labelled and separated from verification outputs.

Recommendation:

- Return explicit `status: "estimate"` / `method: "heuristic"` metadata from synthetic endpoints.
- Wire `/partition` to the existing partitioner or remove the endpoint until ready.
- Keep synthetic quantization/fault/power outputs out of deploy readiness gates.

### P1: Akida `remote_server` mode is an SSRF-capable network primitive

Evidence:

- `Neurochip/neurochip/app/routers/akida.py:184-202` accepts any absolute `http://` or `https://` `target_url` and posts the generated ZIP.
- `Neurochip/neurochip/app/auth.py:7-8` disables auth by default and defines a default secret when auth is enabled.
- `Neurochip/neurochip/app/main.py:91-107` defaults CORS to `*` when `ALLOWED_ORIGINS` is unset.

Impact:

If exposed beyond a trusted local process, this can be used to make the NeuroChip backend POST to internal services. The payload is a generated ZIP, but it is still arbitrary outbound connectivity to caller-supplied hosts.

Recommendation:

- Require authentication for `remote_server` mode.
- Add an allowlist for remote Akida hosts or disable arbitrary URLs by default.
- Block link-local, loopback, private-network, and metadata-service targets unless explicitly configured.

### P2: Authentication and CORS defaults are development-friendly but not hardware-safe

Evidence:

- `Neurochip/neurochip/app/auth.py:7` sets `NEUROCHIP_AUTH_ENABLED` default to false.
- `Neurochip/neurochip/app/auth.py:8` uses `neurochip-secret-key` as the default API key if auth is enabled but a key is not configured.
- `Neurochip/neurochip/app/main.py:91-107` defaults CORS to `*`.
- Routes include serial flashing, PYNQ deploy, Akida remote dispatch, deployment records, and loop start/stop.

Impact:

The defaults are acceptable only for loopback development. They are not appropriate for a hardware control plane that can run subprocesses, flash devices, control boards, and open outbound network connections.

Recommendation:

- Keep `/health` public, but require explicit opt-out for mutating hardware routes.
- Fail startup when `NEUROCHIP_AUTH_ENABLED=true` and the key remains the default.
- Narrow default CORS to launcher origins or loopback origins.

### P2: Flash jobs are unbounded and in-memory only

Evidence:

- `Neurochip/neurochip/app/services/flash_service.py:38-42` stores all jobs and hooks in module-level globals.
- `Neurochip/neurochip/app/services/flash_service.py:91-105` starts an unbounded daemon thread per flash request.
- `Neurochip/neurochip/app/services/flash_service.py:122-123` extracts the uploaded ZIP without a size cap.
- `Neurochip/neurochip/app/services/flash_service.py:142-178` runs compile/upload subprocesses with fixed 120-second timeouts.
- `Neurochip/neurochip/app/services/flash_service.py:223-224` has no expiry or persistence for completed jobs.

Impact:

Repeated flash requests can exhaust threads, memory, disk, or PlatformIO processes. Completed job state disappears on restart but grows forever during a long-running process.

Recommendation:

- Add upload size limits and ZIP member count/size checks.
- Use a bounded worker queue.
- Add job TTL cleanup.
- Persist only durable deployment records, not arbitrary in-memory job histories.

### P2: PYNQ compile extracts uploaded artifacts without explicit member validation

Evidence:

- `Neurochip/neurochip/app/services/pynq_compiler.py:166-170` calls `archive.extractall(destination)`.
- The same service later trusts extracted paths under `artifact_root / "pynq_deploy"` when building the compiler request at `pynq_compiler.py:246-259`.

Impact:

Python's `zipfile.extractall()` performs some path sanitization in modern versions, but the compile path still lacks explicit policy for absolute paths, parent traversal, duplicate names, symlinks, member count, or decompressed size. This is an uploaded artifact boundary and should be treated as hostile input.

Recommendation:

- Validate every ZIP member path before extraction.
- Reject absolute paths, `..`, duplicate required files, symlinks, and oversized members.
- Prefer reading required JSON files directly from the archive where possible.

### P2: Target/profile handling hides broken manifests

Evidence:

- `Neurochip/neurochip/app/routers/targets.py:27-37` silently suppresses any exception while listing target profiles.
- `Neurochip/neurochip/app/routers/targets.py:42-56` returns a 500 for malformed individual profiles, but list mode simply omits them.
- `Neurochip/neurochip/contracts/hardware_contracts.py:32` leaves `access` as a free string rather than a constrained enum.

Impact:

The target catalog can appear healthy while silently dropping malformed targets. That undermines profile-as-source-of-truth architecture.

Recommendation:

- Return profile load diagnostics in list responses or fail list with structured issues.
- Constrain `access` to the documented values.
- For target-specific extensions, use typed submodels instead of ignored extras.

### P2: Quantization target resolution silently falls back to Teensy

Evidence:

- `Neurochip/neurochip/app/routers/quantization.py:18-30` permits unknown target strings.
- `Neurochip/neurochip/app/services/quantizer.py:138-147` resolves unknown target strings to `TargetDevice.TEENSY_41`.
- `Neurochip/neurochip/app/routers/quantization.py:88-93` batch mode only matches enum values, not enum names, before falling back to Teensy defaults.

Impact:

Typos or frontend/schema drift can produce Teensy quantization results for a different target. That is silent misclassification.

Recommendation:

- Reject unknown target IDs with 422.
- Normalize accepted target identifiers through one shared function.
- Add tests for `pynq_z2`, `PYNQ_Z2`, `PYNQ-Z2`, `akida`, and unknown strings.

### P2: Loihi/Lava/BrainScaleS/Neuromorphic export support is overstated

Evidence:

- `Neurochip/neurochip/app/services/loihi_generator.py` explicitly notes production work would use real HDF5/crossbar export and currently writes placeholder weights.
- `Neurochip/neurochip/app/services/quantizer.py`, `fault_runner.py`, and `power_estimator.py` likewise describe production integrations that are not present.
- `Neurochip/README.md:30-39` presents multi-target support as a product capability.

Impact:

The repository reads as broader in capability than the implementation. This creates operator confusion and makes it easy for suite-level UI to overpromise.

Recommendation:

- Introduce explicit support levels per target: `profile_only`, `scaffold_export`, `simulated`, `sdk_mapped`, `hardware_verified`.
- Surface support level in target profile responses and export/deploy responses.
- Make unsupported production paths return 501 or clearly labelled scaffold outputs.

### P2: Deployment state is stored inside the package directory

Evidence:

- `Neurochip/neurochip/app/services/deployment_store.py:9` stores SQLite at `Neurochip/neurochip/deployments.db`.

Impact:

Runtime state is written into the source/package tree. This is brittle for containers, installed wheels, read-only deployments, and test isolation.

Recommendation:

- Move deployment state to a configurable app data directory.
- Add `NEUROCHIP_DEPLOYMENT_DB_PATH`.
- Make tests set a temp DB path.

### P2: Generated artifacts use weak or partial integrity semantics

Evidence:

- `Neurochip/neurochip/app/services/pynq_generator.py:237-249` computes a checksum before adding `manifest.json`; therefore the checksum does not cover itself, but it also does not clearly define canonical artifact hashing semantics.
- `Neurochip/neurochip/app/services/teensy_generator.py:238-247` checksums rendered text files before adding the manifest.
- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py:422-438` records `manifest_checksum_sha256` from the manifest but does not recompute and compare it to canonical artifact contents.

Impact:

The checksum field currently proves "some generator content hash", not full artifact integrity. That may be acceptable, but the contract name implies stronger guarantees.

Recommendation:

- Define canonical checksum semantics per artifact type.
- Validate checksum fields against those semantics.
- Include tests that tamper with `weights.bin`, `overlay_config.json`, and `manifest.json`.

### P3: Documentation and implementation have stale or contradictory paths

Evidence:

- `Neurochip/AGENTS.md:5-16` references missing frontend files.
- `Neurochip/README.md:58` links `../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md`, which is outside the Neurochip directory and was not present in the checked Neurochip ADR list.
- `Neurochip/neurochip_spec.md` still describes a standalone Flutter frontend even though the current product frontend is integrated into CNL Studio.
- Some endpoint descriptions still read like product-surface promises rather than backend/hardware capability descriptions.

Impact:

Agent instructions and user-facing docs steer contributors toward nonexistent standalone frontend files and incomplete verification. They also obscure the actual ownership boundary: CNL Studio owns the deployment UI flow, while NeuroChip owns backend artifact generation, hardware provisioning, compile/deploy APIs, and diagnostics.

Recommendation:

- Reconcile the docs around the established ownership model: CNL Studio frontend, NeuroChip backend/hardware layer.
- Replace standalone frontend file trees and Flutter checks with references to the owning CNL Studio surfaces and tests.
- Keep the NeuroChip spec focused on API behavior, target contracts, provisioning, hardware diagnostics, and supported capability levels.
- Mark stale spec sections as historical or update them to current architecture.

## Cross-Module Contract Assessment

PYNQ is the healthiest contract area. The 15,360-word-MMIO limit now appears in:

- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`
- `Neurochip/hardware/pynq_z2/overlay_manifest.json`
- `Neurochip/overlay_staging/pynq_z2/overlay_manifest.json`
- `neurocnl/neurocnl/contracts/pynq_deployment_contract.py`
- `neurocnl/neurocnl/contracts/pynq_runtime_artifact_contract.py`
- `nmtk/launcher_control/server.py`
- `nmtk_ui_core/lib/models/pynq_deployment_model.dart`

That said, PYNQ still has two serious truthfulness gaps:

- Export can emit invalid artifacts if declared counts and generated connections diverge.
- Deploy can succeed under simulator fallback without telling the caller in the success payload.

Teensy is reasonably bounded by a payload contract, but flash execution needs stronger resource and upload controls.

Akida has a better status model than most targets, but `remote_server` is too open and the distinction between scaffold, simulator, SDK simulator, and hardware needs to be enforced consistently.

Lava currently violates the optional-runtime rule by breaking base app import when `numpy` is absent.

## Implementation Plan

This plan is ordered by risk to the CNL Studio deployment flow. Phases 1-3 are release-blocking because they affect startup, tests, and artifact truthfulness. Phases 4-7 are product-contract work: they prevent CNL Studio and launcher surfaces from overstating deployment readiness. Phases 8-10 are hardening and support-level cleanup.

### Phase 1: Restore base backend startup

Priority: P0

Goal: `neurochip.app.main` must import and start when optional hardware SDKs are missing.

Files:

- `Neurochip/neurochip/app/main.py`
- `Neurochip/neurochip/app/routers/lava.py`
- `Neurochip/neurochip/app/services/lava_backend.py`
- `Neurochip/pyproject.toml`
- `Neurochip/neurochip/tests/test_main.py`
- `Neurochip/neurochip/tests/test_lava.py`

Implementation steps:

1. Remove import-time NumPy requirements from Lava fallback paths, or make `numpy` an explicit non-optional dependency if fallback logic truly requires it.
2. Keep `lava-nc` optional: missing Lava must produce structured unavailable status, not import failure.
3. Add a focused startup test that imports `neurochip.app.main` with Lava, PYNQ, Akida, Speck, and optional SDKs absent.
4. If router-level imports remain risky, move optional backend imports inside endpoint handlers or introduce router mount guards that record degraded capability status.

Verification:

```bash
rtk poetry run python -c "import neurochip.app.main"
rtk poetry run pytest neurochip/tests/test_main.py neurochip/tests/test_lava.py -q
rtk poetry run ruff check neurochip/app/main.py neurochip/app/routers/lava.py neurochip/app/services/lava_backend.py
```

Exit criteria:

- Base app import succeeds in a clean Poetry environment.
- Missing optional runtimes appear as degraded/unavailable capabilities, not startup crashes.

### Phase 2: Make the NeuroChip verification harness green

Priority: P0

Goal: The documented NeuroChip checks must be runnable and trustworthy.

Files:

- `Neurochip/pyproject.toml`
- `Neurochip/AGENTS.md`
- `Neurochip/neurochip/tests/**`
- `Neurochip/neurochip/app/routers/lava.py`
- `Neurochip/neurochip/app/services/lava_backend.py`

Implementation steps:

1. Fix the test invocation/path mismatch so the documented command works from `Neurochip/`.
2. If the intended command requires `PYTHONPATH=.`, update `AGENTS.md` and local docs consistently.
3. Resolve the current `mypy` errors in Lava router/backend and tests, or narrow strictness only with a documented rationale.
4. Keep `ruff` green.

Verification:

```bash
rtk poetry run pytest neurochip/tests -q
rtk poetry run ruff check .
rtk poetry run mypy .
```

Exit criteria:

- Pytest collection succeeds.
- Full NeuroChip test suite, ruff, and mypy are green.

### Phase 3: Make PYNQ export fail closed before returning artifacts

Priority: P0

Goal: NeuroChip must never return a PYNQ ZIP that its own contract validator rejects.

Files:

- `Neurochip/neurochip/app/routers/export.py`
- `Neurochip/neurochip/app/services/pynq_generator.py`
- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`
- `Neurochip/neurochip/tests/test_artifact_contracts.py`
- `Neurochip/neurochip/tests/test_pynq_compile.py`
- `Neurochip/neurochip/tests/test_generators.py`

Implementation steps:

1. Add a helper that computes actual topology counts from `NetworkInput.populations` and `connections[].weight_count`.
2. Reject payloads when declared `num_synapses` / `num_neurons` disagree with generated topology, unless the contract explicitly allows inferred counts and normalizes them.
3. Validate generated `overlay_config`, `register_map`, and final ZIP with `PynqOverlayConfigArtifactContract` / `validate_pynq_compile_artifact()` before returning a response.
4. Convert validation errors to structured 422 responses in `/api/neurochip/export/pynq` and websocket compile paths.
5. Add regression coverage for a payload with `num_synapses=1` but `weight_count=16384`.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_artifact_contracts.py neurochip/tests/test_pynq_compile.py neurochip/tests/test_generators.py -q
```

Exit criteria:

- Oversized generated topologies fail before artifact return.
- Every returned PYNQ export artifact passes `validate_pynq_compile_artifact()`.

### Phase 4: Add target-specific profile limits to analysis

Priority: P1

Goal: Compatibility analysis must agree with export/deploy contracts, especially PYNQ's 15,360-synapse overlay limit.

Files:

- `Neurochip/neurochip/contracts/hardware_contracts.py`
- `Neurochip/neurochip/targets/pynq_z2.json`
- `Neurochip/neurochip/targets/*.json`
- `Neurochip/neurochip/app/services/constraint_analyzer.py`
- `Neurochip/neurochip/app/routers/targets.py`
- `Neurochip/neurochip/tests/test_constraint_analyzer.py`
- `Neurochip/neurochip/tests/test_targets_router.py`
- Cross-module follow-up: CNL Studio/launcher target support models if they consume profile fields.

Implementation steps:

1. Extend `HardwareProfile` or introduce target-specific capability submodels for optional fields: `synapse_capacity`, `max_populations`, `overlay_id`, `overlay_version`, `support_level`, and `supported_topologies`.
2. Stop silently dropping important target metadata. Either forbid unknown fields or preserve them in a typed `capabilities`/`metadata` model.
3. Update `constraint_analyzer.analyze()` to fail or warn on synapse capacity and population count.
4. Make target listing return malformed-profile diagnostics instead of silently omitting broken target manifests.
5. Add PYNQ tests at 15,360 and 15,361 synapses.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_constraint_analyzer.py neurochip/tests/test_targets_router.py -q
```

Exit criteria:

- PYNQ analysis, PYNQ export, NeuroCNL handoff, and UI target metadata agree on the same hard limits.

### Phase 5: Make deploy semantics explicit and fail-closed where needed

Priority: P1

Goal: Deploy responses must distinguish scaffold, simulator, SDK simulator, and real hardware.

Files:

- `Neurochip/neurochip/app/routers/pynq.py`
- `Neurochip/neurochip/app/services/pynq_backend.py`
- `Neurochip/neurochip/app/schemas/runtime.py`
- `nmtk_ui_core/lib/models/pynq_deployment_model.dart`
- CNL Studio deployment provider/surface that calls NeuroChip PYNQ deploy.

Implementation steps:

1. Extend PYNQ deploy response schema with `runtime_mode`, `preflight_status`, `hardware_required`, and `support_level`.
2. Add `require_hardware` to deploy/verify requests used by CNL Studio or launcher-visible flows.
3. If `require_hardware=true`, return a structured failure when the backend would fall back to simulator.
4. Keep simulator deploy possible for tests and local development, but label it explicitly.
5. Update Dart-side models/providers to render simulator/degraded/real-board states distinctly.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_pynq_backend.py neurochip/tests/test_pynq_sitl_verify.py -q
rtk flutter test
```

Run the Flutter command in the owning CNL Studio/frontend package, not `Neurochip/frontend`.

Exit criteria:

- CNL Studio cannot display simulator configuration as real PYNQ hardware deployment.

### Phase 6: Repair PYNQ error taxonomy

Priority: P1

Goal: Operators should be able to distinguish missing hardware, stale/failed device probe, invalid overlay contract, MMIO overflow, DMA failures, and internal errors.

Files:

- `Neurochip/neurochip/app/routers/pynq.py`
- `Neurochip/neurochip/app/services/pynq_backend.py`
- `Neurochip/neurochip/app/services/pynq_worker.py`
- `Neurochip/neurochip/app/services/pynq_errors.py`
- `nmtk_ui_core/lib/models/pynq_deployment_model.dart`
- CNL Studio/launcher PYNQ error rendering.

Implementation steps:

1. Map `PYNQ_DEVICE_NOT_FOUND`, `PYNQ_DEVICE_PROBE_FAILED`, and `PYNQ_DEVICE_PROBE_TIMEOUT` to 503-class readiness failures.
2. Map overlay id/version/register-map mismatches to 422.
3. Map `MMIO_WEIGHT_OVERFLOW` to 413 or 422 with a direct synapse-limit hint.
4. Preserve worker `error_code` verbatim at the HTTP boundary.
5. Add remediation hints for stale zocl, missing XRT/BOARD env, missing overlay assets, and wrong worker runtime.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_pynq_backend.py neurochip/tests/test_pynq_agent_app.py -q
```

Exit criteria:

- PYNQ errors are actionable without reading board logs for common readiness failures.

### Phase 7: Reconcile documentation with CNL Studio frontend ownership

Priority: P1

Goal: NeuroChip docs must describe the actual ownership boundary.

Files:

- `Neurochip/AGENTS.md`
- `Neurochip/README.md`
- `Neurochip/neurochip_spec.md`
- `Neurochip/docs/neurochip/*.md`
- Relevant ADR/spec references in root docs if they mention standalone NeuroChip frontend ownership.

Implementation steps:

1. Replace standalone `Neurochip/frontend` instructions with CNL Studio frontend references.
2. Replace `cd frontend && flutter test` with the owning CNL Studio/frontend verification command.
3. Reframe NeuroChip as backend/hardware layer: artifact generation, target contracts, compile/deploy APIs, provisioning, diagnostics, and hardware readiness.
4. Mark old standalone frontend diagrams as historical or remove them.
5. Ensure docs distinguish product UI flow from backend capability level.

Verification:

```bash
rtk rg -n "Neurochip/frontend|cd frontend && flutter test|standalone Flutter frontend|frontend/pubspec.yaml" Neurochip docs
```

Exit criteria:

- No active docs imply that a standalone NeuroChip Flutter app is required for current product UX.

### Phase 8: Harden mutating hardware and upload surfaces

Priority: P2

Goal: Hardware-control endpoints should be safe by default outside local development.

Files:

- `Neurochip/neurochip/app/auth.py`
- `Neurochip/neurochip/app/main.py`
- `Neurochip/neurochip/app/routers/akida.py`
- `Neurochip/neurochip/app/services/flash_service.py`
- `Neurochip/neurochip/app/services/pynq_compiler.py`
- `Neurochip/neurochip/app/services/deployment_store.py`
- `Neurochip/neurochip/tests/test_auth.py`
- `Neurochip/neurochip/tests/test_flash_service.py`
- `Neurochip/neurochip/tests/test_pynq_compile.py`

Implementation steps:

1. Require explicit configuration for production auth/CORS; reject default API key when auth is enabled.
2. Restrict Akida `remote_server` mode with an allowlist and block loopback/private/link-local/metadata targets unless explicitly allowed.
3. Add upload size, ZIP member count, path traversal, duplicate member, and decompressed-size validation for flash and PYNQ compile uploads.
4. Replace unbounded flash job threads with a bounded queue or concurrency guard.
5. Add flash job TTL cleanup.
6. Move deployment SQLite storage to a configurable app data path via `NEUROCHIP_DEPLOYMENT_DB_PATH`.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_auth.py neurochip/tests/test_flash_service.py neurochip/tests/test_pynq_compile.py neurochip/tests/test_deployment_store.py -q
```

Exit criteria:

- Mutating hardware endpoints are guarded for non-local deployment.
- Uploaded artifacts cannot exhaust disk/memory or write outside intended extraction roots.

### Phase 9: Make heuristic features honest support-level outputs

Priority: P2

Goal: Quantization, fault, power, latency, partition, and broad target exports must not look more authoritative than they are.

Files:

- `Neurochip/neurochip/app/services/quantizer.py`
- `Neurochip/neurochip/app/services/fault_runner.py`
- `Neurochip/neurochip/app/services/power_estimator.py`
- `Neurochip/neurochip/app/services/partitioner.py`
- `Neurochip/neurochip/app/routers/analysis.py`
- `Neurochip/neurochip/app/routers/quantization.py`
- `Neurochip/neurochip/app/routers/faults.py`
- `Neurochip/neurochip/app/routers/estimation.py`
- `Neurochip/neurochip/app/services/loihi_generator.py`

Implementation steps:

1. Add response fields such as `support_level`, `method`, `is_estimate`, and `readiness_gate_eligible`.
2. Wire `/partition` to `suggest_partitions()` or return 501 until a real response model is implemented.
3. Reject unknown quantization target IDs instead of falling back to Teensy.
4. Label synthetic quantization/fault/power outputs as heuristic estimates.
5. For Loihi/Lava/BrainScaleS exports, return scaffold/support-level metadata or 501 for unsupported production paths.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_quantization_router.py neurochip/tests/test_fault_runner.py neurochip/tests/test_power_estimator.py neurochip/tests/test_partitioner.py neurochip/tests/test_export_router.py -q
```

Exit criteria:

- No heuristic result participates in deploy-readiness decisions.
- Unknown target IDs fail closed.

### Phase 10: Define artifact checksum semantics

Priority: P2

Goal: Artifact integrity fields must mean something precise and testable.

Files:

- `Neurochip/neurochip/contracts/deployment_contracts.py`
- `Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py`
- `Neurochip/neurochip/app/services/pynq_generator.py`
- `Neurochip/neurochip/app/services/teensy_generator.py`
- `Neurochip/neurochip/tests/test_artifact_contracts.py`
- `Neurochip/neurochip/tests/test_teensy_generator.py`

Implementation steps:

1. Define whether checksums cover payload files only, manifest-excluding bundle contents, or a canonical manifest-including digest.
2. Encode the chosen semantics in contract docs and validators.
3. Recompute and compare checksums in PYNQ artifact validation.
4. Add tamper tests for `weights.bin`, `overlay_config.json`, `register_map.json`, and `manifest.json`.

Verification:

```bash
rtk poetry run pytest neurochip/tests/test_artifact_contracts.py neurochip/tests/test_teensy_generator.py -q
```

Exit criteria:

- Artifact checksum validation catches payload tampering and is documented clearly.

### Overall Verification Gate

Run after phases that touch shared deployment contracts or CNL Studio-visible behavior:

```bash
cd Neurochip
rtk poetry run pytest neurochip/tests -q
rtk poetry run ruff check .
rtk poetry run mypy .

cd ..
rtk python3 scripts/launcher_control_service.py --doctor --json
rtk python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py -q
```

Add owning CNL Studio/frontend Flutter tests for phases that touch deployed status models or UI rendering.

## Final Assessment

NeuroChip has a credible contract-driven skeleton, and the PYNQ overlay repair work is the strongest part of the implementation. But as of this review, the module is not production-ready and not even fully self-verifying in the local environment. The core engineering direction is sound; the current implementation is uneven and too willing to present incomplete or simulated paths as if they were deployable hardware workflows.
