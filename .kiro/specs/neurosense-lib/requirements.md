# Requirements Document

## Introduction

NeuroSense-Lib consolidates the fragmented internal encoding scripts in the `Neurosense` submodule into a
single, production-grade Python library. It provides a unified API for converting multi-modal sensory
signals — Lidar, Radar, EMG, and EEG — into spike trains and event streams that are fully compatible with
the NIR (Neuromorphic Intermediate Representation) format used by NMTK hardware backends. The library also
exposes hardware-aware quantization algorithms that optimise spike density against the bit-width constraints
of specific neuromorphic chips, using hardware profiles sourced from the `Neurochip` module. NeuroSense-Lib
serves as the standard sensory-encoding dependency for all NMTK modules and is installable as a standalone
Python package.

---

## Glossary

- **NeuroSense_Lib**: The unified Python library being specified in this document; lives inside the `Neurosense` module at `neurosense/`.
- **Encoder**: A component within NeuroSense_Lib that converts a raw sensory signal into a spike train or event stream.
- **Spike_Train**: A time-ordered sequence of spike timestamps (and optional channel IDs) representing neural firing events produced by an Encoder.
- **Event_Stream**: An asynchronous, address-event representation compatible with event-based sensors such as event cameras; a generalisation of Spike_Train for spatial data.
- **NIR_Graph**: A Neuromorphic Intermediate Representation graph as defined by the `nir` Python package; the exchange format for spike-encoding pipelines across NMTK.
- **NIR_Service**: The existing `NIRService` class in `neurosense/app/services/nir_service.py` that writes and reads NIR_Graph objects.
- **Lidar_Encoder**: The Encoder responsible for converting Lidar point-cloud frames into Event_Streams.
- **Radar_Encoder**: The Encoder responsible for converting Radar range-Doppler frames into Spike_Trains.
- **Bio_Encoder**: The Encoder responsible for converting biosignal channels (EMG or EEG) into Spike_Trains using rate, temporal, or delta modulation; extends the existing `SpikeEncoder` service.
- **Quantizer**: The component within NeuroSense_Lib that reduces spike density or parameter precision to satisfy the bit-width constraints of a target neuromorphic chip.
- **Hardware_Profile**: A JSON-backed descriptor (e.g., `akida.json`, `loihi2.json`) in the `Neurochip` module that specifies `weight_bit_widths`, `neuron_capacity`, `power_envelope_mw`, and `pj_per_spike_op` for a given chip.
- **QuantizationConfig**: The Pydantic contract in `Neurochip/neurochip/contracts/quantization_contracts.py` that enforces target-device bit-width validity.
- **QuantizationResult**: The Pydantic contract in the same file that enforces `accuracy_loss_pct ≤ 25 %` and `spike_fidelity` bounds for a completed quantization pass.
- **EncodingConfig**: The Pydantic contract in `neurosense/contracts/encoding_contracts.py` that specifies encoding method and parameters (rate, temporal, delta).
- **Neurobench**: The NMTK benchmarking module used to validate encoder accuracy and performance.
- **neurocnl**: The NMTK compilation pipeline that consumes NIR_Graphs produced by NeuroSense_Lib.

---

## Requirements

### Requirement 1: Unified Library API

**User Story:** As an NMTK module developer, I want to import NeuroSense-Lib as a standard Python package dependency, so that I can call a consistent encoding API without copying internal scripts.

#### Acceptance Criteria

1. THE NeuroSense_Lib SHALL expose a top-level `neurosense` package importable via `import neurosense` after installation with `pip install -e .` from the `Neurosense/` workspace root.
2. THE NeuroSense_Lib SHALL provide a public `encode` function with the signature `encode(signal: Any, config: EncodingConfig, *, sampling_rate: float) -> dict` that dispatches to `Lidar_Encoder`, `Radar_Encoder`, or `Bio_Encoder` based on `config.method`.
3. THE NeuroSense_Lib SHALL expose `Lidar_Encoder`, `Radar_Encoder`, and `Bio_Encoder` as importable classes from the `neurosense.encoders` namespace.
4. THE NeuroSense_Lib SHALL export a `__version__` string in `neurosense/__init__.py` that follows semantic versioning (MAJOR.MINOR.PATCH).
5. IF a caller invokes any public Encoder method without first calling `configure()`, THEN THE NeuroSense_Lib SHALL raise a `RuntimeError` whose message includes the class name of the unconfigured Encoder.
6. THE NeuroSense_Lib SHALL include a `py.typed` marker file so that static type checkers treat the package as typed.
7. IF `encode` is called with an `EncodingConfig` whose `method` value is not one of `"rate"`, `"temporal"`, or `"delta"`, THEN THE NeuroSense_Lib SHALL raise a `ValueError` that identifies the unsupported method value and lists the valid values.

