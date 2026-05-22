# Requirements Document

## Introduction

The **Neurotraining Extensions** build on the existing NMTK training pipeline to promote it from a prototype to a production-grade system. Three orthogonal extensions are in scope:

1. **Realistic Dataset Ingestion** — replace the hardcoded synthetic N-MNIST fixture in the `SnnTorchAdapter` with a file-system path loader that accepts raw DVS event files or local folder datasets, selectable from the UI.
2. **New Framework Adapters** — add at least one additional SNN learning engine (Norse, SpikingJelly, NengoDL, or BrainScaleS-2) by subclassing `BaseTrainingAdapter` and registering it in `factory.py`.
3. **Model Zoo Weight Handoff / Export** — after a successful training run, let the user export the `learned_weights` back into a `.nir` graph and download the result, enabling deployment to PYNQ/Teensy targets.

All three extensions must integrate cleanly with the existing adapter pattern (`training_registry.py`), the REST job pipeline (`routers/training.py` + `training_service.py`), and the Flutter training inspector panel.

---

## Glossary

- **Adapter**: A concrete subclass of `BaseTrainingAdapter` registered with the `TrainingAdapterRegistry`.
- **DVS File**: A raw Dynamic Vision Sensor event-stream file (e.g., `.aedat`, `.aedat4`, or directory of NumPy `.npy` frames) produced by cameras such as the Davis 346.
- **EventDatasetFixture**: The frozen dataclass defined in `dataset_fixtures.py` that carries spike-frame tensors, labels, and metadata consumed by `SnnTorchAdapter._run_real`.
- **Factory**: `neurocnl/neurocnl/training/factory.py` — the singleton builder that instantiates and registers all adapters.
- **Job Store**: The async thread-pool queue (`backend/app/services/job_store.py`) that executes adapter `run()` calls and tracks status by `job_id`.
- **NIR Graph**: A `nir.NIRGraph` object (from the `nir` Python package) representing a neuromorphic network's topology and weights.
- **NirExporter**: `neurocnl/neurocnl/export/nir_exporter.py` — the existing module that materializes `NetworkIR` or `nengo.Network` to `.nir` files.
- **TrainingInspectorPanel**: The Flutter widget (`training_inspector_panel.dart`) that presents backend selection, configuration, and result summary to the user.
- **TrainingResult**: The frozen dataclass in `training_registry.py` that carries `learned_weights`, `loss_curve`, `status`, and `metadata` from an adapter run.
- **WeightInjector**: The new domain component (to be created) responsible for mapping `TrainingResult.learned_weights` back into a `NIR Graph`'s `nir.Linear` weight matrices.
- **Dataset_Loader**: The new domain component responsible for resolving a dataset path string to an `EventDatasetFixture` usable by `SnnTorchAdapter`.

---

## Requirements

### Requirement 1: File-System Dataset Path Resolution

**User Story:** As an ML engineer, I want to point the snnTorch adapter at a local DVS dataset folder or file instead of the built-in synthetic fixture, so that I can train on real event-stream data without modifying source code.

#### Acceptance Criteria

1. WHEN the `TrainingRunRequest` payload contains a `dataset_path` key with a non-empty string value, THE `Dataset_Loader` SHALL resolve the path to an `EventDatasetFixture` with `synthetic = False`.
2. WHEN the `dataset_path` payload key is absent or empty, THE `Dataset_Loader` SHALL fall back to the existing synthetic N-MNIST fixture and set `synthetic = True`.
3. WHEN a `dataset_path` points to a directory, THE `Dataset_Loader` SHALL scan the directory for `.npy` frame files, validate that each file is a NumPy array with at least one element and no non-finite values (NaN or Inf), and raise a `ValueError` if no valid samples are found before assembling the `EventDatasetFixture` sample tensor.
4. WHEN a `dataset_path` points to a single `.aedat4` file, THE `Dataset_Loader` SHALL parse the file's event stream into the `EventDatasetFixture` sample tensor; IF the file parses successfully but yields zero events, THEN THE `Dataset_Loader` SHALL raise a `ValueError` stating that no events were decoded.
5. IF the resolved path does not exist on the file system, THEN THE `Dataset_Loader` SHALL raise a `ValueError` with a message that includes the invalid path and SHALL NOT return any fixture.
6. IF the resolved path exists but contains no recognizable event data files (no `.npy` files for a directory; unsupported extension for a single file), THEN THE `Dataset_Loader` SHALL raise a `ValueError` that lists the expected file formats (`.npy` directories, `.aedat4` files).
7. IF the `Dataset_Loader` loads a fixture that contains zero samples or zero timesteps, THEN THE `Dataset_Loader` SHALL raise a `ValueError` that identifies which dimension (samples or timesteps) is empty.
8. WHEN `SnnTorchAdapter` returns a `TrainingResult`, THE `SnnTorchAdapter` SHALL populate `metadata["dataset_path"]` with the resolved path (or an empty string for the synthetic fixture) and `metadata["synthetic"]` with `True` or `False` so callers can distinguish real from synthetic runs.

