# neurocnl + Neurochip + Neuro-Dream-Hand Pipeline Analysis

**Date:** 08-Apr-2026
**Branch:** `dev`
**Scope:** neurocnl, Neurochip, Neuro-Dream-Hand — inter-module pipeline readiness and POC task breakdown

---

## How Far Along

The Teensy path is the most complete. The PYNQ path is real but has a coordination gap. Akida is feature-gated behind a proprietary SDK.

| Path | Status |
|------|--------|
| CNL → Neurochip Teensy firmware → flash → NDH verification | **Fully implemented end-to-end** |
| CNL → Neurochip PYNQ artifact → PYNQ simulator | **Works today (simulator fallback)** |
| CNL → Neurochip PYNQ → real PYNQ Z2 board | **Blocked: `.bit` bitstream not in repo** |
| CNL → Neurochip Akida | **501 without BrainChip SDK** |

---

## How Well They Work Together

The artifact handoff between neurocnl and Neurochip is tight and deliberately mirrored. The `NetworkInput` schema that Neurochip's export endpoints expect is exactly what neurocnl's `map_network_ir_to_teensy_payload()` produces — same field names, same types, same hardware limit constants. Both repos have property-based tests that verify these don't drift.

The Neuro-Dream-Hand handoff is a direct function import, not HTTP. Neurochip's flash router calls `neurodreamhand.toolkit_handoff.verify_post_flash_runtime()` after a successful flash, which runs a 3-phase serial verification:
1. Serial smoke check — connect, send zero-grip, time first round-trip
2. Hardware demo — 5 grip commands at 0.5, count valid sensor frames
3. Optional HITL latency benchmark (p50/p95/p99)

**Gap: no orchestration layer.** Each stage is a separate HTTP call. Nothing chains `neurocnl → Neurochip → NDH` in one invocation. The `neurochip_pynq_handoff.py` module in neurocnl partially solves this for PYNQ as a Python library, but it is not exposed over HTTP.

---

## Endpoint Map

### neurocnl (port 8000)

| Endpoint | Role in pipeline |
|----------|-----------------|
| `POST /api/deploy/teensy/network` | Parse + IR lower + fail-closed Teensy gate → returns `NetworkInput` payload |
| `POST /api/deploy/pynq/network` | Parse + IR lower + exportability planning → returns verdict only (no payload) |
| `POST /api/export` (format=pynq) | Generates neurocnl-side PYNQ artifact ZIP |
| `POST /api/generate` | Returns `NetworkGraph` (needed for manual PYNQ `NetworkInput` reconstruction) |

### Neurochip (port 8002)

| Endpoint | Role in pipeline |
|----------|-----------------|
| `POST /api/neurochip/export/teensy` | Accepts `NetworkInput` → Jinja2 PlatformIO firmware ZIP |
| `POST /api/neurochip/export/pynq` | Accepts `NetworkInput` + weights → `pynq_deploy/` ZIP |
| `POST /api/neurochip/serial/flash` | Uploads firmware ZIP, runs PlatformIO flash job |
| `GET /api/neurochip/serial/flash/{job_id}` | Poll flash job status |
| `POST /api/neurochip/serial/flash/{job_id}/verify` | Calls NDH `verify_post_flash_runtime()` → `VerificationReport` |
| `POST /hardware/pynq/deploy` | Loads FPGA overlay, writes weights via MMIO |
| `POST /hardware/pynq/run` | DMA spike inference → `output_spikes` |
| `GET /hardware/pynq/status` | Backend lifecycle state |

### Neuro-Dream-Hand (library, not HTTP service)

