# Requirements Document

## Introduction

The Neuromorphic Datasets feature centralises and standardises neuromorphic dataset
infrastructure across NMTK. Currently scattered across the `Neurobench` module and ad-hoc
scripts, this initiative creates four cohesive workstreams:

1. **Event-ification Pipelines** — convert legacy frame-based video, audio, and tabular
   signal datasets into NMTK-standard `.h5` event streams using `Neurosense` encoding utilities.
2. **Synthetic Data Generators** — extend the existing `neurobench dataset` CLI and
   validation suites with physics-informed generators for robotic tactile and
   proprioceptive spike data.
3. **Neurohub Integration** — publish and retrieve Dataset artefacts via the Neurohub
   Global Registry using `neurohub://` URIs.
4. **NMTK UI Integration** — one-click dataset download and experiment tracking
   integration in the `nmtk_ui_core`-based desktop application.

Primary module: `Neurobench`. Cross-module integration: `Neurohub` (hosting),
`nmtk_ui_core` (UI), `Neurosense` (encoding utilities), `neurocli` (CLI scaffolding).

---

## Glossary

- **Dataset_Pipeline**: A configurable, reproducible pipeline that reads a legacy source and writes a normalised `.h5` event stream file.
- **Event_Stream**: A sparse sequence of `(neuron_id, time_ms)` pairs stored in HDF5 COO format.
- **HDF5_File**: An HDF5 binary file (`.h5`) carrying an Event_Stream or raw spike tensor plus provenance attributes.
- **Synthetic_Generator**: A deterministic, seed-driven `DatasetGenerator` subclass that produces benchmark-grade spike data without live sensor hardware.
- **Tactile_Generator**: A Synthetic_Generator for robotic fingertip tactile spike data.
- **Proprioceptive_Generator**: A Synthetic_Generator for joint angle and torque spike data.
- **Validation_Suite**: The four statistical validators (`firing_stats`, `sparsity`, `separability`, `temporal_stats`) that every generated HDF5_File must pass.
- **Dataset_Artefact**: A Registry artefact of type `dataset` stored with a `neurohub://dataset/{owner}/{slug}@{version}` URI.
- **neurohub_CLI**: The `neurohub` sub-command group within `neurocli`.
- **Dataset_Card**: A structured metadata document attached to a Dataset_Artefact.
- **ExperimentTracker**: The `ExperimentTracker` class used to record dataset events into `manifest.yaml` output files.
- **Download_Manager**: The Neurobench backend service responsible for resolving a `neurohub://` URI and downloading the Dataset_Artefact blob.
- **Dataset_Browser**: The Flutter widget panel that lists available Dataset_Artefacts and exposes a one-click download action.
- **Preset**: One of three generation size targets — `smoke` (CI), `medium` (development), or `large` (publication-grade).
- **Neurosense_Encoder**: An encoding utility from the `Neurosense` module that converts raw signals into spike trains.

---

## Requirements

---

### Requirement 1: Event-ification Pipeline Infrastructure

**User Story:** As a neuromorphic data engineer, I want a centralised pipeline framework for converting legacy datasets into NMTK-standard event streams, so that I can produce `.h5` event stream files that downstream benchmarks and models can consume directly.

#### Acceptance Criteria