---

### Requirement 2: Dataset Path UI Controls

**User Story:** As a user in NeuroStudio, I want to optionally enter a local dataset path in the Training Inspector Panel before starting a training run, so that I can choose between synthetic and real event data without editing configuration files.

#### Acceptance Criteria

1. WHEN the selected training capability is `snntorch`, THE `TrainingInspectorPanel` SHALL display a dataset source toggle with options `Synthetic (N-MNIST)` and `Local Path`.
2. WHEN the user selects `Local Path`, THE `TrainingInspectorPanel` SHALL display a text field accepting a file-system path string of at most 4096 characters.
3. WHEN the user selects `Synthetic (N-MNIST)`, THE `TrainingInspectorPanel` SHALL hide the path text field and omit `dataset_path` from the submitted payload.
4. WHEN the `dataset_path` field is visible and the user submits with an empty or whitespace-only path, THE `TrainingInspectorPanel` SHALL display the inline message "Dataset path is required" and SHALL NOT submit the training request; WHILE the `Local Path` toggle is not selected, THE `TrainingInspectorPanel` SHALL not enforce path validation.
5. WHEN a training run completes and `result.metadata['synthetic']` is `false`, THE `TrainingInspectorPanel` SHALL display a "Real dataset" badge alongside the result summary; WHEN `result.metadata['synthetic']` is `true` or absent, THE `TrainingInspectorPanel` SHALL display a "Synthetic dataset" badge.

---

### Requirement 3: New SNN Framework Adapter — Norse

**User Story:** As a researcher, I want to train SNN models using the Norse framework's functional spike operations, so that I can compare gradient-based learning approaches across frameworks without changing the UI or REST contract.

#### Acceptance Criteria

1. THE `NorseAdapter` SHALL subclass `BaseTrainingAdapter` and declare `capability.backend_name = "norse"` and `capability.adapter_name = "norse"`.
2. THE `NorseAdapter` SHALL declare `supported_training_modes = ("functional_gradient",)` and `default_training_mode = "functional_gradient"`.
3. WHEN `norse` is not installed, THE `NorseAdapter.is_available()` SHALL return `TrainingAvailability(available=False)` with `UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING` and `dependency_name = "norse"`.
4. WHEN `norse` is installed, THE `NorseAdapter.run()` SHALL execute a forward pass of a LIF network using `norse.torch.LIFState` for each requested epoch, return a `TrainingResult` with `status = "completed"`, `adapter_name = "norse"`, `n_epochs` matching the request value, and non-null `learned_weights`.
5. IF an unhandled exception occurs during Norse training, THEN THE `NorseAdapter.run()` SHALL return a `TrainingResult` with `status = "failed"` and `error` populated with `str(exception)`.
6. THE `build_training_registry()` factory SHALL always instantiate and register `NorseAdapter` regardless of whether `norse` is installed.
7. WHEN `norse` is not installed, THE `GET /api/training/capabilities` response SHALL include an entry for `"norse"` with `available: false` and a non-empty `unavailable_reason`.
8. THE `NorseAdapter` SHALL accept `n_epochs` (default 3, range 1–1000), `learning_rate` (default 1e-3, range 1e-6–1.0), `hidden_neurons` (default 128, range 1–4096), and `dataset` payload keys; IF a value falls outside its valid range, THEN THE `NorseAdapter.run()` SHALL return a `TrainingResult` with `status = "failed"` and `error` describing the invalid parameter.

---

### Requirement 4: New SNN Framework Adapter — SpikingJelly

**User Story:** As a researcher, I want to train SNN models using SpikingJelly's multi-step simulation, so that I have access to a PyTorch-native SNN framework with built-in neuron models.

#### Acceptance Criteria

