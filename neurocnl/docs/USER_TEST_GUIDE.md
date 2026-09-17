# neurocnl — User Test Guide

> **Version**: neurocnl 0.6.0
> **Prerequisites**: Python ≥ 3.11, the neurocnl `.venv` must be active.
> **Working directory for every command in this guide**: `neurocnl/` (the submodule root, where `pyproject.toml` lives).

---

## 0 · Setup Checklist

Before running any test, make sure you are inside the correct environment:

```bash
# From the repo root
cd neurocnl
source .venv/bin/activate   # or your venv of choice

# Confirm the install
python -c "import neurocnl; print(neurocnl.__version__)"
```

**Expected output:**
```
0.6.0
```

If you see `ModuleNotFoundError`, install the package first:

```bash
pip install -e ".[dev,viz]"
```

---

## 1 · Automated Test Suite

This is the fastest and most thorough check. Run it first.

### 1.1 · Full unit / regression suite

```bash
PYTHONPATH=. pytest neurocnl/ backend/tests/ -v --tb=short
```

**What it covers:**
- CNL parser (all 21 concepts)
- IR lowering (NetworkIR construction)
- Layer 1 & Layer 2 validation
- Nengo network generation
- Pipeline orchestration (`run_pipeline`)
- Spike encoding
- Visualization lazy-import behaviour
- All 8 built-in template specs (regression)
- Export artefact regression
- Teensy deployment contract
- Logging configuration

**Expected outcome:**
All tests should `PASS`. The full suite typically finishes in **20–60 s** on a laptop (simulation tests are the slowest).

> [!NOTE]
> Tests that call `run_pipeline(..., skip_simulation=False)` internally start a real Nengo simulation, which is the source of most of the runtime.

**Exit code 0** = everything green. Any failures print a short traceback with the exact assertion that failed.

### 1.2 · Run only regression tests (8 demo specs)

```bash
PYTHONPATH=. pytest neurocnl/neurocnl/tests/test_demo_spec_regression.py -v -m regression
```

**Expected outcome per spec name:**

| Spec | Parse | Lower to IR | Validate | Generate | Simulate |
|---|---|---|---|---|---|
| `reflex_arc` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `emg_gripper` | ✓ | `LoweringError` expected | ✓ | ✓ (direct) | ✓ (direct) |
| `audio_wakeword` | ✓ | `LoweringError` expected | ✓ | ✓ (direct) | ✓ (direct) |
| `eeg_attention` | ✓ | ✓ (has `axonal_delay` in metadata) | ✓ | ✓ | ✓ |
| `visual_tracker` | ✓ | ✓ (populations have explicit sizes) | ✓ | ✓ | ✓ |
| `slip_reflex` | ✓ | ✓ (has `axonal_delay` in metadata) | ✓ | ✓ | ✓ |
| `prosthetic_reflex` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `prosthetic_sleep` | ✓ | ✓ | ✓ | ✓ | ✓ |

`emg_gripper` and `audio_wakeword` contain `stdp_learning` sentences, which are not yet supported by `lower_to_ir()`. The regression test explicitly asserts a `LoweringError` for them, then falls back to calling the Nengo generator directly — this is **expected and correct** behaviour.

### 1.3 · Run with coverage

```bash
PYTHONPATH=. pytest neurocnl/ backend/tests/ --cov=neurocnl --cov-report=term-missing
```

**Expected outcome:** `TOTAL` line should show ≥ 70 % coverage (the configured floor in `pyproject.toml`).

### 1.4 · Linting & type checking

```bash
ruff check .          # style / correctness
mypy .                # type checking
```

Both should produce zero errors for the committed codebase.

---

## 2 · Python Library API — Manual Spot Checks

Open a Python REPL from the `neurocnl/` directory:

```bash
python
```

### 2.1 · Version and top-level imports

```python
import neurocnl

print(neurocnl.__version__)  # → '0.6.0'
print(dir(neurocnl))  # shows all public symbols
```

**Expected:** version string `0.6.0` and a list containing `parse`, `validate`, `generate`, `run_pipeline`, `rate_encode`, `temporal_encode`, `delta_encode`, `export`, `EXPORTERS`.

---

### 2.2 · Parsing CNL sentences

