# Implementation Plan: Neurotraining Extensions

## Overview

Implements three orthogonal extensions to the NMTK training pipeline: file-system
dataset ingestion via `DatasetLoader`, two new SNN framework adapters (`NorseAdapter`
and `SpikingJellyAdapter`), and trained-weight export to NIR via `WeightInjector` and
a new REST endpoint with Flutter UI controls. All changes preserve the existing
`BaseTrainingAdapter` contract and REST job pipeline.

---

## Tasks

- [ ] 1. Implement `DatasetLoader`
  - [ ] 1.1 Create `neurocnl/neurocnl/training/dataset_loader.py` with `DatasetLoader` class
    - Implement `load()`: return synthetic N-MNIST fallback when `dataset_path` is `None`/empty; otherwise delegate to `_load_npy_directory` or `_load_aedat4` based on path type
    - Implement `_load_npy_directory()`: glob `*.npy`, validate each with `_validate_array`, stack surviving arrays, assign round-robin labels, return `EventDatasetFixture(synthetic=False)`
    - Implement `_load_aedat4()`: lazy-import `dv`, iterate events, bin into frames, return `EventDatasetFixture(synthetic=False)`; raise `ValueError` if zero events decoded
    - Implement `_validate_array()`: raise `ValueError` if `arr.size == 0` or `not np.all(np.isfinite(arr))`
    - Implement all `ValueError` messages per the Error Handling table (path not found, no `.npy` files, all invalid, zero samples, zero timesteps)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [ ]* 1.2 Write property tests for `DatasetLoader` (Hypothesis, min 100 examples each)
    - **Property P1: Real path produces non-synthetic fixture** — generate a temp dir with valid `.npy` arrays; assert `fixture.synthetic == False`, `len(fixture.samples) > 0`, `len(fixture.samples[0]) > 0`
    - **Property P2: `.npy` directory produces all-finite samples** — generate finite-only `.npy` files; assert `np.all(np.isfinite(np.array(fixture.samples)))` on the result
    - **Property P3: Non-existent path raises `ValueError` containing the path string** — generate arbitrary non-existent path strings; assert `ValueError` is raised and the path string appears in the message
    - Place in `neurocnl/tests/unit/training/test_dataset_loader_properties.py`
    - Tag each test with `# Feature: neurotraining-extensions, Property N: <text>`
    - _Requirements: 1.1, 1.3, 1.5_

  - [ ]* 1.3 Write unit tests for `DatasetLoader` example cases
    - `load(dataset_path=None)` → synthetic fixture returned
    - `load(dataset_path="")` → synthetic fixture returned
    - `.aedat4` mock returning zero events → `ValueError`
    - Empty directory → `ValueError` listing expected formats
    - Directory with all-NaN arrays → `ValueError`
    - Fixture with zero samples → `ValueError`
    - Place in `neurocnl/tests/unit/training/test_dataset_loader.py`
    - _Requirements: 1.2, 1.4, 1.6, 1.7_

- [ ] 2. Patch `SnnTorchAdapter` to use `DatasetLoader`
  - [ ] 2.1 Replace `_resolve_fixture` in `neurocnl/neurocnl/training/snntorch_adapter.py`
    - Remove the existing `_resolve_fixture` method that only handles `"n-mnist"` by name
    - Import `DatasetLoader` from `neurocnl.training.dataset_loader`
    - Rewrite `_resolve_fixture` to call `DatasetLoader().load(dataset_path=payload.get("dataset_path"), num_classes=..., timesteps=..., input_size=...)`
    - In `_run_real`, add `"dataset_path": payload.get("dataset_path", "") or ""` and `"synthetic": fixture.synthetic` to the `metadata` dict of the returned `TrainingResult`
    - Remove the old `"synthetic_fixture"` metadata key and replace with `"synthetic"` (boolean matching `fixture.synthetic`)
    - _Requirements: 1.1, 1.2, 1.8_

  - [ ]* 2.2 Write property test for `SnnTorchAdapter` metadata fields (Hypothesis)
    - **Property P4: metadata reflects dataset source** — for any payload, assert `result.metadata["dataset_path"] == payload.get("dataset_path", "") or ""` and `result.metadata["synthetic"] == True` when no path supplied, `False` when a valid real path supplied
    - Place in `neurocnl/tests/unit/training/test_snntorch_adapter_properties.py`
    - _Requirements: 1.8_

