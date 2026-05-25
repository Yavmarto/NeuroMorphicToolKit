# Requirements Document

## Introduction

The NIR + Training Bundle feature introduces a formal project bundle format (`.nmtk`) for NeuroMorphicToolKit. The bundle is a ZIP container that unifies a network's structural representation (`.nir`), its learning rule configuration (`training.json`), and a canonical internal IR (`internal_ir.json`) in a single artefact. The internal `NetworkIR` dataclass is the sole source of truth for editing; `graph.nir` and `training.json` are generated outputs only. The feature spans five implementation phases: fixing the adapter–canvas disconnect (Phase 0), formalising the bundle format (Phase 1), surfacing learning rules on the canvas (Phase 2), extending the IR and deployment modes (Phase 3), and adding simulation-only (BindsNET) and Lava online-learning adapters (Phases 4/4b).

---

## Glossary

- **Bundle**: A `.nmtk` ZIP container that holds `manifest.json`, `graph.nir`, `training.json`, `internal_ir.json`, and optionally `weights.h5`.
- **BundleSerializer**: The Python component responsible for reading and writing `.nmtk` ZIP files.
- **CanvasEdge**: The Flutter canvas data model representing a directed connection between two populations.
- **CanvasNode**: The Flutter canvas data model representing a neuron population.
- **Compiler**: The `compile_to_nir()` pipeline that transforms CNL text into a `nir.NIRGraph`.
- **DeploymentMode**: An enumeration with values `offline_train`, `online_learn`, and `deploy_only`.
- **GraphNir**: The `graph.nir` entry inside a Bundle — a NIR-spec-compliant HDF5 file generated from `NetworkIR`.
- **InternalIR**: The `internal_ir.json` entry inside a Bundle — the JSON serialisation of `NetworkIR` that serves as the sole editable source of truth.
- **LavaOnlineAdapter**: The training adapter that targets Lava → Loihi 2 for on-chip plasticity.
- **LearningRuleIR**: The `LearningRuleIR` dataclass in `neurocnl/ir/types.py` that stores a normalised learning rule scoped to an optional connection.
- **LearningRuleProjection**: A Flutter data class that mirrors `LearningRuleIR` on the canvas edge, carrying `kind`, `rate`, `window`, and `rewardSignal`.
- **Manifest**: The `manifest.json` entry inside a Bundle that records schema version, creation date, target backend, and deployment mode.
- **NetworkIR**: The `NetworkIR` dataclass in `neurocnl/ir/types.py` — the top-level normalised network representation and the single source of truth for a project.
- **ProjectBundle**: The Python dataclass that wraps a `NetworkIR`, `Manifest`, and training configuration for serialisation to and from a `.nmtk` file.
- **RuleMode**: A field in `training.json` with values `strict` or `advisory` that controls whether a backend must honour or may ignore a learning rule.
- **SnnTorchAdapter**: The existing `SnnTorchAdapter` class in `neurocnl/training/snntorch_adapter.py` that runs surrogate-gradient training.
- **TrainingAdapterRegistry**: The registry class in `neurocnl/training_registry.py` that selects and dispatches to training adapters.
- **TrainingConfig**: The structured representation of `training.json` content: target backend, training mode, deployment mode, hyperparameters, and learning rules.
- **TrainingInspectorPanel**: The Flutter widget in `training_inspector_panel.dart` that provides the training UI.
- **TrainingRequest**: The `TrainingRequest` dataclass in `neurocnl/training_registry.py` passed to adapters at dispatch time.

---

## Requirements

---

### Requirement 1: Adapter–Canvas Topology Connection (Phase 0)

**User Story:** As a researcher, I want the training backend to use the network topology I have drawn on the canvas, so that training results reflect my actual network design rather than a hardcoded demo model.

#### Acceptance Criteria

