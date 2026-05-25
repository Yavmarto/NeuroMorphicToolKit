# Implementation Plan: NIR + Training Bundle (`nir-training-bundle`)

## Overview

Implement the NIR + Training Bundle feature in five ordered phases. Each phase builds on
the previous: Phase 0 fixes the adapter–canvas disconnect (no new files, pure fixes), Phase 1
formalises the `.nmtk` bundle container, Phase 2 surfaces learning rules on the canvas, Phase 3
extends the IR and deployment modes, Phases 4/4b add BindsNET and Lava online-learning adapters,
and Phase 5 exposes FastAPI bundle endpoints. The `NetworkIR` dataclass is the single source of
truth throughout; `graph.nir` and `training.json` are always generated outputs, never edited
sources.

---

## Tasks

- [ ] 0. Phase 0 — Fix Adapter–Canvas Disconnect (no new files)
  - [ ] 0.1 Update `SnnTorchAdapter` to accept `nir_graph` from payload
    - In `neurocnl/neurocnl/training/snntorch_adapter.py`, update `_run_real()` to read
      `payload.get("nir_graph")` and branch: if `None` → fall back to `TinySnn` and set
      `metadata["topology_source"] = "fallback_demo"`; if `dict` → call
      `_build_model_from_nir_dict()`; if `nir.NIRGraph` → call
      `_build_model_from_nir_graph()`; else → raise `ValueError` identifying the unexpected type.
    - Add `online_learn` guard at the top of `run()`: read `deployment_mode` from
      `(request.payload or {}).get("deployment_mode")` falling back to
      `getattr(request, "deployment_mode", None) or "offline_train"`;
      if `"online_learn"` raise `AdapterSelectionError` with `NOT_IMPLEMENTED` and a message
      containing `"online_learn"`.
    - _Requirements: 1.3, 1.4, 1.6, 1.7, 9.1, 9.2, 9.3_

  - [ ] 0.2 Update `TrainingInspectorPanel` to compile before dispatch
    - In `neurocnl/frontend/lib/widgets/training_inspector_panel.dart`, convert `_startTraining()`
      to `async`; call `_compileCnlToNir(ref.read(specTextProvider))` before
      `submitTraining`; include `nir_graph: nirGraph.toJson()`,
      `deployment_mode: _selectedDeploymentMode`, and `learning_rules: _collectEdgeLearningRules()`
      in the payload map.
    - Catch `CompileError`, display `e.diagnostics.first.message` via `_showCompileError()`,
      and return without dispatching.
    - _Requirements: 1.1, 1.2, 1.5_


