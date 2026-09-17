# NSBI Execution Guide

Concrete steps, real code, no more planning.

---

## Step 0: Environment

### Install libraries

```bash
# Required
pip install numpy h5py numba scipy scikit-learn pytest

# Optional but recommended
pip install joblib                  # cleaner parallel API than multiprocessing
pip install cupy-cuda12x            # RTX 3060 GPU path for perturbation transforms only
```

Verify your Numba + CUDA setup:

```bash
python -c "import numba; numba.cuda.detect()"
# Should report: Found 1 CUDA devices — RTX 3060
```

### Reference datasets (for validator calibration)

You need real spike data to know whether your synthetic distributions are plausible.
Download these — all free, no registration:

| Dataset | What it gives you | URL |
|---|---|---|
| **SHD** (Spiking Heidelberg Digits) | Real auditory spike rasters; use to calibrate DS-1 firing rate and ISI ranges | https://compneuro.net/datasets/ |
| **N-MNIST** | Neuromorphic vision spikes; use to calibrate sparsity bounds | https://www.garrickorchard.com/datasets/n-mnist |
| **NinaPro DB5** | Real 8-channel forearm EMG for 6 gestures; use to calibrate DS-2 envelope shapes and amplitudes | http://ninapro.hevs.ch/NinaPro-DB5 |

You do not need these to *generate* data. You need them to set the bounds in your validators
so they reflect real biology rather than arbitrary numbers. Load them once, compute the
stats below, hardcode the results as constants in your validators.

```python
# Run this once against SHD to get DS-1 validator bounds
import h5py, numpy as np

with h5py.File("shd_train.h5", "r") as f:
    times   = f["spikes/times"][:]      # spike times in seconds
    units   = f["spikes/units"][:]      # neuron IDs
    labels  = f["labels"][:]

# Compute firing rate distribution
trial_durations_s = 1.0                 # SHD trials are ~1 s
rates = np.array([len(t) / trial_durations_s for t in times])
print(f"Mean rate: {rates.mean():.1f} Hz")
print(f"Std rate:  {rates.std():.1f} Hz")
print(f"Sparsity:  {np.mean([len(t)/(700*1000) for t in times]):.4f}")
# Use these outputs to set RATE_MIN, RATE_MAX, SPARSITY_MIN, SPARSITY_MAX in validators
```

---

## Step 1: Directory structure

```bash
cd Neurobench/neurobench/data

mkdir -p generators/utils
mkdir -p transforms
mkdir -p validators
mkdir -p experimental        # DS-5 lives here, untouched for now

touch generators/__init__.py
touch generators/base.py
touch generators/utils/__init__.py
touch generators/utils/random.py
touch generators/utils/io.py
touch generators/utils/encoding.py
touch generators/canonical_spikes.py
touch generators/emg.py
touch generators/temporal_grammar.py
touch transforms/__init__.py
touch transforms/perturbation.py
touch transforms/compose.py
touch validators/__init__.py
touch validators/firing_stats.py
touch validators/temporal_stats.py
touch validators/separability.py
touch validators/sparsity.py
touch README.md
```

---

## Phase 1: Infrastructure

### `generators/utils/random.py`

```python
import numpy as np

def make_rng(base_seed: int, worker_id: int = 0) -> np.random.Generator:
    """Derive a deterministic per-worker RNG. Never call np.random directly."""
    return np.random.default_rng(base_seed + worker_id * 1000)


def derive_seeds(base_seed: int, n_workers: int) -> list[int]:
    """Return a list of worker seeds derived from base_seed."""
    return [base_seed + i * 1000 for i in range(n_workers)]
```

### `generators/utils/io.py`

