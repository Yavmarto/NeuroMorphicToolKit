# Synthetic Dataset Generation Plan for NeuroBench

> **Version**: 0.2.0 — consolidated from two draft plans
> **Status**: Approved for implementation
> **See also**: [`NSBI_execution_guide.md`](./NSBI_execution_guide.md) for full code
> **Scripts**: [`scripts/generate_all_datasets.sh`](../../scripts/generate_all_datasets.sh)

---

## Design Philosophy

**Goal**: Build a lean, benchmark-grade synthetic data layer that solves immediate NeuroBench
usability gaps — not a comprehensive neuromorphic simulation ecosystem.

Frame this externally as:

> **"Synthetic benchmark infrastructure for event-driven ML evaluation."**

Not "biologically realistic neural simulation." The former is defensible, adoptable, and
finishable. The latter is a research programme.

Every generator optimises for:

- **Reproducibility** — deterministic re-generation from seed + config
- **Benchmark utility** — temporal structure that actually stresses SNN dynamics
- **Computational tractability** — runs to completion on a consumer workstation
- **Ease of validation** — outputs that can be checked statistically, not just visually

---

## Hardware Mapping

| Resource | Capacity | Role |
|---|---|---|
| Ryzen 9 5900X (12C / 24T) | ~24 parallel workers | Primary workhorse for all generation |
| 48 GB RAM | ~40 GB usable | In-memory generation before HDF5 flush; stream-write mandatory |
| RTX 3060 (12 GB VRAM) | CUDA via CuPy | Perturbation transform sweeps only (DS-3) |
| NVMe SSD | Fast sequential write | Chunked HDF5 streaming |

> **Rule**: All generators must stream-write to HDF5. No generator may hold a full dataset in
> memory. Peak RAM budget per generator: **8 GB**.

---

## Reproducibility Policy

> **This is a benchmark suite. Deterministic re-generation is non-negotiable.**

Every generator must:

1. Accept an explicit `--seed <int>` argument (default `42`).
2. Derive per-worker seeds deterministically: `worker_seed = seed + worker_id * 1000`.
3. Use `np.random.default_rng(worker_seed)` — **no module-level `np.random` calls**.
4. Store full provenance in HDF5 root `attrs` on every output file:

```python
hdf5_file.attrs["neurobench_generator_version"] = "0.1.0"
hdf5_file.attrs["seed"]                          = seed
hdf5_file.attrs["generated_at"]                  = iso8601_utc_now()
hdf5_file.attrs["hostname"]                      = socket.gethostname()
hdf5_file.attrs["synthetic_config"]              = json.dumps(config_dict)
hdf5_file.attrs["content_sha256"]                = sha256_of_primary_dataset
```

5. Support `neurobench dataset verify <path>` — recomputes SHA-256 and compares to stored value.
   CI uses this to catch generator regressions between releases.

---

## Preset System

All generators support three preset sizes:

| Preset | Purpose | Approx. Trials | Peak RAM |
|---|---|---|---|
| `smoke` | CI, quick testing | 500–1,000 | < 500 MB |
| `medium` | Benchmark development | 5,000–10,000 | < 4 GB |
| `large` | Publication-grade | 20,000–50,000 | < 8 GB |

`large` is generated on demand only — not run in CI. `medium` is the default.

---

## Dataset Tiers

### Tier 1 — Essential (ship first)

These make NeuroBench immediately useful. Do not begin Tier 2 until Tier 1 passes all
validation checks and `neurobench run` integration tests pass end-to-end.

---

### 🥇 DS-1: `canonical_spike_library` — Canonical Spike Pattern Library

**Why first**: Foundational primitive. Every other generator and downstream benchmark either
calls it directly or is validated against it. Shipping this gives immediate coverage of
`spike_classification` and unlocks energy/latency benchmarking.

**What it is**: Labelled spike raster corpus with configurable temporal structure:

| Pattern family | Description |
|---|---|
| Rate-coded | Homogeneous / inhomogeneous Poisson |
| Oscillatory | Theta / beta / gamma modulated firing |
| Burst | Clustered temporal events |
| Delay-coded | Class information encoded in timing offsets |
| Drifted | Gradual temporal distribution shift (robustness probe) |

**Configurable parameters**:
- `n_neurons`: 10 – 10,000 (default 256)
- `n_trials`: 1,000 – 50,000
- `encoding`: `rate | temporal | burst | delay | drift`
- `snr_db`: inter-class separability in dB
- `duration_ms`: trial length

**Generation approach**:
- Vectorized NumPy Poisson for rate coding
- Gamma ISI sampling for temporal coding
- Numba JIT `@numba.njit` for the ISI inner loop (performance-critical path)
- `joblib.Parallel(n_jobs=12)` over `(class × trial × seed)` batches