1. WHEN a training job is submitted via the TrainingInspectorPanel, THE TrainingInspectorPanel SHALL invoke the Compiler to produce a `nir.NIRGraph` from the current canvas topology before dispatching the TrainingRequest.
2. WHEN the Compiler produces a `nir.NIRGraph`, THE TrainingInspectorPanel SHALL include the serialised graph structure in the `TrainingRequest.payload` under the key `nir_graph`.
3. WHEN the SnnTorchAdapter receives a TrainingRequest whose payload contains a `nir_graph` key, THE SnnTorchAdapter SHALL build the snnTorch model from that graph rather than from the internal hardcoded `TinySnn` topology.
4. WHEN the SnnTorchAdapter receives a TrainingRequest whose payload does not contain a `nir_graph` key, THE SnnTorchAdapter SHALL fall back to the `TinySnn` demo topology and include a warning in `TrainingResult.metadata` with key `topology_source` set to `"fallback_demo"`.
5. IF the Compiler raises a `CompileError` during pre-training compilation, THEN THE TrainingInspectorPanel SHALL display the `Diagnostic.message` of the first diagnostic entry to the user AND SHALL NOT dispatch the TrainingRequest.
6. THE SnnTorchAdapter SHALL accept a `nir_graph` payload key whose value is either a serialised NIR graph dict or a `nir.NIRGraph` object, and SHALL build the snnTorch model from the provided graph in both cases without falling back to the demo topology.
7. IF the `nir_graph` payload value is neither a dict nor a `nir.NIRGraph` object, THEN THE SnnTorchAdapter SHALL raise a `ValueError` with a message identifying the unexpected type and SHALL NOT proceed with training.

---

### Requirement 2: NetworkIR JSON Serialisation (Phase 1)

**User Story:** As a developer, I want `NetworkIR` to be serialisable to and from a JSON-safe dictionary, so that the internal IR can be stored inside a `.nmtk` bundle without loss of structure.

#### Acceptance Criteria

1. THE NetworkIR SHALL expose a `to_dict()` method that returns a JSON-serialisable `dict` representing all fields: `populations`, `connections`, `learning_rules`, `timing_declarations`, `backend_hints`, `akida_hardware`, `akida_connection_properties`, and `metadata`.
2. THE NetworkIR SHALL expose a `from_dict(data: dict)` class method that reconstructs a `NetworkIR` instance from the output of `to_dict()`.
3. FOR ALL valid `NetworkIR` instances `ir`, calling `NetworkIR.from_dict(ir.to_dict())` SHALL produce an instance where every string, integer, boolean, and list field compares equal by value to the corresponding field in `ir`.
4. WHEN a `ConnectionIR.weight` value is a `numpy.ndarray`, THE `to_dict()` method SHALL serialise it as a nested Python list so the result is JSON-safe.
5. WHEN `NetworkIR.from_dict()` encounters a `weight` field that is a nested list, THE `from_dict()` method SHALL reconstruct it as a `numpy.ndarray` with `dtype=float`. WHEN `weight` is a scalar float, THE `from_dict()` method SHALL reconstruct it as a `numpy.ndarray` with shape `()` and `dtype=float`.
6. IF `NetworkIR.from_dict()` receives a dict that is missing any of the keys `populations`, `connections`, `learning_rules`, `timing_declarations`, or `backend_hints`, THEN THE `from_dict()` method SHALL raise a `ValueError` with a message identifying the missing key.
7. FOR ALL valid `NetworkIR` instances `ir` containing `ConnectionIR` entries with `numpy.ndarray` weights, calling `NetworkIR.from_dict(ir.to_dict())` SHALL produce weight arrays that are element-wise equal to the original arrays within a tolerance of 1×10⁻⁹.

---

### Requirement 3: ProjectBundle Container (Phase 1)

**User Story:** As a researcher, I want to save my entire network project — structure, learning rules, and training configuration — into a single portable `.nmtk` file, so that I can share, version-control, and reload complete projects.

#### Acceptance Criteria