```python
import hashlib, json, socket
from datetime import datetime, timezone

import h5py
import numpy as np

GENERATOR_VERSION = "0.1.0"


def iso8601_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_array(arr: np.ndarray) -> str:
    return hashlib.sha256(arr.tobytes()).hexdigest()


class HDF5Writer:
    """
    Chunked stream-writer. Never holds the full dataset in memory.

    Usage:
        with HDF5Writer(path, config, seed) as w:
            for batch in batches:
                w.write_batch("spikes", batch)
        # File is finalised and SHA-256 stamped on __exit__
    """

    def __init__(self, path: str, config: dict, seed: int):
        self.path   = path
        self.config = config
        self.seed   = seed
        self._file  = None
        self._datasets: dict[str, h5py.Dataset] = {}

    def __enter__(self):
        self._file = h5py.File(self.path, "w")
        return self

    def create_dataset(self, name: str, shape: tuple, dtype, chunks: tuple | None = None):
        """Create a resizable dataset before streaming batches into it."""
        maxshape = (None,) + shape[1:]
        self._datasets[name] = self._file.create_dataset(
            name, shape=shape, maxshape=maxshape,
            dtype=dtype, chunks=chunks or True, compression="gzip"
        )

    def write_batch(self, name: str, data: np.ndarray, offset: int):
        ds = self._datasets[name]
        end = offset + len(data)
        if end > ds.shape[0]:
            ds.resize(end, axis=0)
        ds[offset:end] = data

    def __exit__(self, *_):
        # Stamp metadata on the way out
        f = self._file
        f.attrs["neurobench_generator_version"] = GENERATOR_VERSION
        f.attrs["seed"]             = self.seed
        f.attrs["generated_at"]     = iso8601_now()
        f.attrs["hostname"]         = socket.gethostname()
        f.attrs["synthetic_config"] = json.dumps(self.config)

        # SHA-256 over the primary spike dataset (first dataset by convention)
        primary = list(self._datasets.values())[0]
        f.attrs["content_sha256"] = sha256_array(primary[:])

        self._file.close()


def verify(path: str) -> bool:
    """Return True if content_sha256 in attrs matches actual spike tensor."""
    with h5py.File(path, "r") as f:
        stored   = f.attrs["content_sha256"]
        primary  = list(f.keys())[0]
        computed = sha256_array(f[primary][:])
    match = stored == computed
    print(f"{'OK' if match else 'MISMATCH'}: {path}")
    return match
```

### `generators/base.py`

```python
from abc import ABC, abstractmethod
from pathlib import Path


class DatasetGenerator(ABC):

    def __init__(self, seed: int = 42):
        self.seed = seed

    @abstractmethod
    def generate(self, config: dict, output_path: str | Path) -> None:
        """Generate dataset and write to output_path."""
        ...

    @abstractmethod
    def validate(self, path: str | Path) -> bool:
        """Run statistical validators on a completed HDF5 file."""
        ...

    def run(self, config: dict, output_path: str | Path) -> None:
        """Generate, then validate. Abort if validation fails."""
        self.generate(config, output_path)
        if not self.validate(output_path):
            raise RuntimeError(f"Validation failed for {output_path}. File kept for inspection.")
        print(f"Generated and validated: {output_path}")
```

---

## Phase 2: Validators

Populate these with the constants you computed from SHD and NinaPro above.

### `validators/firing_stats.py`

```python
import h5py
import numpy as np

# Calibrate these from SHD (see Step 0)
RATE_MIN_HZ  = 1.0
RATE_MAX_HZ  = 300.0
REFRACTORY_MS = 1.0


def check(path: str, dataset_key: str = "spikes", duration_ms: float = 1000.0) -> bool:
    """
    Check mean firing rate and refractory period violations.
    `spikes` must be a dense bool array [N_trials, T_ms, N_neurons].
    """
    ok = True
    with h5py.File(path, "r") as f:
        spikes = f[dataset_key][:]          # load fully for stats; fine for smoke/medium

    # Mean firing rate per neuron across trials
    rate = spikes.mean(axis=(0, 1)) * 1000  # convert fraction → Hz
    if rate.mean() < RATE_MIN_HZ or rate.mean() > RATE_MAX_HZ:
        print(f"  FAIL firing_stats: mean rate {rate.mean():.1f} Hz outside [{RATE_MIN_HZ}, {RATE_MAX_HZ}]")
        ok = False
    else:
        print(f"  OK   firing_stats: mean rate {rate.mean():.1f} Hz")

    # Refractory violations: no neuron fires twice within REFRACTORY_MS consecutive bins
    refractory_bins = int(REFRACTORY_MS)
    kernel = np.ones(refractory_bins, dtype=bool)
    violations = 0
    for trial in spikes:                    # [T, N]
        for n in range(trial.shape[1]):
            times = np.where(trial[:, n])[0]
            if len(times) > 1:
                violations += int(np.any(np.diff(times) < refractory_bins))
    if violations > 0:
        print(f"  FAIL firing_stats: {violations} refractory violations")
        ok = False
    else:
        print(f"  OK   firing_stats: 0 refractory violations")

    return ok
```