- [ ] 3. Implement `NorseAdapter`
  - [ ] 3.1 Create `neurocnl/neurocnl/training/norse_adapter.py` with `NorseAdapter` class
    - Subclass `BaseTrainingAdapter`; declare `capability` with `backend_name="norse"`, `supported_training_modes=("functional_gradient",)`, `default_training_mode="functional_gradient"`, `output_format="weights"`
    - Implement `is_available()`: lazy `import_module("norse")` inside a try/except; return `TrainingAvailability(available=False, unavailable_reason=UnavailableReason(code=OPTIONAL_DEPENDENCY_MISSING, ..., dependency_name="norse"))` on `ImportError`
    - Implement `_validate_params()`: check `n_epochs`, `learning_rate`, `hidden_neurons` against `_PARAM_RANGES`; return error string on first violation, `None` if all valid
    - Implement `_run_real()`: build LIF network (`nn.Linear` → `norse.torch.LIFRecurrent` → `nn.Linear`), forward loop over timesteps, accumulate spikes, `nn.MSELoss` on spike counts vs one-hot; set `learned_weights = fc_out.weight.detach().cpu().tolist()`
    - Implement `run()`: call `_validate_params` first — return `TrainingResult(status="failed", error=msg)` immediately if non-None; wrap `_run_real` in `try/except Exception`; return `status="failed"` for unhandled exceptions
    - Use `DatasetLoader` for fixture resolution (same pattern as patched `SnnTorchAdapter`)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.8_

  - [ ]* 3.2 Write property tests for `NorseAdapter` (Hypothesis)
    - **Property P5: Valid params produce completed result** — generate `(n_epochs, learning_rate, hidden_neurons)` within valid ranges; assert `status == "completed"`, `n_epochs` matches, `learned_weights` non-null/non-empty (mock `norse` import when unavailable, skip if not installed)
    - **Property P7 (Norse): Out-of-range params produce failed result** — generate any param value outside its declared range; assert `status == "failed"` and `error` string contains the parameter name and valid range
    - Place in `neurocnl/tests/unit/training/test_norse_adapter_properties.py`
    - _Requirements: 3.4, 3.8_

  - [ ]* 3.3 Write unit tests for `NorseAdapter` example cases
    - `is_available()` with mocked missing `norse` import → `available=False`, `dependency_name="norse"`
    - `run()` with unhandled exception in `_run_real` → `status="failed"`, `error` populated
    - _Requirements: 3.3, 3.5_

- [ ] 4. Implement `SpikingJellyAdapter`
  - [ ] 4.1 Create `neurocnl/neurocnl/training/spikingjelly_adapter.py` with `SpikingJellyAdapter` class
    - Subclass `BaseTrainingAdapter`; declare `capability` with `backend_name="spikingjelly"`, `supported_training_modes=("multi_step",)`, `default_training_mode="multi_step"`, `output_format="weights"`
    - Implement `is_available()`: lazy `import_module("spikingjelly")` inside try/except; return `TrainingAvailability(available=False, ..., dependency_name="spikingjelly")` on `ImportError`
    - Implement `_validate_params()`: same `_PARAM_RANGES` and pattern as `NorseAdapter`
    - Implement `_run_real()`: build multi-step LIF network (`nn.Linear` → `neuron.LIFNode(surrogate_function=surrogate.ATan())` → `nn.Linear`); call `functional.set_step_mode(net, 'm')`; shape input as `[T, batch, features]` with `T ≥ 2`; call `functional.reset_net(net)` each epoch; set `learned_weights = fc_out.weight.detach().cpu().tolist()`
    - Implement `run()`: same validation-first + exception-wrapping pattern as `NorseAdapter`
    - Use `DatasetLoader` for fixture resolution
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7_

  - [ ]* 4.2 Write property tests for `SpikingJellyAdapter` (Hypothesis)
    - **Property P6: Valid params produce completed result** — same generation strategy as P5; assert `status == "completed"`, `n_epochs` matches, `learned_weights` non-null/non-empty
    - **Property P7 (SpikingJelly): Out-of-range params produce failed result** — same strategy as NorseAdapter P7 variant
    - Place in `neurocnl/tests/unit/training/test_spikingjelly_adapter_properties.py`
    - _Requirements: 4.4, 4.7_

  - [ ]* 4.3 Write unit tests for `SpikingJellyAdapter` example cases
    - `is_available()` with mocked missing `spikingjelly` import → `available=False`, `dependency_name="spikingjelly"`
    - `run()` with unhandled exception → `status="failed"`, `error` populated
    - _Requirements: 4.3, 4.5_