1. THE BundleSerializer SHALL produce a `.nmtk` file that is a valid ZIP archive containing at minimum `manifest.json`, `internal_ir.json`, `graph.nir`, and `training.json`.
2. WHEN `ProjectBundle.save(path)` is called, THE BundleSerializer SHALL generate `graph.nir` and `training.json` from the `NetworkIR` source of truth and SHALL NOT accept externally supplied versions of those files as inputs.
3. WHEN `ProjectBundle.load(path)` is called, THE BundleSerializer SHALL read `internal_ir.json` as the sole source of truth for the `NetworkIR` and SHALL ignore the contents of `graph.nir` and `training.json` for reconstruction purposes.
4. WHEN `ProjectBundle.save(path)` is called and `TrainingResult.learned_weights` is not `None`, THE BundleSerializer SHALL write the weights to `weights.h5` inside the ZIP. WHEN `TrainingResult.learned_weights` is `None`, THE BundleSerializer SHALL NOT include `weights.h5` in the ZIP.
5. THE `manifest.json` entry SHALL contain the fields `bundle_schema_version` (a string in `MAJOR.MINOR` format), `nmtk_version` (string), `created_at` (ISO 8601 UTC string), `target_backend` (string), and `deployment_mode` (one of `"offline_train"`, `"online_learn"`, `"deploy_only"`).
6. IF `ProjectBundle.load(path)` is called on a file that is not a valid ZIP archive, THEN THE BundleSerializer SHALL raise a `BundleLoadError` with a message identifying the file path.
7. IF `ProjectBundle.load(path)` is called on a ZIP that is missing `internal_ir.json`, THEN THE BundleSerializer SHALL raise a `BundleLoadError` with a message stating that the internal IR is absent.
8. IF `ProjectBundle.load(path)` is called on a ZIP whose `manifest.json` contains a `bundle_schema_version` value that the current BundleSerializer does not support, THEN THE BundleSerializer SHALL raise a `BundleLoadError` naming the unsupported version.
9. IF `ProjectBundle.load(path)` is called on a ZIP whose `manifest.json` is missing or malformed JSON, THEN THE BundleSerializer SHALL raise a `BundleLoadError` with a message indicating the manifest could not be parsed.
10. FOR ALL valid `ProjectBundle` instances `b`, calling `ProjectBundle.load(path)` on the file written by `b.save(path)` SHALL produce a `ProjectBundle` whose `NetworkIR` matches `b.network_ir` field-by-field: string and integer fields are exactly equal, and floating-point fields are equal within a tolerance of 1×10⁻⁶.

---

### Requirement 4: Training Configuration Schema (Phase 1)

**User Story:** As a developer, I want `training.json` to follow a versioned schema that explicitly records the target backend, deployment mode, and learning rules with a rule-mode flag, so that adapters and future migrations have an unambiguous contract.

#### Acceptance Criteria

1. THE `training.json` entry written by the BundleSerializer SHALL contain the fields `schema_version`, `target_backend`, `training_mode`, `deployment_mode`, `rule_mode`, `hyperparameters`, and `learning_rules`.
2. THE `rule_mode` field in `training.json` SHALL be exactly one of the string values `"strict"` or `"advisory"`.
3. IF `rule_mode` is `"strict"` and the selected adapter's `AdapterCapability.supported_rule_kinds` does not include every rule kind present in the `learning_rules` array, THEN THE TrainingAdapterRegistry SHALL raise `AdapterSelectionError` with a message naming the first unsupported rule kind before dispatching.
4. IF `rule_mode` is `"advisory"` and the selected adapter does not support all rule kinds, THEN THE TrainingAdapterRegistry SHALL allow the dispatch to proceed and the adapter SHALL record the unsupported rule kind strings in `TrainingResult.metadata["skipped_rules"]` as a list of strings.
5. THE `learning_rules` array in `training.json` SHALL be a direct serialisation of `NetworkIR.learning_rules`, with each entry containing at minimum the fields `kind`, `source`, `target`, `rate`, `window`, `weight_min`, `weight_max`, and `reward_signal`.
6. IF `schema_version` in a loaded `training.json` does not match the single schema version string supported by the current BundleSerializer, THEN THE BundleSerializer SHALL raise a `BundleLoadError` naming the unsupported schema version.
7. THE `AdapterCapability` class SHALL include a `supported_rule_kinds` field (a collection of strings) listing the learning rule kind values the adapter can process, so that the registry can enforce `rule_mode` checking.