---

### Requirement 2: Lidar Encoder

**User Story:** As a robotics engineer, I want to convert Lidar point-cloud frames into NIR-compatible event streams, so that I can feed spatial sensor data into neuromorphic hardware backends.

#### Acceptance Criteria

1. WHEN a Lidar point-cloud frame is provided as a NumPy structured array with fields `x`, `y`, `z`, and `intensity` (all `float32`), THE Lidar_Encoder SHALL produce an Event_Stream containing spike timestamps and neuron addresses for every point whose `intensity` exceeds the `intensity_threshold` configured in the Lidar_Encoder (a non-negative float32 value).
2. THE Lidar_Encoder SHALL accept a `voxel_resolution` parameter (positive float in the range 0.01 m to 100.0 m) that controls the spatial binning grid used to map 3-D coordinates to neuron addresses.
3. WHEN the input point-cloud contains zero points, THE Lidar_Encoder SHALL return an Event_Stream with an empty `addresses` list, an empty `relative_timestamps_us` list, and a `counts` value of 0.
4. THE Event_Stream returned by Lidar_Encoder SHALL always have `len(addresses) == len(relative_timestamps_us)` for any valid input (shape invariant).
5. WHEN `to_nir()` is called on a configured Lidar_Encoder, THE Lidar_Encoder SHALL return a NIR_Graph such that calling `NIR_Service.write_nir(graph)` on the returned graph does not raise an exception.
6. WHEN the point-cloud contains at least one coordinate outside the per-axis (min, max) float range configured as `sensor_range`, THE Lidar_Encoder SHALL raise a `ValueError` that identifies the out-of-range value and the axis name (`x`, `y`, or `z`).
7. IF the structured array is missing any of the required fields (`x`, `y`, `z`, `intensity`) or has a dtype other than `float32` for those fields, THEN THE Lidar_Encoder SHALL raise a `ValueError` identifying the missing or invalid field before encoding begins.

---

### Requirement 3: Radar Encoder

**User Story:** As an automotive or drone systems engineer, I want to convert Radar range-Doppler frames into spike trains, so that I can process velocity and range data on neuromorphic chips.

#### Acceptance Criteria

1. WHEN a Radar range-Doppler frame is provided as a 2-D NumPy array of shape `(range_bins, doppler_bins)` with `float32` dtype, THE Radar_Encoder SHALL produce a Spike_Train where each spike corresponds to the (range_bin, doppler_bin) cell index whose power exceeds the CFAR threshold computed from `cfar_threshold_factor`, `cfar_guard_cells`, and `cfar_training_cells`.
2. THE Radar_Encoder SHALL accept `cfar_guard_cells` (non-negative integer), `cfar_training_cells` (positive integer ≥ 2), and `cfar_threshold_factor` (positive float) at configuration time; each dimension of the input frame SHALL be at least `2 * cfar_guard_cells + 2 * cfar_training_cells + 1`.
3. WHEN the Radar frame is all zeros, THE Radar_Encoder SHALL produce a Spike_Train with `spike_counts == 0`.
4. THE Spike_Train returned by Radar_Encoder SHALL always have `spike_counts <= range_bins * doppler_bins` for any valid input (upper-bound invariant).
5. WHEN `to_nir()` is called on a configured Radar_Encoder, THE Radar_Encoder SHALL return a NIR_Graph such that calling `NIR_Service.write_nir(graph)` on the returned graph does not raise an exception.
6. IF `cfar_training_cells` is less than 2 at configuration time, THEN THE Radar_Encoder SHALL raise a `ValueError` naming the parameter and the minimum value before any frame is processed.
7. IF the input array is not 2-D, does not have `float32` dtype, or any dimension is smaller than the minimum required by the CFAR window, THEN THE Radar_Encoder SHALL raise a `ValueError` identifying the violated constraint before processing begins.

---

### Requirement 4: Bio-Sensor Encoder (EMG and EEG)

**User Story:** As a BCI researcher, I want to encode EMG and EEG biosignal channels into spike trains using rate, temporal, or delta modulation, so that I can drive neuromorphic models with biological input.

#### Acceptance Criteria