```python
from neurocnl import parse, ParseError

# --- Valid sentence ---
spec = parse("The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0")
print(spec)
```

**Expected output** (a `ParsedSentence` TypedDict):
```python
{
    "concept": "threshold_firing",
    "subject": "sensory neuron",
    "action": "fire",
    "verb": "MUST",
    "negated": False,
    "condition": "membrane potential exceeds 1.0",
    "raw": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
}
```

```python
# --- Parse error (should raise ParseError) ---
try:
    parse("This is not valid CNL")
except ParseError as e:
    print(e.detail)  # expects a dict with 'message', 'line', 'raw'
```

**Expected:** `ParseError` is raised; `e.detail['message']` contains a human-readable explanation.

---

### 2.3 · Parsing multi-line spec text

```python
from neurocnl.pipeline import parse_spec_text

spec_text = """
# Comment lines are skipped
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8
"""

results = parse_spec_text(spec_text)
print(f"Lines parsed: {len(results)}")  # → 2
print(f"All valid: {all(r['valid'] for r in results)}")  # → True
```

---

### 2.4 · Validation

```python
from neurocnl import validate

spec = parse("The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0")
params = {
    "threshold": 1.0,
    "resting_potential": 0.0,
    "refractory_period": 0.002,
    "tau": 0.02,
    "reset_potential": 0.0,
    "current_voltage": 0.5,
}
report = validate([spec], params)
print(report)
```

**Expected:** a dict with `overall` (`True`/`False`), `passed` (list of invariant names), `failed` (list), and optionally `warnings`.

**Validation failure example** (threshold below current voltage):

```python
bad_params = {**params, "threshold": 0.1, "current_voltage": 0.5}
bad_report = validate([spec], bad_params)
print(bad_report["overall"])  # → False
print(bad_report["failed"])  # → list of invariant failure dicts
```

---

### 2.5 · Network generation (Nengo)

```python
from neurocnl.pipeline import parse_spec_text, default_params_from_specs
from neurocnl.generation.nengo_generator import generate

REFLEX_SPEC = """
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0
"""

results = parse_spec_text(REFLEX_SPEC)
parsed = [r["parsed"] for r in results if r["valid"]]
params = default_params_from_specs(parsed)
net = generate(parsed, params)

print(type(net))  # → <class 'nengo.network.Network'>
print([ens.label for ens in net.all_ensembles])  # → ['sensory neuron', 'motor neuron']
```

---

### 2.6 · Full pipeline in one call

```python
from neurocnl.pipeline import run_pipeline

result = run_pipeline(REFLEX_SPEC, skip_simulation=True)

print(result.overall_pass)  # → True
print(result.validation["overall"])  # → True
print(result.planner.verdict)  # → 'faithful'
print([p.label for p in result.network.all_ensembles])
```

**Run with simulation** (takes ~1–3 s for 1.0 s of simulation):

```python
result = run_pipeline(
    REFLEX_SPEC,
    skip_simulation=False,
    skip_assertions=True,
    duration=0.5,
    dt=0.001,
)

print(result.overall_pass)  # → True
print(result.simulation["duration"])  # → 0.5
print(result.simulation["wall_time_seconds"])  # → float < 10.0
print(list(result.summary.keys()))
# → ['sensory_spike_count', 'motor_spike_count',
#    'sensory_mean_rate', 'motor_mean_rate',
#    'first_output_spike', 'input_to_output_latency']
print(result.summary["sensory_spike_count"])  # → int ≥ 0
```

---

### 2.7 · What `result.summary` means

| Key | Meaning | Typical range |
|---|---|---|
| `sensory_spike_count` | Total spikes fired by sensory ensemble over the entire simulation | 0–1000+ |
| `motor_spike_count` | Total spikes fired by motor ensemble | 0–1000+ |
| `sensory_mean_rate` | Spikes divided by duration (Hz) for sensory neurons | 0–500 Hz |
| `motor_mean_rate` | Same for motor neurons | 0–300 Hz |
| `first_output_spike` | Time (s) of first motor spike | 0.0–duration or `None` |
| `input_to_output_latency` | `first_motor_spike – first_sensory_spike` | ≥ 0.0 or `None` |