1. THE `SpikingJellyAdapter` SHALL subclass `BaseTrainingAdapter` and declare `capability.backend_name = "spikingjelly"`.
2. THE `SpikingJellyAdapter` SHALL declare `supported_training_modes = ("multi_step",)` and `default_training_mode = "multi_step"`.
3. WHEN `spikingjelly` is not installed, THE `SpikingJellyAdapter.is_available()` SHALL return `TrainingAvailability(available=False)` with `UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING` and `dependency_name = "spikingjelly"`.
4. WHEN `spikingjelly` is installed, THE `SpikingJellyAdapter.run()` SHALL execute a multi-step simulation of at least 2 timesteps using `spikingjelly.activation_based` neurons and return a `TrainingResult` with `status = "completed"`, `adapter_name = "spikingjelly"`, `n_epochs` matching the requested value, and non-null `learned_weights`.
5. IF an unhandled exception occurs during SpikingJelly training, THEN THE `SpikingJellyAdapter.run()` SHALL return a `TrainingResult` with `status = "failed"` and `error` populated with `str(exception)`.
6. THE `build_training_registry()` factory SHALL always instantiate and register `SpikingJellyAdapter` regardless of whether the `spikingjelly` package is installed, so that `GET /api/training/capabilities` always lists `"spikingjelly"` (with `available: false` when not installed).
7. THE `SpikingJellyAdapter` SHALL accept `n_epochs` (default 3, range 1–1000), `learning_rate` (default 1e-3, range 1e-6–1.0), `hidden_neurons` (default 128, range 1–4096), and `dataset` payload keys; IF a value falls outside its valid range, THEN THE `SpikingJellyAdapter.run()` SHALL return a `TrainingResult` with `status = "failed"` and `error` describing the invalid parameter.

---

### Requirement 5: Adapter Availability and UI Lock-State

**User Story:** As a user, I want to see which framework adapters are available on my machine and understand exactly what to install to unlock unavailable ones, so that I am never left wondering why a backend is greyed out.

#### Acceptance Criteria

1. WHEN a registered adapter returns `available = False`, THE `TrainingInspectorPanel` SHALL display a lock icon and the `unavailableReason` string (truncated to 120 characters if longer) next to that adapter's name in the dropdown; IF `unavailableReason` is null or empty, THE `TrainingInspectorPanel` SHALL display "Unavailable" as a fallback.
2. WHEN a registered adapter returns `available = False` due to `OPTIONAL_DEPENDENCY_MISSING`, THE `TrainingInspectorPanel` SHALL display the exact `pip install <dependency_name>` command in the lock tooltip or subtitle.
3. IF a registered adapter returns `available = False` for a reason other than `OPTIONAL_DEPENDENCY_MISSING`, THEN THE `TrainingInspectorPanel` SHALL display the `unavailableReason` message and any `resolution_guidance` string from the `TrainingAvailability` response (or omit that section if `resolution_guidance` is absent).
4. THE `TrainingAdapterRegistry.list_capabilities()` SHALL include all registered adapters regardless of availability, so the UI can render both locked and unlocked states.
5. WHEN an adapter entry in the dropdown has `available = False`, THE `TrainingInspectorPanel` SHALL render that option as non-selectable (disabled), preventing the user from submitting a run against an unavailable backend.

---

### Requirement 6: Weight Injection into NIR Graph

**User Story:** As a hardware deployment engineer, I want to take the weights produced by a training run and write them back into the network's `.nir` graph, so that the trained model can be exported and deployed to PYNQ or Teensy targets.

#### Acceptance Criteria

1. THE `WeightInjector` SHALL accept a `nir.NIRGraph` and a `learned_weights: dict[str, array-like]` mapping node names to weight matrices and return a new `nir.NIRGraph` with updated `nir.Linear` weight matrices.
2. WHEN the `learned_weights` dict contains a key that matches the name of a `nir.Linear` node in the graph, THE `WeightInjector` SHALL replace that node's `weight` attribute with the provided matrix, preserving all other node attributes unchanged.
3. WHEN a `learned_weights` key does not match any node in the graph, THE `WeightInjector` SHALL log a warning at WARNING level and leave the graph unchanged for that key.
4. WHEN a `learned_weights` key matches a node in the graph that is not of type `nir.Linear`, THE `WeightInjector` SHALL log a warning and leave that node unchanged.
5. WHEN the shape of a provided weight matrix does not match the existing `nir.Linear` node's weight shape, THE `WeightInjector` SHALL raise a `ValueError` that identifies the node name, the expected shape, and the provided shape.
6. THE `WeightInjector` SHALL not mutate the input `nir.NIRGraph`; it SHALL return a new graph object with updated nodes, leaving the original graph unmodified.
7. IF `learned_weights` is `None` or empty, THEN THE `WeightInjector` SHALL return a copy of the input `nir.NIRGraph` with no modifications.
8. FOR ALL valid `(nir_graph, learned_weights)` inputs where shapes match, injecting then re-extracting the weights SHALL produce matrices numerically equal (within floating-point precision) to the injected values (round-trip property).

---

### Requirement 7: Weight Export REST Endpoint

**User Story:** As a backend API consumer, I want a dedicated endpoint that takes a `job_id` for a completed training job and a NIR spec, combines the learned weights with the graph, and returns a downloadable `.nir` file, so that downstream tools can consume the trained model without calling multiple endpoints.

#### Acceptance Criteria

