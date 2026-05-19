# Requirements Document

## Introduction

NeuroTrain is a model optimization pipeline integrated directly into the `neurocnl` compilation pipeline as a sequence of passes. It bridges the gap between public SNN frameworks (snnTorch, Norse, Lava) and NMTK's hardware backends by providing native tooling for three tightly coupled capabilities:

1. **ANN-to-SNN Conversion** — converting standard PyTorch-based ANN or SNN models from snnTorch, Norse, Lava, or plain PyTorch into NIR-compatible graphs within the toolkit.
2. **Quantization-Aware Fine-Tuning** — hardware-specific weight optimization using `Neurochip` hardware profiles (Akida, Loihi 2, Xylo / PYNQ-Z2) respecting each target's bit-width constraints.
3. **Structural Optimization** — pruning and topology merging passes attached to the `neurocnl` IR materializer for energy efficiency.

All three workstreams share a single design constraint: their output must be a valid `nir.NIRGraph` that is consumable by the existing `neurocnl` → hardware deployment pipeline without modification to downstream consumers.

The feature lives primarily in `neurocnl/neurocnl/` (library) and `neurocnl/backend/` (API routes). It reuses and extends the existing `TrainingAdapterRegistry`, `ModelConverter` / `pivot.py`, and `transforms/quantise.py` infrastructure.

---

## Glossary

- **ANN**: Artificial Neural Network — a standard deep learning model with continuous activations.
- **SNN**: Spiking Neural Network — a network where information is carried by discrete spike events over time.
- **NIR** / **NIR Graph**: Neuromorphic Intermediate Representation — the common graph format (`nir.NIRGraph`) used as the interchange format between compilation and hardware deployment.
- **CNL**: Controlled Natural Language — the domain-specific language owned by `neurocnl` for authoring SNN specs.
- **Converter**: The NeuroTrain subsystem that converts an external framework model into an `nir.NIRGraph`.
- **QuantizationPass**: The NeuroTrain optimization pass that applies hardware-aware weight quantization to an `nir.NIRGraph`, using `QuantizationConfig` constraints from `Neurochip`.
- **StructuralOptimizationPass**: The NeuroTrain optimization pass that prunes low-magnitude synaptic connections and merges compatible neuron populations.
- **NeuroTrainPipeline**: The top-level orchestrator that sequences Conversion → Quantization → Structural Optimization and emits a final `nir.NIRGraph`.
- **TargetDevice**: The hardware target enum (`neurochip.contracts.deployment_contracts.TargetDevice`) whose bit-width constraints govern the QuantizationPass.
- **TrainingAdapterRegistry**: The existing adapter dispatch mechanism in `neurocnl/neurocnl/training_registry.py`.
- **ConversionError**: A structured exception raised by the Converter, carrying a list of `Diagnostic` objects.
- **OptimizationError**: A structured exception raised by StructuralOptimizationPass when a graph cannot be optimized without violating structural invariants.
- **QAT**: Quantization-Aware Training — fine-tuning while simulating integer quantization during the forward pass.
- **HardwareProfile**: The `neurochip.contracts.hardware_contracts.HardwareProfile` Pydantic model.

---

## Requirements

### Requirement 1: ANN-to-SNN Conversion

**User Story:** As an NMTK developer, I want to convert a trained PyTorch ANN or snnTorch/Norse/Lava SNN model into an NIR-compatible graph inside the toolkit, so that I can leverage existing trained weights without re-authoring the network in CNL.

#### Acceptance Criteria