> [!NOTE]
> Nengo encoders are randomised per build. Exact spike counts will vary across runs; the structure (`overall_pass = True`, keys present, types correct) is what matters.

---

### 2.8 · Spike encoding utilities

```python
import numpy as np
from neurocnl import rate_encode, temporal_encode, delta_encode

signal = np.sin(np.linspace(0, 2 * np.pi, 1000))  # 1 s sine wave at dt=0.001
dt = 0.001

spikes_rate = rate_encode(signal, dt, max_rate=100.0)
spikes_temporal = temporal_encode(signal, dt, n_phases=8)
spikes_delta = delta_encode(signal, dt, threshold=0.1)

for name, spikes in [("rate", spikes_rate), ("temporal", spikes_temporal), ("delta", spikes_delta)]:
    print(
        f"{name}: shape={spikes.shape}, spike_count={int(spikes.sum())}, values in {{0.0,1.0}}: {set(spikes)}"
    )
```

**Expected:**
```
rate:     shape=(1000,), spike_count=<some positive int>, values in {0.0, 1.0}: {0.0, 1.0}
temporal: shape=(1000,), spike_count=8, values in {0.0, 1.0}: {0.0, 1.0}
delta:    shape=(1000,), spike_count=<varies>, values in {0.0, 1.0}: {0.0, 1.0}
```

All three return binary arrays (0.0 / 1.0) with the same length as the input signal.

- `temporal_encode` with `n_phases=8` always emits exactly **8 spikes** (one per phase window).
- `rate_encode` is stochastic (seeded at 42) — results are reproducible within a run.
- `delta_encode` is deterministic; spike count depends on signal variance and threshold.

---

### 2.9 · Visualization (requires `pip install -e ".[viz]"`)

```python
import numpy as np
from neurocnl.visualization import spike_raster, membrane_traces, to_html

# Generate fake spike data (100 timesteps, 5 neurons)
spike_data = (np.random.rand(100, 5) > 0.95).astype(float)
voltage_data = np.random.randn(100, 5)

fig_raster = spike_raster(spike_data, dt=0.001, title="Test Raster")
fig_traces = membrane_traces(voltage_data, dt=0.001)

# Export to inline HTML
html_img = to_html(fig_raster)
print(html_img[:50])  # → '<img src="data:image/png;base64,...'
```

**Expected:** no exceptions, `fig_raster` is a `matplotlib.figure.Figure`, `html_img` starts with `<img src="data:image/png;base64,`.

**Without `[viz]`:** accessing `neurocnl.spike_raster` should raise `AttributeError` cleanly (not `ImportError`):

```python
import neurocnl

try:
    _ = neurocnl.spike_raster
except AttributeError as e:
    print(f"AttributeError raised cleanly: {e}")  # expected
```

---

## 3 · Export Formats

The `export()` function and `EXPORTERS` dict accept format names for code generation.

### 3.1 · List available exporters

```python
from neurocnl.export import EXPORTERS

print(list(EXPORTERS.keys()))
```

**Expected keys** (core set, actual list may vary by installed extras):
`neuroml`, `c_header`, `loihi`, `lava`, `spinnaker`

### 3.2 · Export to Lava script

```python
from neurocnl.export import export

net = generate(parsed, params)  # from section 2.5
lava_script = export(net, format="lava")
print(lava_script[:300])  # Python source code for Intel Lava
```

**Expected:** a Python string beginning with comments and `import lava` / `from lava` statements.

### 3.3 · Export to NeuroML

```python
nml_xml = export(net, format="neuroml")
print(nml_xml[:200])  # XML content
```

**Expected:** XML string starting with `<?xml` or `<neuroml`.

### 3.4 · Export to NIR format

```python
from neurocnl.export.nir_exporter import export_to_nir
import tempfile, os

with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as f:
    tmp = f.name
export_to_nir(net, tmp)
print(f"NIR file size: {os.path.getsize(tmp)} bytes")  # > 0
os.unlink(tmp)
```

---

## 4 · Backend Capability Interrogation

### 4.1 · Query all backend capabilities

```python
from neurocnl.backends.capabilities import BACKEND_CAPABILITIES

for name, caps in BACKEND_CAPABILITIES.items():
    print(f"{name}: {caps.verdict}")
```

**Expected output** (matches `docs/support_matrix.md`):