1. THE Dataset_Pipeline SHALL accept a source descriptor specifying: `dataset_type` (one of `video_frames`, `audio`, `tabular`), `source_path` (path to source data), and `encoder_name` (a registered Neurosense_Encoder name); IF `encoder_name` is not registered, THE Dataset_Pipeline SHALL raise a `ValueError` identifying the unrecognised name before any file I/O.
2. IF the specified `source_path` does not exist or cannot be read, THEN THE Dataset_Pipeline SHALL raise an `IOError` identifying the path before attempting to create the output file.
3. IF the specified `output_path` already exists, THEN THE Dataset_Pipeline SHALL raise a `FileExistsError` and halt without overwriting or creating any new files.
4. WHEN a Dataset_Pipeline is executed against a valid source, THE Dataset_Pipeline SHALL produce a single HDF5_File at `output_path` containing an Event_Stream with COO layout (`neuron_id`, `time_ms`, `trial_id` datasets) and five provenance attributes: `neurobench_generator_version`, `seed`, `generated_at` (ISO 8601 UTC), `hostname`, and `content_sha256`.
5. THE Dataset_Pipeline SHALL write the output HDF5_File in chunks of at most 256 MB and SHALL NOT hold the full converted dataset in memory; peak RAM per pipeline process SHALL NOT exceed 8 GB.
6. WHEN a Dataset_Pipeline completes successfully, THE Validation_Suite SHALL automatically run `firing_stats`, `sparsity`, and `temporal_stats` on the output HDF5_File.
7. IF any of the three automatic validators fail, THEN THE Dataset_Pipeline SHALL delete the output HDF5_File and return a structured error containing, for each failing validator: its name, the observed value, and the expected valid range.
8. THE Dataset_Pipeline SHALL accept `--seed` (integer 0–2,147,483,647, defaulting to `42`) and derive per-worker seeds as `worker_seed = seed + worker_id * 1000` where `worker_id` is a zero-based sequential integer.
9. THE Dataset_Pipeline SHALL be invocable via `neurobench dataset eventify --source <path> --encoder <name> --output <path> [--seed <int>]`.
10. WHERE the `simulation` optional extra is installed, THE Dataset_Pipeline SHALL use the `Neurosense` GPU encoding path; WHERE it is not installed, THE Dataset_Pipeline SHALL use the CPU path and emit a single line to stderr: `WARNING: simulation extra not installed, using CPU encoding`.

---

### Requirement 2: Tactile Spike Data Generator

**User Story:** As a robotics researcher, I want a physics-informed generator for robotic fingertip tactile spike data, so that I can produce controllable, parametric spike patterns for benchmarking grip and touch tasks without requiring real robot hardware.

#### Acceptance Criteria

1. THE Tactile_Generator SHALL extend `DatasetGenerator` from `neurobench/data/generators/base.py` and implement `generate(config, output_path)` and `validate(path)`.
2. WHEN invoked with a valid config, THE Tactile_Generator SHALL produce an HDF5_File containing: `spikes` of shape `[N_trials, T_ms, N_taxels]` dtype `bool`; `pressure_maps` of shape `[N_trials, T_ms, N_taxels]` dtype `float32` (values in Pascals); `labels` of shape `[N_trials]` dtype `uint8`.
3. THE Tactile_Generator SHALL accept: `n_taxels` (integer 1–256, default 64), `n_trials` (positive integer), `duration_ms` (positive integer), `contact_types` (non-empty list of uint8 class labels), `snr_db` (float), `seed` (integer ≥ 0, default 42).
4. IF `n_taxels` is outside 1–256, `n_trials` ≤ 0, `duration_ms` ≤ 0, or `seed` < 0, THEN THE Tactile_Generator SHALL raise a `ValueError` naming the invalid field and its constraint before any file I/O.
5. WHEN run twice on the same machine with identical `seed` and `config`, THE Tactile_Generator SHALL produce files whose `spikes` datasets are byte-for-byte identical; the `content_sha256` attributes SHALL be equal (determinism property).
6. WHEN `validate(path)` is called on a completed HDF5_File, THE Validation_Suite SHALL check: mean taxel firing rate in 1–300 Hz; event density in 0.1–5%; LDA cross-validation accuracy over `labels` > 60%; returning a structured report with PASS/FAIL per check.
7. THE Tactile_Generator SHALL be invocable via `neurobench dataset generate tactile_spikes` and SHALL support `smoke` (~500 trials), `medium` (~5000 trials), and `large` (~20000 trials) Presets.
8. IF `generate` encounters an unrecoverable error (invalid config or IO failure), THE Tactile_Generator SHALL leave any partially-written HDF5_File in place for inspection and SHALL raise a `DatasetGenerationError` identifying the failed parameter or IO path.

---

### Requirement 3: Proprioceptive Spike Data Generator

**User Story:** As a robotics researcher, I want a physics-informed generator for joint angle and torque spike data, so that I can produce parametric proprioceptive spike patterns for benchmarking motor control tasks.

#### Acceptance Criteria