- [ ] 5. Update `factory.py` and harden `TrainingAdapterRegistry`
  - [ ] 5.1 Update `neurocnl/neurocnl/training/factory.py` to register new adapters
    - Import `NorseAdapter` from `neurocnl.training.norse_adapter`
    - Import `SpikingJellyAdapter` from `neurocnl.training.spikingjelly_adapter`
    - Add both to the `TrainingAdapterRegistry` list in `build_training_registry()`; order: `[SleepPesAdapter(), SnnTorchAdapter(), NorseAdapter(), SpikingJellyAdapter()]`
    - Both adapters instantiated unconditionally regardless of optional dependency presence
    - _Requirements: 3.6, 4.6, 9.1_

  - [ ] 5.2 Harden `TrainingAdapterRegistry` in `neurocnl/neurocnl/training_registry.py`
    - The duplicate `backend_name` detection in `__init__` already uses `.strip().lower()` — verify the check is case-insensitive and covers all whitespace variants; add a regression test if any gap is found
    - Verify `dispatch()` raises `AdapterSelectionError` (not a raw exception) for both unavailable adapters and unknown backend names — the current code already does this; confirm no edge-case path bypasses it
    - Add `is_available()` 500 ms timeout budget enforcement: wrap each `adapter.is_available()` call in `__init__` or in `get_available_adapters()` with a `concurrent.futures.ThreadPoolExecutor` + `Future.result(timeout=0.5)` guard; on timeout, treat adapter as unavailable with `UnavailableReasonCode.ADAPTER_ERROR`
    - _Requirements: 9.2, 9.4, 9.5_

  - [ ]* 5.3 Write property tests for `TrainingAdapterRegistry` (Hypothesis)
    - **Property P8: All registered adapters appear in capabilities** — generate lists of N mock adapters with unique names; assert `len(list_capabilities()) == N` and result is sorted by `backend_name`
    - **Property P12: Duplicate backend names raise `AdapterSelectionError`** — generate pairs of adapters whose `backend_name` values are equal after `.strip().lower()`; assert `AdapterSelectionError` is raised on construction
    - **Property P13: `dispatch()` raises `AdapterSelectionError` for unavailable/unknown backends** — for unavailable adapters assert `dispatch()` raises; for unregistered names assert `dispatch()` raises
    - Place in `neurocnl/tests/unit/training/test_registry_properties.py`
    - _Requirements: 5.4, 9.2, 9.3, 9.4_

  - [ ]* 5.4 Write unit tests for factory and registry example cases
    - `build_training_registry()` → backend name list includes `["norse", "sleep_pes", "snntorch", "spikingjelly"]`
    - Two adapters with same name after normalization → `AdapterSelectionError`
    - _Requirements: 3.6, 4.6, 9.2_

- [ ] 6. Checkpoint — Ensure all Python domain-layer tests pass
  - Run `python3 -m pytest neurocnl/tests/unit/training/ -x`; resolve any failures before proceeding.