1. WHEN a biosignal array of shape `(channels, samples)` with `float32` dtype and `channels ≥ 1` and an EncodingConfig specifying `method="rate"` are provided, THE Bio_Encoder SHALL produce a Spike_Train whose `spike_trains` list contains exactly `channels` entries, each a list of non-negative float spike times in seconds.
2. WHEN a biosignal array of shape `(channels, samples)` with `float32` dtype and `channels ≥ 1` and an EncodingConfig specifying `method="temporal"` are provided, THE Bio_Encoder SHALL produce a Spike_Train whose `spike_trains` list contains exactly `channels` entries, each a list of non-negative float spike times in seconds.
3. WHEN a biosignal array of shape `(channels, samples)` with `float32` dtype and `channels ≥ 1` and an EncodingConfig specifying `method="delta"` are provided, THE Bio_Encoder SHALL produce a Spike_Train whose `spike_trains` list contains exactly `channels` entries, each a list of non-negative float spike times in seconds.
4. WHEN the same biosignal array, EncodingConfig, and integer `seed` (passed to `configure()`) are used on two separate `encode()` calls, THE Bio_Encoder SHALL produce identical `spike_trains` lists (determinism invariant).
5. WHEN a biosignal array containing only zero-valued samples is provided with `method="delta"`, THE Bio_Encoder SHALL produce a Spike_Train where every entry in `spike_trains` is an empty list `[]`.
6. WHEN `to_nir()` is called on a Bio_Encoder configured with any valid EncodingConfig, THE Bio_Encoder SHALL return a NIR_Graph that (a) does not raise an exception when passed to `NIR_Service.write_nir()`, and (b) when subsequently read back via `NIR_Service.read_nir()` produces a NIR_Graph that yields the same `method` value and all method-specific parameters when converted via `NIR_Service.nir_to_encoding_config()`.
7. IF an EncodingConfig is missing a required method-specific parameter (`rate_max_hz` for `method="rate"`, `threshold` for `method="temporal"`, `delta` for `method="delta"`), THEN THE Bio_Encoder SHALL raise a `pydantic.ValidationError` before encoding begins.
8. IF the biosignal array has fewer than 2 samples, THEN THE Bio_Encoder SHALL raise a `ValueError` whose message states that a minimum of 2 samples is required.

---

### Requirement 5: NIR Round-Trip Compliance

**User Story:** As a pipeline engineer integrating with neurocnl, I want to serialize and deserialize encoder configurations through NIR, so that encoding graphs can be exchanged between NMTK modules without data loss.

#### Acceptance Criteria

1. THE NIR_Service SHALL be able to convert any valid EncodingConfig with `method` in `{"rate", "temporal", "delta"}` to a NIR_Graph via `encoding_config_to_nir()` and back via `nir_to_encoding_config()`, producing an EncodingConfig with the same `method` value and all method-specific parameter values as the original (round-trip property).
2. WHEN a NIR_Graph is written to a file using `NIR_Service.write_nir()` and then read back using `NIR_Service.read_nir()`, THE NIR_Service SHALL return a NIR_Graph whose node keys, node parameter values, and edge list are identical to the original (serialisation round-trip); the recognisable node types are those defined in `neurosense/app/services/nir_service.py::RECOGNISABLE_NODE_TYPES`.
3. WHEN a NIR_Graph produced by `neurocnl` that contains at least one recognisable node type is passed to `NIR_Service.nir_to_encoding_config()`, THE NIR_Service SHALL return an EncodingConfig without raising an exception.
4. WHEN a NIR_Graph that contains no recognisable encoder node is passed to `NIR_Service.nir_to_encoding_config()`, THE NIR_Service SHALL return a default EncodingConfig with `method="rate"` and `rate_max_hz=200.0` without raising an exception.
5. WHEN `NIR_Service.encoding_config_to_nir()` is called for a `method="temporal"` EncodingConfig, THE NIR_Service SHALL include all temporal-encoding-specific parameters in the NIR_Graph, and the round-trip SHALL recover those values without loss.

---

### Requirement 6: Hardware-Aware Quantization

**User Story:** As a hardware engineer targeting Akida or Loihi 2, I want to quantize spike-encoded outputs to the bit-width constraints of my target chip, so that the encoded data fits within the hardware's capacity without exceeding accuracy loss budgets.

#### Acceptance Criteria

1. WHEN a Spike_Train and a QuantizationConfig specifying `target_device=TargetDevice.AKIDA` and `bit_width=4` are provided, THE Quantizer SHALL return a QuantizationResult where `bit_width` is 4 and `accuracy_loss_pct` is ≤ 25.0.
2. WHEN a Spike_Train and a QuantizationConfig specifying `target_device=TargetDevice.LOIHI_2` and `bit_width=8` are provided, THE Quantizer SHALL return a QuantizationResult where `bit_width` is 8 and `accuracy_loss_pct` is ≤ 25.0.
3. THE `spike_fidelity` field of the QuantizationResult SHALL be greater than 0.0 for any Spike_Train and QuantizationConfig where `bit_width` is present in the target device's `weight_bit_widths` list.
4. WHEN a QuantizationConfig specifies a `bit_width` not present in the target device's `weight_bit_widths` list, THE Quantizer SHALL raise a `pydantic.ValidationError` at model instantiation time, before any quantization processing begins.
5. THE Quantizer SHALL produce a `QuantizationResult.accuracy_loss_pct` that is less than or equal to the `accuracy_loss_pct` produced for the same Spike_Train and the same target device with a lower `bit_width` (monotonicity property); all other NetworkInput fields are held constant between the two comparisons.
6. WHEN quantizing a Spike_Train for a given `target_device`, THE Quantizer SHALL use the chip parameters (`weight_bit_widths`, `neuron_capacity`, `power_envelope_mw`, `pj_per_spike_op`) exactly as read from the Hardware_Profile JSON file at `Neurochip/neurochip/targets/{target_device}.json`.
7. IF the Hardware_Profile JSON file for the requested `target_device` does not exist at the expected path, THEN THE Quantizer SHALL raise a `FileNotFoundError` whose message includes the full expected file path.