```
nengo:      faithful
loihi:      approximate
lava:       approximate
spinnaker:  approximate
spinnaker2: approximate
akida:      approximate
teensy:     approximate
pynq:       approximate
sinabs:     approximate
rockpool:   unsupported
nir:        faithful
```

---

## 5 · REST API (Backend Server)

### 5.1 · Start the server

```bash
# From neurocnl/ directory, with venv active
PYTHONPATH=. uvicorn backend.app.main:app --host 127.0.0.1 --port 8000 --reload
```

**Expected startup output:**
```
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

Once running, open **http://127.0.0.1:8000/docs** in your browser for Swagger UI.

---

### 5.2 · Health check

```bash
curl -s http://127.0.0.1:8000/health | python3 -m json.tool
```

**Expected response:**
```json
{
    "status": "ok",
    "neurocnl_version": "0.6.0",
    "timestamp": "2026-...",
    "modules": {
        "nengo": { "available": true, "version": "3.x.x" },
        "nengo_loihi": { "available": false },
        "mujoco": { "available": false },
        ...
    },
    "disk": { "total_gb": ..., "used_gb": ..., "free_gb": ..., "low_space": false },
    "nengo_available": true
}
```

`status` should be `"ok"` (not `"degraded"`). If `nengo_available` is `false` the server returns HTTP 503.

---

### 5.3 · List templates

```bash
curl -s http://127.0.0.1:8000/api/templates | python3 -m json.tool
```

**Expected:** JSON with `"templates"` key containing ≥ 8 objects, each with `id`, `name`, `description`, `spec` (CNL text).

Known template IDs: `reflex_arc`, `emg_gripper`, `audio_wakeword`, `eeg_attention`, `visual_tracker`, `slip_reflex`, `prosthetic_reflex`, `prosthetic_sleep`.

---

### 5.4 · Parse endpoint

```bash
curl -s -X POST http://127.0.0.1:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"}' \
  | python3 -m json.tool
```

**Expected:**
```json
{
    "results": [
        {
            "line": 1,
            "raw": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "concept": "threshold_firing",
            "subject": "sensory neuron",
            "action": "fire",
            "verb": "MUST",
            "negated": false,
            "condition": "membrane potential exceeds 1.0",
            "valid": true,
            "error": null
        }
    ],
    "parse_error_count": 0,
    "overall_valid": true
}
```

**Parse error case:**

```bash
curl -s -X POST http://127.0.0.1:8000/api/parse \
  -H "Content-Type: application/json" \
  -d '{"spec": "This is not CNL"}' \
  | python3 -m json.tool
```

**Expected:** `"overall_valid": false`, `"parse_error_count": 1`, `results[0]["error"]` is a non-null message.

---

### 5.5 · Validate endpoint

```bash
curl -s -X POST http://127.0.0.1:8000/api/validate \
  -H "Content-Type: application/json" \
  -d '{
    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8\nThe sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    "params": {},
    "backend": "nengo"
  }' | python3 -m json.tool
```

**Expected:**
```json
{
  "overall": true,
  "layer1": { "overall": true, "passed": [...], "failed": [], "warnings": [] },
  "layer2": { "overall": true, "checks_passed": [...], "checks_failed": [], "neurons_found": ["sensory neuron", "motor neuron"] }
}
```

**Validation failure (zero-weight synapse):**

```bash
curl -s -X POST http://127.0.0.1:8000/api/validate \
  -H "Content-Type: application/json" \
  -d '{
    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.0",
    "params": {}
  }' | python3 -m json.tool
```

**Expected:** `"overall": false`, `layer2.checks_failed` contains an entry with `"check": "zero_weight_synapse"`.

---

### 5.6 · Simulate endpoint (async job)

Submit a simulation job:

```bash
curl -s -X POST http://127.0.0.1:8000/api/simulate \
  -H "Content-Type: application/json" \
  -d '{
    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8\nThe sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    "duration": 0.5,
    "dt": 0.001
  }'