1. THE Proprioceptive_Generator SHALL extend `DatasetGenerator` from `neurobench/data/generators/base.py` and implement `generate(config, output_path)` and `validate(path)`.
2. WHEN invoked with a valid config, THE Proprioceptive_Generator SHALL produce an HDF5_File containing: `spikes` of shape `[N_trials, T_ms, N_joints * 2]` dtype `bool`; `kinematics` of shape `[N_trials, T_ms, N_joints, 2]` dtype `float32` (angle in radians, torque in N·m); `labels` of shape `[N_trials]` dtype `uint8`.
3. THE Proprioceptive_Generator SHALL accept: `n_joints` (integer 1–32, default 7), `n_trials` (positive integer), `duration_ms` (positive integer), `movement_types` (non-empty list of uint8 labels), `snr_db` (float), `seed` (integer ≥ 0, default 42).
4. IF `n_joints` is outside 1–32 or `seed` < 0, THEN THE Proprioceptive_Generator SHALL raise a `ValueError` naming the invalid field and its constraint before any file I/O.
5. WHERE `robot_type` is provided in config, THE Proprioceptive_Generator SHALL validate `n_joints` against that robot's valid joint range; IF incompatible, THEN THE Proprioceptive_Generator SHALL raise a `ValueError` identifying the robot type, its valid joint range, and the supplied `n_joints` value before any file I/O.
6. WHEN run twice on the same machine with identical `seed` and `config`, THE Proprioceptive_Generator SHALL produce files whose `spikes` datasets are byte-for-byte identical.
7. WHEN `validate(path)` is called, THE Validation_Suite SHALL check: mean per-joint channel firing rate in 1–300 Hz; event density in 0.1–5%; LDA accuracy over `labels` > 60%.
8. THE Proprioceptive_Generator SHALL be invocable via `neurobench dataset generate proprioceptive_spikes` with `smoke` (~500), `medium` (~5000), `large` (~20000) Preset support; the CLI SHALL validate all parameters before invoking the generator and print a descriptive error to stderr and exit code `1` on invalid input.

---

### Requirement 4: Dataset Validation and Integrity CLI

**User Story:** As a developer integrating datasets into a benchmark pipeline, I want CLI commands to verify dataset integrity and run the full statistical validation suite, so that I can catch generator regressions and corrupted downloads before they affect benchmark results.

#### Acceptance Criteria

1. THE CLI `dataset verify <path>` SHALL recompute SHA-256 over the `neuron_id` dataset bytes in the HDF5_File, compare to `content_sha256`; WHEN matching, print `OK: <path>` and exit `0`; WHEN mismatching, print `MISMATCH: <path>` and exit `1`.
2. IF `<path>` does not exist or is not a valid HDF5 file, THEN `dataset verify` and `dataset validate` SHALL print a descriptive error to stderr and exit with code `2` (distinct from integrity failure code `1`).
3. THE CLI `dataset validate <path>` SHALL run all four Validation_Suite checks and print one line per check in the format `<check_name>: <PASS|FAIL|WARN> <observed_value>`, then exit `0` if all pass or `1` if any fail.
4. THE CLI `dataset list` SHALL print the registered `generator_id` and description of every registered Synthetic_Generator, one per line, and exit `0`.
5. THE `dataset verify` command SHALL return the same output and exit code on every invocation against the same unmodified file (idempotence property).
6. WHEN `dataset validate` is run on a file missing the `content_sha256` attribute, THE CLI SHALL print `content_sha256: WARN (attribute absent)` and continue running the remaining three validators.
7. THE CLI `dataset validate` SHALL accept `--expected-encoding <value>` where value is one of `rate`, `burst`, `delay`, `oscillatory`, `drift`; this value SHALL be forwarded to the `temporal_stats` validator to select the appropriate ISI distribution test.

---

### Requirement 5: Neurohub Dataset Publishing

**User Story:** As a data engineer, I want to publish generated or converted datasets to the Neurohub Global Registry as Dataset_Artefacts, so that the team and the community can discover and reuse them without manual file sharing.

#### Acceptance Criteria