---

### Requirement 5: Canvas Learning Rule Projection (Phase 2)

**User Story:** As a researcher, I want to see which edges in my network canvas have learning rules attached, so that I can visually distinguish plastic connections from static ones and configure rule parameters per edge.

#### Acceptance Criteria

1. THE CanvasEdge SHALL include an optional `learningRule` field of type `LearningRuleProjection` that carries `kind` (string), `rate` (nullable double), `window` (nullable double), and `rewardSignal` (nullable string).
2. WHEN the backend projects a `NetworkIR` to a `CanvasProjection`, THE backend SHALL populate `CanvasEdge.learningRule` for every edge whose directed source-node-ID → target-node-ID pair matches a `LearningRuleIR` entry in `NetworkIR.learning_rules`. IF multiple `LearningRuleIR` entries match the same directed pair, THE backend SHALL use the last matching entry.
3. WHEN a `CanvasEdge.learningRule` is not `null`, THE canvas edge painter SHALL render the edge with a dashed stroke to distinguish it from static edges.
4. WHEN a `CanvasEdge.learningRule` is `null`, THE canvas edge painter SHALL render the edge with a solid stroke.
5. WHEN an edge is selected, THE edge parameter inspector panel SHALL display a `learningRule` kind dropdown with options `"static"`, `"stdp"`, and `"surrogate"`.
6. WHEN a user selects a `learningRule` kind other than `"static"` in the inspector panel, THE TrainingInspectorPanel SHALL replace any existing entry for that edge in the `learning_rules` array of the TrainingRequest payload with the updated rule, or insert a new entry if none exists.
7. WHEN a user selects `"static"` as the `learningRule` kind in the inspector panel, THE CanvasEdge SHALL set its `learningRule` field to `null` and the canvas edge painter SHALL re-render the edge with a solid stroke.
8. IF the canvas state contains an edge whose `learningRule` is not `null` but the edge is currently rendered with a solid stroke, THE canvas edge painter SHALL re-render the edge with a dashed stroke.

---

### Requirement 6: Atomic Edge Deletion with Learning Rule Cleanup (Phase 2)

**User Story:** As a researcher, I want deleting a canvas edge to automatically remove the associated learning rule from the network, so that the internal IR never contains orphaned rules that reference non-existent connections.

#### Acceptance Criteria

1. WHEN a user deletes a `CanvasEdge`, THE backend SHALL either remove both the matching `ConnectionIR` and every `LearningRuleIR` whose `source` and `target` fields exactly equal the deleted edge's source and target, or remove neither, leaving all other `LearningRuleIR` entries unchanged.
2. WHEN a `ConnectionIR` is removed and no `LearningRuleIR` references that connection, THE backend SHALL remove only the `ConnectionIR` without error.
3. WHEN a `ConnectionIR` is successfully removed, THE backend SHALL regenerate `graph.nir` and `training.json` in the active ProjectBundle from the updated `NetworkIR`, and SHALL return HTTP 200 only after both files have been written.
4. IF the backend cannot complete all removals or file regeneration due to a serialisation error at any stage, THEN THE backend SHALL roll back all changes to the `NetworkIR` and SHALL return an HTTP error response without modifying the persisted bundle.
5. IF the `DELETE /api/bundle/connection` endpoint is called with `source` and `target` values that do not match any `ConnectionIR` in the active `NetworkIR`, THEN THE backend SHALL return an HTTP 404 error response without modifying the `NetworkIR`.
6. THE backend SHALL expose a `DELETE /api/bundle/connection` endpoint that accepts `source` and `target` as query parameters and performs the atomic removal described above.

---

### Requirement 7: Deployment Mode Enforcement (Phase 3)