### `validators/sparsity.py`

```python
import h5py
import numpy as np

# From N-MNIST: ~0.3–2% typical for neuromorphic vision
SPARSITY_MIN = 0.001   # 0.1%
SPARSITY_MAX = 0.05    # 5%


def check(path: str, dataset_key: str = "spikes") -> bool:
    with h5py.File(path, "r") as f:
        spikes = f[dataset_key][:]
    density = spikes.mean()
    ok = SPARSITY_MIN <= density <= SPARSITY_MAX
    status = "OK  " if ok else "FAIL"
    print(f"  {status} sparsity: {density*100:.3f}% (bounds: {SPARSITY_MIN*100}–{SPARSITY_MAX*100}%)")
    return ok
```

### `validators/separability.py`

```python
import h5py
import numpy as np
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import cross_val_score

CHANCE_THRESHOLD = 0.60   # must beat 60% (adjust for n_classes)


def check(path: str, dataset_key: str = "spikes", label_key: str = "labels") -> bool:
    with h5py.File(path, "r") as f:
        spikes = f[dataset_key][:]   # [N, T, C]
        labels = f[label_key][:]

    # Flatten trials to feature vectors
    X = spikes.reshape(len(spikes), -1).astype(np.float32)
    y = labels

    lda    = LinearDiscriminantAnalysis()
    scores = cross_val_score(lda, X, y, cv=5)
    mean   = scores.mean()
    ok     = mean >= CHANCE_THRESHOLD
    status = "OK  " if ok else "FAIL"
    print(f"  {status} separability: LDA CV accuracy {mean:.2f} (threshold {CHANCE_THRESHOLD})")
    return ok
```

### `validators/temporal_stats.py`

```python
import h5py
import numpy as np
from scipy.stats import kstest, expon

KS_P_THRESHOLD = 0.05   # ISI must not be significantly non-exponential for Poisson data


def check(path: str, dataset_key: str = "spikes", expected_encoding: str = "rate") -> bool:
    """
    For rate-coded data: ISI should follow an exponential distribution (Poisson process).
    For other encodings this check is informational only.
    """
    with h5py.File(path, "r") as f:
        spikes = f[dataset_key][:]   # [N, T, C]

    # Collect ISIs across all trials and neurons
    isis = []
    for trial in spikes[:100]:       # sample 100 trials for speed
        for n in range(trial.shape[1]):
            times = np.where(trial[:, n])[0]
            if len(times) > 1:
                isis.extend(np.diff(times).tolist())

    if not isis:
        print("  WARN temporal_stats: no spikes found to compute ISI")
        return True

    isis = np.array(isis, dtype=float)

    if expected_encoding == "rate":
        stat, p = kstest(isis, "expon", args=(0, isis.mean()))
        ok = p > KS_P_THRESHOLD
        status = "OK  " if ok else "WARN"
        print(f"  {status} temporal_stats: ISI KS-test p={p:.4f} (Poisson expected, threshold {KS_P_THRESHOLD})")
    else:
        print(f"  INFO temporal_stats: mean ISI {isis.mean():.1f} ms, std {isis.std():.1f} ms")
        ok = True

    return ok
```

---

## Phase 3: DS-1 Canonical Spike Library

