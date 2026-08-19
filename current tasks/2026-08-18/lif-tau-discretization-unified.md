# One network, three neuron models: unifying LIF tau discretization

Date: 2026-08-18

## Symptom

`workspaces/mnist-latest2.nmtk` trains cleanly (loss 0.88 → 0.39, val 85.5 %, eval
89.3 %) but Execute → Review shows nonsense: the snnTorch raster is saturated —
nearly every neuron firing every step — and SC-NeuroCore's membrane trace runs to
±10⁶ instead of hovering near a threshold of 1.0.

## Cause

`nir.LIF.tau` is a time constant **in seconds**, but every execution backend
invented its own timestep, so one trained network became a different neuron model
on every target.

| path | file:line | formula | dt | at tau = 0.002 s |
|---|---|---|---|---|
| training codegen | `backend/app/routers/notebook.py:925-945` | `beta = 1 − dt/tau`, `thr /= r·dt/tau` | `metadata["dt"]`, default 1e-4 | beta 0.95, threshold 20 |
| snnTorch sim | `neurocnl/runtime/snntorch_simulator.py:199-233` | `exp(−1/tau)` clamped to [0.01, 0.99], threshold raw | dt ≡ 1 step | beta **0.01**, threshold 1.0 |
| SC-NeuroCore | `neurocnl/runtime/sc_neurocore_simulator.py:75-94` | raw tau, hardcoded `dt: 1.0` | 1.0 | dt/tau = **500** |
| Lava sim | `neurocnl/runtime/lava_simulator.py:439` | `LIF(shape, vth)` — tau never read | — | no leak at all |

`exp(−1/0.002) ≈ 2e-22` clamps to the 0.01 floor, so the snnTorch simulator ran a
memoryless neuron with a threshold 20× too low. SC-NeuroCore's forward Euler is
unstable above `dt/tau = 2`; at 500 the membrane diverges, alternating sign — the
measured floor of **−498.8** is exactly the predicted `beta = −499`.

Two further defects surfaced while mapping this, both on live paths:

- **Silent data corruption.** `nir_topology.fuse_recurrent_pairs` ran the same
  clamped conversion on the **NIR → canvas import** path, and `cnl.*` alpha/beta
  are *persisted* canvas parameters (`nir_graph_serializer.py:143-165, 517-545`).
  Because every realistic tau clamps to the same 0.01, distinct time constants
  collapsed onto one value, and re-exporting rewrote `tau_mem` 0.02 s → 0.217 s
  inside saved `.nmtk` files. The clamp is lossy, so the original tau is gone.
- **CubaLIF ignored its own time constant.** `snntorch_simulator.py:388` called
  `_lif_beta(node)` on a `nir.CubaLIF`, which has `tau_mem`/`tau_syn` and no
  `.tau`; the `except AttributeError` guard fired and every CubaLIF silently got
  `beta = 0.9`.

## Fix

**One shared helper: `neurocnl/lif_semantics.py`.** A leaf module (math, numpy,
nir only) so `runtime/`, `converter/`, `handoff/` and `backend/app/**` can all
import it — `backend/app` already depends on `neurocnl.*` at 105 sites and never
the reverse.

Canonical conversion is `beta = 1 − dt/tau` with the threshold divided by
`input_scale = r·dt/tau`. This is not an approximation: it is the exact forward
Euler discretization of `tau·dv/dt = (v_leak − v) + R·I` under the change of
variables `u = v/input_scale` that makes it identical to snnTorch's `Leaky`
(`u[t+1] = beta·u[t] + I[t]`, which has no input-gain term). It is also
byte-identical to upstream `snntorch.import_nir._nir_to_snntorch_module` — the
code path a user hits when they load an exported `.nir` in stock snnTorch.
`DiscretizationScheme.EXACT` (`exp(−dt/tau)`) exists for comparison but is not
the default: it would buy 0.13 % at `dt/tau = 0.05` and cost divergence from the
one library we cannot patch.