**User Story:** As a researcher, I want the system to reject or warn clearly when I select a deployment mode that is incompatible with my chosen backend, so that I never accidentally lose learning rules by exporting to a backend that does not support them.

#### Acceptance Criteria

1. THE `TrainingRequest` dataclass SHALL include a `deployment_mode` field of type `DeploymentMode` with a default value of `"offline_train"`. WHEN `deployment_mode` is absent or `None` in the request, THE TrainingAdapterRegistry SHALL treat it as `"offline_train"`.
2. IF `deployment_mode` is `"online_learn"` and the selected backend is not `"lava"`, THEN THE TrainingAdapterRegistry SHALL raise `AdapterSelectionError` with `UnavailableReasonCode.NOT_IMPLEMENTED` and a message that contains the substring `"online_learn"` before dispatching.
3. WHEN `deployment_mode` is `"deploy_only"`, THE BundleSerializer SHALL generate `graph.nir` and SHALL write an empty `learning_rules` array in `training.json`.
4. WHEN `deployment_mode` is `"offline_train"`, THE BundleSerializer SHALL generate both `graph.nir` and a `training.json` whose `learning_rules` array contains one entry for every `LearningRuleIR` in `NetworkIR.learning_rules`.
5. WHEN `deployment_mode` is `"online_learn"` and the selected backend is `"lava"`, THE BundleSerializer SHALL include an `stdp_config.json` entry in the ZIP alongside `graph.nir`, and `training.json` SHALL still contain the serialised learning rules.
6. WHILE the user has `"online_learn"` selected in the TrainingInspectorPanel and the currently selected backend is not `"lava"`, THE TrainingInspectorPanel SHALL display a non-blocking inline warning indicating that online learning requires the Lava backend targeting Loihi 2.
7. WHILE the user has `"bindsnet"` selected as the backend in the TrainingInspectorPanel, THE TrainingInspectorPanel SHALL display a non-blocking inline notice indicating that BindsNET training produces weights for simulation only and that export to neuromorphic hardware requires the Lava backend.

---

### Requirement 8: LearningRuleIR Reward Signal Extension (Phase 3)

**User Story:** As a researcher, I want to express three-factor (reward-modulated) STDP rules in my network design, so that I can target Lava → Loihi 2 with on-chip reinforcement-based plasticity.

#### Acceptance Criteria

1. THE `LearningRuleIR` dataclass SHALL include a `reward_signal` field of type `str | None` with a default value of `None`.
2. WHEN `LearningRuleIR.kind` is `"r-stdp"` and `reward_signal` is `None`, THE NetworkIR lowering stage SHALL raise a `LoweringError` with a message stating that reward-modulated STDP requires a `reward_signal` population name.
3. WHEN a `PopulationIR` has `role` equal to `"reward_signal"`, THE NetworkIR lowering stage SHALL accept that population as a valid `reward_signal` reference in a `LearningRuleIR` without raising an error.
4. WHEN `LearningRuleIR.reward_signal` is a non-empty string that does not match the name of any `PopulationIR` with `role="reward_signal"` in the same `NetworkIR`, THE NetworkIR lowering stage SHALL raise a `LoweringError` naming the unresolved population reference.
5. WHEN the canvas contains a population with `role="reward_signal"`, THE canvas node painter SHALL render that node with a fill style that is visually distinct from all other population role styles and is reserved exclusively for reward-signal populations.
6. THE `NetworkIR.to_dict()` method SHALL serialise `LearningRuleIR.reward_signal` as a JSON string field, preserving `None` as JSON `null`.
7. THE `NetworkIR.from_dict()` method SHALL reconstruct `LearningRuleIR.reward_signal` as a Python string when the JSON value is a string, and as `None` when the JSON value is `null`.

---

### Requirement 9: SnnTorch Adapter Deployment Mode Guard (Phase 3)

**User Story:** As a developer, I want the SnnTorchAdapter to explicitly reject `online_learn` requests rather than silently ignore learning rules, so that users receive an honest error instead of a static deployment that pretends to be plastic.