1. WHEN a caller provides a PyTorch `nn.Module` as input with `source_framework="pytorch"`, THE Converter SHALL produce an `nir.NIRGraph` that contains at least one `nir.LIF` node and at least one `nir.Linear` node.
2. WHEN a caller provides a snnTorch model as input, THE Converter SHALL extract `Leaky` and `Synaptic` neuron layers and map them to `nir.LIF` and `nir.Linear` NIR nodes respectively.
3. WHEN a caller provides a Norse model as input, THE Converter SHALL extract `LIF` and `Linear` functional layers and map them to `nir.LIF` and `nir.Linear` NIR nodes respectively.
4. WHEN a caller provides a Lava process graph as input, THE Converter SHALL delegate to the existing `LavaIO.to_nir()` method; IF `LavaIO.to_nir()` raises an exception, THE Converter SHALL wrap it in a `ConversionError` with the original exception message as `Diagnostic.message` and `code="lava_io_error"`.
5. IF the source model contains a layer type that the Converter cannot map to a supported NIR node type, THEN THE Converter SHALL raise a `ConversionError` containing at least one `Diagnostic` with a non-empty machine-readable `code` and a non-empty human-readable `message` identifying the unmappable layer, and SHALL NOT produce any `nir.NIRGraph` output.
6. THE Converter SHALL expose a `convert(model, source_framework)` method that accepts `source_framework` values of `"pytorch"`, `"snntorch"`, `"norse"`, and `"lava"` and returns an `nir.NIRGraph`; IF `source_framework` is any other value, THE Converter SHALL raise a `ConversionError` with `code="unsupported_framework"` listing the four valid values.
7. IF the optional dependency for `source_framework` is not installed when `convert()` is called, THEN THE Converter SHALL raise a `ConversionError` with `code="optional_dependency_missing"` and a `dependency_name` field set to the missing package name.
8. THE Converter SHALL produce an `nir.NIRGraph` where the total input dimensionality across all `nir.Input` nodes equals the source model's input dimensionality, and the total output dimensionality across all `nir.Output` nodes equals the source model's output dimensionality (I/O shape preservation property).
9. THE `nir.NIRGraph` returned by the Converter SHALL include a `metadata["conversion_summary"]` dict containing `source_framework` (string), `source_layer_count` (non-negative integer), and `nir_node_count` (positive integer).

---

### Requirement 2: Quantization-Aware Fine-Tuning

**User Story:** As an NMTK developer, I want to fine-tune a converted or native SNN model with hardware-specific weight quantization constraints, so that the resulting model is ready for deployment on a specific Neurochip target without violating that target's bit-width requirements.

#### Acceptance Criteria

1. THE QuantizationPass SHALL read all hardware bit-width constraints from a `QuantizationConfig` instance sourced from `neurochip.contracts.quantization_contracts` and SHALL NOT hardcode any bit-width limits or device parameters.
2. WHEN `QuantizationPass.quantize(graph, config)` is applied, every `nir.Linear` weight tensor in the returned `nir.NIRGraph` SHALL contain only integer values in the closed range `[-(2^(bit_width-1)), 2^(bit_width-1) - 1]` for the `config.bit_width` value.
3. IF `config.target_device` and `config.bit_width` together identify a combination not present in `QuantizationConfig.SUPPORTED_BIT_WIDTHS`, THEN THE QuantizationPass SHALL raise a `ValueError` before any weight modification, with a message naming the unsupported device and listing its supported bit-widths.
4. WHEN `QuantizationPass.quantize(graph, config)` is applied, all `nir.LIF`, `nir.Input`, `nir.Output`, and `nir.Delay` nodes and all edges in the input graph SHALL appear in the returned graph with parameter values unchanged.
5. WHERE `config.layer_configs` contains an entry for a named `nir.Linear` node, THE QuantizationPass SHALL quantize that node using the override `bit_width` from `layer_configs` rather than `config.bit_width`.
6. THE `quantize(graph, config)` method SHALL return a new `nir.NIRGraph` and SHALL NOT modify any field of the input `graph`.
7. THE returned `nir.NIRGraph` SHALL include a `metadata["quantization"]` dict with fields `target_device` (string), `bit_width` (integer), and `scale_factor` (float), matching the schema in `transforms/quantise.py`.
8. WHEN QAT fine-tuning runs with `n_epochs ≥ 1` and all epoch loss values are finite floats, THE QuantizationPass SHALL set `loss_curve` to a tuple of exactly `n_epochs` finite floats where `loss_curve[-1] <= loss_curve[0]`; WHEN training does not run (n_epochs=0) or any loss value is NaN or infinite, THE QuantizationPass SHALL set `loss_curve` to an empty tuple `()`.
9. IF `torch` or `snntorch` is not installed, THEN `QuantizationPass.is_available()` SHALL return a dict with `available: False` and `code: "optional_dependency_missing"` naming the first missing package.

---

### Requirement 3: Structural Optimization

**User Story:** As an NMTK developer, I want to reduce the synaptic connection count and merge compatible neuron populations in an NIR graph, so that the resulting model has lower energy consumption and fits within the resource constraints of target neuromorphic hardware.

#### Acceptance Criteria