dt precedence: `node.metadata["beta"]` → `node.metadata["dt"]` →
`graph.metadata["dt"]` → `DEFAULT_LIF_DT_SECONDS = 1e-4`. Deliberately no
request-level dt — admitting one recreates the "two timesteps disagree" bug at a
new location.

**Default stays 1e-4.** Per the user's direction (accuracy first, no magic).
Deriving dt from tau automatically would make first-run rasters prettier while
silently reinterpreting every trained checkpoint. The consequence is surfaced
instead, not guessed at.

**Per backend.**

- *snnTorch* — routes through `discretize_lif`; the `[0.01, 0.99]` clamp is gone,
  replaced by a hard `dt >= tau` error carrying an actionable message. Reported
  membrane traces are multiplied back by `input_scale` so the panel's y-axis is
  in NIR volts, matching the other backends instead of being 200× off.
- *SC-NeuroCore* — `tau_mem = tau/dt` (timesteps), `dt = 1.0`, and the NIR input
  gain folded into **`resistance`**, leaving `v_threshold`/`v_leak`/`v_reset`
  raw. Chosen over dividing the threshold (also algebraically valid) because
  `v_rest`, `v_reset` and `noise_std` are voltages too and would break at any
  non-zero leak, and because the membrane trace is plotted.
- *Lava* — `LIF(du=1.0, dv=1−beta, vth=threshold/input_scale)`; `dv = dt/tau` is
  the mapping `paper/nir_to_lava.py` uses. `Loihi2SimCfg()` takes no
  `select_tag`, so it resolves to the float model and no 12-bit quantization is
  needed. `lava_io` now carries `r`, `v_leak` and `dt` alongside the `tau_rc` the
  simulator never read, and no longer crashes on `nir.CubaLIF` (it read `.tau`).
- *Akida, PYNQ, Neurobench* — untouched, deferred (see below).

**Corruption path closed.** `fuse_recurrent_pairs` converts at the graph's
resolved timestep and stamps that dt onto the emitted `cnl.*` node;
`cnl_flatten._tau_from_decay` became `dt/(1−beta)` — the exact inverse — instead
of `−1/log(beta)`, which produced a timestep-unit tau inside a seconds-typed
field.

**Dedup.** `notebook.py` (both the codegen branch and the deliberately-separate
`_implausible_lif_thresholds` diagnostic) and `converter/sinabs_io.py` now
resolve dt through the shared helper, so the default cannot drift. The training
codegen's *formula* was not touched — that is the point, and the anchor tests
prove it.

**Diagnostic surfaced.** `unreachable_threshold_warnings` reports populations
whose effective threshold is out of reach and names a suggested timestep
(≈ tau/10). It already existed but only ever reached the generated notebook, so a
user running from Review never saw it.

**UI.** The per-node `dt` and `beta` palette controls are deleted — neither was
ever read (`_deserialize_node` builds `nir.LIF` from tau/threshold/r/v_leak
only), and a control that does nothing is worse than none. `dt_ms` is relabelled
"Raster time scale (ms/step)" and documented as display-only on the schema, since
wiring a second timestep into dynamics would rebuild this exact bug.

## Verification

Same network, same stimulus, same seed, before vs after:

| backend | spikes before | spikes after | membrane before | membrane after |
|---|---|---|---|---|
| snnTorch | 2095 | **7** | [−3.05, 2.95] | [−1.13, 1.03] |
| SC-NeuroCore | 11420 | **7** | [−498.8, 0.99] | [−1.13, 0.99] |

The two backends now agree exactly on spike count and neuron identity, and their
membrane traces sit in the same units near the same threshold. Before, they
disagreed by 5×.

Test env: `.test-venv` (nir 1.0.7 — the app venv's 1.0.4 lacks `nir.CubaLI` and
cannot import the backend) with `PYTHONPATH=.:<repo root>`, plus torch, snntorch,
sc-neurocore installed. Command:

```bash
cd neurocnl && PYTHONPATH=.:/Users/yoshimartodihardjo/NeuroMorphicToolKit ../.test-venv/bin/python -m pytest -p no:nengo -q --ignore=backend/tests/test_deploy_ir_population_keys.py neurocnl/ backend/tests/
```