1. THE `Training_Router` SHALL expose `POST /api/training/jobs/{job_id}/export-nir` that accepts a JSON body containing `spec` (CNL text string) and returns a `.nir` binary file response with `Content-Type: application/octet-stream` on success; all error responses SHALL use `Content-Type: application/json` with a structured error body containing `detail` and `code` fields.
2. IF the `job_id` does not exist in the job store, THEN THE `Training_Router` SHALL return HTTP 404 with a structured error body.
3. IF the job exists but its status is not `"completed"` (e.g., queued, running, or failed), THEN THE `Training_Router` SHALL return HTTP 409 with a structured error body indicating the current job status.
4. IF the job is `"completed"` but its `TrainingResult` contains no `learned_weights` or `learned_weights` is empty, THEN THE `Training_Router` SHALL return HTTP 422 with an error body describing the missing weights.
5. IF the `spec` field is absent, empty, or cannot be parsed or lowered to a `NetworkIR`, THEN THE `Training_Router` SHALL return HTTP 422 with the parser error details.
6. WHEN weight injection succeeds and the NIR graph is serialized, THE `Training_Router` SHALL return the binary `.nir` payload with a `Content-Disposition: attachment; filename="trained_network.nir"` header.
7. IF weight injection raises a `ValueError` (e.g., shape mismatch), THEN THE `Training_Router` SHALL return HTTP 422 with the injector error details.
8. IF NIR graph serialization fails for any other reason, THEN THE `Training_Router` SHALL return HTTP 500 with a structured error body.
9. THE `POST /api/training/jobs/{job_id}/export-nir` endpoint SHALL be rate-limited to 10 requests per minute per client; WHEN the rate limit is exceeded, THE endpoint SHALL return HTTP 429 with a `Content-Type: application/json` error body containing `detail` and `retry_after` fields.

---

### Requirement 8: Export Button in Training Inspector Panel

**User Story:** As a NeuroStudio user, I want to click an "Export to NIR" button after a successful training run, so that I can download the trained network file directly from the UI without using the API manually.

#### Acceptance Criteria

1. WHEN `TrainingProviderStatus` is `success` and `result.learnedWeights` is non-null, THE `TrainingInspectorPanel` SHALL display an `Export to NIR` button in the success view.
2. WHEN the user taps `Export to NIR`, THE `TrainingInspectorPanel` SHALL capture the CNL editor content at the moment of the tap, call `POST /api/training/jobs/{job_id}/export-nir` with that content, and present a loading indicator; IF the CNL editor content is empty (0 characters) at the time of the tap, THE `TrainingInspectorPanel` SHALL display the inline message "CNL spec is required for export" and SHALL NOT submit the export request.
3. WHEN the export request returns a binary payload, THE `TrainingInspectorPanel` SHALL dismiss the loading indicator and trigger a file save dialog (or file download) with filename `trained_network.nir`.
4. IF the export request fails, THEN THE `TrainingInspectorPanel` SHALL dismiss the loading indicator and display an inline error message showing the HTTP status code and the `detail` field from the error body, without resetting the training result state.
5. IF `result.learnedWeights` is null, THEN THE `TrainingInspectorPanel` SHALL hide the `Export to NIR` button.
6. WHEN the user taps `Export to NIR` and the CNL editor is not empty, THE `TrainingInspectorPanel` SHALL disable the `Export to NIR` button and show the loading indicator until the export request completes (success or failure), preventing duplicate submissions.

---

### Requirement 9: Adapter Contract Stability

**User Story:** As a developer adding a new adapter, I want a guaranteed interface contract so that my new adapter will work with the existing registry, REST layer, and UI without changes to any other component.

#### Acceptance Criteria

1. THE `BaseTrainingAdapter` interface SHALL define `capability: AdapterCapability`, `is_available() -> TrainingAvailability`, and `run(request: TrainingRequest) -> TrainingResult` as the complete contract for all adapters.
2. THE `TrainingAdapterRegistry` SHALL raise `AdapterSelectionError` if two adapters with the same `backend_name` (compared case-insensitively after stripping leading/trailing whitespace) are registered.
3. WHEN a new adapter is added to `build_training_registry()` and its dependency is not installed, THE `GET /api/training/capabilities` response SHALL include the adapter with `available: false` and a non-empty `unavailable_reason`.
4. IF the requested backend name matches a registered adapter whose `is_available()` returns `available = False`, THEN `TrainingAdapterRegistry.dispatch()` SHALL raise `AdapterSelectionError` with the adapter's `unavailableReason` and SHALL NOT propagate the raw `TrainingAvailability` object; IF the requested backend name does not match any registered adapter, THEN `TrainingAdapterRegistry.dispatch()` SHALL raise `AdapterSelectionError` indicating the backend name is unknown.
5. FOR ALL adapters registered in `build_training_registry()`, calling `is_available()` SHALL complete within 500 ms when measured in a process where the optional dependency import has not previously been cached; repeated calls within the same process MAY complete faster due to import caching.
