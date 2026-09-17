# neurocnl Backend Support Matrix

This document is the canonical reference for what `neurocnl` can honestly claim to do today.
All other docs cross-reference this file. Claims here are derived directly from
`neurocnl/backends/capabilities.py`, the individual backend capability profiles, and
confirmed implementation state in the exporter and converter code.

---

## Fidelity Terms

`neurocnl` uses three terms consistently across the project:

- `faithful` — execution closely preserves the intended semantics
- `approximate` — execution or export works, but semantics rely on heuristics or backend-specific simplifications
- `unsupported` — the project cannot honestly claim runtime or backend support yet

A fourth term, `parser-recognized`, means the sentence family is accepted by `neurocnl.cnl.cnl_parser` but says nothing about execution fidelity.

**Important:** parser recognition is broader than execution fidelity, and exporter availability is not the same as validated on-hardware execution. Producing an export file (a Python script, C header, or ZIP overlay) means the artifact was generated — it does not mean the artifact has been compiled, flashed, or run on real hardware. On the Akida path specifically, NeuroCNL exportability is not proof of BrainChip SDK deployability; that confirmation must come from Neurochip runtime verification in the target environment.

---

## Backend Support Matrix

| Backend | Overall Status | Execution Type | Topology Support | Key Constraints | Environment Requirements |
|---|---|---|---|---|---|
| `nengo` | **approximate** | Notebook-generation target via `neurocnl.converter.nengo_io.NengoIO.from_nir` (NIR to Nengo Python source, reachable via Hardware Deployment's Nengo target / `framework="nengo"`) | approximate | Handles `nir.Input`, `nir.Output`, `nir.Linear`, `nir.Affine`, `nir.LIF`, and `nir.CubaLIF` — including CNLStudio's `cnl.RSynaptic` / `cnl.Synaptic`, which the NIR exporter represents as a flat `nir.CubaLIF` plus a same-population recurrent `nir.Linear` self-loop, not a nested subgraph. Other primitives (Conv2d, pooling, etc.) raise rather than silently degrade. Nengo's own discretization is a real, inherent accuracy ceiling relative to snnTorch on an identical architecture (roughly 78.6% vs roughly 92% on the reference Braille RNN) — this is not a bug to chase further. The standalone `POST /api/export` endpoint does not support `format="nengo"` (returns HTTP 400 Unsupported, not 410 Gone) — Nengo is reachable only through notebook generation, not the generic export endpoint. | `pip install nengo` plus the `nir` package |
| `loihi` | **approximate** | NengoLoihi script | approximate | Placement-aware topology mapping is still pending; timing resolution fixed at 1 ms | `pip install ".[loihi]"` + Intel Loihi developer access |
| `lava` | **approximate** | NeuroCNL deployability + Neurochip Loihi 2 simulator handoff | approximate | Simulator-first e2e is supported for static-weight LIF networks; structured topology may surface warnings; hardware mode is preflight-only unless a real Loihi 2 runtime is available | `lava` package (Intel) |
| `spinnaker` | **approximate** | Export script (PyNN) | approximate | Projection topology may need backend-specific manual tuning | PyNN + SpiNNaker toolchain |
| `spinnaker2` | **approximate — export only** | Export script (py-spinnaker2) | approximate | I/O modules are still stubs; connectivity is lowered to explicit connection lists using represented-dimension weights | `py-spinnaker2` package |
| `akida` / `akida2` | **approximate** for CNL mapping; **hardware-verified companion available** | IR-direct generator + Neurochip handoff, plus versioned ONNX bundle conversion | approx (akida2 CNL), unsupported (akida1 CNL); reusable ONNX conversion path | CNL exportability is not SDK deployability. The separate `AkidaModelBundleV1` path validates ONNX/calibration/evaluation data, uses QuantizeML + CNN2SNN, persists `.fbz`, and reports hardware verified only when the paired host maps a physical device. STDP, homeostatic plasticity, STP, receptor dynamics remain unsupported on CNL-mapped Akida targets. | BrainChip Akida, CNN2SNN, QuantizeML, ONNX; Linux/Windows Python 3.10–3.12; **macOS is not supported by the akida package** |
| `teensy` | **approximate** | Handoff to Neurochip (port 8002) | unsupported (multi-population) | Feedforward LIF only; no recurrent connections, no axonal delays, no learning rules; int8 / int16 / float32 weights | Teensy 4.1 hardware; Neurochip backend running |
| `pynq` | **approximate — export only** | Export overlay ZIP | approximate | Max ~64 K synapses at int4 precision; **FINN compilation pipeline is a Phase 2 placeholder — the FINN stage is not yet wired** | PYNQ Z2 (Zynq-7000 SoC); overlay ZIP must be manually loaded |
| `sinabs` | **partial — inference/codegen only** | Trained NIR import and inference wrapper | approximate | Sequential Linear/Affine/LIF/IF graphs are supported. Studio presents inputs for 25 timesteps, resets state per batch, and exposes spike-count outputs; decay/threshold/reset are mapped approximately. There is no Sinabs training adapter, so Studio never emits the generic snnTorch optimizer loop for this target. | `sinabs` package + PyTorch |
| `rockpool` | **partial — sequential only** | Rockpool module export | approximate (sequential) / **unsupported (branching)** | Sequential feed-forward exports work through NIR and direct IR lowering; branching and merged topologies remain unsupported | `rockpool` package |
| `nir` | **approximate — primary supported surface** | Direct `CNL -> IR -> NIR` compile, plus `NIR -> CNL` round-trip document generation | approximate | Materializer emits `Input`, `Output`, `LIF`, dense `Linear`, and `Delay` nodes; delays are executable; STP depression and homeostatic plasticity now lower approximately (weight scale and LIF threshold respectively); neuromodulation and facilitation-type STP survive as validated structured metadata; learning rules, timing, and exact tensor intent survive as advisory metadata | `nir` package |

---

## What "export only" Means

Several backends above are marked *export only*. This means `neurocnl` generates a file artifact
(a Python script, C header, or ZIP overlay) that must be separately compiled and deployed via the
vendor's toolchain. Producing the artifact is the extent of neurocnl's responsibility for those
backends — it does not imply compilation success, hardware validation, or runtime correctness on
the target device.

---

## Environment Requirements Summary

| Backend | pip extras / packages | OS restrictions |
|---|---|---|
| `nengo` | `pip install nengo` (`nir` already required elsewhere) | None documented; not reachable via `POST /api/export` — notebook generation only |
| `loihi` | `pip install ".[loihi]"` (NengoLoihi) | Loihi developer program access required for hardware |
| `lava` | `lava` (Intel) | None documented; Loihi 2 hardware remains optional and environment-dependent |
| `spinnaker` | PyNN, spynnaker / spalloc | SpiNNaker board or HBP access |
| `spinnaker2` | `py-spinnaker2` | SpiNNaker 2 board access |
| `akida` | BrainChip `akida`, `cnn2snn`, `quantizeml`, `onnx` | **macOS not supported** by the akida package; physical proof requires a paired Linux/Windows host |
| `teensy` | none (generation only); Neurochip backend for deploy | Teensy 4.1 hardware for actual deployment |
| `pynq` | none (export only); PYNQ board + Vivado for full pipeline | PYNQ Z2 board; FINN toolchain for Phase 2 |
| `sinabs` | `sinabs`, `torch` | None; inference/codegen only in Studio |
| `rockpool` | *(broken — do not use)* | — |
| `nir` | `nir` | None |

---

## NIR Fidelity Subset

The `nir` row above is intentionally `approximate`, not `faithful`, even though it is now the primary supported product surface.

Today, NeuroCNL can export a valid NIR graph directly from `NetworkIR`, but only a subset is represented as executable NIR structure rather than advisory metadata.

Faithful in current NIR export:

- threshold firing via `nir.LIF.v_threshold`
- membrane potential decay via `nir.LIF.tau`
- synaptic weights via `nir.Linear.weight`
- matrix-native CNL for explicit dense, identity, and diagonal connection weights now lowers directly
  into exact `nir.Linear.weight` tensors when the connection shape is declared or deterministic
- inhibitory polarity via signed `nir.Linear.weight`
- basic population I/O boundaries via `nir.Input` and `nir.Output`

Approximate or metadata-backed in current NIR export:

- refractory period is preserved in node metadata, not as a first-class NIR neuron parameter
- timing declarations are carried as advisory metadata rather than executable NIR timing semantics,
  but the materializer now machine-checks duplicate kinds and delay-quantization consistency
- STDP and related learning rules are preserved in metadata, not as executable graph nodes
- homeostatic plasticity lowers **approximately**: when `homeostatic_target_rate_hz` is present on a
  population, the LIF threshold is adjusted as `v_threshold = target_rate × tau`; the original default
  threshold and target rate are preserved in node metadata for round-trip fidelity; populations without
  a numeric target rate remain metadata-only
- neuromodulation is preserved in graph metadata as a **validated structured schema** (each rule must
  carry at minimum a `modulator` field; optional `effect_type` is range-checked); no executable
  modulatory control nodes are emitted
- short-term plasticity lowers **approximately** for the depression subtype when the CNL sentence
  includes a numeric `utilization_rate`: the `Linear` weight is scaled by
  `(1 − utilization_rate)` at steady state; facilitation-type STP and rules without a numeric
  `utilization_rate` stay metadata-only (fail-closed)
- adaptive spiking is preserved in population metadata, not as an adaptive neuron operator
- receptor dynamics are preserved in connection or graph metadata, not as executable synapse operators
  and should be treated as a stable metadata-only contract for the current NeuroCNL NIR bridge
- background noise is preserved in population metadata, not as an executable stochastic process
- population coding range is preserved in population metadata, not as an executable encoding-range operator
- lateral inhibition lowers **approximately**: when shape-aware neighborhood information is available
  it becomes an equivalent dense inhibitory weight mask; when shape info is absent the materializer
  falls back to an approximate dense inhibitory interpretation, preserves the radius intent as
  metadata, **and emits an explicit warning** in the lowering summary so the caller is aware of
  the degraded fidelity
- advisory metadata now uses a versioned `advisory_semantics` schema so downstream consumers can
  read stable `delay`, `learning_rules`, `connectivity_pattern`, `shape_intent`, and
  `timing_declarations`, `neuromodulation_rules`, and `short_term_plasticity_rules` fields
  without inferring semantics from scattered keys
- first-class population shape survives in NIR metadata and graph summaries, but current executable node sizes still flatten the population to a scalar neuron count
- one-to-one and explicit binary-mask spatial-connectivity families lower into exact dense `nir.Linear` weights, but locality- and probability-based spatial connectivity remain unsupported
- connectivity is materialized as dense `nir.Linear` weights even when the source semantics are more structured or sparse

Faithful in current NIR export, in addition:

- axonal delay lowers to executable `nir.Delay` nodes on delayed projections, including connections
  that inherit the current global default axonal delay

The subset that round-trips most honestly today is feed-forward or branching LIF networks whose semantics are fully described by populations, dense weighted projections, inhibitory sign, and basic input/output structure. Exact matrices, masks, and other non-grammar-visible details are preserved through the reserved embedded CNL metadata block used by the `NIR -> CNL -> NIR` path.

---

## NIR Simulator Support Matrix

This section documents the explicit support verdict for every NIR primitive in each simulator backend.
The verdicts below are the canonical source of truth; they mirror `_BACKEND_NIR_SUPPORT` in
`neurocnl/runtime/nir_support.py`. Update both files together whenever a verdict changes.

### lava-nc vs lava-dl distinction

`lava_sim` uses **lava-nc** — Intel's low-level Lava process library (`lava.proc.lif`, `lava.proc.dense`,
etc.). It does **not** use **lava-dl** (the higher-level deep-learning library, also called `netx`),
which is what the official NIR community reference implementation targets when it lists "Lava" as a
supported backend at [neuroir.org/docs/supported-primitives](https://neuroir.org/docs/supported-primitives).

This distinction matters because several NIR primitives — notably `Affine`, `Conv2d`, and `Flatten` —
are supported by lava-dl/netx but have **no corresponding lava-nc process type**. When users consult the
official NIR support matrix and see those primitives listed under Lava, they may expect `lava_sim` to
handle them. It cannot, and the table below reflects that honestly.

The `unsupported` verdicts for those primitives are not oversights. They are deliberate, documented
decisions that can be promoted to `exact` when lava-dl netx integration is added to `lava_sim`. See the
[Promotability](#promotability) note at the end of this section.

### Fidelity terms

| Term | Meaning |
|---|---|
| `exact` | The backend executes the primitive with faithful semantics — the output is indistinguishable from the NIR specification's intent within normal floating-point tolerance. |
| `approximate` | The backend executes the primitive but with documented, known semantic limitations (e.g. quantization, missing parameters, or model simplification). The result is usable but not specification-accurate. |
| `unsupported` | The backend cannot execute the primitive. Graphs containing this node type are rejected at preflight with HTTP 422 before any execution is attempted. |

### lava_sim (lava-nc) support verdicts

`lava_sim` dispatches to Intel lava-nc low-level processes. Only the six process types natively available
in lava-nc can receive an `exact` or `approximate` verdict; all others are `unsupported`.

| Primitive | Verdict | Notes |
|---|---|---|
| `Input` | exact | Boundary node; no lava-nc process required |
| `Output` | exact | Boundary node; no lava-nc process required |
| `Linear` | exact | Mapped to `lava.proc.dense.Dense` |
| `LIF` | exact | Mapped to `lava.proc.lif.LIF` |
| `CubaLIF` | approximate | Approximated via `lava.proc.lif.LIF` with adjusted tau parameters; the synaptic current filter (alpha) is not modelled |
| `Delay` | approximate | Implemented as a buffer register; sub-timestep delays are lost due to timestep quantization |
| `Affine` | unsupported | lava-nc has no affine (weight + bias) process; lava-dl netx supports it — out of scope for lava_sim |
| `Conv2d` | unsupported | lava-nc has no Conv process; lava-dl netx supports Conv2d — out of scope for lava_sim |
| `Flatten` | unsupported | lava-nc has no flatten process; tensor reshaping is a lava-dl / compiler concern |
| `IF` | unsupported | lava-nc `LIF.du` and `LIF.dv` cannot replicate true IF (infinite-tau) dynamics |
| `LI` | unsupported | No lava-nc leaky integrator without threshold |
| `I` | unsupported | No lava-nc pure integrator |
| `AvgPool2d` | unsupported | No lava-nc pooling process; lava-dl has it |
| `SumPool2d` | unsupported | No lava-nc pooling process |
| `Scale` | unsupported | No lava-nc scalar-multiply process |
| `Threshold` | unsupported | No separate lava-nc threshold process |
| `Sigmoid` | unsupported | Not a lava-nc process |
| `CubaLI` | unsupported | No lava-nc process for CubaLI |

### snntorch_sim (snnTorch) support verdicts

`snntorch_sim` dispatches to snnTorch fixed-weight inference. It covers a broader set of NIR primitives
because PyTorch and snnTorch together provide the necessary building blocks.

> **Note:** simulation and training-notebook codegen now share one
> discretization, defined in `neurocnl/lif_semantics.py`:
> `beta = 1 - dt/tau` with the firing threshold divided by
> `input_scale = r*dt/tau`, matching `snntorch.import_nir`. `tau` is in
> **seconds**; `dt` comes from an author-declared network
> `with timestep <seconds>` clause (propagated to `nir.LIF`
> `metadata["dt"]`), falling back to `1e-4`.
>
> Previously `neurocnl/runtime/snntorch_simulator.py` used a different
> formula (`beta=exp(-1/tau)`, clamped to `[0.01, 0.99]`, threshold left
> unscaled), so a network trained through the codegen ran as a different
> neuron model when simulated. That divergence is gone.
>
> Without a declared timestep, typical hand-authored `tau`/`threshold`
> values still produce a firing threshold that realistically-scaled input
> cannot reach (the neuron never spikes). Declare a network timestep
> roughly a tenth of your neurons' time constant.

| Primitive | Verdict | Notes |
|---|---|---|
| `Input` | exact | Driven by `ValidatedStimulus` injection |
| `Output` | exact | Passthrough boundary collector |
| `Linear` | exact | `nn.Linear(weight, no bias)` |
| `Affine` | exact | `nn.Linear(weight + bias)` |
| `Conv2d` | exact | `nn.Conv2d(in_ch, out_ch, kernel, stride, padding)` |
| `Flatten` | exact | `nn.Flatten(start_dim, end_dim)` |
| `IF` | exact | `snntorch.Lapicque` with very large `R×C` (effectively infinite tau) |
| `LIF` | exact | `snntorch.Leaky(beta=1-dt/tau, threshold/(r*dt/tau))` — see `neurocnl/lif_semantics.py` |
| `CubaLIF` | approximate | `snntorch.Leaky` from `tau_mem`; the synaptic current filter (alpha, from `tau_syn`) is not modelled |
| `Delay` | approximate | Passthrough in timestep loop; sub-timestep delays not modelled |
| `LI` | unsupported | No snnTorch equivalent without enabling training mode |
| `I` | unsupported | No snnTorch pure integrator equivalent |
| `AvgPool2d` | exact | `nn.AvgPool2d(kernel_size, stride)` |
| `SumPool2d` | exact | `nn.AvgPool2d(kernel_size, stride, divisor_override=1)` — snnTorch has no distinct SumPool2d op; codegen builds a true-sum AvgPool2d, matching real oracle behavior |
| `Scale` | unsupported | No NIR-native snnTorch equivalent |
| `Threshold` | unsupported | No NIR-native snnTorch equivalent |
| `Sigmoid` | unsupported | Not a NIR primitive; handled gracefully |
| `CubaLI` | unsupported | No snnTorch equivalent |

### Promotability

The following `lava_sim` primitives are marked `unsupported` solely because `lava-nc` lacks the
corresponding process type. They are **not** architecturally incompatible with the Lava runtime — they
are fully supported by the lava-dl (`netx`) layer that sits above lava-nc:

| Primitive | What is needed to promote |
|---|---|
| `Conv2d` | Add lava-dl netx integration to `lava_sim`; map `nir.Conv2d` to `lava.lib.dl.netx.utils.NetDict` convolution entry |
| `Flatten` | Add lava-dl netx integration; tensor reshape is handled at the netx compilation stage |
| `Affine` | Add lava-dl netx integration; map `nir.Affine` to a netx dense layer with bias |

When lava-dl netx support is added, update `_BACKEND_NIR_SUPPORT["lava_sim"]` in `nir_support.py`,
change the verdicts above from `unsupported` to `exact`, and update this file in the same commit per
the constraint in `neurocnl/AGENTS.md`.

---

## Training Support

Training adapters are registered with `TrainingAdapterRegistry` and report
honest availability. When an adapter's optional dependency is missing, the
endpoint returns `available: false` with a structured reason — never a silent
failure or degraded fallback via the generic API.

| Adapter | Backend Name | Mode | Fidelity | Key Constraints | Environment Requirements |
|---|---|---|---|---|---|
| Sleep PES | `sleep_pes` | `offline_sleep` | **faithful** (with neurodreamhand) / **mock** (without) | Sleep-phase consolidation training; deterministic fallback when dependency absent | `pip install neurodreamhand` for real execution; fallback works without it |
| snnTorch | `snntorch` | `surrogate` | **real** (with optional deps) / **unavailable** (without) | Trains from downloaded or locally imported datasets when Studio provides a ready server-local path. Studio Setup can import Tier-1 neuromorphic formats via `POST /api/datasets/import-local` (`.aedat`, `.aedat4`, `.h5`/`.hdf5`, `.bin`, and common archives). Supported loaders currently cover HDF5 event/spike datasets, N-MNIST binary folders, AEDAT v2, and AEDAT4 when its optional reader dependency is installed. When the NIR graph contains recurrent `cnl.RSynaptic`/`cnl.Synaptic` neurons, training dispatches to a dedicated mini-batched real-gradient loop (`SnnTorchAdapter._run_recurrent_training`) instead of the feed-forward fallback, with a per-epoch held-out validation pass and best-validation-accuracy checkpointing to disk (`neurocnl.training.checkpoint_store`, gated by `payload["save_best_checkpoint"]`, default on). A separate eval-phase `/training/run` submission (`payload["load_best_checkpoint"]` + `payload["train_job_id"]`) reloads that checkpoint and reports `metadata["test_accuracy"]` against a held-out test set. | `pip install "neurocnl[training]"` or install `torch` + `snntorch` |

### Availability Semantics

- `GET /api/training/capabilities` returns `available: true/false` per adapter
- `POST /api/training/run` returns **422** for unavailable backends (no silent fallback)
- `POST /api/prosthetic/sleep` (legacy) **does** use fallback — backward-compatible behavior
- Unavailable adapters surface `unavailable_reason` with a machine-readable code and human-readable message

### Adding New Adapters

1. Create a class extending `BaseTrainingAdapter` in `neurocnl/training/`
2. Implement `is_available()` and `run()`
3. Register in `neurocnl/training/factory.py`
4. The adapter automatically appears in capabilities and is dispatchable via `/api/training/run`
