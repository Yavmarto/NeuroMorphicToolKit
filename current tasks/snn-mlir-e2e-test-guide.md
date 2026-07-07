# SNN-MLIR Integration — End-to-End Test Guide

## Verified Implementation Status (2026-07-04)

**Status: DONE.** Analysis/verification-procedure doc — it documents how to test an already-built pipeline
rather than proposing new work, but since it makes concrete implementation claims, those were checked
against code:

- **Step 1 (no-Docker sanity tests):** exist and pass. `workers/snn_mlir_compiler/test_codegen.py` (4 tests)
  and `Neurobench/neurobench/tests/test_snn_mlir_runner.py` (6 tests) both ran green in this session
  (`python -m pytest ... -p no:nengo -v`).
- **Step 2 (real worker build):** `docker-compose.yml` defines a `snn-mlir-compiler` service exposing port
  8007 with a `/health` healthcheck (`start_period` configured) and `SNN_MLIR_COMPILER_WORKER_URL` wired into
  dependent services. `workers/snn_mlir_compiler/main.py` exposes `snn_opt_available`/`snn_mlir_available`
  in its health payload as described.
- **Step 3/4 (NIR export + worker `/compile`):** `neurocnl/backend/app/routers/nir_inspect.py` and the
  simulators preflight router (`neurocnl/backend/app/routers/simulators.py`, `preflight-nir` referenced in
  `neurocnl/frontend/lib/services/api_client.dart` and `simulator_preflight.dart`) exist as described.
  `workers/snn_mlir_compiler/main.py` has `_compile_c_to_binary()`.
- **Step 5 (Neurobench e2e run):** `Neurobench/neurobench/app/routers/snn_mlir.py` defines
  `run_snn_mlir_benchmark`, registered in `Neurobench/neurobench/app/main.py`, backed by
  `Neurobench/neurobench/app/runners/snn_mlir_runner.py` — matches the documented
  `/api/neurobench/snn_mlir/run` flow.
- **Known limitation called out in the doc (constant all-zero stimulus in `_compile_c_to_binary`,
  `spike_fidelity` reads 0):** still current in `workers/snn_mlir_compiler/main.py` — this is a documented,
  intentional limitation, not a discrepancy.

**Missing:** nothing implementation-wise; this doc's claims all check out against code and passing tests.
The heavier Docker build (step 2) and full live e2e curl calls (steps 3-5) were not executed in this audit
(would require live services), but all referenced files/endpoints/routers exist and are wired together.

Companion to the SNN-MLIR integration plan (Phases 1-4: pip toolchain, `.mlir` text
export, native C codegen worker, Neurobench fast-sim runner). Use this to verify the
full pipeline works, and to verify an exported `.nir` file is actually correct rather
than assuming it.

## 1. No-Docker sanity check (fast, do this first)

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
python -m pytest workers/snn_mlir_compiler/test_codegen.py -p no:nengo -v
cd Neurobench/neurobench && python -m pytest tests/test_snn_mlir_runner.py -p no:nengo -v
```

Proves the C codegen and runner logic work against real gcc + mocked worker. Green
here means the logic is sound before paying for the heavy build below.

## 2. Build the real worker (heavy — multi-GB, multi-minute, builds LLVM/MLIR from source)

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
docker compose build snn-mlir-compiler
docker compose up -d snn-mlir-compiler
```

Wait for healthy (healthcheck has `start_period: 60s`):

```bash
docker compose ps snn-mlir-compiler
curl http://localhost:8007/health
```

Expect `{"status":"ok","snn_opt_available":true,"snn_mlir_available":true}`. If
`status: degraded`, one of the two is missing — check `docker compose logs snn-mlir-compiler`.

## 3. Get a `.nir` file

Build a simple feedforward network in NeuroStudio (canvas), then export it:

- Toolbar → export dialog → pick `NIR (.nir)` (or `SNN-MLIR (.mlir)` to eyeball the
  text export directly — both now go through the real `neurosim` export route,
  `/api/neurosim/export/{format}`).