1. WHEN `StructuralOptimizationPass.optimize(graph, pruning_threshold, merge_populations)` is applied with `pruning_threshold` in (0, 1], THE pass SHALL set to zero every weight entry in each `nir.Linear` weight matrix whose absolute value is strictly less than `pruning_threshold × max(|weight|)` for that matrix; IF `max(|weight|) = 0` for a matrix, THE pass SHALL leave that matrix unchanged.
2. THE connectivity check SHALL run before any weight entries are zeroed; IF the pruning threshold would reduce to zero all non-zero weights on every path between any `nir.Input` and any `nir.Output` node, THEN THE StructuralOptimizationPass SHALL raise an `OptimizationError` identifying the disconnected path before modifying any weights.
3. WHEN `merge_populations=True` and two or more `nir.LIF` nodes share identical `tau`, `v_threshold`, `v_leak`, and `r` parameter arrays AND share the same set of source node identities on all incoming edges AND the same set of target node identities on all outgoing edges, THE pass SHALL merge them into a single `nir.LIF` node with `n_neurons` equal to the sum of the originals' `n_neurons`, rewiring all edges from/to the eliminated nodes to/from the merged node.
4. THE `optimize` method SHALL accept `pruning_threshold` as a required float argument and `merge_populations` defaulting to `False`, and SHALL return a new `nir.NIRGraph` without mutating any field of the input graph.
5. THE non-zero entry count across all `nir.Linear` weight matrices in the output graph SHALL be less than or equal to the non-zero entry count in the input graph for any valid input (non-increasing synapse count property).
6. WHEN `merge_populations=True`, THE `nir.LIF` node count in the output graph SHALL be less than or equal to the `nir.LIF` node count in the input graph (non-increasing population count property).
7. THE returned `nir.NIRGraph` SHALL include a `metadata["optimization_summary"]` dict with fields: `pruned_connection_count` (non-negative integer: number of entries set to zero by this pass), `merged_population_count` (non-negative integer: number of `nir.LIF` nodes eliminated by merging), `input_synapse_count` (non-negative integer: non-zero entries in input graph), and `output_synapse_count` (non-negative integer: non-zero entries in output graph).
8. IF `pruning_threshold` is not in the range (0, 1], THEN THE StructuralOptimizationPass SHALL raise a `ValueError` naming the parameter and the valid range before any graph modification.

---

### Requirement 4: NeuroTrain Pipeline Integration

**User Story:** As an NMTK developer, I want the NeuroTrain passes to integrate as a named sequence in the `neurocnl` compilation pipeline, so that I can invoke ANN-to-SNN conversion, quantization, and structural optimization from a single entry point that produces a deployment-ready NIR graph.

#### Acceptance Criteria

1. THE NeuroTrainPipeline SHALL expose `run(model, source_framework, target_device, *, pruning_threshold, merge_populations, n_epochs, quantization_config)` that executes Conversion → Quantization → Structural Optimization in that order and returns a `NeuroTrainResult`.
2. WHEN `run()` completes without any pass raising an exception, THE NeuroTrainPipeline SHALL return a `NeuroTrainResult` with: `nir_graph` (final `nir.NIRGraph`), `conversion_summary` (dict), `quantization` (dict), `optimization_summary` (dict), `status="completed"`, and `error=None`.
3. WHEN any pass raises a `ConversionError`, `ValueError`, or `OptimizationError`, THE NeuroTrainPipeline SHALL stop execution of subsequent passes, set `status="failed"`, and set `error` to the exception's string representation; THE exception SHALL NOT propagate to the caller.
4. THE NeuroTrainPipeline SHALL be a subclass of `BaseTrainingAdapter` registered in `TrainingAdapterRegistry` with `backend_name="neurotrain"` and `supported_training_modes=("convert_and_optimize",)`.
5. WHEN `TrainingAdapterRegistry.dispatch("neurotrain", ...)` is called, THE NeuroTrainPipeline SHALL return a `TrainingResult` with `adapter_name="neurotrain"` and `status` of either `"completed"` or `"failed"`, matching the existing adapter protocol.
6. WHEN `run()` returns `status="completed"`, the `nir_graph` in the result SHALL be accepted by `neurocnl.compile.compile_to_nir()` without raising a `CompileError` (consumability property).
7. IF all of `torch`, `snntorch`, and `nir` are installed, THEN `NeuroTrainPipeline.is_available()` SHALL return `{"available": True}`.
8. IF any of `torch`, `snntorch`, or `nir` is not installed, THEN `NeuroTrainPipeline.is_available()` SHALL return `{"available": False, "reason": {"code": "optional_dependency_missing", "dependency_name": "<first missing package name>"}}`.
9. WHEN `run()` is called with `source_framework="lava"`, `target_device=TargetDevice.LOIHI_2`, and no explicit `quantization_config`, THE NeuroTrainPipeline SHALL auto-construct a `QuantizationConfig` using `QuantizationConfig.SUPPORTED_BIT_WIDTHS[TargetDevice.LOIHI_2]` and complete without error for a well-formed Lava process graph.