**Output format** (sparse COO):
```
/ds1_canonical_spikes_{preset}.h5
  /spikes_coo/
    neuron_id   [E]          uint16
    time_ms     [E]          float32
    trial_id    [E]          uint32
  /labels       [N_trials]   uint8
  attrs: n_neurons, encoding_type, snr_db, seed, content_sha256, ...
```

**Benchmark wiring**: `spike_classification.json` → `input_spec.synthetic_config`

**Generation times** (12 cores, including ~1 min Numba JIT on first run):

| Preset | Trials | Neurons | Time |
|---|---|---|---|
| `smoke` | 1,000 | 128 | ~2 min |
| `medium` | 10,000 | 512 | ~15–20 min |
| `large` | 50,000 | 2,048 | ~45–70 min |

---

### 🥈 DS-2: `emg_gestures` — Synthetic Multi-Channel EMG

**Why second**: Maps directly to `grip_stability` and Neurosense. High community relevance
(prosthetics, wearable sensing). The stochastic envelope model is faster to implement and
easier to validate than full motor unit physiology — and equally benchmark-meaningful.

**Approach — stochastic envelope model**:

Each gesture class is defined by:
- **Activation envelope**: temporal shape of muscle activation (rise/hold/decay)
- **Channel covariance profile**: spatial correlation across 8 channels
- **Temporal onset dynamics**: per-trial jitter on activation start (±10 ms)
- **Noise regime**: additive Gaussian at configurable SNR

Full MUAP convolution physiology can be added in v0.2 if the community requests it.

**Output format**:
```
/ds2_emg_gestures_{preset}.h5
  /raw_signals  [N, T, C=8]   float32   # raw EMG envelope (mV)
  /spikes       [N, T, C=8]   bool      # delta-encoded spike trains
  /labels       [N]           uint8     # gesture class 0–5
  attrs: gesture_classes, snr_db, seed, content_sha256, ...
```

**Benchmark wiring**: `grip_stability.json` → `input_spec.synthetic_config`

**Generation times** (12 cores):

| Preset | Trials | Time |
|---|---|---|
| `smoke` | 500 | ~2 min |
| `medium` | 5,000 | ~8–12 min |
| `large` | 20,000 | ~20–30 min |

---

### ⚙️ DS-3: `transforms/perturbation.py` — Robustness Transform Layer

**This is not a dataset.** It is a composable transform module applied at benchmark runtime,
enabling NB-RP1/RP2 fault sweep benchmarks which are currently stubbed.

**Transforms** (composable via `Compose([...])`):

| Transform | Description |
|---|---|
| `SpikeDropout(p)` | Random spike deletion |
| `TemporalJitter(sigma_ms)` | Per-event timing shift |
| `BurstCorruption(p, duration_ms)` | Contiguous noise injection |
| `ChannelFailure(channels)` | Full-channel zeroing |
| `AdditiveEventNoise(rate_hz)` | Spurious spike injection |

**GPU path**: CuPy used automatically when available (RTX 3060 gives ~10× speedup).
Falls back to NumPy otherwise. Import is guarded:

```python
try:
    import cupy as cp
    CUPY_AVAILABLE = True
except ImportError:
    CUPY_AVAILABLE = False
```

**No HDF5 output.** Perturbation parameters are logged to the benchmark result JSON under
`perturbation_metadata`. Pre-generation can be added later as `neurobench dataset prefault`
if sweep latency becomes a bottleneck.

---

### Tier 1 Validation Gate

Before beginning Tier 2, all Tier 1 outputs must pass the validation suite:
firing rate distributions within physiological bounds, no refractory violations, class
separability above chance at all intended SNR levels, and `content_sha256` reproducible
across two independent runs from the same seed.

---

### Tier 2 — Valuable Extension (only after Tier 1 is stable)

---

### 🥉 DS-4: `temporal_grammar` — Hierarchical Temporal Grammar Dataset

**Why**: Targets the biggest open SNN benchmarking gap — **multi-scale temporal dependency
evaluation**. Maps to `pattern_recognition` and `wake_word_detection`.

**What it is**: Synthetic event sequences with short / medium / long temporal structure:
- **Short** (< 50 ms): atomic spike motifs
- **Medium** (50–500 ms): phrase-level motif combinations
- **Long** (500 ms – 5 s): word-level phrase sequences

**Grammar spec (pinned at v0.1)**:
```python
MOTIF_GRAMMAR_V1 = {
    "atoms":   8,   # distinct short-duration spike patterns
    "phrases": 16,  # ordered atom combinations
    "words":   32,  # ordered phrase combinations
}
# Stored verbatim as JSON in HDF5 attrs on every output file.
```