- [ ] 1. Phase 1 — Bundle Format
  - [ ] 1.1 Extend IR types in `neurocnl/neurocnl/ir/types.py`
    - Add `reward_signal: str | None = None` field to `LearningRuleIR` (after `weight_max`).
    - Add `supported_rule_kinds: tuple[str, ...] = ()` and
      `supported_deployment_modes: tuple[str, ...] = ()` fields to `AdapterCapability` in
      `neurocnl/neurocnl/training_registry.py`.
    - Add `deployment_mode: str | None = None` field to `TrainingRequest` in
      `neurocnl/neurocnl/training_registry.py`.
    - _Requirements: 4.7, 7.1, 8.1, 9.4_

  - [ ] 1.2 Implement `NetworkIR.to_dict()` and `NetworkIR.from_dict()` in `ir/types.py`
    - Implement `to_dict()` returning a JSON-serialisable `dict` for all eight fields:
      `populations`, `connections`, `learning_rules`, `timing_declarations`, `backend_hints`,
      `akida_hardware`, `akida_connection_properties`, and `metadata`.
    - Serialise `numpy.ndarray` weights via `.tolist()`.
    - Implement `from_dict(data)` classmethod; raise `ValueError` naming the key if any of
      `populations`, `connections`, `learning_rules`, `timing_declarations`, or `backend_hints`
      are absent; reconstruct list-encoded weights as `np.array(..., dtype=float)` and scalar
      floats as `np.array(value, dtype=float)` with `shape == ()`.
    - Serialise `LearningRuleIR.reward_signal` as JSON string / `null`.
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 8.6, 8.7_

  - [ ]* 1.3 Write PBT for `NetworkIR` round-trip (Property 1)
    - **Property 1: `NetworkIR` serialisation round-trip**
    - Place test in `neurocnl/neurocnl/tests/properties/test_nir_bundle_properties.py`.
    - Use `network_ir_strategy` composite strategy (from design doc §Testing Strategy).
    - Assert `json.dumps(ir.to_dict())` does not raise; assert scalar/list fields equal;
      assert ndarray weights element-wise equal within 1×10⁻⁹.
    - `@settings(max_examples=200)` — tag comment: `Feature: nir-training-bundle, Property 1`.
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 8.6, 8.7**

  - [ ] 1.4 Create `neurocnl/neurocnl/bundle/manifest.py`
    - Create the `bundle/` package (`__init__.py`).
    - Implement `Manifest` frozen dataclass with fields: `bundle_schema_version`, `nmtk_version`,
      `created_at` (ISO 8601 UTC), `target_backend`, `deployment_mode`.
    - _Requirements: 3.5, 14.1_

  - [ ] 1.5 Create `neurocnl/neurocnl/bundle/serializer.py` — `BundleSerializer` and `ProjectBundle`
    - Implement `BundleLoadError(Exception)`.
    - Implement `ProjectBundle` dataclass with `network_ir`, `manifest`, `training_config`,
      and optional `training_result`; add `save(path)` and `load(path)` convenience methods.
    - Implement `BundleSerializer` with stub skeletons for `save()`, `load()`, `export()`,
      and `migrate()`.
    - Expose `SUPPORTED_BUNDLE_VERSIONS: frozenset[str] = frozenset({"1.0"})` and
      `SUPPORTED_TRAINING_SCHEMA_VERSIONS: frozenset[str] = frozenset({"1.0"})` as module-level
      constants.
    - _Requirements: 3.1, 3.2, 3.3, 3.6, 14.4_


  - [ ] 1.6 Implement `ProjectBundle.save()` / `BundleSerializer.save()`
    - Write a valid ZIP to `path` containing at minimum: `manifest.json`, `internal_ir.json`
      (from `NetworkIR.to_dict()`), `graph.nir` (from `nir_exporter`), and `training.json`
      (schema_version, target_backend, training_mode, deployment_mode, rule_mode,
      hyperparameters, learning_rules).
    - Write `weights.h5` iff `bundle.training_result.learned_weights is not None`.
    - Write `stdp_config.json` iff `deployment_mode == "online_learn"` and
      `target_backend == "lava"`.
    - `training.json` learning_rules: empty list when `deploy_only`; full list when
      `offline_train` or `online_learn`.
    - _Requirements: 3.1, 3.2, 3.4, 4.1, 4.2, 4.5, 7.3, 7.4, 7.5_

  - [ ] 1.7 Implement `ProjectBundle.load()` / `BundleSerializer.load()`
    - Raise `BundleLoadError` if path is not a valid ZIP.
    - Raise `BundleLoadError` if `internal_ir.json` absent.
    - Raise `BundleLoadError` if `manifest.json` absent, malformed JSON, or missing
      `bundle_schema_version`.
    - Raise `BundleLoadError` if `bundle_schema_version` not in `SUPPORTED_BUNDLE_VERSIONS`.
    - Reconstruct `NetworkIR` via `NetworkIR.from_dict()` from `internal_ir.json` only;
      ignore `graph.nir` and `training.json`.
    - _Requirements: 3.3, 3.6, 3.7, 3.8, 3.9, 3.10, 14.3, 14.8_

  - [ ] 1.8 Implement `BundleSerializer.migrate()` with `.bak` preservation
    - Validate `target_version` is in `SUPPORTED_BUNDLE_VERSIONS` before touching any file
      (raise `BundleLoadError` on unsupported version without creating `.bak`).
    - Copy original to `<name>.nmtk.bak`.
    - Load `internal_ir.json`, apply version transformations (currently no-op for 1.0→1.0),
      write updated bundle back with updated `manifest.bundle_schema_version`.
    - _Requirements: 14.5, 14.6, 14.7_

  - [ ]* 1.9 Write PBT for `ProjectBundle` round-trip (Property 2)
    - **Property 2: `ProjectBundle` round-trip**
    - Use `project_bundle_strategy` composite strategy.
    - Assert ZIP contains `{"manifest.json", "internal_ir.json", "graph.nir", "training.json"}`.
    - Assert `restored.network_ir` matches `bundle.network_ir` within 1×10⁻⁶ for floats.
    - Assert `manifest` fields equal exactly.
    - `@settings(max_examples=150)` — tag: `Feature: nir-training-bundle, Property 2`.
    - **Validates: Requirements 3.1, 3.3, 3.5, 3.10, 14.1, 14.2**

  - [ ]* 1.10 Write PBT for `weights.h5` conditional inclusion (Property 3)
    - **Property 3: Weights inclusion conditional on `TrainingResult`**
    - Generate `ProjectBundle` with `has_weights: bool`; when True replace `training_result`
      with a `TrainingResult` carrying non-None `learned_weights`.
    - Assert `weights.h5` present iff `has_weights`.
    - `@settings(max_examples=100)` — tag: `Feature: nir-training-bundle, Property 3`.
    - **Validates: Requirements 3.4, 11.7**

  - [ ]* 1.11 Write PBT for `training.json` structure completeness (Property 4)
    - **Property 4: `training.json` structure completeness**
    - For any `ProjectBundle`, assert saved `training.json` is valid JSON containing all seven
      required fields and that `rule_mode` is exactly `"strict"` or `"advisory"`.
    - `@settings(max_examples=150)` — tag: `Feature: nir-training-bundle, Property 4`.
    - **Validates: Requirements 4.1, 4.2**