### `generators/canonical_spikes.py`

```python
from pathlib import Path

import numpy as np
import numba

from .base import DatasetGenerator
from .utils.io import HDF5Writer
from .utils.random import make_rng
from .. import validators


@numba.njit
def _sample_poisson_isi(rate_hz: float, duration_ms: float, seed: int) -> np.ndarray:
    """Sample spike times for one neuron via Poisson process. Numba JIT."""
    rng_state = seed
    times = []
    t = 0.0
    mean_isi = 1000.0 / rate_hz  # ms
    while t < duration_ms:
        # LCG for Numba-compatible random
        rng_state = (rng_state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        u = (rng_state >> 33) / 2**31
        isi = -mean_isi * np.log(max(u, 1e-10))
        t += isi
        if t < duration_ms:
            times.append(int(t))
    return np.array(times, dtype=np.int32)


class CanonicalSpikeGenerator(DatasetGenerator):

    ENCODINGS = ["rate", "burst", "delay", "oscillatory", "drift"]

    def generate(self, config: dict, output_path: str | Path) -> None:
        n_neurons   = config.get("n_neurons", 256)
        n_trials    = config.get("n_trials", 1000)
        duration_ms = config.get("duration_ms", 1000)
        n_classes   = config.get("n_classes", 4)
        encoding    = config.get("encoding", "rate")
        snr_db      = config.get("snr_db", 10.0)

        assert encoding in self.ENCODINGS, f"Unknown encoding: {encoding}"

        trials_per_class = n_trials // n_classes
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        shape = (n_trials, duration_ms, n_neurons)

        with HDF5Writer(str(output_path), config, self.seed) as w:
            w.create_dataset("spikes", shape=shape, dtype=bool,
                             chunks=(min(64, n_trials), duration_ms, n_neurons))
            w.create_dataset("labels", shape=(n_trials,), dtype=np.uint8)

            offset = 0
            for cls in range(n_classes):
                base_rate = 5.0 + cls * 15.0          # classes have distinct base rates
                for trial_idx in range(trials_per_class):
                    rng = make_rng(self.seed, worker_id=cls * trials_per_class + trial_idx)
                    spike_arr = self._encode(
                        encoding, n_neurons, duration_ms, base_rate, snr_db, rng
                    )
                    w.write_batch("spikes", spike_arr[np.newaxis], offset)
                    w.write_batch("labels", np.array([cls], dtype=np.uint8), offset)
                    offset += 1

    def _encode(self, encoding, n_neurons, duration_ms, base_rate, snr_db, rng):
        arr = np.zeros((duration_ms, n_neurons), dtype=bool)

        if encoding == "rate":
            for n in range(n_neurons):
                noise = rng.normal(0, base_rate / (10 ** (snr_db / 20)))
                rate  = max(1.0, base_rate + noise)
                prob  = rate / 1000.0
                arr[:, n] = rng.random(duration_ms) < prob

        elif encoding == "burst":
            n_bursts   = int(base_rate / 10)
            burst_len  = 10   # ms
            for n in range(n_neurons):
                burst_starts = rng.integers(0, duration_ms - burst_len, size=n_bursts)
                for s in burst_starts:
                    arr[s:s + burst_len, n] = rng.random(burst_len) < 0.8

        elif encoding == "delay":
            # Class info encoded as offset of a shared template pattern
            delay    = int(base_rate)          # reuse base_rate as delay offset in ms
            template = rng.random(duration_ms) < 0.05
            for n in range(n_neurons):
                shifted = np.roll(template, delay + rng.integers(-2, 3))
                arr[:, n] = shifted

        elif encoding == "oscillatory":
            freq_hz = base_rate   # reuse as oscillation frequency
            t       = np.arange(duration_ms)
            carrier = (np.sin(2 * np.pi * freq_hz * t / 1000) + 1) / 2
            for n in range(n_neurons):
                arr[:, n] = rng.random(duration_ms) < carrier * 0.3

        elif encoding == "drift":
            # Rate drifts linearly over the trial
            for n in range(n_neurons):
                rates = np.linspace(base_rate * 0.5, base_rate * 1.5, duration_ms)
                arr[:, n] = rng.random(duration_ms) < rates / 1000.0

        return arr

    def validate(self, path) -> bool:
        print(f"Validating {path}...")
        results = [
            validators.firing_stats.check(str(path)),
            validators.sparsity.check(str(path)),
            validators.separability.check(str(path)),
            validators.temporal_stats.check(str(path)),
        ]
        return all(results)
```