```

**Expected HTTP 202 response:**
```json
{ "job_id": "some-uuid-string", "status": "queued" }
```

Poll the job (replace `<JOB_ID>`):

```bash
JOB_ID="<paste-job-id-here>"
curl -s http://127.0.0.1:8000/api/jobs/$JOB_ID | python3 -m json.tool
```

**While running:** `"status": "running"`.

**On completion:** `"status": "complete"` + result:
```json
{
  "status": "complete",
  "result": {
    "duration": 0.5,
    "dt": 0.001,
    "timesteps": 500,
    "wall_time_seconds": <float>,
    "probes": { "<probe_key>": { "type": "spike_raster", "times": [...], "neuron_indices": [...] } },
    "summary": {
      "sensory_spike_count": <int>,
      "motor_spike_count": <int>,
      "sensory_mean_rate": <float>,
      "motor_mean_rate": <float>,
      "first_output_spike": <float or null>,
      "input_to_output_latency": <float or null>
    },
    "backend_support": { "backend": "nengo", "verdict": "faithful", "warnings": [] }
  }
}
```

> [!NOTE]
> A 0.5 s simulation (500 timesteps, dt=0.001) typically completes in under 5 seconds of wall time on a laptop.

**Duration limit:** requests with `"duration" > 10.0` return HTTP 422.

```bash
curl -s -X POST http://127.0.0.1:8000/api/simulate \
  -H "Content-Type: application/json" \
  -d '{"spec": "...", "duration": 99.0, "dt": 0.001}' | python3 -m json.tool
# Expected: HTTP 422, detail contains "Duration must be at most 10.0s"
```

---

### 5.7 · Export endpoint

**Export as `.cnl` file:**

```bash
curl -s -X POST http://127.0.0.1:8000/api/export \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0", "format": "cnl"}' \
  -o spec.cnl
cat spec.cnl
```

**Expected:** the CNL text written to `spec.cnl`, HTTP 200 with `Content-Disposition: attachment; filename="spec.cnl"`.

**Export as HTML report:**

```bash
curl -s -X POST http://127.0.0.1:8000/api/export \
  -H "Content-Type: application/json" \
  -d '{"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0", "format": "html"}' \
  -o report.html
open report.html        # opens in browser on macOS
```

**Expected:** a self-contained HTML page with dark theme, CNL spec block, validation section, simulation section.

**Export as Lava script:**

```bash
curl -s -X POST http://127.0.0.1:8000/api/export \
  -H "Content-Type: application/json" \
  -d '{
    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8\nThe sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\nThe sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds\nThe connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    "format": "lava"
  }' -o network.py && head -20 network.py
```

**Expected:** Python file, HTTP response header `X-NeuroCNL-Backend-Verdict: faithful`.

---

### 5.8 · Backend smoke test (automated, with server)

This test starts the server itself; you do not need to start it separately:

```bash
PYTHONPATH=. NEUROCNL_RUN_BACKEND_SMOKE=1 pytest tests/test_backend_smoke.py -v
```

**Expected:** One test `test_studio_backend_flow_smoke` passes, exercises the full `templates → validate → simulate → poll` cycle against a real server process.

---

## 6 · Known Limitations to Verify Against

These are intentional limitations documented in `docs/support_matrix.md`. Verify that the system behaves exactly as documented:

### 6.1 · `rockpool` backend is broken

```python
from neurocnl.export import EXPORTERS

# rockpool should NOT appear in EXPORTERS (it is not wired)
print("rockpool" in EXPORTERS)  # → False (expected)
```

Importing `rockpool_io` directly also raises `NameError` on undefined variables at lines 27/32/77. **Do not attempt to use this path.**

### 6.2 · `sinabs` — branching topologies fail

```python
from neurocnl.converter.sinabs_io import SinabsConverter

# Only sequential topologies are supported.
# Any branching or recurrent spec will raise NotImplementedError.
```

The sequential path works; branching raises `NotImplementedError` at runtime.

### 6.3 · Akida — no recurrent connections

A spec with a self-connection and `backend="akida"` must fail at the planner step:

```python
from neurocnl.pipeline import run_pipeline

