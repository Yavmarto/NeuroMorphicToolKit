# Intel Loihi / Lava Integration — Status & Testing Guide

> Date: 2026-05-04

There are **two Intel neuromorphic paths** in the codebase — Intel Loihi 2 (via NxSDK) and Intel Lava framework. No OpenVINO or Intel MKL integration exists anywhere in the suite.

---

## Integration Status

### Fully working

| Component | Location | Notes |
|---|---|---|
| Loihi 2 NxSDK package generator | `Neurochip/neurochip/app/services/loihi_generator.py` | Templates, caching, ZIP packaging wired up. Weight binaries are zero-filled placeholders (explicitly marked mock) |
| Lava FastAPI router | `Neurochip/neurochip/app/routers/lava.py` | `POST /compile`, `/run`, `/stop` — correct 503/500 branching, session management |
| NengoLoihi code-gen exporter | `neurocnl/neurocnl/export/loihi_exporter.py` | Generates valid `nengo_loihi` simulator code from a Nengo network |
| Lava code-gen exporter | `neurocnl/neurocnl/export/lava_exporter.py` | Generates Lava `LIF`/`Dense` process code, correctly switches `Loihi2SimCfg` vs `Loihi2HwCfg` |
| LavaIO NIR converter | `neurocnl/neurocnl/converter/lava_io.py` | NIR→Lava and Lava→NIR. Edge extraction from Lava runtime graph is a known limitation (acknowledged in source) |
| `LoihiExportContract` validator | `neurocnl/neurocnl/contracts/hardware_export.py` | Validates weight quantizability, ≤1024 neurons/core, ≤62-tick delay budget |
| `LAVA_PROFILE` capability profile | `neurocnl/neurocnl/backends/lava_capabilities.py` | Correct and complete |
| `LoihiExporter` class | `Neuro-Dream-Hand/neurodreamhand/hardware/loihi_exporter.py` | Builds Nengo SNN from trained weights, runs via `nengo_loihi.Simulator`, computes latency/energy |
| Lava bridge / weight exporter | `Neuro-Dream-Hand/neurodreamhand/hardware/lava_bridge.py` | `LavaWeightExporter`, INT4/INT8 quantization, `build_lava_reflex_spec`, `SpikeEncoder/Decoder` — complete |
| Hardware target manifest | `Neurochip/neurochip/targets/loihi2.json` | 128 cores, 1M neurons, 1–8-bit weights, 1000 mW, 2.5 pJ/spike-op |
| Suite API proxy | `suite_api/domains/neurochip/router.py` | Proxies `/api/neurochip/hardware/lava/{path}` to hw-worker port 8002 |

### Partial / stubbed

| Component | Issue |
|---|---|
| `LavaBackend.compile()` weights | Connection weights default to identity diagonal (`np.fill_diagonal(weights, 1.0)`). Comment: *"In a real implementation, weights would be mapped from network.connections"* |
| `lava_generator.py` ZIP scaffold | Outputs a hardcoded single-LIF template with `# ... additional setup ...` — scaffold only, not real deployment code |
| `_generate_mock_hdf5_bytes()` | Explicitly mocked — writes zeroed weight matrices. Production path would use `h5py` + `crossbar_exporter` |

### Requires external hardware / deps

- **Lava execution** (`/compile`, `/run`, `/stop`) requires `lava-nc` installed (Python <3.11). Without it → 503.
- **Physical Loihi 2 hardware run** requires an Intel INRC board + `nxsdk` (restricted academic access).
- **NengoLoihi simulator** requires `nengo-loihi>=1.0.0` optional extra.

---

## Step-by-Step Testing Guide

### Step 1 — Neurochip unit tests (no hardware required)

Tests the generator logic, ZIP structure, and caching. All should pass without any Intel deps installed.

```bash
cd Neurochip
python -m pytest neurochip/tests/test_loihi_generator.py -v
```

Covers:
- `test_build_template_context` — template context dict built correctly from a `NetworkInput`
- `test_build_template_context_large_network` — neuron-to-core mapping (5000 neurons → 4 cores)
- `test_generate_mock_hdf5_bytes_8bit/32bit` — weight binary byte layout matches expected struct format
- `test_generate_loihi_package_cache_miss` — full ZIP built with correct contents, progress callback fires, cache written
- `test_generate_loihi_package_cache_hit` — returns cached bytes immediately, fires single callback

---

### Step 2 — Neurochip Lava endpoint smoke test (no hardware required)

Verifies the router returns HTTP 503 (not 500) when `lava-nc` is absent.

```bash
cd Neurochip
python -m pytest neurochip/tests/test_lava.py -v
```

Covers:
- `test_lava_compile_missing_dep` — POSTs to `/api/neurochip/hardware/lava/compile`, asserts HTTP 503 and `"not installed"` in detail

---

### Step 3 — Neurochip contract and pipeline tests

Covers `TargetDevice.LOIHI_2`, `TargetDevice.LAVA`, and `DeploymentManifest` validation.

```bash
cd Neurochip
python -m pytest neurochip/tests/test_contracts.py neurochip/tests/test_artifact_contracts.py neurochip/tests/test_hardware_pipeline.py neurochip/tests/properties/ -v
```

---

### Step 4 — NeuroCNL Lava/Loihi export tests

Tests code-generation for both sim and hardware targets. Requires `nengo` and `nir` (core deps — no hardware needed).