- Python: **25 failed → 19 failed**, 1690 → 1748 passed. Six previously-red tests
  now pass, including a NIR fixture round-trip and two preflight endpoints.
- `flutter test` (frontend): **35 → 33 failing**; the two that went green are the
  palette-param tests. The remaining 33 are red at HEAD — verified by reverting
  the two unrelated uncommitted Dart files and seeing the identical 35.
- `ruff check` / `ruff format` / `mypy` clean on every touched file.
- Anchor tests (`test_notebook_codegen.py:760, 826, 842, 867` and
  `test_notebook_codegen_network_timestep.py:43, 53, 64, 98-107`) pass
  **unchanged** — the training convention provably did not move.

## Follow-up: the compiled graph had no neuron parameters at all

Reported immediately after the change: both simulators returned "run failed" on
the default workspace, individually and via Run all.

Cause, and it is the deeper half of the original bug. A CNL spec records a
neuron as a *shape*, not a value — `with time constant shape (256,)` — so
`compile_to_nir` zero-fills it. The graph reaching `POST /api/simulators/run`
therefore had `tau = 0`, `v_threshold = 0` **and** `r = 0` for every population;
the canvas values (tau 0.002 / 0.02 s) never travelled. `apply_trained_weights_to_graph`
overlaid weight matrices only, so the neuron parameters stayed zero.

Before this work that was invisible: `_decay_from_tau(0)` returned a hardcoded
0.9 and a threshold of 0 fires every step — which is a second, independent cause
of the saturated snnTorch raster — while sc-neurocore's `max(1e-6, 0)` gave
`dt/tau = 1e6`, stacking on top of the unit mismatch to produce the ±10⁶ trace.
Rejecting a zero time constant turned that silent garbage into a hard failure.

Fix: `_overlay_neuron_parameters` in `backend/app/services/pynq_trained_weights.py`
now copies tau / tau_mem / tau_syn / v_threshold / v_leak / r / w_in from the
trained `.nir` alongside the weights, matched by position among LIF-family nodes
exactly as the weight overlay is. A population is judged shape-only by its
**time constant** rather than field by field: a zero `v_leak` or `v_threshold` is
a value a user could legitimately mean, whereas a zero tau describes a membrane
that cannot integrate at all, and `compile_to_nir` zeroes a node's parameters
together. A neuron with a real tau is left completely untouched.

Verified against the actual `mnist-latest2` CNL: before the overlay both
populations read `tau=0, vth=0`; after, `tau=0.002/0.02, vth=1.0, r=1.0`, and
both simulators run (7 spikes each). The zero-tau error message now names the
NIR Exporter rather than a canvas field the user did set.

## Follow-up 2: the trained .nir was blank too

Still failing after the overlay fix. Reproduced directly against the dev backend
rather than guessing:

```bash
curl -s "http://192.168.2.90:9000/api/neurocnl/notebook/artifacts/latest-trained-nir?workspace_folder=mnist-latest2"
curl -s -X POST "http://192.168.2.90:9000/api/neurocnl/simulators/run" -H 'Content-Type: application/json' --data-binary @body.json
```

Both backends returned the new `tau = 0` error. Reading the artifact itself
explained why: `model.nir` has **real weights and blank neurons** —
`Linear(256,784)` with 200 704 non-zeros, and every `LIF` at
`tau=0, v_threshold=0, r=0`. There was nothing for the overlay to copy.

Cause: the `nirExporter` codegen (`notebook.py`, `case "nirExporter"`) loads
`best_model.pt` and copies **only `weight`/`bias`** onto the CNL-compiled graph,
then writes it. Neuron parameters were never read back off the trained
`snn.Leaky` modules, so the exporter propagated the compiled graph's zeros.