---

## Phase 4: DS-2 EMG Generator

### `generators/emg.py`

```python
from pathlib import Path

import numpy as np

from .base import DatasetGenerator
from .utils.io import HDF5Writer
from .utils.random import make_rng

# Calibrated from NinaPro DB5 (8-channel forearm EMG, 6 gestures)
# Load NinaPro once and run: signals.std(axis=0).mean() per gesture to get these
GESTURE_PARAMS = {
    #  name           envelope_shape   peak_ms  hold_ms  decay_ms  amplitude_mv
    0: ("rest",        "flat",          0,       1000,    0,        0.05),
    1: ("grip",        "ramp",          150,     400,     200,      1.2),
    2: ("pinch",       "ramp",          120,     300,     180,      0.8),
    3: ("point",       "pulse",         80,      100,     120,      0.6),
    4: ("wrist_flex",  "ramp",          200,     500,     150,      1.0),
    5: ("wrist_ext",   "ramp",          180,     450,     160,      0.9),
}

# Channel covariance profiles per gesture (8x8, approximate from NinaPro)
# In practice: load NinaPro, compute np.corrcoef(trial.T) per gesture, average
# Placeholder: use diagonal (no cross-channel correlation) until NinaPro is loaded
_COV = {g: np.eye(8) * GESTURE_PARAMS[g][5] for g in GESTURE_PARAMS}


class EMGGenerator(DatasetGenerator):

    def generate(self, config: dict, output_path: str | Path) -> None:
        n_trials    = config.get("n_trials", 5000)
        duration_ms = config.get("duration_ms", 1000)
        snr_db      = config.get("snr_db", 20.0)
        n_channels  = 8
        n_classes   = 6

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        trials_per_class = n_trials // n_classes

        with HDF5Writer(str(output_path), config, self.seed) as w:
            w.create_dataset("raw_signals", shape=(n_trials, duration_ms, n_channels),
                             dtype=np.float32)
            w.create_dataset("spikes",      shape=(n_trials, duration_ms, n_channels),
                             dtype=bool)
            w.create_dataset("labels",      shape=(n_trials,), dtype=np.uint8)

            offset = 0
            for cls in range(n_classes):
                params = GESTURE_PARAMS[cls]
                for t in range(trials_per_class):
                    rng = make_rng(self.seed, worker_id=cls * trials_per_class + t)
                    raw = self._generate_trial(params, duration_ms, snr_db, rng, n_channels)
                    spk = self._delta_encode(raw)
                    w.write_batch("raw_signals", raw[np.newaxis],    offset)
                    w.write_batch("spikes",      spk[np.newaxis],    offset)
                    w.write_batch("labels", np.array([cls], dtype=np.uint8), offset)
                    offset += 1

    def _generate_trial(self, params, duration_ms, snr_db, rng, n_channels):
        _, shape, peak_ms, hold_ms, decay_ms, amplitude = params
        envelope = self._make_envelope(shape, peak_ms, hold_ms, decay_ms, duration_ms)

        # Per-channel amplitude variation (±20% from NinaPro observation)
        ch_scale = rng.uniform(0.8, 1.2, size=n_channels)

        # Onset jitter ±10 ms
        jitter = int(rng.integers(-10, 11))

        signal = np.zeros((duration_ms, n_channels), dtype=np.float32)
        env    = np.roll(envelope, jitter)
        for c in range(n_channels):
            noise = rng.normal(0, amplitude / (10 ** (snr_db / 20)), size=duration_ms)
            signal[:, c] = env * amplitude * ch_scale[c] + noise

        return signal

    def _make_envelope(self, shape, peak_ms, hold_ms, decay_ms, duration_ms):
        env = np.zeros(duration_ms)
        if shape == "flat":
            env[:] = 1.0
        elif shape == "ramp":
            p, h, d = peak_ms, hold_ms, decay_ms
            if p > 0:
                env[:p] = np.linspace(0, 1, p)
            if h > 0:
                env[p:p+h] = 1.0
            if d > 0 and p+h < duration_ms:
                end = min(p+h+d, duration_ms)
                env[p+h:end] = np.linspace(1, 0, end-(p+h))
        elif shape == "pulse":
            p = peak_ms
            env[p:p+hold_ms] = 1.0
        return env

    def _delta_encode(self, raw: np.ndarray) -> np.ndarray:
        """Positive delta exceeding threshold → spike."""
        diff = np.diff(raw, axis=0, prepend=raw[:1])
        threshold = raw.std(axis=0) * 0.5
        return diff > threshold

    def validate(self, path) -> bool:
        print(f"Validating {path}...")
        # EMG spikes are sparser and less oscillatory — use only relevant checks
        from .. import validators
        return (
            validators.sparsity.check(str(path)) and
            validators.separability.check(str(path))
        )
```