result = run_pipeline(
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to sensory neuron MUST have WITH synaptic weight of 1.0",
    backend="akida",
    skip_simulation=True,
)
print(result.overall_pass)  # → False
print(
    result.errors[0]
)  # → "Layer 1 validation failed (akida_no_recurrent_connections / akida_topology_is_sequential): ..."
```

### 6.4 · Low-risk NIR concepts lower to IR but stay metadata-only in NIR

```python
result = run_pipeline(
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
    "The sensory neuron MUST exhibit firing adaptation WITH time constant of 0.2 seconds",
    skip_simulation=True,
)
print(result.overall_pass)  # → True
print(result.ir is not None)  # → True
print(result.ir.populations["sensory neuron"].attributes["adaptive_spiking_enabled"])  # → True
print(result.ir.populations["sensory neuron"].attributes["adaptation_time_constant"])  # → 0.2
```

This is expected. The current low-risk set now lowers into IR:

- `population_coding_range`
- `adaptive_spiking`
- `receptor_dynamics`
- `background_noise`

For the `nir` backend these concepts are currently exportable as metadata-backed semantics, not executable NIR operators.

For `receptor_dynamics` specifically, this is now an explicit policy decision rather than a
temporary ambiguity: NeuroCNL preserves receptor type and time constant as advisory NIR metadata
for downstream consumers, and the current bridge does not promise an executable synapse-operator
lowering path.

### 6.5 · Loihi timestep mismatch is a warning, not a failure

```python
result = run_pipeline(
    "The network MUST operate WITH timestep of 2 ms\n"
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    backend="loihi",
    skip_simulation=True,
)
print(result.overall_pass)  # → True  (warnings do not fail the pipeline)
print(result.planner.verdict)  # → 'approximate'
warnings = result.validation["layer1"]["warnings"]
print(any("Declared network_timestep" in w["message"] for w in warnings))  # → True
```

---

## 7 · CLI Entry Point

```bash
neurocnl --help
```

**Expected:** usage text printed without `ImportError` or `ModuleNotFoundError`. The entry point is `neurocnl.simulation.run_simulation:main`.

Run a simulation via the CLI (reads a CNL file, simulates, prints JSON result):

```bash
cat backend/app/templates/reflex_arc.cnl | python -m neurocnl.simulation.run_simulation \
  --duration 0.3 --dt 0.001
```

> [!NOTE]
> The CLI reads CNL from stdin or a file path argument depending on the `run_simulation.py` implementation. Check `python -m neurocnl.simulation.run_simulation --help` for exact usage.

---

## 8 · Install Smoke Tests (optional, slow)

These tests create fresh virtual environments and build a wheel from source. They are skipped by default because they take several minutes.

```bash
NEUROCNL_RUN_INSTALL_SMOKE=1 pytest tests/test_install_smoke.py -v
```

**Expected:**

| Test | What it checks |
|---|---|
| `test_core_import` | `import neurocnl` works in a clean venv with no other dependencies |
| `test_core_version_accessible` | `__version__ == '0.6.0'` |
| `test_core_public_api` | `parse`, `validate`, `generate`, `run_pipeline` all importable |
| `test_core_entry_point` | CLI `--help` exits cleanly |
| `test_core_viz_absent_is_graceful` | `spike_raster` absent without `[viz]` (no crash) |
| `test_viz_matplotlib_available` | `[viz]` extra installs matplotlib |
| `test_viz_spike_raster_importable` | visualization module importable |
| `test_sinabs_gate_clean` | `sinabs` absent in core venv → clean `ModuleNotFoundError` |

---

## 9 · Summary Pass / Fail Criteria

| Area | Pass condition |
|---|---|
| Automated suite | All `pytest` tests green; coverage ≥ 70 % |
| CNL parsing | All 8 template specs parse without errors; invalid CNL raises `ParseError` |
| Validation | `reflex_arc` and the 6 non-STDP specs validate `overall=True`; zero-weight synapse triggers `zero_weight_synapse` |
| Generation | `result.network` is a Nengo `Network` with ≥ 2 ensembles |
| Simulation | `result.overall_pass=True`; `simulation.duration` matches request; `summary` keys all present |
| Spike encoding | All 3 encoders return binary arrays of correct shape |
| REST API server | `/health` → `status: ok`; `/api/templates` → ≥ 8 templates; simulation job cycle works end-to-end |
| Export | `cnl`, `html`, `lava`, `neuroml` exports return non-empty content without errors |
| Known limits | `rockpool`, `akida` recurrent, and metadata-only NIR concepts behave exactly as documented |