---

### Requirement 5: Backend API Exposure

**User Story:** As a CNL Studio user, I want to invoke NeuroTrain operations through the `neurocnl` backend API, so that I can trigger model conversion and optimization from the Studio UI without writing Python.

#### Acceptance Criteria

1. THE Backend SHALL expose `POST /api/neurotrain/run` accepting a JSON body with required fields `source_framework` (string), `target_device` (string), `pruning_threshold` (float), `merge_populations` (boolean), `n_epochs` (integer ≥ 0), and optional `quantization_config` (object); on acceptance it SHALL return HTTP 202 with a JSON body containing `job_id` (string UUID).
2. IF `source_framework` in a `POST /api/neurotrain/run` request is not one of `"pytorch"`, `"snntorch"`, `"norse"`, `"lava"`, THEN THE Backend SHALL return HTTP 422 with a JSON error body that includes both the received value and the list of valid values.
3. IF the required optional dependencies are not installed when `POST /api/neurotrain/run` is called, THEN THE Backend SHALL return HTTP 422 with a JSON error body containing `"code": "optional_dependency_missing"` and SHALL NOT return HTTP 500.
4. THE Backend SHALL expose `GET /api/neurotrain/capabilities` returning a JSON object in the same schema as `GET /api/training/capabilities`, reflecting the current `NeuroTrainPipeline.is_available()` result.
5. WHEN a NeuroTrain job reaches `status="completed"`, `GET /api/neurotrain/jobs/{job_id}/result` SHALL return HTTP 200 with the serialized `nir.NIRGraph` as an HDF5 binary body and `Content-Type: application/octet-stream`; WHEN the job is not yet complete, THE endpoint SHALL return HTTP 202; WHEN the job does not exist, THE endpoint SHALL return HTTP 404.
6. IF `target_device` and `bit_width` (from `quantization_config.bit_width` or the default) are incompatible per `QuantizationConfig.SUPPORTED_BIT_WIDTHS`, THEN THE Backend SHALL return HTTP 422 before dispatching the job, with a JSON error body that names the conflicting device and lists its supported bit-widths.

---

### Requirement 6: Parser and Serialization Contracts

**User Story:** As an NMTK developer, I want NeuroTrain's intermediate representations to serialize and deserialize correctly, so that pipeline results can be persisted, inspected, and re-loaded without data loss.

#### Acceptance Criteria

1. THE `NeuroTrainResult` class SHALL expose a `to_dict()` method returning a JSON-serializable `dict`, and a `from_dict(d)` class method reconstructing a `NeuroTrainResult` from that dict.
2. FOR ANY valid `NeuroTrainResult r`, `NeuroTrainResult.from_dict(r.to_dict())` SHALL produce an object whose `conversion_summary`, `quantization`, `optimization_summary`, `status`, and `error` fields are equal to those of `r`; the `nir_graph` field SHALL be excluded from `to_dict()` / `from_dict()` and round-tripped separately via `nir.write` / `nir.read`.
3. THE `NeuroTrainResult` class SHALL expose `save(path: str)` that writes the NIR graph to `{path}.nir` using `nir.write` and all other fields to `{path}.json` as UTF-8 JSON; and a `load(path: str)` class method that reads both files and reconstructs the `NeuroTrainResult`.
4. WHEN `save(path)` is called and the parent directory of `path` does not exist, THE `NeuroTrainResult` SHALL create all necessary parent directories before writing the files.
5. IF `load(path)` is called and `{path}.nir` does not exist, THEN THE `NeuroTrainResult` SHALL raise a `FileNotFoundError` whose message names the missing `{path}.nir` file; IF `{path}.json` does not exist, THE `NeuroTrainResult` SHALL raise a `FileNotFoundError` naming `{path}.json`; both checks SHALL occur before any file is read.