```bash
cd neurocnl
python -m pytest neurocnl/export/test_lava_integration.py neurocnl/export/test_lava_sim_path.py neurocnl/backends/test_capabilities.py neurocnl/contracts/test_contracts.py -v
```

Covers:
- `test_lava_exporter_hw_mode_false` — generated code contains `Loihi2SimCfg`, not `Loihi2HwCfg`
- `test_lava_exporter_hw_mode_true` — generated code contains `Loihi2HwCfg()`
- `test_lava_io_from_nir_hw_mode_false/true` — same assertions via the NIR→Lava path
- `LAVA_PROFILE` capability profile fields
- `LoihiExportContract` validation (neuron/core limits, weight quantizability, delay budget)

---

### Step 5 — Neuro-Dream-Hand Lava bridge tests

Comprehensive weight quantization and spec-building tests. No hardware or `lava-nc` required.

```bash
cd Neuro-Dream-Hand
python -m pytest tests/test_neurodreamhand/test_lava_bridge.py -v
```

Covers:
- `LavaWeightExporter` — default 8-bit, custom 4-bit, invalid bit-widths raise `ValueError`
- Weight quantization: shape preservation, INT8 range `[-127, 127]`, INT4 range `[-7, 7]`, zero weights, per-call bit override
- JSON export to disk
- `build_lava_reflex_spec` — default/multi-finger/process-type/custom config variants
- `SpikeEncoder` / `SpikeDecoder` construction
- Full round-trip: `create_lava_process_from_model`

---

### Step 6 — Neuro-Dream-Hand Loihi exporter tests

Tests `LoihiExporter` class — builds a Nengo SNN and runs it via `nengo_loihi.Simulator`.

```bash
cd Neuro-Dream-Hand
python -m pytest tests/test_neurodreamhand/test_loihi_exporter.py -v
```

> If `nengo-loihi` is not installed, the `ImportError` test passes; remaining tests fail with a missing-dep error. Install with:
> ```bash
> pip install ".[chip]"   # installs h5py + nengo-loihi
> ```

---

### Step 7 — Suite integration checks

Cross-module integration tests verifying contracts between Neurochip, NeuroCNL, and the rest of the suite.

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
python3 -m pytest tests/integration/test_cross_module.py -v
python3 -m pytest tests/integration/test_teensy_e2e.py -v
```

---

### Step 8 — Launcher doctor

Verify the control plane has no fatal errors blocking startup.

```bash
python3 scripts/launcher_control_service.py --doctor --json
```

Treat `fatalCount > 0` as a blocker. Then run the full launcher guardrails:

```bash
bash scripts/run_launcher_guardrails.sh
```

---

### Step 9 — Smoke test the live Loihi export endpoint

With Neurochip backend running (`uvicorn neurochip.app.main:app --port 8002`):

```bash
curl -s -X POST http://localhost:8002/api/neurochip/export \
  -H "Content-Type: application/json" \
  -d '{
    "target": "loihi",
    "num_neurons": 512,
    "num_synapses": 1024,
    "neuron_model": "LIF",
    "populations": [{"name": "input", "size": 256}, {"name": "output", "size": 256}],
    "connections": [{"pre": "input", "post": "output", "weight_count": 1024}],
    "weight_bit_width": 8,
    "network_depth": 2
  }' --output loihi_package.zip && unzip -l loihi_package.zip
```

Expected ZIP contents: `loihi_deploy/deploy.py`, `loihi_deploy/config.json`, `loihi_deploy/crossbar_weights.bin`, `loihi_deploy/README.md`.

---

### Step 10 — Test Lava endpoints (requires `lava-nc` + Python <3.11)

Install the optional dep first:

```bash
pip install "lava-nc"
```

Then with Neurochip running on port 8002:

```bash
# 1. Compile
SESSION=$(curl -s -X POST http://localhost:8002/api/neurochip/hardware/lava/compile \
  -H "Content-Type: application/json" \
  -d '{"network": {"num_neurons": 10, "num_synapses": 5, "neuron_model": "LIF", "populations": [], "connections": [], "weight_bit_width": 8, "network_depth": 1}, "run_config": "sim"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")

echo "Session: $SESSION"

# 2. Run 100 steps
curl -s -X POST http://localhost:8002/api/neurochip/hardware/lava/run \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION\", \"steps\": 100}"

# 3. Stop
curl -s -X POST http://localhost:8002/api/neurochip/hardware/lava/stop \
  -H "Content-Type: application/json" \
  -d "{\"session_id\": \"$SESSION\"}"
```

> **Known limitation:** The compile step uses identity-diagonal weights instead of real network connections — functional for sim loop validation but not representative of a real network.

---

## Capability Matrix

| | No extra deps | With `nengo-loihi` | With `lava-nc` (Py <3.11) | With INRC board |
|---|:---:|:---:|:---:|:---:|
| Loihi generator unit tests | ✅ | ✅ | ✅ | ✅ |
| Lava 503 smoke test | ✅ | ✅ | ✅ | ✅ |
| NeuroCNL Lava/Loihi code-gen | ✅ | ✅ | ✅ | ✅ |
| Lava bridge & weight exporter | ✅ | ✅ | ✅ | ✅ |
| Loihi exporter (Neuro-Dream-Hand) | ⚠️ partial | ✅ | ✅ | ✅ |
| Lava `/compile` `/run` `/stop` | ❌ 503 | ❌ 503 | ✅ (stub weights) | ✅ |
| Real Loihi 2 board deployment | ❌ | ❌ | ❌ | ✅ (INRC access required) |