| Entry point | Role in pipeline |
|-------------|-----------------|
| `toolkit_handoff.verify_post_flash_runtime()` | 3-phase post-flash serial verification |
| `hardware/pynq_controller.py` | PYNQ hardware path with CPU fallback |
| `verification/pynq_sitl_verifier.py` | SITL verification (mirrors Neurochip's) |

---

## Complete Teensy Flow (today)

```
1. POST /api/deploy/teensy/network          (neurocnl)
   Input:  {spec: CNL text, weight_bit_width: 8|16|32}
   Output: {verdict, warnings, payload: NetworkInput}
           payload = {num_neurons, num_synapses, neuron_model="LIF",
                      populations: [{name, size}],
                      connections: [{pre, post, weight_count}],
                      weight_bit_width, network_depth}

2. POST /api/neurochip/export/teensy        (Neurochip)
   Input:  NetworkInput (from step 1 payload)
   Output: application/zip → neurochip_firmware.zip
           (PlatformIO project with Jinja2-rendered C++ firmware)

3. POST /api/neurochip/serial/flash         (Neurochip)
   Input:  multipart {file: firmware.zip, port: "/dev/ttyACM0"}
   Output: {job_id, status, progress_pct}

4. POST /api/neurochip/serial/flash/{id}/verify   (Neurochip → NDH)
   Input:  {port, run_demo, run_hitl, hitl_samples, timeout_s}
   Output: VerificationReport {smoke, demo, hitl, passed, summary}
```

Without hardware, step 3 runs in PlatformIO simulation mode and step 4 is unit-testable with mock serial.

---

## Complete PYNQ Flow (today, simulator fallback)

```
1. POST /api/deploy/pynq/network            (neurocnl)
   Input:  {spec: CNL text, weight_bit_width: 4|8|16}
   Output: {support_state, warnings, rejections, network_summary}
           ← verdict only, no NetworkInput payload (gap — see tasks)

2. POST /api/neurochip/export/pynq          (Neurochip)
   Input:  NetworkInput + quantized_weights + bit_width
   Output: pynq_deploy.zip
           {overlay_config.json, weights.bin, register_map.json, manifest.json, README.md}

3. POST /hardware/pynq/deploy               (Neurochip)
   Input:  {weights, config, bitstream_path, register_map}
   Output: {"status": "success"}
           (PynqSimulator used when `pynq` library absent)

4. POST /hardware/pynq/run                  (Neurochip)
   Input:  {input_spikes: List[int], timesteps: int}
   Output: {output_spikes: List[int], timesteps, execution_time_us}
```

For real PYNQ Z2 hardware, step 3 requires `snn_overlay.bit` + `snn_overlay.hwh` (not in repo).

---

## Artifact Format Alignment

The `NetworkInput` schema is symmetrically defined and tested across both modules:

| Field | neurocnl produces | Neurochip expects |
|-------|------------------|-------------------|
| `num_neurons` | sum of pop sizes | `int` |
| `num_synapses` | sum of weight_counts | `int` |
| `neuron_model` | hardcoded `"LIF"` | `str` |
| `populations` | `[{name, size}]` | `List[{name, size}]` |
| `connections` | `[{pre, post, weight_count}]` | `List[{pre, post, weight_count}]` |
| `weight_bit_width` | from request param | `int` |
| `network_depth` | computed via BFS | `int` |

Hardware limits are mirrored:
- Teensy: 4096 neurons, 1 MB, 8/16/32-bit — identical in `neurocnl.contracts.teensy_deployment_contract` and `Neurochip.contracts.teensy_deployment_contract`
- PYNQ: 65536 neurons, 512 KB, 4/8/16-bit — identical in both `pynq_deployment_contract` mirrors
- Property-based tests (Hypothesis) in both repos validate these constants don't drift

---

## What Is Stubbed or Missing

| Item | Location | Impact |
|------|----------|--------|
| `POST /api/neurochip/partition` | `Neurochip/routers/analysis.py` | Returns placeholder string — no implementation |
| `POST /api/neurochip/compare` | `Neurochip/routers/analysis.py` | Returns placeholder string — no implementation |
| Akida deploy + inference | `Neurochip/routers/akida.py` | HTTP 501 without BrainChip `cai` SDK |
| `snn_overlay.bit` + `.hwh` | Referenced throughout | Real PYNQ hardware path blocked without bitstream |
| Loihi zero weights | `Neurochip/loihi_generator.py:91` | Loihi ZIP always has zero-weight network unless caller supplies pre-quantized weights |
| PYNQ coordination gap | `neurocnl/routers/deploy.py` | `/api/deploy/pynq/network` returns verdict only, not `NetworkInput` payload — caller must manually reconstruct |
| Orchestration layer | Nowhere | No single call chains neurocnl → Neurochip → NDH |

---

## Core Tasks for a Serious POC

### P0 — Must-do before any demo

**1. Build an orchestration endpoint or script**
A caller should be able to send `{spec, port, weight_bit_width}` and get back a `VerificationReport`. Currently requires 4 separate HTTP calls across 2 services with manual payload passing between them. Options:
- Add an orchestration router to Neurochip that calls neurocnl internally, or
- Write a thin CLI script that chains the calls (faster to demo, lower coupling)

**2. Fix the PYNQ coordination gap in neurocnl**
`POST /api/deploy/pynq/network` returns a verdict but not a `NetworkInput` payload. The Teensy endpoint is the right model — it returns both. Update the PYNQ deploy endpoint to return `payload: NetworkInput` alongside the verdict so both paths are symmetric.

**3. Triage Neurochip's 370 mypy errors**
Many are SDK-import availability errors suppressible with `TYPE_CHECKING`. Split into:
- SDK-import false positives → suppress with `TYPE_CHECKING` guard
- Genuine annotation gaps → fix

You cannot confidently refactor or extend Neurochip's pipeline until type coverage is trustworthy.

### P1 — Needed for a credible demo

**4. Synthesize or stub the PYNQ bitstream**
`snn_overlay.bit` + `snn_overlay.hwh` are referenced everywhere but not in the repo. For hardware demo, either synthesize via Vivado or add a clearly documented stub `.bit` that exercises the load path without real inference so the full deploy→run cycle is demonstrable.

**5. Replace `print()` with logging in NDH and Neurochip**
`neurodreamhand/toolkit_handoff.py` and `verification/pynq_sitl_verifier.py` both use `print()` in production paths. Replace with `logging.getLogger(__name__)` per `CODING_STYLE_GUIDE.md`.

**6. Remove or implement the `/partition` and `/compare` stub endpoints**
Both return `{"message": "... placeholder"}` with HTTP 200. A reviewer hitting these will doubt the whole Neurochip service. Either implement them minimally or drop them from the router so they 404.

### P2 — Polish before showing externally

**7. Resolve Neurochip's dirty submodule pointer** in the parent repo (`+` prefix in `git submodule status` looks like uncommitted in-flight work).

**8. Wire the HITL benchmark into the demo flow**
`verify_post_flash_runtime()` has a fully implemented optional HITL latency phase that defaults to disabled. Running this and surfacing p50/p95/p99 latency numbers is exactly the kind of concrete hardware proof point that makes a POC credible.

**9. Tighten PBT coverage on the PYNQ handoff mapper**
Property-based tests cover the Teensy handoff thoroughly. The PYNQ handoff mapper (`neurochip_pynq_handoff.py`) has lighter coverage. Add Hypothesis strategies for `PynqRuntimeArtifact` → `NetworkInput` mapping to match the Teensy path.

---

## Readiness Summary

| Module | Pipeline Readiness | Primary Debt |
|--------|--------------------|-------------|
| neurocnl | 90% in pipeline role | PYNQ endpoint coordination gap; 11 mypy errors |
| Neurochip | 75% in pipeline role | 370 mypy errors; 2 stub endpoints; missing bitstream |
| Neuro-Dream-Hand | 85% in pipeline role | No HTTP service (library only); print() in prod paths |
| **Full Teensy path** | **~85%** | Orchestration layer; mypy debt |
| **Full PYNQ path** | **~70%** | Bitstream + coordination gap + orchestration layer |

The Teensy path is the cleanest shot at a first serious POC. Artifact formats are aligned, the verification handoff is real code, and PlatformIO simulation mode means no hardware required on day one. The PYNQ path is one bitstream file and one endpoint fix away from being equally complete.