- Or via API:

```bash
curl -s -X POST http://localhost:<neurosim-port>/api/neurosim/export/nir?allow_approximate=true \
  -H "Content-Type: application/json" \
  -d '{"nodes": [...], "edges": [...], "metadata": {}}' \
  | python -c "import sys,json,base64; open('network.nir','wb').write(base64.b64decode(json.load(sys.stdin)['content']))"
```

### How to verify the `.nir` is actually correct (not "probably")

The export dialog's "Export Target Fidelity" banner is **not** a per-file check —
every `.nir`/`.mlir` export always shows the same hardcoded `approximate` verdict
("produced by a NeuroSim-local serializer"). It says nothing about whether this
specific file is valid. Use one of these instead:

1. **NIR Importer panel** — in the canvas/Studio screen, toolbar icon tooltipped
   "NIR Importer" (upload icon, top right). Import the exported `.nir` there. It
   calls `POST /api/nir/inspect`, which uses `h5py` to walk the real HDF5 file and
   returns the actual group/dataset tree (shapes, dtypes, attrs, data previews).
   Malformed file → visible error, not a silent pass.
2. **Simulator Preflight** (Simulator panel) — upload the same `.nir` + pick a
   backend (`lava_sim`, `snntorch_sim`, `sc_neurocore_sim`). Calls
   `POST /api/simulators/preflight-nir`, which does a real `nir.read()` (hard
   422 `nir_parse_error` if malformed) then classifies concept support against
   that backend — the same `nir` package the snn-mlir worker uses.

If both load the file and show sensible content, the file is structurally valid.

## 4. Test the worker directly

```bash
NIR_B64=$(base64 -i network.nir | tr -d '\n')
curl -s -X POST http://localhost:8007/compile \
  -H "Content-Type: application/json" \
  -d "{\"nir_content_b64\":\"$NIR_B64\",\"compile_binary\":true,\"n_steps\":100}" \
  | python -m json.tool
```

Check the response has non-empty `main_c`, `snn_data_h`, and a `binary_b64` string.

## 5. Full end-to-end via Neurobench

```bash
curl -s -X POST http://localhost:<neurobench-port>/api/neurobench/snn_mlir/run \
  -H "Content-Type: application/json" \
  -H "X-API-Key: <your-key>" \
  -d '{"benchmark_id":"e2e-test-1","network_path":"/absolute/path/to/network.nir"}' \
  | python -m json.tool
```

## 6. How to verify it worked

- HTTP 200 with a `BenchmarkResult` JSON body, `target_id: "snn-mlir"`,
  `metric_provenance: "cpu_estimated"`.
- `metrics.latency_ms` is a real positive number (actual wall-clock of the
  compiled C binary running).
- `metrics.accuracy` is `null` — expected, no labeled dataset drives this path yet.
- `metrics.spike_fidelity`: expect this key to be either absent or `0` on a real
  end-to-end run today. The worker feeds the compiled binary a constant all-zero
  stimulus (`workers/snn_mlir_compiler/main.py`'s `_compile_c_to_binary`), so
  nothing crosses threshold — known limitation (no real spike-train input format
  wired up yet), not a bug. To see nonzero spikes, use the unit-test path (step 1),
  where fake layers get a real `[1.0, 1.0]`-style stimulus.
- 502 → worker unreachable/timed out — check `docker compose logs snn-mlir-compiler`
  and that `SNN_MLIR_COMPILER_WORKER_URL` resolves from Neurobench's container network.
- 400 → `.nir` graph is likely non-feedforward or non-fully-connected — snn-mlir's
  hard topology constraint (see the integration plan doc).

## Known limitations / follow-ups

- `spike_fidelity` will read 0 until a real spike-train input format is wired into
  the worker's `_compile_c_to_binary` (currently constant zero stimulus).
- `Neurochip` (Teensy) parity for snn-mlir is deferred (Phase 3b), not started.