#### Acceptance Criteria

1. WHEN the SnnTorchAdapter `run()` method is called with a `TrainingRequest` whose `deployment_mode` field equals `"online_learn"`, THE SnnTorchAdapter SHALL raise `AdapterSelectionError` with `UnavailableReasonCode.NOT_IMPLEMENTED` and a message containing the substring `"online_learn"`.
2. WHEN the SnnTorchAdapter `run()` method is called with a `TrainingRequest` whose `deployment_mode` field equals `"offline_train"` or `"deploy_only"`, THE SnnTorchAdapter SHALL not raise an error due to `deployment_mode` and SHALL proceed to return a `TrainingResult`.
3. WHEN `deployment_mode` is absent or `None` in the `TrainingRequest`, THE SnnTorchAdapter SHALL treat it as `"offline_train"` and proceed normally.
4. THE `AdapterCapability` returned by the SnnTorchAdapter SHALL include `"offline_train"` and `"deploy_only"` in its `supported_deployment_modes` collection and SHALL NOT include `"online_learn"`.

---

### Requirement 10: Lava Exporter Online Learning Branch (Phase 3)

**User Story:** As a researcher, I want the Lava exporter to emit on-chip learning rule configuration when `deployment_mode` is `"online_learn"`, so that the resulting bundle can be deployed directly to Loihi 2 with plasticity rules running on hardware.

#### Acceptance Criteria

1. WHEN `lava_exporter.py` is called with `deployment_mode` equal to `"online_learn"`, THE Lava_Exporter SHALL generate an `stdp_config.json` alongside `graph.nir` containing the on-chip learning rule parameters derived from `NetworkIR.learning_rules`.
2. WHEN `lava_exporter.py` is called with `deployment_mode` equal to `"offline_train"` or `"deploy_only"`, THE Lava_Exporter SHALL generate only `graph.nir` and SHALL NOT generate `stdp_config.json`.
3. THE `stdp_config.json` produced by the Lava_Exporter SHALL contain a `rules` array where each entry includes the fields `kind`, `source`, `target`, `rate`, `window`, `weight_min`, and `weight_max` derived from the corresponding `LearningRuleIR`, with no extraneous fields added.
4. IF a `LearningRuleIR` entry has a `kind` value other than `"stdp"`, THEN THE Lava_Exporter SHALL raise a `LoweringError` naming the unsupported rule kind.
5. WHEN `deployment_mode` is `"online_learn"` and `NetworkIR.learning_rules` is empty, THE Lava_Exporter SHALL raise a `LoweringError` with a message indicating that at least one learning rule is required for online_learn deployment.
6. IF a `LearningRuleIR` entry has `source` equal to `None` or `target` equal to `None`, THEN THE Lava_Exporter SHALL raise a `LoweringError` naming the rule kind and indicating that both source and target must be specified for on-chip export.

---

### Requirement 11: BindsNET Simulation-Only Adapter (Phase 4)

**User Story:** As a researcher, I want to simulate STDP behaviour locally using BindsNET without requiring Loihi 2 hardware, so that I can validate learning rule configurations before committing to a hardware deployment.

#### Acceptance Criteria