Worth noting what this implies about the original diagnosis: because tau was 0,
the training codegen's own fallback applied — `beta = 0.95`, threshold 1.0, and
`w_scale` collapsing to 1.0 means **no threshold rescale happened**. So this
model was fitted at beta 0.95 / threshold 1.0 for *both* layers, not at the
20/200 thresholds the canvas values would imply. The canvas tau never reached
training either.

Fix, two parts:

1. **Exporter records what was built.** The codegen now emits
   `_nmtk_nir_neuron_params` (nir node name → module var, dt, input_scale, r,
   v_leak) alongside `_nmtk_nir_module_names`, and the exporter inverts it from
   the live modules: `tau = dt/(1-beta)`, `v_threshold = module.threshold *
   input_scale`. Read via `globals().get(...)` so the cell still runs standalone
   and older notebooks degrade rather than raising `NameError`.
2. **Recovery for artifacts already on disk.** `_fill_from_training_fallback`
   reconstructs a blank population from the codegen's own fallback constants
   (beta 0.95, no rescale → `tau = dt/0.05`), which describes the model that was
   actually fitted. Reported separately from a genuine copy: "…were
   reconstructed. Re-run training to record the real ones."

Verified with the **real** downloaded artifacts, not synthetic ones:

| | before | after |
|---|---|---|
| LIF tau / threshold | `0.0` / `0.0` | `0.002` / `1.0` |
| snnTorch | run failed | 113 spikes, membrane [−2.54, 1.11] |
| SC-NeuroCore | run failed | 116 spikes, membrane [−2.54, 1.00] |

## Follow-up 3: Lava was failing for an unrelated reason

Reported as "either Lava works and the other two don't, or the other way round".
Measured against the live backend instead of guessing — three backends, two
passes each:

| backend | pass 1 | pass 2 |
|---|---|---|
| snntorch_sim | OK, 113 spikes | OK, 113 spikes |
| sc_neurocore_sim | OK, 116 spikes | OK, 116 spikes |
| lava_sim | FAIL | FAIL |

So it is deterministic, not alternating, and the two halves of the report were
different points in time: **before** the redeploy, Lava was the only one that
"worked" — because `_lava_lif_params` fell back to Lava's own decay on a zero
time constant while snnTorch and SC-NeuroCore refused. **After** the redeploy the
other two work and Lava fails on its own, unrelated problem.

Lava's error:

```
Remote Lava worker request failed: HTTP 422:
{"detail":"Execution failed: [Errno 24] Too many open files: '/psm_4c5885de'"}
```

A two-neuron network fails identically, so it is not the graph — the worker is in
a permanently exhausted state.

Cause: a resource leak in the Lava worker, predating all of this. Lava's runtime
is OS processes backed by POSIX shared memory (`/psm_*`) that only `stop()`
releases. `Neurochip/neurochip/app/services/lava_backend.py`'s `run()` called
`stop()` **only in its error path**, and the client
(`lava_io.compile_and_run_remote`) calls `/compile` and `/run` but never `/stop`.
So every *successful* Lava simulation leaked a whole runtime until the worker hit
its descriptor limit, after which every run failed until the container restarted.

Fixes:

- `lava_backend.run()` releases the runtime in a `finally`, after the spikes have
  been collected. Regression test added (`test_lava.py`).
- `lava_io.compile_and_run_remote` calls `/stop` in a `finally`, best-effort, so
  cleanup also happens against an older worker or when the run raises.
- `_lava_lif_params` now **raises** on a zero time constant with the same
  actionable message the other two backends give, instead of quietly substituting
  Lava's defaults. That leniency is what made one backend appear to work while
  the others failed on the identical network — which reads as the backends
  disagreeing rather than as the network missing its parameters.

Verification: `neurocnl` 19 failed / 1752 passed (unchanged failure set);
`Neurochip` 12 failed / 439 passed against a HEAD baseline of 12 failed / 438
passed — same failures, plus the new test. The two red Neurochip tests near this
area (`test_artifact_contracts`) concern export zips and do not import
`lava_backend`.

**The deployed worker is still holding leaked handles** and needs restarting once
before it recovers; redeploying the backend does that.