**Output format**:
```
/ds4_temporal_grammar_{preset}.h5
  /rate/     sequences [N, T, C]   float32
  /temporal/ sequences [N, T, C]   float32
  /burst/    sequences [N, T, C]   float32
  /labels/
    short_label  [N]   uint8
    medium_label [N]   uint8
    long_label   [N]   uint8
  attrs: grammar (JSON), snr_levels, seed, content_sha256, ...
```

**Benchmark wiring**: `pattern_recognition.json`, `wake_word_detection.json`

**Realistic generation time**: ~25–40 min for 25k sequences (12 cores).

---

### Tier 3 — Experimental (placeholder)

**DS-5: `motor_cortex`** — Only implement if: (a) DS-1/2 adoption exists, (b) contributors
request it, and (c) reference statistics from real cortical datasets are available to validate
against. Without (c), synthetic motor cortex data risks pseudo-realism that could mislead
rather than benchmark.

---

## Validation Suite

> **This is the most important structural addition.**

Create `neurobench/data/validators/` alongside the generators. Every generator runs its
validator before writing the final HDF5 file.

```
data/
  validators/
    __init__.py
    firing_stats.py     # mean rate, variance, refractory violations
    temporal_stats.py   # autocorrelation, ISI distribution
    separability.py     # class separability (LDA cross-val)
    sparsity.py         # event density (critical for neuromorphic relevance)
```

### How to verify datasets are actually what they claim

**The four checks that answer this question:**

| Validator | What it confirms | Failure means |
|---|---|---|
| `firing_stats` | Mean rate within physiological bounds (1–300 Hz); zero refractory violations | Generator has a bug or wrong parameters |
| `sparsity` | Event density 0.1–5% (calibrated from N-MNIST/SHD) | Data is too dense (useless for sparse hardware) or too sparse (no information) |
| `separability` | LDA cross-val accuracy > 60% at intended SNR | Classes aren't distinguishable — benchmark would test nothing |
| `temporal_stats` | ISI follows expected distribution (exponential for Poisson, gamma for regular coding) | Encoding model is broken |

**Calibration** — Run these once against real datasets to set the validator bounds:
- **SHD** (Spiking Heidelberg Digits) → calibrates DS-1 firing rate and ISI ranges
- **N-MNIST** → calibrates sparsity bounds
- **NinaPro DB5** → calibrates DS-2 envelope shapes and amplitudes

All three are free, no registration required. URLs in `NSBI_execution_guide.md` Step 0.

Run `neurobench dataset validate <path>` against any generated file to get a full report.

---

## Package Structure

```
neurobench/data/
  generators/
    __init__.py
    base.py                   # Abstract generator: HDF5 writer, checkpointing, seed policy
    utils/
      encoding.py             # Rate, temporal, delta, burst encoders (NumPy/Numba)
      io.py                   # HDF5 helpers, metadata schema, SHA-256 checksums
      random.py               # Seed derivation utilities
    canonical_spikes.py       # DS-1
    emg.py                    # DS-2
    temporal_grammar.py       # DS-4 (Tier 2)
  transforms/
    __init__.py
    perturbation.py           # DS-3: composable runtime transforms
    compose.py
  validators/
    __init__.py
    firing_stats.py
    temporal_stats.py
    separability.py
    sparsity.py
  experimental/               # DS-5 lives here, untouched for now
  README.md
```

---

## Dependencies

| Package | Required? | Purpose |
|---|---|---|
| `numpy` | **Yes** | Core numerical generation (already in pyproject.toml) |
| `h5py` | **Yes** | HDF5 read/write |
| `numba` | **Yes** | JIT for ISI sampling inner loops |
| `scipy` | **Yes** | ISI KS-test in temporal_stats validator (already in pyproject.toml) |
| `scikit-learn` | **Yes** | LDA separability check in separability validator |
| `joblib` | Optional | Parallel job orchestration (falls back to `multiprocessing`) |
| `cupy-cuda12x` | Optional | GPU acceleration for perturbation transforms (RTX 3060, CUDA 12) |

Add to `pyproject.toml`:
```toml
h5py = ">=3.10.0"
numba = ">=0.59.0"
scikit-learn = ">=1.4.0"
joblib = {version = ">=1.4.0", optional = true}
cupy-cuda12x = {version = "*", optional = true}
```

---

## Implementation Order

### Phase 1 — Infrastructure (1–2 days)
- `base.py`: HDF5 writer, checkpointing, seed policy
- `utils/io.py`: metadata schema, SHA-256 checksums
- `utils/random.py`: seed derivation
- `validators/__init__.py`: validator runner harness (stubs)