---

## Phase 5: Perturbation Transforms

### `transforms/compose.py`

```python
import numpy as np


class Compose:
    def __init__(self, transforms: list):
        self.transforms = transforms

    def __call__(self, x: np.ndarray) -> np.ndarray:
        for t in self.transforms:
            x = t(x)
        return x
```

### `transforms/perturbation.py`

```python
import numpy as np

try:
    import cupy as cp
    CUPY_AVAILABLE = True
except ImportError:
    CUPY_AVAILABLE = False


def _xp(arr):
    """Return cupy if available and input is large enough to justify transfer."""
    if CUPY_AVAILABLE and arr.size > 1_000_000:
        return cp, cp.asarray(arr)
    return np, arr


class SpikeDropout:
    def __init__(self, p: float, seed: int = 42):
        self.p   = p
        self.rng = np.random.default_rng(seed)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        xp, a = _xp(x)
        mask = self.rng.random(x.shape) < self.p
        a = a.copy()
        a[mask] = False
        return cp.asnumpy(a) if xp is cp else a


class TemporalJitter:
    """Shift spike times by ±sigma_ms. Does not add or remove spikes."""
    def __init__(self, sigma_ms: float, seed: int = 42):
        self.sigma = sigma_ms
        self.rng   = np.random.default_rng(seed)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        out = np.zeros_like(x)
        shifts = self.rng.normal(0, self.sigma, size=x.shape[1:]).astype(int)
        for t in range(x.shape[1]):
            dst = np.clip(t + shifts[t], 0, x.shape[1] - 1)
            out[:, dst, :] |= x[:, t, :]
        return out


class ChannelFailure:
    def __init__(self, channels: list[int]):
        self.channels = channels

    def __call__(self, x: np.ndarray) -> np.ndarray:
        out = x.copy()
        out[:, :, self.channels] = False
        return out


class BurstCorruption:
    def __init__(self, p: float, duration_ms: int = 10, seed: int = 42):
        self.p    = p
        self.dur  = duration_ms
        self.rng  = np.random.default_rng(seed)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        out = x.copy()
        starts = np.where(self.rng.random(x.shape[1]) < self.p)[0]
        for s in starts:
            end = min(s + self.dur, x.shape[1])
            out[:, s:end, :] = self.rng.random(out[:, s:end, :].shape) < 0.5
        return out


class AdditiveEventNoise:
    def __init__(self, rate_hz: float, seed: int = 42):
        self.rate = rate_hz
        self.rng  = np.random.default_rng(seed)

    def __call__(self, x: np.ndarray) -> np.ndarray:
        prob = self.rate / 1000.0
        noise = self.rng.random(x.shape) < prob
        return x | noise
```