1. THE system SHALL include a `BindsNETAdapter` class that implements `BaseTrainingAdapter` and registers with the TrainingAdapterRegistry under the backend name `"bindsnet"`.
2. THE `AdapterCapability` returned by `BindsNETAdapter` SHALL set `output_format` to `"weights_only"` and SHALL list `"stdp"` and `"reward_modulated_stdp"` in `supported_training_modes`.
3. WHEN the BindsNETAdapter `run()` method receives a `TrainingRequest`, THE BindsNETAdapter SHALL consume the `learning_rules` array from `TrainingRequest.payload` and map each entry to the corresponding BindsNET `Connection` constructor arguments. IF a `learning_rules` entry has a `kind` value that the BindsNETAdapter does not support, THEN THE BindsNETAdapter SHALL raise `AdapterSelectionError` naming the unsupported kind.
4. WHEN the BindsNETAdapter training run completes, THE BindsNETAdapter SHALL return a `TrainingResult` where `learned_weights` is a non-None, non-empty mapping and `metadata["output_format"]` is set to `"weights_only"`.
5. IF the `TrainingRequest.deployment_mode` field equals `"online_learn"` or `"deploy_only"`, THEN THE BindsNETAdapter SHALL raise `AdapterSelectionError` with `UnavailableReasonCode.NOT_IMPLEMENTED` and a message indicating that BindsNET is a simulation-only backend.
6. IF the `bindsnet` Python package is not importable at the time `is_available()` is called, THEN THE BindsNETAdapter SHALL return `TrainingAvailability(available=False, reason=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING)` with a message naming `"bindsnet"` as the missing dependency.
7. WHEN the BundleSerializer writes a `TrainingResult` produced by the BindsNETAdapter, THE BundleSerializer SHALL write `learned_weights` to `weights.h5` inside the ZIP.
8. WHEN the BundleSerializer writes a `TrainingResult` produced by the BindsNETAdapter, THE BundleSerializer SHALL set `manifest.deployment_mode` to `"offline_train"` regardless of the value in the original TrainingRequest.

---

### Requirement 12: Lava Online Learning Adapter (Phase 4b)

**User Story:** As a researcher, I want a dedicated Lava adapter that targets on-chip plasticity on Loihi 2, so that I can produce a fully deployable `.nmtk` bundle with learning rules that execute on neuromorphic hardware.

#### Acceptance Criteria

1. THE system SHALL include a `LavaOnlineAdapter` class that implements `BaseTrainingAdapter` and registers under the backend name `"lava"`.
2. THE `AdapterCapability` returned by `LavaOnlineAdapter` SHALL set `output_format` to `"nir+stdp_config"`, list `"stdp"` and `"r-stdp"` in `supported_training_modes`, and list `"online_learn"` in `supported_deployment_modes`.
3. WHEN the LavaOnlineAdapter `run()` method receives a TrainingRequest, THE LavaOnlineAdapter SHALL translate each `LearningRuleIR` entry with `kind == "stdp"` into a Lava `STDPLoihi` process configuration, and each entry with `kind == "r-stdp"` into a Lava `Rmax` process configuration. IF a `LearningRuleIR` entry has an unsupported `kind`, THE LavaOnlineAdapter SHALL raise `AdapterSelectionError` naming the unsupported kind.
4. WHEN the LavaOnlineAdapter `run()` completes, THE LavaOnlineAdapter SHALL return a `TrainingResult` whose `metadata["stdp_config"]` contains a dict with at minimum the keys `kind`, `source`, `target`, and at least one of `rate`, `window`, `weight_min`, or `weight_max` for each translated rule.
5. IF `deployment_mode` is `"online_learn"` and the TrainingAdapterRegistry resolves to an adapter other than the LavaOnlineAdapter, THEN THE TrainingAdapterRegistry SHALL raise `AdapterSelectionError` with `UnavailableReasonCode.NOT_IMPLEMENTED` before calling `dispatch()`.
6. WHEN `is_available()` is called and the `lava-nc` Python package is not importable, THE LavaOnlineAdapter SHALL return `TrainingAvailability(available=False, reason=UnavailableReasonCode.OPTIONAL_DEPENDENCY_MISSING)` with a message naming `"lava-nc"` as the missing dependency.
7. WHEN the LavaOnlineAdapter `run()` method receives a TrainingRequest with an empty `learning_rules` list, THE LavaOnlineAdapter SHALL raise `ValueError` with a message indicating that at least one learning rule is required.

---

### Requirement 13: Bundle API Endpoints (Phase 5)

**User Story:** As a developer, I want backend API endpoints for saving, loading, and exporting `.nmtk` bundles, so that the Flutter Studio frontend can perform all bundle lifecycle operations without direct file system access.

#### Acceptance Criteria