### Phase 2 — DS-1 Canonical Spike Library (2–3 days)
- `canonical_spikes.py`: all 5 pattern families
- All 4 validators fleshed out for spike raster data
- CLI: `neurobench dataset generate canonical_spikes --preset smoke|medium|large`
- CI: smoke preset + SHA-256 reference checksum committed

### Phase 3 — DS-2 EMG Generator (2–3 days)
- `emg.py`: stochastic envelope model, 6 gesture classes
- Extend validators with EMG-specific checks
- Wire `grip_stability.json` `input_spec` to DS-2 output

### Phase 4 — DS-3 Perturbation Transforms (1–2 days)
- `transforms/perturbation.py`: all 5 transforms + Compose helper
- Integration into `benchmark_runner.py` for NB-RP1/RP2 sweep support
- Smoke test: apply each transform to DS-1 `smoke` preset

### Phase 5 — Validation suite completion (1–2 days)
- Harden all 4 validators against edge cases
- `neurobench dataset validate <path>` CLI command
- Document expected ranges per dataset in `data/README.md`

### Phase 6 — DS-4 Temporal Grammar (3–5 days, Tier 2)
- `temporal_grammar.py`: motif library, probabilistic sequencing, 3 encoding variants
- Wire `pattern_recognition.json` and `wake_word_detection.json`

**Total realistic MVP (Tier 1 complete): ~2 weeks of focused work.**

---

## Storage Layout

```
Neurobench/
  neurobench/data/
    generated/                    # gitignored
      ds1_canonical_spikes_smoke.h5
      ds1_canonical_spikes_medium.h5
      ds2_emg_gestures_medium.h5
      ...
    README.md
```

A `neurobench dataset push` command is planned for future NeuroHub integration.
Team sharing in the interim: use the QNAP ts317 NAS path and symlink `data/generated/`.

---

## CLI

```bash
neurobench dataset generate <dataset_id> [--preset smoke|medium|large] [--seed N] [--output PATH]
neurobench dataset list
neurobench dataset verify <path>      # SHA-256 integrity check
neurobench dataset validate <path>    # full statistical validation suite
```

---

## Estimated Generation Times Summary

| Dataset | Size (HDF5 medium) | CPU Time (12 cores) | GPU Assist? |
|---|---|---|---|
| DS-1: Canonical Spikes | ~2 GB | ~15–20 min | No |
| DS-2: EMG Gestures | ~500 MB | ~8–12 min | No |
| DS-3: Perturbation (runtime) | 0 disk | ~0 min | Yes (10×) |
| DS-4: Temporal Grammar | ~1.5 GB | ~25–40 min | No |
| **Total (Tier 1 medium)** | **~2.5 GB** | **~30 min** | — |

---

## Verification Checklist

### Automated (CI)
```bash
# 1. Unit tests
python3 -m pytest neurobench/tests/test_generators.py -v

# 2. Reproducibility (two runs, same seed → same SHA-256)
neurobench dataset generate canonical_spikes --preset smoke --seed 42 --output /tmp/run_a
neurobench dataset generate canonical_spikes --preset smoke --seed 42 --output /tmp/run_b
diff <(neurobench dataset verify /tmp/run_a/ds1_canonical_spikes_smoke.h5) \
     <(neurobench dataset verify /tmp/run_b/ds1_canonical_spikes_smoke.h5)

# 3. Statistical validation
neurobench dataset validate /tmp/run_a/ds1_canonical_spikes_smoke.h5

# 4. End-to-end benchmark run
neurobench run grip_stability --network tests/fixtures/simple_net.cnl
neurobench run spike_classification --network tests/fixtures/simple_net.cnl
```

Reference SHA-256 checksums committed to `tests/fixtures/generator_checksums.json`.
Updated manually on intentional generator changes; version bump required.

### Manual Visual Checks
- **DS-1**: Plot rasters for all 5 encoding types. Confirm visually distinct temporal structure.
  Confirm class separability degrades gracefully at low SNR.
- **DS-2**: Plot 3 trials per gesture class. Confirm distinct activation envelopes,
  plausible amplitude (~0.1–2 mV), delta-encoded spikes at 5–50 Hz.
- **DS-3 transforms**: Apply each transform at min/max severity to a DS-1 trial. Plot
  before/after. Confirm dropout removes spikes, jitter shifts without adding/removing events,
  channel failure zeros complete channels.
- **DS-4**: Plot one sequence per (encoding × temporal scale). Confirm short/medium/long
  label structure is visible in timing.
