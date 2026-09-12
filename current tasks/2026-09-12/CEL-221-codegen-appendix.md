

---

## Appendix A — All Studio deploy targets (not just simulators)

Studio lists **13 deploy targets** in `deploy_target_catalog/support.dart`. They fall into **four buckets**. Only the first bucket uses `POST /api/neurocnl/simulators/run` and shows spike rasters on the Review step.

### Bucket 1 — In-app simulators (`kind: simulator`)

| Target id | Label | Dev SDK (suite_api container) | Review step | Live spike test |
|---|---|:---:|:---:|:---:|
| `snntorch_sim` | snnTorch | ✅ snntorch + torch | ✅ | ✅ 760 spikes (`shd_digit_classifier_akida.cnl`) |
| `lava_sim` | Lava (Simulator) | ✅ via remote worker `:8012` | ✅ | ⚠️ runs, 0 spikes |
| `sc_neurocore_sim` | SC-NeuroCore (Simulation) | ✅ sc_neurocore | ✅ | ⚠️ runs, 0 spikes |

### Bucket 2 — Codegen / notebook frameworks (`kind: codegen`)

These are **not simulators**. They do **not** call `/api/simulators/run`. Studio generates a **Jupyter notebook cell** via `_generate_arch_code` in `notebook_target_codegen.py`. The Review step **never** shows a spike raster for them — they are compile/preview/verdict only (`deploy_review_step/support.dart`).

| Target id | Label | Dev SDK | What actually works | Recommended models |
|---|---|:---:|---|---|
| **brian2** | Brian2 | ✅ `brian2` | `Brian2IO().from_nir(graph)` emits runnable Brian2 script in notebook | `reflex_arc.cnl`, `coincidence_detector.cnl`, any feedforward LIF with scalar tau |
| **nengo** | Nengo | ✅ `nengo` | `NengoIO().from_nir(graph, dt=cfg.nengo_dt)` → Nengo Python; **not** reachable via `POST /api/export format=nengo` | Same feedforward LIF templates; RSynaptic/CubaLIF supported with approximate semantics |
| **sinabs** | Sinabs | ✅ `sinabs` + torch | **Inference/codegen only** — notebook explicitly says "Inference / code generation only"; no training loop | Sequential Linear→LIF chains after weights exist (e.g. `shd_digit_classifier.cnl` post-training) |
| **rockpool** | Rockpool | ✅ `rockpool` | Sequential feed-forward export via `RockpoolIO`; branching graphs unsupported. Support matrix marks rockpool exporter as degraded — treat as experimental | Simple sequential stacks only (`reflex_arc.cnl` class) |
| **pynn** | PyNN | ❌ `pyNN` not installed on dev | `PyNNIO().from_nir(graph)` when pyNN present; primarily for SpiNNaker export path | Feedforward LIF; used as export intermediate, not an in-app runner |

**How to "run" these:** Train (usually snnTorch) → open Compiled Artifacts / notebook → pick framework in pipeline config → execute the generated cell in Jupyter (`:8008`). There is no one-click Play raster in Studio for Brian2/Nengo/etc.

**Reachability API note:** `target_reachability.py` uses legacy ids `brian2_sim`, `nengo_sim`, `sinabs_sim`, `rockpool_sim` for SDK install probes. Studio deploy ids drop the `_sim` suffix (`brian2`, `nengo`, …).

### Bucket 3 — Hardware deploy (`kind: hardware`)

| Target id | Label | Dev status | Execution path | Recommended models |
|---|---|---|---|---|
| **akida** | Akida | ✅ SDK + card (`neurochip.service` active) | Neurochip `/api/neurochip/akida/*` deploy + inference | `shd_digit_classifier_akida.cnl`, `mnist_cnn_classifier_akida.cnl` (trained bundle) |
| **pynq** | PYNQ-Z2 | launcher preflight (not in container) | Overlay ZIP export + board SSH via launcher | Feedforward networks under synapse budget |
| **lava** | Lava / Loihi2 | ✅ worker reachable | Neurochip Loihi2 handoff; hardware needs `LOIHI_HOST` | Static-weight LIF networks |
| **sc_neurocore_fpga** | SC-NeuroCore FPGA RTL | needs `SC_NEUROCORE_FPGA_HOST` | RTL synthesis after sim passes; no Review raster | Same graphs as `sc_neurocore_sim` |

### Bucket 4 — Export-only (not in Studio deploy table, but in support matrix)

| Backend | Status | How accessed |
|---|---|---|
| **SpiNNaker (PyNN)** | approximate export | `spinnaker_exporter.py` / PyNN codegen |
| **SpiNNaker2** | export only; sim path has known `brian2_sim` import bug | `spinnaker2_exporter.py` |
| **Teensy** | handoff to Neurochip | C header export |
| **Loihi (NengoLoihi)** | approximate | `loihi_exporter.py`; needs Loihi dev access |
| **NengoLoihi** | via Nengo + loihi extra | not a separate Studio tile |

---

## Appendix B — Dev backend package probe (2026-09-12)

Inside `nmtk-deploy-suite_api-1` container:

| Package | Installed |
|---|:---:|
| brian2 | ✅ |
| nengo | ✅ |
| sinabs | ✅ |
| rockpool | ✅ |
| pynn (pyNN) | ❌ |
| snntorch + torch | ✅ |
| lava (in-process) | ❌ (worker at `:8012` instead) |
| sc_neurocore | ✅ |
| akida | ✅ |

`GET /api/neurocnl/notebook/target-availability` returned 500 on dev during this audit — use container probe or Studio target-availability UI as fallback.

---

## Appendix C — Quick answer to "what about Nengo and Brian2?"

| Question | Answer |
|---|---|
| Are they simulators? | **No.** Studio classifies them as `codegen`. |
| Do they show on Review? | **No** — no in-app spike raster. |
| Do they work at all? | **Yes for code generation** — converters exist, packages installed on dev, notebook tests cover Nengo/Rockpool/Sinabs codegen. |
| How do I run a model? | Generate notebook for that framework, execute in Jupyter. |
| Best shared demo model | `reflex_arc.cnl` or `shd_digit_classifier.cnl` (train on snnTorch first, then export notebook to Nengo/Brian2/Sinabs). |