---

### Requirement 7: Preset Encoding Pipelines

**User Story:** As a developer who does not want to configure each stage manually, I want to apply a named preset that bundles signal filtering, encoding method, and quantization target into a single callable, so that I can produce hardware-ready spike trains in one step.

#### Acceptance Criteria

1. THE NeuroSense_Lib SHALL ship with at least four built-in presets available at import time: `"emg_prosthetic"`, `"eeg_alpha_bci"`, `"lidar_obstacle_detection"`, and `"radar_velocity_tracking"`.
2. WHEN `neurosense.encode_with_preset(signal, preset_name, *, hardware_target)` is called, THE NeuroSense_Lib SHALL apply the preset's filter configuration before encoding, and SHALL apply hardware-aware quantization only when `hardware_target` is not `None`.
3. WHEN `hardware_target` is not `None`, THE QuantizationConfig constructed internally SHALL use the `weight_bit_widths` list read from the Hardware_Profile JSON file for `hardware_target`, with no bit-width values hardcoded in the preset definition.
4. IF `preset_name` is not a key in the built-in or registered preset registry, THEN THE NeuroSense_Lib SHALL raise a `KeyError` whose message lists all currently available preset names.
5. THE NeuroSense_Lib SHALL allow callers to register a custom preset at runtime via `neurosense.register_preset(name, preset_config)`; a subsequent call to `encode_with_preset` with that `name` SHALL use the registered `preset_config`.
6. WHEN `encode_with_preset(signal, preset_name, hardware_target=None)` is called twice in succession with the same `signal` and `preset_name` and no intervening `register_preset` call, THE NeuroSense_Lib SHALL return identical output dictionaries (idempotence property).

---

### Requirement 8: Neurobench Validation Integration

**User Story:** As a research engineer, I want to run NeuroSense-Lib encoding outputs through Neurobench benchmarks, so that I can measure and report encoder accuracy against standardised neuromorphic datasets.

#### Acceptance Criteria

1. THE Spike_Train returned by any NeuroSense_Lib Encoder SHALL be directly passable to the `Neurobench` benchmark harness entry point without requiring a caller-side format conversion step.
2. WHEN `neurosense.to_neurobench_format(spike_train)` is called, THE NeuroSense_Lib SHALL return a `dict` containing at minimum the keys `"spike_times"` (list of lists of floats), `"channel_ids"` (list of ints), and `"metadata"` (dict).
3. THE `neurosense.to_neurobench_format` function SHALL be importable and callable in a Python environment where `Neurobench` is not installed; importing `neurosense` SHALL NOT attempt to import any symbol from the `Neurobench` package at module level.

---

### Requirement 9: Hardware-Bridge and Testability

**User Story:** As a CI engineer, I want all NeuroSense-Lib encoding and quantization paths to be testable without physical neuromorphic hardware attached, so that the CI pipeline can validate correctness on every commit.

#### Acceptance Criteria

1. THE NeuroSense_Lib SHALL provide `neurosense.simulate_lidar_frame()`, `neurosense.simulate_radar_frame()`, and `neurosense.simulate_biosignal()` functions that return NumPy arrays of the correct shape and dtype for each Encoder without requiring a physical device.
2. THE NeuroSense_Lib SHALL NOT import `metavision_sdk`, `brainflow`, `pynq`, or any symbol from other hardware-only packages at module level; each such import SHALL be wrapped in a `try/except ImportError` block consistent with the pattern in `spike_encoder.py`; IF any of these packages is imported at module level during a pytest session, the affected test SHALL fail with an `AssertionError` identifying the forbidden import by name.
3. THE NeuroSense_Lib SHALL produce zero test failures when the full test suite is executed with `PYTHONPATH=neurosense pytest neurosense/tests/` on a machine with no physical neuromorphic hardware connected.
4. WHEN `python neurosense/tests/verify_hardware_bridge.py` is executed and the process exits normally (not killed or interrupted), THE script SHALL exit with code 0 when no physical device is detected and the simulated path is active.