- [ ] 2. Checkpoint — Phase 1 complete
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x` and `ruff check .`.
  - Ensure all tests pass, ask the user if questions arise.


- [ ] 3. Phase 2 — Canvas Learning Rule Projection
  - [ ] 3.1 Create `neurocnl/frontend/lib/models/learning_rule_projection.dart`
    - Implement `LearningRuleProjection` class with `kind` (String), `rate` (double?),
      `window` (double?), `rewardSignal` (String?) fields.
    - Implement `factory LearningRuleProjection.fromJson(Map<String, dynamic> json)` reading
      `kind`, `rate`, `window`, `reward_signal` (snake_case) keys.
    - Implement `Map<String, dynamic> toJson()` emitting snake_case keys.
    - _Requirements: 5.1_

  - [ ] 3.2 Add `learningRule` field to `CanvasEdge` in `canonical_editor_document.dart`
    - Add `final LearningRuleProjection? learningRule;` to `CanvasEdge`.
    - Update constructor, `fromJson` (read `learning_rule` key), and `toJson`
      (emit `learning_rule` key when non-null).
    - Add `bool get hasLearningRule => learningRule != null;` getter.
    - _Requirements: 5.1, 5.3, 5.4_

  - [ ] 3.3 Update backend `CanonicalEditorDocument` Pydantic contract and projection logic
    - Add `learning_rule: LearningRuleProjectionSchema | None = None` to the edge projection
      Pydantic model in the neurocnl backend.
    - In the backend projection function, for each `ConnectionIR` scan
      `NetworkIR.learning_rules` for entries where `source == conn.source` and
      `target == conn.target`; use the last matching entry (last-match-wins); populate
      `CanvasEdge.learning_rule` from it.
    - _Requirements: 5.2_

  - [ ] 3.4 Update `network_graph_view.dart` edge painter for dashed/solid stroke
    - In `_NetworkPainter._paintEdges()`, switch between `_drawDashedLine()` and a solid
      `canvas.drawLine()` based on `edge.hasLearningRule`.
    - Solid stroke when `learningRule == null`; dashed stroke when non-null.
    - _Requirements: 5.3, 5.4, 5.8_

  - [ ] 3.5 Add `learningRule` kind dropdown to `EdgeParameterInspector`
    - Import `LearningRuleProjection` and add a `DropdownButton<String>` with items
      `['static', 'stdp', 'surrogate', 'r-stdp']`.
    - When `kind != 'static'`, upsert a `LearningRuleProjection` into the edge and push it
      into the `TrainingInspectorPanel`'s pending `learning_rules` payload array.
    - When `kind == 'static'`, set `edge.learningRule` to `null`; canvas re-renders solid.
    - Wire to `edge_parameter_inspector.dart`; import and use `edgeParameterInspector` from
      the relevant widget tree.
    - _Requirements: 5.5, 5.6, 5.7_

  - [ ]* 3.6 Write PBT for backend projection populates `learningRule` (Property 6)
    - **Property 6: Backend projection populates `learningRule` on matching edges**
    - For any `NetworkIR` with at least one `LearningRuleIR` with non-None `source`/`target`,
      assert every matching `CanvasEdge` in the produced `CanvasProjection` has a non-null
      `learning_rule` with `kind` equal to the rule's `kind`.
    - `@settings(max_examples=200)` — tag: `Feature: nir-training-bundle, Property 6`.
    - **Validates: Requirements 5.2**

  - [ ] 3.7 Implement atomic `DELETE /api/bundle/connection` endpoint
    - Add `delete_connection(source, target)` route to
      `neurocnl/backend/app/routers/bundle.py` (can be a stub file at this stage if Phase 5
      is not yet started — the route logic is self-contained).
    - Snapshot `NetworkIR` before mutation; remove matching `ConnectionIR` and all
      `LearningRuleIR` entries with matching `(source, target)`; call
      `state.bundle.regenerate_outputs()`; commit on success or rollback and raise HTTP 422.
    - Return HTTP 404 when `(source, target)` not found.
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [ ]* 3.8 Write PBT for atomic connection + rule removal (Property 7)
    - **Property 7: Atomic connection + rule removal**
    - For any `NetworkIR` with connections, pick one `ConnectionIR`; call `atomic_remove_connection`;
      assert no `ConnectionIR` with `(source, target)` remains; assert no `LearningRuleIR`
      with `(source, target)` remains; assert all other connections unchanged.
    - `@settings(max_examples=200)` — tag: `Feature: nir-training-bundle, Property 7`.
    - **Validates: Requirements 6.1, 6.2**

- [ ] 4. Checkpoint — Phase 2 complete
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x`, `ruff check .`, and
    `cd frontend && flutter test`.
  - Ensure all tests pass, ask the user if questions arise.