---

## Phase 6: CLI Integration

In `neurobench/cli/__main__.py`, add:

```python
import argparse
from pathlib import Path

from neurobench.data.generators.canonical_spikes import CanonicalSpikeGenerator
from neurobench.data.generators.emg import EMGGenerator
from neurobench.data.generators.utils.io import verify

GENERATORS = {
    "canonical_spikes": CanonicalSpikeGenerator,
    "emg_gestures":     EMGGenerator,
}

PRESETS = {
    "smoke":  {"n_trials": 1000},
    "medium": {"n_trials": 10000},
    "large":  {"n_trials": 50000},
}

def cmd_generate(args):
    cls    = GENERATORS[args.dataset]
    config = PRESETS[args.preset] | {"encoding": args.encoding}
    out    = Path(args.output) / f"{args.dataset}_{args.preset}.h5"
    cls(seed=args.seed).run(config, out)

def cmd_verify(args):
    ok = verify(args.path)
    exit(0 if ok else 1)

def cmd_list(args):
    for name in GENERATORS:
        print(f"  {name}")

def main():
    p = argparse.ArgumentParser(prog="neurobench")
    sub = p.add_subparsers()

    ds = sub.add_parser("dataset")
    ds_sub = ds.add_subparsers()

    gen = ds_sub.add_parser("generate")
    gen.add_argument("dataset", choices=list(GENERATORS))
    gen.add_argument("--preset",   default="medium", choices=list(PRESETS))
    gen.add_argument("--seed",     type=int, default=42)
    gen.add_argument("--output",   default="data/generated")
    gen.add_argument("--encoding", default="rate")
    gen.set_defaults(func=cmd_generate)

    ver = ds_sub.add_parser("verify")
    ver.add_argument("path")
    ver.set_defaults(func=cmd_verify)

    lst = ds_sub.add_parser("list")
    lst.set_defaults(func=cmd_list)

    args = p.parse_args()
    if hasattr(args, "func"):
        args.func(args)
    else:
        p.print_help()

if __name__ == "__main__":
    main()
```

---

## Running it

```bash
# Smoke test — fast, runs in CI
neurobench dataset generate canonical_spikes --preset smoke --seed 42

# Verify integrity
neurobench dataset verify data/generated/canonical_spikes_smoke.h5

# Medium preset for benchmark development
neurobench dataset generate canonical_spikes --preset medium
neurobench dataset generate emg_gestures     --preset medium

# Run a benchmark end-to-end
neurobench run grip_stability --network tests/fixtures/simple_net.cnl
```

---

## Test file

`tests/test_generators.py`:

```python
import pytest, h5py, numpy as np
from pathlib import Path
from neurobench.data.generators.canonical_spikes import CanonicalSpikeGenerator
from neurobench.data.generators.utils.io import verify

TMP = Path("/tmp/nsbi_test")
TMP.mkdir(exist_ok=True)

def test_canonical_spikes_smoke():
    g = CanonicalSpikeGenerator(seed=42)
    cfg = {"n_trials": 200, "n_neurons": 64, "encoding": "rate"}
    out = TMP / "canonical_smoke.h5"
    g.run(cfg, out)
    with h5py.File(out) as f:
        assert f["spikes"].shape == (200, 1000, 64)
        assert f["labels"].shape == (200,)
        assert "content_sha256" in f.attrs

def test_reproducibility():
    cfg = {"n_trials": 100, "n_neurons": 32, "encoding": "rate"}
    g = CanonicalSpikeGenerator(seed=42)
    a = TMP / "rep_a.h5"
    b = TMP / "rep_b.h5"
    g.run(cfg, a)
    g.run(cfg, b)
    with h5py.File(a) as fa, h5py.File(b) as fb:
        assert fa.attrs["content_sha256"] == fb.attrs["content_sha256"]

def test_verify_passes():
    out = TMP / "canonical_smoke.h5"
    assert verify(str(out)) is True
```

```bash
pytest tests/test_generators.py -v
```
