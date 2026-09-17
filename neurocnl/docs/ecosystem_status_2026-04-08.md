# NeuroCNL Ecosystem — Status & Remaining Work

**Date:** 2026-04-09 (updated)
**Scope:** neurocnl + directly coupled submodules (Neurosim, Neurochip, Neuro-Dream-Hand, Neurobench)

---

## 1. Overview

`neurocnl` is the central pipeline module of the NMTK stack. It provides CNL parsing, biological validation, Nengo code generation, hardware export, and a FastAPI service (port 8000) consumed by multiple submodules. The four modules below have non-trivial coupling — either importing neurocnl Python packages directly, calling its HTTP API, or acting as a handoff target.

```
Flutter Frontend (port 8000)
        │
        ▼
neurocnl backend (FastAPI, port 8000)
        │── parse / validate / generate / simulate / export
        │── deploy → Neurochip (port 8002) [Teensy / PYNQ handoff]
        │── prosthetic → Neuro-Dream-Hand [MuJoCo co-sim]
        │
Neurosim (port 8001)  ─── imports neurocnl.cnl / .ir / .planner
Neurobench            ─── imports neurocnl.simulation.run_pipeline
```

---

## 2. Module Status

### 2.1 neurocnl (v0.6.0 — Pre-Beta)

**Overall: GO for pre-beta labeling.** All 7 prerequisite issues (#22–#29) are closed. Tests: 860 passed, 82.94% coverage. CI: ruff, mypy strict, 70% floor, 3-OS matrix.

| Area | State | Notes |
|------|-------|-------|
| CNL Parser (19 families) | Stable | Regex-based; all families parser-recognized |
| Layer 1 Validator (16 invariants) | Stable | Biological constraints enforced |
| Layer 2 Validator | Stable | Cross-sentence consistency |
| Nengo Generator | Stable — faithful | Primary execution path |
| Simulation Runner | Stable | Full pipeline orchestration |
| Lava exporter | Working — approximate | Not hardware-validated |
| SpiNNaker exporter | Working — approximate | Projection scaling heuristics |
| SpiNNaker2 exporter | Partial — export-only | All-to-all connector is a stub primitive |
| Akida generator (Akida2) | Working — approximate | Sequential constraints apply; macOS SDK unavailable |
| Teensy handoff | Production-ready | Fail-closed; 100+ contract tests; real-hardware flash pending |
| PYNQ exporter + handoff | Export-ready | ZIP artifact + quantization done; FINN compilation not wired |
| sinabs converter | Partial — sequential only | `NotImplementedError` on branching topologies |
| rockpool exporter | Broken | `NameError` at runtime; do not use |
| NIR exporter | Working — faithful format | Weight distribution has a placeholder value |
| FastAPI backend | Stable | SQLite job store, structlog, Prometheus metrics, request ID middleware |
| Flutter frontend | Functional | Deploy screens production-ready; some secondary tabs stubbed |
| Hardware planner | Stable | Explicit fidelity verdicts: faithful / approximate / unsupported |

---

### 2.2 Neurosim (port 8001) — ~80% complete

**Coupling:** Imports `neurocnl.cnl.cnl_parser.parse()`, `neurocnl.ir.lower_to_ir()`, `neurocnl.pipeline`, `neurocnl.planner.plan_backend_support()` via `neurosim/app/services/neurocnl_bridge.py`.

| Area | State | Notes |
|------|-------|-------|
| 2-node reflex-arc CNL bridge | Working | Sensory → motor arcs parse and validate correctly |
| Multi-node graph bridge | Partial — fail-open | Falls back to local Neurosim generation; not fail-closed |
| Graph-to-CNL bidirectional sync | Partial | One direction works; round-trip sync incomplete |
| Backend API | Mature | Core simulation routes operational |
| Frontend UI migration | Pending | Some screens still on older widget patterns |

---

### 2.3 Neurochip (port 8002) — ~85% complete

**Coupling:** Acts as the handoff *target* for neurocnl's Teensy and PYNQ deployment paths. Receives HTTP POSTs from `neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py` and `neurochip_teensy_mapper.py`. Mirrors deployment contracts in `neurochip/contracts/teensy_deployment_contract.py`.

| Area | State | Notes |
|------|-------|-------|
| Teensy deployment endpoint | Production-ready | Contract gating, fail-closed; awaiting real-hardware flash on Teensy 4.1 |
| PYNQ deployment endpoint | Export-ready | Overlay ZIP accepted; FINN compilation pipeline is Phase 2 |
| Contract parity with neurocnl | Maintained | Both repos mirror the same hardware limits; must stay in sync |
| Integration tests (neurocnl → Neurochip) | Passing | Covered in neurocnl backend tests |

---

### 2.4 Neuro-Dream-Hand — ~95% complete

**Coupling:** `neurodreamhand/core/cnl_integration.py` imports `neurocnl.cnl.cnl_parser.parse()`, `neurocnl.layers.layer1_invariants.ALL_INVARIANTS`, and `neurocnl.utils.extract_numeric()`. `compile_cnl.py` runs the full neurocnl pipeline to compile specs for the SNN controller.

| Area | State | Notes |
|------|-------|-------|
| CNL spec compilation | Working | Full parse → validate → generate pipeline via neurocnl |
| Nengo reflex agent | Working | Feedforward SNN controller operational |
| MuJoCo drop-test co-sim | Working | Integrated in neurocnl prosthetic backend |
| Quantized STDP (Loihi/Akida) | Not started | Requires hardware-aware STDP quantization from neurocnl |
| HITL control loop | Not started | Human-in-the-loop real-time control integration |

---

### 2.5 Neurobench — ~70% complete

**Coupling:** `neurobench/app/services/benchmark_runner.py` imports `neurocnl.simulation.run_simulation.run_pipeline()`. Uses CNL specs as benchmark workloads and runs encoding comparisons through the neurocnl pipeline.

| Area | State | Notes |
|------|-------|-------|
| neurocnl pipeline benchmark | Working | Runs CNL specs through neurocnl; collects metrics |
| Hardware benchmark integration | Not started | Cross-hardware comparison (Nengo vs. Loihi vs. Teensy) |
| Cloud orchestration | Not started | Distributed benchmark execution |
| Backend API | Partial | Core routes operational |

---

## 3. Remaining Tasks

### 3.1 neurocnl — Fixes & Completions

#### Critical (blocks honest support claims)
- [ ] **Fix rockpool exporter** — `neurocnl/export/rockpool_exporter.py`: resolve `NameError` on `model`, `nodes`, `edges` (lines 27, 32, 77 of `rockpool_io.from_neurocnl`). Currently labeled "do not use" in support matrix.
- [ ] **Fix sinabs branching** — `neurocnl/converter/sinabs_io.py` line 201: implement branching topology support instead of raising `NotImplementedError`. Sequential path already works.
- [ ] **Fix NIR weight placeholder** — `neurocnl/export/nir_exporter.py` line 149: replace `weight = 1.0  # placeholder` with real weight distribution logic from the IR.

#### Near-term (post-beta, tracked as soft blockers)
- [ ] **SpiNNaker2 all-to-all connector** — `neurocnl/export/spinnaker2_exporter.py`: replace stub `AllToAllConnector` with a real SpiNNaker2 connectivity primitive or document the limitation clearly.
- [ ] **PYNQ FINN compilation pipeline** — Wire FINN compiler invocation into `pynq_exporter.py`. Currently generates overlay ZIP only; FPGA bitstream compilation is manual (Phase 2).
- [ ] **Loihi placement-aware mapping** — `neurocnl/export/loihi_exporter.py`: implement NxNet placement-aware core mapping. Currently uses default placement (approximate).
- [ ] **SSE streaming in hardware provider** — `neurocnl/frontend/lib/providers/hardware_provider.dart` lines 113–121: replace mock periodic polling with real Server-Sent Events from the backend.
- [ ] **Fault injection analysis tab** — `neurocnl/frontend/lib/screens/analysis_screen.dart` line 271: implement the fault injection analysis UI (currently entirely stubbed).
- [ ] **MuJoCo stream view widget** — `neurocnl/frontend/lib/widgets/mujoco_stream_view.dart`: wire MJPEG streaming from the prosthetic physics backend.

---

### 3.2 Neurosim — Remaining Work

- [ ] **Multi-node graph bridge — fail-closed** — `Neurosim/neurosim/app/services/neurocnl_bridge.py` lines 32–33: when topology exceeds 2-node reflex arc, either reject explicitly (fail-closed) or implement multi-node CNL synthesis. The current silent fallback to local generation is misleading.
- [ ] **Bidirectional graph↔CNL sync** — Complete the round-trip: graph edits should update the CNL spec, and CNL edits should update the graph visualization consistently.
- [ ] **Frontend UI migration** — Migrate remaining screens from older widget patterns to current nmtk_ui_core components.

---

### 3.3 Neurochip — Remaining Work

- [ ] **Teensy 4.1 real-hardware validation** — Flash a compiled network to actual Teensy 4.1 hardware and verify sensor I/O, timing, and spike thresholds match the contract spec.
- [ ] **PYNQ Z2 FINN compilation** — Coordinate with neurocnl Phase 2: implement FINN compiler invocation on the Neurochip side once neurocnl wires the overlay → bitstream step.
- [ ] **Contract version pinning** — Add a shared version field to the mirrored `teensy_deployment_contract.py` in both repos and enforce parity in CI so drift is caught automatically.

---

### 3.4 Neuro-Dream-Hand — Remaining Work

- [ ] **Quantized STDP (Loihi/Akida)** — Implement hardware-aware STDP quantization for on-chip learning. Depends on neurocnl providing quantized weight deltas from its Loihi/Akida generators.
- [ ] **HITL control loop** — Integrate a real-time human-in-the-loop control path: sensor → SNN inference → actuator command cycle that can be interrupted by human input.

---

### 3.5 Neurobench — Remaining Work

- [ ] **Hardware benchmark integration** — Run the same CNL spec through Nengo, Loihi, and Teensy paths and collect and compare timing, energy, and accuracy metrics.
- [ ] **Cloud orchestration** — Distributed benchmark execution across multiple hardware targets in parallel.

---

### 3.6 Cross-Module / Integration

- [ ] **Cross-hardware equivalence tests** — Verify that a given CNL spec produces equivalent spike behavior (within documented tolerances) across Nengo, Loihi, and Teensy. This is the foundational validation that all "approximate" claims need.
- [ ] **neurocnl ↔ Neurochip contract CI parity** — Mirror contract version in both repos; add a CI job that fails if the versions diverge.
- [ ] **Prosthetic SSE stream** — neurocnl backend `prosthetic/` router: push real-time MuJoCo simulation frames over SSE for the Flutter frontend to consume.

---

## 4. Priority Order

| Priority | Task | Module |
|----------|------|--------|
| 1 | Fix rockpool NameError | neurocnl |
| 2 | Fix sinabs branching NotImplementedError | neurocnl |
| 3 | Fix NIR weight placeholder | neurocnl |
| 4 | Multi-node graph bridge (fail-closed or implement) | Neurosim |
| 5 | Teensy 4.1 real-hardware flash | Neurochip |
| 6 | SpiNNaker2 all-to-all connector | neurocnl |
| 7 | SSE streaming (hardware provider + prosthetic) | neurocnl frontend |
| 8 | Bidirectional graph↔CNL sync | Neurosim |
| 9 | PYNQ FINN compilation pipeline | neurocnl + Neurochip |
| 10 | Cross-hardware equivalence tests | cross-module |
| 11 | Quantized STDP (Loihi/Akida) | Neuro-Dream-Hand |
| 12 | HITL control loop | Neuro-Dream-Hand |
| 13 | Hardware benchmark integration | Neurobench |
| 14 | Fault injection analysis tab | neurocnl frontend |
| 15 | Loihi placement-aware mapping | neurocnl |

---

## 5. Hardware Demo Checklists

What needs to happen to run an end-to-end live demo on each target. "Demo" means: author a CNL spec in the UI → receive a deployment verdict → generate firmware/scaffold → deploy to real hardware → observe output.

---

### 5.1 Teensy 4.1 — Closest to Ready

**Demo path:**
```
CNL spec (editor) → POST /api/deploy/teensy/network (neurocnl:8000)
  → verdict + NetworkInput payload
  → POST /hardware/teensy/deploy (Neurochip:8002)
  → Jinja2 firmware generation (main.ino, lif_engine.h, network_params.h, platformio.ini)
  → ZIP download → PlatformIO compile + serial upload → board runs LIF loop
```

**Software — already done:**
- [x] Fail-closed deployability verdict (contract gate)
- [x] Teensy validator: LIF-only, feedforward, static weights enforced
- [x] Neurochip firmware generator: Jinja2 templates produce valid C++ (`main.ino`, `lif_engine.h`, `network_params.h`, `platformio.ini`)
- [x] Flash service lifecycle: PENDING → COMPILING → UPLOADING → VERIFYING → DONE
- [x] Serial port enumeration + Teensy auto-detection
- [x] Flutter UI stepper: CNL → verdict → firmware → serial port → progress → verify
- [x] 100+ contract tests; E2E integration tests cover happy path + rejection cases

**What still needs to happen:**

Setup (one-time):
- [ ] Install [PlatformIO](https://platformio.org/install/cli) on the machine running Neurochip (port 8002)
- [ ] Install `pyserial` in the Neurochip venv (`pip install pyserial`)
- [ ] Plug in Teensy 4.1 via USB; confirm it appears as a serial device (`/dev/ttyACM*` on Linux, `COMx` on Windows)

Software gaps:
- [ ] **Post-flash runtime verification** — `Neurochip/neurochip/app/routers/serial.py` lines 65–107: returns 503 when `neurodreamhand` is not installed. Wire a fallback serial echo test that doesn't require Dream-Hand so verification step passes without the prosthetic stack.
- [ ] **Flash subprocess error propagation** — `Neurochip/neurochip/app/services/flash_service.py` lines 109–190: full stderr/stdout parsing from PlatformIO subprocess not finalized. Add structured error reporting so flash failures surface in the UI with actionable messages.
- [ ] **Contract CI parity** — Add a version field to both mirrored contracts (`neurocnl/contracts/teensy_deployment_contract.py` and `Neurochip/neurochip/contracts/teensy_deployment_contract.py`) and a CI job that fails on divergence.

Demo script (once setup is done):
1. Start neurocnl (`uvicorn backend.app.main:app --port 8000`)
2. Start Neurochip (`uvicorn neurochip.app.main:app --port 8002`)
3. Open the NMTK launcher → navigate to CNL editor
4. Paste a feedforward LIF spec (e.g., `examples/emg_reflex.cnl`)
5. Click Deploy → Teensy; confirm verdict shows `deployable`
6. Download firmware ZIP or trigger auto-flash via the serial port step
7. Observe LED blink / serial output confirming spike events

**Estimated effort to demo-ready:** ~1 day (mostly setup + verifying flash subprocess on real hardware).

---

### 5.2 PYNQ Z2 — Blocked on FPGA Bitstream

**Demo path:**
```
CNL spec (editor) → POST /api/deploy/pynq/network (neurocnl:8000)
  → exportability verdict + PynqOverlayConfig
  → ZIP artifact (overlay_config.json, weights.bin, register_map.json, manifest.json)
  → POST /hardware/pynq/deploy (Neurochip:8002)
  → load_overlay(snn_overlay.bit, snn_overlay.hwh) on PYNQ Z2 board
  → MMIO weight configuration → DMA spike transfer → inference result
```

**Software — already done:**
- [x] Exportability verdict (two-tier: exportable / exportable_with_warnings / not_exportable)
- [x] Weight packing: int4 (nibble-packed), int8, int16
- [x] ZIP artifact generation and contract validation
- [x] HTTP handoff from neurocnl → Neurochip (`neurochip_pynq_handoff.py`, 353 lines)
- [x] `pynq_backend.py` hardware abstraction: load_overlay, MMIO config, DMA spike transfer
- [x] `PynqSimulator` fallback: full LIF inference in-process when board unavailable
- [x] Flutter UI stepper: Prepare → Deploy → Monitor → SITL Verify
- [x] 136+ tests covering exporter, handoff, contracts, backend, and SITL path

**Hard blocker — FPGA bitstream missing:**
- [ ] **`snn_overlay.bit` + `snn_overlay.hwh` do not exist in the repo.** These are the Xilinx Vivado-synthesized FPGA bitstream and hardware handoff file that implement the SNN inference IP core. Without them, `load_overlay()` in `pynq_backend.py` cannot configure the programmable logic — the board's ARM core runs but no hardware acceleration is available.

Options for unblocking:
1. **Use the PynqSimulator for the demo** — no bitstream needed; inference runs on the ARM core via in-process Python. The entire UI flow works. Clearly label as "SITL mode" in the demo.
2. **Author a minimal SNN IP core in Vivado HLS** — implement a single LIF neuron layer as an AXI4-Lite IP block; synthesize with Vivado 2022.x targeting the Zynq-7000; export `.bit` + `.hwh`; drop into `Neurochip/neurochip/overlays/`. This is the full hardware path.

**What still needs to happen (for real hardware):**

Setup:
- [ ] Install Vivado 2022.x (or later) with Zynq-7000 device support — requires Xilinx account (~30 GB)
- [ ] Install the `pynq` Python library on both the PYNQ Z2 board (`pip install pynq`) and the dev machine for testing
- [ ] Ensure the PYNQ Z2 board is networked (Ethernet or USB-Ethernet) and reachable at a known IP

Bitstream development (Phase 2, significant effort):
- [ ] **Design SNN IP core in Vivado HLS** — implement LIF neuron array with AXI4-Lite register map matching `register_map.json` schema; weight loading via AXI4-Stream DMA; spike output via interrupt or polling
- [ ] **Synthesize and place-and-route for Zynq-7000** — target xc7z020clg400-1 (PYNQ Z2 chip); confirm BRAM usage ≤ 512 KB
- [ ] **Export `.bit` + `.hwh`** and commit to `Neurochip/neurochip/overlays/snn_overlay.*`
- [ ] **Wire Neurochip's `load_overlay()` path** — `pynq_backend.py` already calls `pynq.Overlay(bit_path)`; ensure bit/hwh paths resolve correctly from the overlay directory
- [ ] **Validate DMA transfer** — confirm weight packing format matches what the IP core reads from AXI4-Stream

Software gaps (independent of bitstream):
- [ ] **Board URL configuration in UI** — the Deploy step in the Flutter stepper has a text field for the board URL; verify this actually reaches the Neurochip service running on the board (not the dev machine's Neurochip) and that auth is handled
- [ ] **SITL → hardware toggle** — add an explicit mode toggle in the UI (SITL / real hardware) so the demo is unambiguous about which path is active
- [ ] **FINN integration (Phase 2, optional)** — `neurocnl/docs/PYNQ_FINN_Integration_Plan.md` documents automated HLS → bitstream via FINN; this is a future optimization, not a blocker for a first demo

Demo script (SITL path — works today):
1. Start neurocnl and Neurochip normally
2. Open NMTK → CNL editor → paste a valid LIF spec within PYNQ limits (≤65K neurons)
3. Click Deploy → PYNQ Z2; confirm verdict shows `exportable`
4. Configure board URL (can be `localhost:8002` for SITL)
5. Trigger deploy; monitor status polling; observe `RUNNING` state in UI
6. Verify step shows SITL inference result

**Estimated effort to demo-ready:**
- SITL demo: **already works** — run it today
- Real FPGA demo: **3–5 days minimum** (Vivado HLS IP design + synthesis + integration)

---

### 5.3 Akida — Works in Simulation; Needs Linux + SDK for Hardware

**Demo path:**
```
CNL spec (editor) → POST /api/deploy/akida/network (neurocnl:8000)
  → exportability verdict (unsupported / exportable_scaffold / sdk_deployable)
  → Python scaffold script + ZIP (akida.Sequential model)
  → POST /hardware/akida/construct + /map + /infer (Neurochip:8002)
  → AkidaSimulator (no SDK) OR akida.Model.map(device) (real hardware)
  → inference result
```

**Software — already done:**
- [x] Three-tier verdict: `unsupported` / `exportable_scaffold` / `sdk_deployable`
- [x] Topology verdict: `faithful` / `approximate` / `unknown`
- [x] Akida mapper: strict feedforward, single root, no cycles, ordered population list
- [x] Akida generator: produces `akida.Sequential()` Python scaffold with `Input` + `FullyConnected` layers
- [x] Weight quantization: 1, 2, 4-bit enforced by contract
- [x] ZIP scaffold package: network config, weights, manifest, README
- [x] `AkidaSimulator`: full LIF inference in-process; lifecycle UNINITIALIZED → CONSTRUCTED → MAPPED → RUNNING
- [x] Neurochip endpoints: `/hardware/akida/construct`, `/map`, `/infer`
- [x] Flutter UI stepper: CNL → readiness check → deploy config (version: akida1/akida2) → status → Neurobench verify
- [x] Akida version normalization (akida1 vs akida2 contract paths)

**What still needs to happen:**

For simulator demo (works on macOS today):
- [ ] **Neurobench verification toggle** — `nmtk/neuro_toolkit/lib/screens/akida_deploy_screen.dart`: the "Verify with Neurobench" checkbox is visually disabled with a "not yet available" label. Wire it to `POST http://localhost:8003/benchmark/run` when Neurobench is running. For the demo this can be a soft skip — just remove the disabled state so it's a real optional step.
- [ ] Confirm Neurochip is reachable from the neurocnl backend at port 8002 (networking check on demo machine)

For real Akida hardware demo:
- [ ] **Linux or Windows machine required** — BrainChip Akida SDK does not support macOS (documented in `akida_generator.py` lines 32–38). The simulator runs correctly on macOS, but `map_to_device()` requires the SDK. Use a Linux dev machine or VM.
- [ ] **Install BrainChip Akida SDK** — requires BrainChip developer program access; install via `pip install akida` (Linux/Windows only); confirm `akida.devices()` returns the target board
- [ ] **Connect Akida hardware** — PCIe card (desktop) or SoC module; confirm device enumeration
- [ ] **Akida 2 block types in generator** — `neurocnl/neurocnl/generation/akida_generator.py` lines 74–80: generator currently emits only `FullyConnected` regardless of Akida version. For an Akida 2 demo that uses recurrence or branching, add `Recurrent` and `BranchingConnector` emission paths. Akida 1 feedforward demo is not affected.
- [ ] **macOS → Linux handoff for SDK path** — since the neurocnl backend and NMTK launcher run on macOS, the Akida SDK call needs to happen on the Neurochip service running on a Linux host. Confirm the Neurochip base URL in the Flutter UI points to the Linux machine's port 8002, not localhost.

Demo script (simulator, works on macOS today):
1. Start neurocnl and Neurochip normally
2. Open NMTK → CNL editor → paste a feedforward LIF spec (e.g., `examples/emg_reflex.cnl`)
3. Click Deploy → Akida; select version `akida1`
4. Confirm verdict shows `sdk_deployable` or `exportable_scaffold`
5. Trigger construct → map → infer; observe lifecycle states in UI
6. Download scaffold ZIP for offline inspection

Demo script (real hardware, Linux):
- Same steps 1–4, but with Neurochip running on the Linux machine with SDK installed
- Step 5: `map_to_device()` targets physical Akida board instead of simulator
- Step 6: Inference result comes from on-chip spike execution

**Estimated effort to demo-ready:**
- Simulator demo (macOS): **works today** — only the Neurobench toggle needs wiring (~2 hours)
- Real hardware demo: **1–2 days** (SDK install + hardware setup + generator fix for Akida 2 block types)

---

### 5.4 Demo Readiness Summary

| Target | Simulator/SITL | Real Hardware | Blocker |
|--------|---------------|---------------|---------|
| **Teensy 4.1** | N/A (firmware, not simulation) | **~1 day** | PlatformIO setup + flash error propagation |
| **PYNQ Z2** | **Works today** (PynqSimulator) | **3–5 days** | FPGA bitstream (`snn_overlay.bit`) doesn't exist |
| **Akida** | **Works today** (AkidaSimulator) | **1–2 days** | Linux + BrainChip SDK + hardware device |

**Recommended demo order:**
1. **Akida simulator** — run today on macOS, clean UI story, no external deps
2. **Teensy 4.1** — highest ROI; all software in place; just needs hardware + PlatformIO
3. **PYNQ Z2 SITL** — demo the full UI pipeline without real FPGA
4. **PYNQ Z2 real hardware** — requires Vivado HLS work; schedule as Phase 2

---

## 6. Reference Files

| Topic | File |
|-------|------|
| Backend support (canonical) | `neurocnl/docs/support_matrix.md` |
| Pre-beta acceptance criteria | `neurocnl/docs/PRE_BETA_READINESS_REVIEW.md` |
| Akida deployment readiness | `neurocnl/docs/AKIDA_RELEASE_READINESS.md` |
| PYNQ deployment readiness | `neurocnl/docs/PYNQ_RELEASE_READINESS.md` |
| Teensy deployment readiness | `neurocnl/docs/TEENSY_RELEASE_READINESS.md` |
| PYNQ FINN Phase 2 plan | `neurocnl/docs/PYNQ_FINN_Integration_Plan.md` |
| Code health analysis | `neurocnl/docs/CODE_HEALTH_ANALYSIS.md` |
| neurocnl → Neurochip handoff (Teensy) | `neurocnl/neurocnl/handoff/neurochip_teensy_mapper.py` |
| neurocnl → Neurochip handoff (PYNQ) | `neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py` |
| Neurosim ↔ neurocnl bridge | `Neurosim/neurosim/app/services/neurocnl_bridge.py` |
| Dream-Hand CNL integration | `Neuro-Dream-Hand/neurodreamhand/core/cnl_integration.py` |