- [ ] 5. Phase 3 — IR Extension and Deployment Mode
  - [ ] 5.1 Add lowering validation for `r-stdp` `reward_signal` in `ir/types.py`
    - Implement a `lower_learning_rules(ir: NetworkIR)` function (or extend the existing
      lowering pipeline entry point) that raises `LoweringError` when:
      - `rule.kind == "r-stdp"` and `rule.reward_signal is None`.
      - `rule.reward_signal` is a non-empty string that does not match any `PopulationIR`
        with `role == "reward_signal"` in `ir.populations`.
    - _Requirements: 8.2, 8.3, 8.4_

  - [ ] 5.2 Update `TrainingAdapterRegistry.dispatch()` with deployment_mode and rule_mode enforcement
    - In `neurocnl/neurocnl/training_registry.py`, add `deployment_mode` enforcement:
      when `deployment_mode == "online_learn"` and `adapter.capability.backend_name != "lava"`,
      raise `AdapterSelectionError` with `NOT_IMPLEMENTED` and message containing `"online_learn"`.
    - Add `rule_mode` enforcement: when `rule_mode == "strict"` check every rule kind against
      `adapter.capability.supported_rule_kinds`; raise `AdapterSelectionError` naming the first
      unsupported kind before calling `adapter.run()`.
    - When `rule_mode == "advisory"`, collect skipped kinds and inject into result metadata
      `skipped_rules` after `adapter.run()` returns.
    - _Requirements: 4.3, 4.4, 7.1, 7.2_

  - [ ] 5.3 Update `SnnTorchAdapter` capability declaration
    - Set `supported_deployment_modes=("offline_train", "deploy_only")` and
      `supported_rule_kinds=("surrogate",)` on `SnnTorchAdapter.capability`.
    - _Requirements: 9.4_

  - [ ] 5.4 Add online_learn branch to `lava_exporter.py`
    - Update `export_lava()` signature to accept `deployment_mode="offline_train"` and `ir=None`.
    - When `deployment_mode == "online_learn"`: raise `LoweringError` if `ir is None` or
      `ir.learning_rules` is empty; call `_generate_stdp_config(ir.learning_rules)` and return
      `(code, stdp_config_dict)`.
    - Implement `_generate_stdp_config(rules)`: raise `LoweringError` on any rule kind ≠ `"stdp"`,
      on missing `source`/`target`; return `{"rules": [...]}` with fields
      `kind, source, target, rate, window, weight_min, weight_max`.
    - When `deployment_mode != "online_learn"` return `(code, None)`.
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [ ] 5.5 Add deployment_mode selector and inline warnings to `TrainingInspectorPanel`
    - Add `_selectedDeploymentMode` state variable defaulting to `"offline_train"`.
    - Add a `DropdownButton` for `["offline_train", "online_learn", "deploy_only"]` in the
      idle content form section.
    - Show `_InlineWarning` when `_deploymentMode == 'online_learn'` and selected backend ≠ `'lava'`.
    - Show `_InlineNotice` when selected backend == `'bindsnet'` (simulation-only notice).
    - _Requirements: 7.6, 7.7_

  - [ ]* 5.6 Write PBT for strict rule-mode enforcement (Property 5)
    - **Property 5: Strict rule-mode enforcement across all adapter capability sets**
    - Generate `supported` frozenset and `rules` list; when any rule kind absent from
      `supported`, assert `_enforce_strict_rule_mode(rules, supported)` raises
      `AdapterSelectionError`; when all supported assert no raise.
    - `@settings(max_examples=300)` — tag: `Feature: nir-training-bundle, Property 5`.
    - **Validates: Requirements 4.3, 4.4**

  - [ ]* 5.7 Write PBT for `online_learn` rejected for non-Lava (Property 8)
    - **Property 8: `online_learn` rejected for all non-Lava backends**
    - Generate any `backend` string where `backend.strip().lower() != "lava"`.
    - Dispatch `TrainingRequest(backend_name=backend, deployment_mode="online_learn")`.
    - Assert `AdapterSelectionError` raised with `"online_learn"` in message.
    - `@settings(max_examples=200)` — tag: `Feature: nir-training-bundle, Property 8`.
    - **Validates: Requirements 7.2, 9.1, 12.5**

  - [ ]* 5.8 Write PBT for deployment mode controls `learning_rules` in `training.json` (Property 9)
    - **Property 9: Deployment mode controls `learning_rules` in `training.json`**
    - For any `NetworkIR` with ≥1 `LearningRuleIR`: saving with `deploy_only` → `learning_rules`
      empty; saving with `offline_train` → `learning_rules` length equals `NetworkIR.learning_rules`.
    - `@settings(max_examples=150)` — tag: `Feature: nir-training-bundle, Property 9`.
    - **Validates: Requirements 7.3, 7.4**

  - [ ]* 5.9 Write PBT for `stdp_config.json` conditional presence (Property 10)
    - **Property 10: `stdp_config.json` present iff `online_learn` + `lava`**
    - For any `ProjectBundle` with `online_learn` + `lava`: ZIP contains `stdp_config.json`.
    - For all other `(deployment_mode, target_backend)` combinations: ZIP does NOT contain
      `stdp_config.json`.
    - `@settings(max_examples=150)` — tag: `Feature: nir-training-bundle, Property 10`.
    - **Validates: Requirements 7.5, 10.1, 10.2**

  - [ ]* 5.10 Write PBT for unresolvable `reward_signal` raises `LoweringError` (Property 11)
    - **Property 11: Unresolvable `reward_signal` always raises `LoweringError`**
    - Generate `rule_reward_signal` (non-empty text) and `population_names` list; when
      `rule_reward_signal` not in valid signals, assert `lower_r_stdp_rule(rule, ir)` raises
      `LoweringError`. Test Unicode names and names matching wrong-role populations.
    - `@settings(max_examples=300)` — tag: `Feature: nir-training-bundle, Property 11`.
    - **Validates: Requirements 8.2, 8.4**