- [ ] 7. Implement `WeightInjector`
  - [ ] 7.1 Create `neurocnl/neurocnl/export/weight_injector.py` with `WeightInjector` class
    - Implement `inject(graph, learned_weights)`: return `_copy_graph(graph)` immediately when `learned_weights` is `None` or empty; otherwise iterate keys, log `WARNING` for unmatched keys and non-`nir.Linear` nodes, call `_replace_linear_weight` for matching `nir.Linear` nodes; return `nir.NIRGraph(nodes=new_nodes, edges=list(graph.edges))`
    - Implement `_copy_graph()`: `copy.deepcopy(graph)`
    - Implement `_replace_linear_weight(node, new_weight, node_name)`: check `node.weight.shape == w.shape`, raise `ValueError` with node name + expected shape + provided shape on mismatch; return `dataclasses.replace(node, weight=w)`
    - The input `graph` must never be mutated; all mutations go through `new_nodes = dict(graph.nodes)` shallow copy
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7, 6.8_

  - [ ]* 7.2 Write property tests for `WeightInjector` (Hypothesis)
    - **Property P9: Round-trip injection preserves immutability and equality** — generate `nir.NIRGraph` with ≥1 `nir.Linear` node; inject matching weights; assert round-trip (`np.allclose`), immutability of original, and non-injected nodes unchanged
    - **Property P10: Unmatched keys leave all nodes unchanged** — generate graph and `learned_weights` with no key matching any node; assert all nodes numerically equal in result vs original
    - **Property P11: Shape mismatch raises `ValueError`** — generate a `nir.Linear` node and a weight with different shape; assert `ValueError` with node name, expected shape, and provided shape in message
    - Place in `neurocnl/tests/unit/export/test_weight_injector_properties.py`
    - _Requirements: 6.1, 6.2, 6.3, 6.5, 6.6, 6.8_

  - [ ]* 7.3 Write unit tests for `WeightInjector` example cases
    - `inject(graph, None)` → deep copy returned, original unchanged
    - `inject(graph, {})` → deep copy returned, original unchanged
    - Non-`nir.Linear` node target → warning logged, node unchanged
    - _Requirements: 6.3, 6.4, 6.7_

- [ ] 8. Add `ExportNirRequest` schema and update `CapabilityResponse`
  - [ ] 8.1 Extend `neurocnl/backend/app/schemas/training.py`
    - Add `ExportNirRequest(BaseModel)` with `spec: str = Field(..., description="CNL text to parse into a NetworkIR")`
    - Add `dependency_name: str | None = None` field to existing `CapabilityResponse`
    - _Requirements: 7.1, 5.2_

  - [ ] 8.2 Update `neurocnl/backend/app/services/training_service.py`
    - In `list_capabilities()`, add `"dependency_name"` key to each result dict: propagate `avail.unavailable_reason.dependency_name` when the `unavailable_reason` is set and its `dependency_name` is non-None, otherwise `None`
    - _Requirements: 5.2, 9.3_

- [ ] 9. Implement the `POST /api/training/jobs/{job_id}/export-nir` REST endpoint
  - [ ] 9.1 Add export-NIR route to `neurocnl/backend/app/routers/training.py`
    - Import `ExportNirRequest` from `backend.app.schemas.training`
    - Import `WeightInjector` from `neurocnl.export.weight_injector`
    - Import `nir`, `io`, and the existing `parse_spec_text`, `lower_to_ir`, `materialize_to_nir` from `neurocnl.export.nir_exporter`
    - Decorate with `@router.post("/training/jobs/{job_id}/export-nir")` and `@limiter.limit("10/minute")`
    - Implement handler logic: fetch job (404 if missing), validate `status == "complete"` (409 if not), check `learned_weights` non-empty (422 `no_learned_weights`), validate `body.spec` non-empty (422 `spec_required`), parse spec (422 `spec_parse_error` on exception), inject weights (422 `weight_shape_mismatch` on `ValueError`), serialize via `nir.write` to `io.BytesIO` (500 `nir_write_error` on exception)
    - Return `Response(content=nir_bytes, media_type="application/octet-stream", headers={"Content-Disposition": 'attachment; filename="trained_network.nir"'})`
    - All error responses: `Content-Type: application/json`, body with `detail` and `code` fields; 429 body additionally includes `retry_after`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9_

  - [ ]* 9.2 Write integration tests for the export-NIR endpoint
    - End-to-end: submit a synthetic snntorch job, wait for completion, call `export-nir` with minimal CNL spec, assert 200 + `application/octet-stream` response
    - Missing `job_id` → 404 with `code: "job_not_found"`
    - Non-completed job → 409 with `code: "job_not_completed"`
    - Empty `spec` → 422 with `code: "spec_required"`
    - Rate-limit: 11 rapid requests → first 10 succeed, 11th returns 429 with `retry_after` field in body
    - Place in `neurocnl/tests/integration/test_export_nir_endpoint.py`
    - _Requirements: 7.1, 7.2, 7.3, 7.5, 7.9_