1. THE CLI `dataset push <path> --owner <owner> --slug <slug> --version <version> [--registry-url <url>]` SHALL upload the HDF5_File as a `dataset` artefact and print the canonical `neurohub://dataset/{owner}/{slug}@{version}` URI on success; `--registry-url` defaults to the value of the `NEUROHUB_REGISTRY_URL` environment variable.
2. WHEN `dataset push` is invoked, THE CLI SHALL first run `dataset verify` on the local file; IF verify exits non-zero or cannot be executed (file missing, HDF5 read error), THE CLI SHALL print the failure reason to stderr and exit `1` without contacting the Registry.
3. WHEN `dataset push` succeeds in uploading the blob but the artefact metadata registration fails, THE CLI SHALL print a structured error to stderr, exit `1`, and the Registry SHALL NOT make a partially-registered artefact discoverable.
4. THE CLI `dataset pull <neurohub_uri> [--output <path>]` SHALL resolve the URI, download the blob to `<path>` (defaulting to `{cwd}/{slug}@{version}.h5`), and run `dataset verify`; IF post-download verify fails, THE CLI SHALL delete the file, print an error to stderr, and exit `1`.
5. IF `dataset pull` references a URI whose artefact does not exist in the Registry, THE CLI SHALL print a descriptive error to stderr identifying the URI and exit `1`.
6. THE `dataset push` command SHALL attach a Dataset_Card containing: `synthetic_config` (from HDF5 root attributes, or `null` if absent), `content_sha256`, `generated_at`, `neurobench_generator_version`, and `validation_summary` (the JSON output of the most recent `dataset validate` run on the file, or `null` if no validation record is found).
7. IF the Registry is unreachable, THE CLI SHALL emit a timeout error to stderr within 30 seconds and exit `1`; the local HDF5_File SHALL remain unmodified.

---

### Requirement 6: Neurohub Dataset Retrieval in Neurobench Backend

**User Story:** As a benchmark runner, I want the Neurobench backend to resolve `neurohub://` dataset URIs and make the corresponding HDF5_Files available to benchmark jobs, so that benchmark definitions can reference Registry datasets without hardcoded file paths.

#### Acceptance Criteria

1. THE `Download_Manager` in `neurobench/app/services/dataset_download_manager.py` SHALL accept a `neurohub://dataset/{owner}/{slug}@{version}` URI, resolve it against the configured Registry, download the blob to a local cache directory, and return the absolute local path.
2. WHEN the Download_Manager downloads a file, THE Download_Manager SHALL verify `content_sha256`; IF the hashes disagree, THE Download_Manager SHALL delete the corrupted file and raise `DatasetIntegrityError` naming the URI and the expected vs actual hash values.
3. WHEN a URI is already cached and `dataset verify` exits `0` for the cached file, THE Download_Manager SHALL return the cached path without network I/O (cache hit); IF a new download attempt fails but a valid cached file exists, THE Download_Manager SHALL return the cached path and log `WARNING: Registry unreachable; serving cached {uri}`.
4. WHILE downloading, THE Download_Manager SHALL emit progress events no less frequently than once per second, each containing `bytes_downloaded` (integer) and `total_bytes` (integer or -1 if unknown).
5. IF the Registry is unreachable, THE Download_Manager SHALL raise `RegistryConnectionError` within 30 seconds of the initial attempt.
6. THE Backend `POST /api/neurobench/datasets/download` endpoint SHALL accept `{"uri": "neurohub://..."}`, return HTTP 202 while downloading, and HTTP 200 with `{"cache_path": "<path>", "sha256_verified": true}` on completion.
7. THE `InputSpec` model SHALL accept an optional `neurohub_uri` (string) field; WHEN set, the benchmark runner SHALL call `Download_Manager` to resolve the file before execution begins.

---

### Requirement 7: NMTK UI Dataset Browser and One-Click Download

**User Story:** As an NMTK desktop user, I want to browse available neuromorphic datasets from the Neurohub Registry within the Neurobench UI and download them with a single click, so that I can load datasets into benchmark jobs without using the CLI.

#### Acceptance Criteria