- [ ] 6. Checkpoint — Phase 3 complete
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x` and `ruff check .`.
  - Ensure all tests pass, ask the user if questions arise.


- [ ] 7. Phase 4 — BindsNET Adapter
  - [ ] 7.1 Create `neurocnl/neurocnl/training/bindsnet_adapter.py`
    - Implement `BindsNETAdapter(BaseTrainingAdapter)` with:
      - `capability = AdapterCapability(backend_name="bindsnet", supported_training_modes=("stdp", "reward_modulated_stdp"), default_training_mode="stdp", output_format="weights_only", supported_rule_kinds=("stdp", "reward_modulated_stdp"), supported_deployment_modes=("offline_train",))`.
      - `is_available()`: try `import_module("bindsnet")`; on `ImportError` return
        `TrainingAvailability(available=False, ...)` with `OPTIONAL_DEPENDENCY_MISSING` naming `"bindsnet"`.
      - `run()`: raise `AdapterSelectionError` with `NOT_IMPLEMENTED` when `deployment_mode` is
        `"online_learn"` or `"deploy_only"`; consume `learning_rules` array from payload, map
        each to BindsNET `Connection` constructor args, raise `AdapterSelectionError` on
        unsupported kind; return `TrainingResult` with non-None `learned_weights` and
        `metadata["output_format"] = "weights_only"`.
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

  - [ ] 7.2 Register `BindsNETAdapter` in `training/factory.py`
    - Import and add `BindsNETAdapter()` to the list passed to `TrainingAdapterRegistry(...)`.
    - _Requirements: 11.1_

  - [ ]* 7.3 Write PBT for `BindsNETAdapter` simulation-mode guard (Property 13)
    - **Property 13: `BindsNETAdapter` simulation-mode guard**
    - For any `deployment_mode` in `("online_learn", "deploy_only")`, assert
      `BindsNETAdapter.run(request)` raises `AdapterSelectionError` with `NOT_IMPLEMENTED`.
    - For `deployment_mode == "offline_train"` (or absent), assert no `deployment_mode` error.
    - `@settings(max_examples=100)` — tag: `Feature: nir-training-bundle, Property 13`.
    - **Validates: Requirements 11.5**

- [ ] 8. Phase 4b — Lava Online Learning Adapter
  - [ ] 8.1 Create `neurocnl/neurocnl/training/lava_online_adapter.py`
    - Implement `LavaOnlineAdapter(BaseTrainingAdapter)` with:
      - `capability = AdapterCapability(backend_name="lava", supported_training_modes=("stdp", "r-stdp"), default_training_mode="stdp", output_format="nir+stdp_config", supported_rule_kinds=("stdp", "r-stdp"), supported_deployment_modes=("online_learn",))`.
      - `is_available()`: try `import_module("lava")` (or `"lava.proc"`); on `ImportError` return
        `TrainingAvailability(available=False, ...)` with `OPTIONAL_DEPENDENCY_MISSING` naming
        `"lava-nc"`.
      - `run()`: raise `ValueError` when `learning_rules` list is empty; for each rule translate
        `"stdp"` → `_translate_to_stdp_loihi(rule)`, `"r-stdp"` → `_translate_to_rmax(rule)`;
        raise `AdapterSelectionError` on unsupported kind; return `TrainingResult` with
        `metadata["stdp_config"]` containing `{"rules": [...]}`.
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.6, 12.7_

  - [ ] 8.2 Register `LavaOnlineAdapter` in `training/factory.py`
    - Import and add `LavaOnlineAdapter()` to the `TrainingAdapterRegistry` list (replaces/extends
      any existing `"lava"` entry if present; only one adapter per backend name is allowed).
    - _Requirements: 12.1, 12.5_

  - [ ]* 8.3 Write PBT for `SnnTorchAdapter` accepts all graph input forms (Property 12)
    - **Property 12: `SnnTorchAdapter` accepts all graph input forms**
    - For any valid `nir.NIRGraph` passed as `dict` (via `ir.to_dict()`) or as `nir.NIRGraph`
      object in `payload["nir_graph"]`, assert `TrainingResult.metadata` does NOT contain
      `topology_source == "fallback_demo"`.
    - `@settings(max_examples=100)` — tag: `Feature: nir-training-bundle, Property 12`.
    - **Validates: Requirements 1.3, 1.6**

- [ ] 9. Checkpoint — Phases 4/4b complete
  - Run `PYTHONPATH=. pytest neurocnl/tests/ -x` and `ruff check .`.
  - Ensure all tests pass, ask the user if questions arise.


- [ ] 10. Phase 5 — FastAPI Bundle Endpoints
  - [ ] 10.1 Create `neurocnl/backend/app/routers/bundle.py` with FastAPI router
    - Define `router = APIRouter(prefix="/api/bundle", tags=["bundle"])`.
    - Define Pydantic request/response schemas for save, load, and export bodies.
    - _Requirements: 13.1, 13.2, 13.3, 13.4_

  - [ ] 10.2 Implement `POST /api/bundle/save` endpoint
    - Accept `bundle` (ProjectBundle serialised dict) and `path` (str) in JSON body.
    - Deserialise `ProjectBundle`, call `BundleSerializer().save(bundle, path)`.
    - Return HTTP 200 `{"absolute_path": str(resolved_path)}`.
    - Return HTTP 422 `{"error": "..."}` on `BundleLoadError` or serialisation error.
    - _Requirements: 13.1, 13.6_

  - [ ] 10.3 Implement `POST /api/bundle/load` endpoint
    - Accept `path` (str) in JSON body.
    - Return HTTP 404 `{"error": "..."}` if path does not exist.
    - Call `ProjectBundle.load(path)`, return HTTP 200 `{"network_ir": ..., "manifest": ...}`.
    - Return HTTP 422 on `BundleLoadError`.
    - _Requirements: 13.2, 13.5_

  - [ ] 10.4 Implement `POST /api/bundle/export` endpoint
    - Accept `bundle` dict and `deployment_mode` (str) in JSON body.
    - Return HTTP 422 when `deployment_mode == "online_learn"` and `target_backend != "lava"`.
    - When valid, call `BundleSerializer().export(bundle, deployment_mode)`, return
      `Response(content=zip_bytes, media_type="application/zip")`.
    - _Requirements: 13.3, 13.7, 13.8_

  - [ ] 10.5 Implement `DELETE /api/bundle/connection` endpoint (or complete stub from 3.7)
    - If the route was already added in task 3.7, ensure it is imported from `routers/bundle.py`.
    - Accept `source` and `target` as query parameters.
    - Perform snapshot-rollback atomic removal (snapshot `NetworkIR`, remove `ConnectionIR` +
      matching `LearningRuleIR`, call `regenerate_outputs()`, commit or rollback to snapshot
      and return HTTP 422).
    - Return HTTP 404 when pair not found; HTTP 200 `{"ok": true}` on success.
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 13.4, 13.9_

  - [ ] 10.6 Register bundle router in `neurocnl/backend/app/main.py`
    - Add `from backend.app.routers import bundle` import.
    - Add `app.include_router(bundle.router)` after existing router registrations.
    - _Requirements: 13.1, 13.2, 13.3, 13.4_

  - [ ]* 10.7 Write integration tests for all 5 bundle endpoints
    - In `neurocnl/backend/tests/test_bundle_router.py` using `fastapi.testclient.TestClient`.
    - `POST /api/bundle/save` returns `absolute_path` (Req 13.1).
    - `POST /api/bundle/load` returns `network_ir` and `manifest` (Req 13.2).
    - `POST /api/bundle/load` returns HTTP 404 on missing path (Req 13.5).
    - `POST /api/bundle/export` returns ZIP bytes (Req 13.3).
    - `POST /api/bundle/export` returns HTTP 422 for `online_learn` + non-lava (Req 13.7).
    - `DELETE /api/bundle/connection` returns HTTP 200 with regenerated outputs (Req 6.3).
    - `DELETE /api/bundle/connection` returns HTTP 404 on missing connection (Req 13.9).
    - `DELETE /api/bundle/connection` rolls back on serialisation error (Req 6.4).
    - _Requirements: 6.3, 6.4, 13.1, 13.2, 13.3, 13.4, 13.5, 13.7, 13.9_

- [ ] 11. Final Checkpoint — all phases complete
  - Run `PYTHONPATH=. pytest neurocnl/tests/ neurocnl/backend/tests/ -x`,
    `ruff check .`, `mypy .`, and `cd frontend && flutter test`.
  - Ensure all tests pass, ask the user if questions arise.


---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; each maps to a
  property from the design's Correctness Properties section.
- Each task references specific requirement clauses for traceability.
- Checkpoints enforce incremental validation after each phase boundary.
- Property tests use Hypothesis (`hypothesis>=6.0`). All PBTs go in
  `neurocnl/neurocnl/tests/properties/test_nir_bundle_properties.py` under the
  `@settings(profile="ci")` profile defined in the existing `conftest.py`.
- `BundleSerializer.migrate()` preserves `.nmtk.bak` before any mutation; raise
  `BundleLoadError` before creating the backup if the target version is unsupported.
- The `DELETE /api/bundle/connection` atomic removal uses a deep-copy snapshot pattern; no
  partial writes are committed to disk.
- BindsNET is simulation-only (`offline_train`); `BundleSerializer` overrides
  `manifest.deployment_mode` to `"offline_train"` for all BindsNET-produced results regardless
  of the original request value.
- `online_learn` is permanently Lava-exclusive in this release; enforcement occurs at two
  layers: `TrainingAdapterRegistry.dispatch()` and `SnnTorchAdapter.run()`.


## Task Dependency Graph

```json
{
  "waves": [
    {
      "id": 0,
      "tasks": ["0.1", "0.2"]
    },
    {
      "id": 1,
      "tasks": ["1.1"]
    },
    {
      "id": 2,
      "tasks": ["1.2", "1.4"]
    },
    {
      "id": 3,
      "tasks": ["1.3", "1.5"]
    },
    {
      "id": 4,
      "tasks": ["1.6", "1.7"]
    },
    {
      "id": 5,
      "tasks": ["1.8", "1.9", "1.10", "1.11"]
    },
    {
      "id": 6,
      "tasks": ["3.1", "3.3", "5.1", "5.2"]
    },
    {
      "id": 7,
      "tasks": ["3.2", "3.4", "5.3", "5.4"]
    },
    {
      "id": 8,
      "tasks": ["3.5", "3.6", "3.7", "5.5"]
    },
    {
      "id": 9,
      "tasks": ["3.8", "5.6", "5.7", "5.8", "5.9", "5.10"]
    },
    {
      "id": 10,
      "tasks": ["7.1", "8.1"]
    },
    {
      "id": 11,
      "tasks": ["7.2", "7.3", "8.2"]
    },
    {
      "id": 12,
      "tasks": ["8.3"]
    },
    {
      "id": 13,
      "tasks": ["10.1"]
    },
    {
      "id": 14,
      "tasks": ["10.2", "10.3", "10.4", "10.5"]
    },
    {
      "id": 15,
      "tasks": ["10.6"]
    },
    {
      "id": 16,
      "tasks": ["10.7"]
    }
  ]
}
```