- [ ] 10. Checkpoint — Ensure all Python tests pass
  - Run `python3 -m pytest neurocnl/tests/ -x`; resolve any failures before proceeding.

- [ ] 11. Update `TrainingCapability` Dart model and `ApiClient`
  - [ ] 11.1 Add `dependencyName` to `TrainingCapability` in `neurocnl/frontend/lib/models/training.dart`
    - Add `final String? dependencyName;` field to `TrainingCapability`
    - Add `dependencyName` to the constructor and `copyWith` (if present)
    - Update `TrainingCapability.fromJson`: `dependencyName: json['dependency_name'] as String?`
    - _Requirements: 5.2_

  - [ ] 11.2 Add `exportTrainingNir` method to `ApiClient` in `neurocnl/frontend/lib/services/api_client.dart`
    - Method signature: `Future<Uint8List> exportTrainingNir(String jobId, String spec) async`
    - POST to `/training/jobs/$jobId/export-nir` with JSON body `{"spec": spec}`
    - Use raw `_http.post` (not `_post`) because response is binary, not JSON
    - On `statusCode == 200`: return `response.bodyBytes` as `Uint8List`
    - On any other status: throw `ApiException(response.statusCode, response.body)`
    - _Requirements: 8.1, 8.2_

- [ ] 12. Update Flutter `TrainingInspectorPanel`
  - [ ] 12.1 Add state fields and dataset source toggle to `neurocnl/frontend/lib/widgets/training_inspector_panel.dart`
    - Add state fields: `bool _useLocalDataset = false`, `final _datasetPathController = TextEditingController()`, `String? _datasetPathError`, `bool _isExporting = false`, `String? _exportError`
    - Dispose `_datasetPathController` in `dispose()`
    - In `_buildIdleContent`, after the capability dropdown, insert: `SegmentedButton<bool>` (shown when `_selectedCapability?.backendName == 'snntorch'`) with segments `Synthetic (N-MNIST)` / `Local Path`; toggle controls `_useLocalDataset`
    - When `_useLocalDataset == true`, show `TextField` bound to `_datasetPathController` with `maxLength: 4096`, hint text, and `errorText: _datasetPathError`
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 12.2 Update `_startTraining` payload construction in `training_inspector_panel.dart`
    - When `_useLocalDataset == true` and path is empty/whitespace: set `_datasetPathError = 'Dataset path is required'` and return early without submitting
    - When `_useLocalDataset == true` and path is valid: add `payload['dataset_path'] = path`
    - When `_useLocalDataset == false`: omit `dataset_path` from payload (do not add empty string)
    - _Requirements: 2.3, 2.4_

  - [ ] 12.3 Add dataset badge and Export NIR button to `_buildSuccessContent` in `training_inspector_panel.dart`
    - After the result summary rows, insert a `Chip` widget: `isSynthetic = result.metadata?['synthetic'] != false`; show "Real dataset" with green background when `!isSynthetic`, "Synthetic dataset" with grey background when `isSynthetic`
    - When `result.learnedWeights.isNotEmpty`, insert: optional `_exportError` `Text` in red; `FilledButton.tonal` labelled "Export to NIR" — disabled when `_isExporting`, shows `CircularProgressIndicator` when `_isExporting`
    - _Requirements: 2.5, 8.1, 8.5_

  - [ ] 12.4 Implement `_exportNir` method and adapter lock enhancements in `training_inspector_panel.dart`
    - Implement `Future<void> _exportNir()`: validate CNL spec non-empty (set `_exportError = 'CNL spec is required for export'` and return); set `_isExporting = true`; call `ref.read(apiClientProvider).exportTrainingNir(jobId, spec)`; on success trigger file save via `FileSaver.instance.saveFile`; on `ApiException` set `_exportError`; always reset `_isExporting` in `finally`
    - In `_buildIdleContent` dropdown, truncate `unavailableReason` to 120 chars before display: `(cap.unavailableReason ?? 'Unavailable').length > 120 ? '${...substring(0, 120)}…' : ...`
    - For adapters with `unavailableReasonCode == OPTIONAL_DEPENDENCY_MISSING`, show `Tooltip(message: 'pip install ${cap.dependencyName}', child: Icon(Icons.info_outline, ...))` next to the lock icon
    - _Requirements: 5.1, 5.2, 8.2, 8.3, 8.4, 8.6_

  - [ ]* 12.5 Write Flutter widget tests for `TrainingInspectorPanel`
    - With snntorch capability selected → dataset source `SegmentedButton` visible
    - Toggle to `Local Path` → path `TextField` visible
    - Toggle to `Synthetic` → path `TextField` hidden
    - Submit with `Local Path` and empty path → inline `"Dataset path is required"`, no API call
    - Success state with `metadata["synthetic"] == false` → "Real dataset" `Chip` present
    - Success state with `learnedWeights` non-empty → "Export to NIR" button present
    - Success state with `learnedWeights` empty → "Export to NIR" button absent
    - Tap "Export to NIR" with empty CNL editor → `"CNL spec is required for export"` error
    - Tap "Export to NIR" with non-empty CNL → button disabled during in-flight (mock API delayed)
    - Export API returns 422 → error message with status code and `detail` field shown
    - Unavailable adapter → lock icon visible, reason truncated to ≤ 120 chars
    - `OPTIONAL_DEPENDENCY_MISSING` adapter → `"pip install <dep>"` tooltip present
    - Place in `neurocnl/frontend/test/widgets/training_inspector_panel_test.dart`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 5.1, 5.2, 8.1, 8.2, 8.4, 8.5, 8.6_