1. THE `Dataset_Browser` panel SHALL list Dataset_Artefacts from the Registry showing per entry: slug, version, generator type, trial count, file size in bytes, and `validation_summary` (if present in the Dataset_Card, else omitted).
2. WHEN a user presses the download button for a selected artefact, THE frontend SHALL call `POST /api/neurobench/datasets/download` and display a progress indicator updated at ≤1-second intervals; THE frontend SHALL enforce a client-side timeout of 30 seconds and display a timeout error if exceeded.
3. WHEN a download completes successfully, THE frontend SHALL populate `input_spec.neurohub_uri` with the downloaded URI and display a confirmation including the local cache path.
4. IF a download fails (integrity mismatch, unreachable Registry, disk full, or client timeout), THE frontend SHALL display a descriptive error banner identifying the failure cause and SHALL clear `input_spec.neurohub_uri` without navigating away.
5. THE Dataset_Browser SHALL display only artefacts of type `dataset` whose Dataset_Card contains a non-null `content_sha256` field; all other artefacts SHALL be silently excluded.
6. WHERE the Registry is not configured or unreachable when the panel opens, THE Dataset_Browser SHALL display the string `"Registry unavailable — check connection"` in the content area and no list items or error widgets.
7. THE Dataset_Browser widget SHALL accept all data via constructor parameters and callbacks, with no imports of `flutter_riverpod`, `provider`, or any module-specific app-state package at the top of the widget file.

---

### Requirement 8: Experiment Tracking Integration

**User Story:** As a researcher running benchmark jobs with neuromorphic datasets, I want dataset download events and generation runs to be automatically recorded in the experiment manifest, so that I have a complete, reproducible audit trail linking dataset provenance to benchmark results.

#### Acceptance Criteria

1. WHEN the Download_Manager completes a successful download, THE Download_Manager SHALL write into the active ExperimentTracker manifest: `dataset_uri`, `dataset_sha256`, `downloaded_at` (ISO 8601 UTC), and `cache_path` (absolute path).
2. WHEN a Synthetic_Generator's `generate` method completes successfully, THE generator SHALL write into the active ExperimentTracker manifest: `generator_id`, `seed`, `preset`, `generated_at` (ISO 8601 UTC), `output_path`, and `content_sha256`.
3. THE manifest entries written by criterion 1 or 2 SHALL conform to the `ExperimentManifest` Pydantic model in `Neuro-Dream-Hand/neurodreamhand/experiments/tracking.py`.
4. WHEN a benchmark result is saved, THE Neurobench backend SHALL include `dataset_uri` and `dataset_sha256` in `BenchmarkResult.metadata` if they are present in the active manifest; WHERE no dataset URI is recorded, THESE fields SHALL be absent from the result.
5. IF no ExperimentTracker is active when a generator or Download_Manager event fires, THE system SHALL emit a `DEBUG`-level log message and SHALL NOT raise an exception.
6. THE `BenchmarkResult.metadata` dataset provenance fields (`dataset_uri`, `dataset_sha256`) SHALL be identical for any two runs that used the same dataset URI and successfully verified the same SHA-256.

---

### Requirement 9: Dataset Pipeline Round-Trip Integrity

**User Story:** As a quality-assurance engineer, I want the event-ification and generation pipelines to guarantee that produced HDF5 files are byte-reproducible and statistically valid, so that benchmark results are attributable to model changes rather than data variation.

#### Acceptance Criteria

1. THE `content_sha256` attribute stored in any HDF5_File produced by a Dataset_Pipeline or Synthetic_Generator SHALL equal the SHA-256 computed over the `neuron_id` dataset bytes in row-major order; `dataset verify` on that file SHALL exit `0`.
2. FOR ANY Synthetic_Generator run twice on the same machine with the same `seed` and `config`, the `spikes` dataset bytes in both output files SHALL be identical (deterministic regeneration property).
3. THE `dataset validate` command SHALL report all four Validation_Suite checks passing for any HDF5_File produced by a Synthetic_Generator at the `smoke`, `medium`, or `large` Preset with default parameters.
4. THE `dataset validate` command SHALL report `firing_stats` and `sparsity` checks passing for any HDF5_File produced by a Dataset_Pipeline on a valid source dataset.
5. FOR ANY HDF5_File with a valid `content_sha256` attribute, computing SHA-256 over the `neuron_id` dataset and comparing to `content_sha256` SHALL return the same boolean result on every invocation without modifying any file (idempotence property).