1. THE backend SHALL expose a `POST /api/bundle/save` endpoint that accepts a JSON body with a `bundle` field (ProjectBundle) and a `path` field (string), writes a `.nmtk` ZIP to that path, and returns HTTP 200 with a JSON body containing an `absolute_path` field on success.
2. WHEN `POST /api/bundle/load` is called with a JSON body containing a `path` field, THE backend SHALL read the `.nmtk` ZIP at that path and return HTTP 200 with a JSON body containing a `network_ir` field (serialised NetworkIR) and a `manifest` field (Manifest dict).
3. THE backend SHALL expose a `POST /api/bundle/export` endpoint that accepts a JSON body with a `bundle` field (ProjectBundle) and a `deployment_mode` field (string), generates `graph.nir` and `training.json`, and returns the ZIP as a binary `application/zip` download.
4. THE backend SHALL expose a `DELETE /api/bundle/connection` endpoint that accepts `source` and `target` as query parameters, performs the atomic `ConnectionIR` + `LearningRuleIR` removal, and returns HTTP 200 on success.
5. IF `POST /api/bundle/load` is called with a `path` that does not refer to an existing file, THEN THE backend SHALL return HTTP 404 with a JSON body containing an `error` field identifying the missing path.
6. IF `POST /api/bundle/save` fails due to a `BundleLoadError` or serialisation error, THEN THE backend SHALL return HTTP 422 with a JSON body containing an `error` field with the diagnostic message.
7. IF `POST /api/bundle/export` is called with `deployment_mode` equal to `"online_learn"` and the bundle's `target_backend` is not `"lava"`, THEN THE backend SHALL return HTTP 422 with a JSON body containing an `error` field with a message indicating that online learning requires the Lava backend.
8. WHEN `POST /api/bundle/export` is called with `deployment_mode` equal to `"online_learn"` and `target_backend` equal to `"lava"`, THE backend SHALL proceed normally and include `stdp_config.json` in the returned ZIP.
9. IF `DELETE /api/bundle/connection` is called with `source` and `target` values that do not match any `ConnectionIR` in the active `NetworkIR`, THEN THE backend SHALL return HTTP 404 with a JSON body containing an `error` field identifying the missing connection.

---

### Requirement 14: Bundle Schema Versioning and Migration (Phase 1 / ongoing)

**User Story:** As a developer, I want the bundle format to carry explicit schema versions and to fail with a clear error on unsupported versions, so that future format changes can be introduced without silently corrupting older projects.

#### Acceptance Criteria

1. THE `manifest.json` `bundle_schema_version` field SHALL be set to `"1.0"` for all bundles produced by this feature release.
2. THE `training.json` `schema_version` field SHALL be set to `"1.0"` for all bundles produced by this feature release.
3. WHEN the BundleSerializer reads a `manifest.json` with a `bundle_schema_version` value that is not in `SUPPORTED_BUNDLE_VERSIONS`, THE BundleSerializer SHALL raise `BundleLoadError` with a message that includes the unrecognised version string.
4. THE BundleSerializer SHALL expose a `SUPPORTED_BUNDLE_VERSIONS` constant (a collection of strings) listing all bundle schema version strings the serialiser can read.
5. WHEN `migrate(path, target_version)` is called, THE BundleSerializer SHALL read the bundle at `path`, transform `internal_ir.json` to the target schema, and write the updated bundle to the same path.
6. WHEN `migrate(path, target_version)` is called, THE BundleSerializer SHALL preserve the original file as `<name>.nmtk.bak` before overwriting.
7. IF `migrate(path, target_version)` is called with a `target_version` that is not in `SUPPORTED_BUNDLE_VERSIONS`, THEN THE BundleSerializer SHALL raise `BundleLoadError` with a message indicating the unsupported target version without modifying any files.
8. IF `ProjectBundle.load(path)` is called on a ZIP whose `manifest.json` is present but does not contain a `bundle_schema_version` field, THEN THE BundleSerializer SHALL raise `BundleLoadError` with a message indicating that the version field is missing.