- [ ] 13. Final checkpoint — Ensure all tests pass
  - Run `python3 -m pytest neurocnl/tests/ -x` and `flutter test neurocnl/frontend/test/` from the workspace root; resolve any failures before marking the feature complete.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use Hypothesis with `max_examples=100` CI profile; configure in `neurocnl/tests/conftest.py` or via `@settings` decorators
- Hypothesis generators for property tests: `st.from_regex(r'[a-z_][a-z0-9_]{0,15}')` for node names; `st.integers(1, 16).flatmap(...)` for shapes; `st.floats(allow_nan=False, allow_infinity=False)` for weight values; `st.integers(1, 50)` for `n_epochs` (to keep runs fast)
- `is_available()` 500 ms budget in task 5.2 guards against slow import probes at registry construction or capability list time
- `FileSaver` (`file_saver` pub.dev package) is the assumed platform-agnostic save mechanism for Flutter; if the project already pins a different mechanism, align with that instead
- The `dependency_name` field on the `CapabilityResponse` schema is backward-compatible (nullable); existing clients that do not read the field are unaffected


## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "2.1"] },
    { "id": 2, "tasks": ["2.2", "3.1", "4.1", "7.1"] },
    { "id": 3, "tasks": ["3.2", "3.3", "4.2", "4.3", "5.1", "7.2", "7.3"] },
    { "id": 4, "tasks": ["5.2", "8.1"] },
    { "id": 5, "tasks": ["5.3", "5.4", "8.2"] },
    { "id": 6, "tasks": ["9.1", "11.1"] },
    { "id": 7, "tasks": ["9.2", "11.2"] },
    { "id": 8, "tasks": ["12.1"] },
    { "id": 9, "tasks": ["12.2", "12.3"] },
    { "id": 10, "tasks": ["12.4"] },
    { "id": 11, "tasks": ["12.5"] }
  ]
}
```