## Follow-up 4: the Lava worker was never restarted, and it ignores tau

"Still the same, only Lava fails." Inspected the worker instead of assuming the
redeploy had reached it:

```
container            nmtk-deploy-lava-backend-1   Up 36 hours (healthy)
/dev/shm psm_* segs  273        (leaked)
fd limit             1024
fds in use           1010       (saturated)
python processes     0          (procs gone, handles not)
```

Two separate facts:

1. **The redeploy never restarted this container** — it was 36 hours old, so it
   had neither the leak fix nor a clean slate. The leak diagnosis was right; the
   fix simply was not running. Restarting it dropped the segments 273 → 7 and
   descriptors 1010 → 42, and all three simulators then ran against the real
   workspace: snnTorch 113, SC-NeuroCore 116, **Lava 967**.

2. **Lava's numbers disagree because the worker never reads tau.** The earlier
   Lava discretization fix landed in `runtime/lava_simulator.py`, which is the
   *in-process* path — and this deployment uses the *remote worker*. The worker
   builds `LIF(shape, vth=threshold)` and its payload parser
   (`_normalize`) drops `tau_rc`, `r`, `v_leak` and `dt` outright, so every
   population runs with Lava's default decay: a pure integrator, threshold
   unscaled. Hence ~8x the spikes of the other two backends.

Fix: keep the discretization in one place and make the worker a dumb executor.
`lif_semantics.lava_lif_parameters` now owns the `(du, dv, vth)` mapping;
`lava_io.to_runtime_payload` emits those three keys per population, and
`lava_simulator._lava_lif_params` prefers them so the in-process and remote paths
cannot compute different neurons from one graph. The worker carries the keys
through `_normalize` and passes them to `LIF(...)`, ignoring them when absent so
an older payload keeps the previous behaviour.

Verified payload for tau = 0.002 s at dt = 1e-4:
`du = 1.0, dv = 0.05 (= dt/tau), vth = 20.0 (= 1.0 / 0.05)`.

`neurocnl` 19 failed / 1752 passed; `Neurochip` 12 failed / 439 passed (baseline
12 / 438) — unchanged failure sets.

**Still required:** the worker image has to be rebuilt and republished for the
du/dv change and the leak fix to take effect. Until then Lava runs (post-restart)
but with Lava's default decay, so its spike counts will keep disagreeing with the
other two backends. Restarting alone does not fix that.

## Not done / known

- `test_diagnostic_properties.py::test_property_7_unknown_primitive_phrase` is
  now red, but **not from this change**: its hypothesis strategy filters
  primitive noun phrases and not the `network` keyword, so
  `"Define a network named x."` parses fine and the test's `pytest.raises` fails.
  Confirmed by feeding that phrase to the parser at HEAD. Hypothesis simply had
  not generated that example before; my runs cached it. Separate fix.
- **Lava is unverified at runtime here.** `lava-nc` 0.10.0 does not import on
  Python 3.13 (`ValueError: mutable default ByteEncoder ... use default_factory`),
  and installing it downgrades numpy. The change is source-correct and its unit
  tests pass, but no live Lava run was executed.
- **Deferred by scope** (each still carries its own convention): PYNQ
  (`neurochip_pynq_handoff.py:203-273` — needs only `resolve_dt` in place of the
  hardcoded `LIF_TRAINING_DT_SECONDS`; keep the log2 shift quantization, which is
  genuinely hardware-specific), Akida (`akida_mapper.py:82` — no-leak is
  defensible but the threshold still needs the `1/input_scale` correction; verify
  the plumbing point, which reads `PopulationIR` rather than `nir.LIF`), and the
  offline exporters (`lava_exporter`, `loihi_exporter`, `c_header_exporter`,
  `brian2_*`, `rockpool_io`, `nengo_io`). Neurobench has zero `tau` references
  and inherits the fix.
- The "Network Timestep" field still shows a static hint rather than a live
  read-out of the resulting beta and effective threshold. That was the
  highest-leverage remaining UI idea and is not implemented.
