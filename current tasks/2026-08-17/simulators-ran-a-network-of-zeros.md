# The three software simulators ran a network of zeros

Date: 2026-08-17

## Symptom

snnTorch, SC-NeuroCore and Lava sim all finished a Run in a fraction of a second
and showed an empty spike raster ("No spikes recorded.") with a membrane trace
flat at 0.0. Status was `completed`, support level `exact`, no error.

## Cause

The simulators were fine. `POST /api/simulators/run` took only the CNL spec text
and recompiled it with `compile_to_nir` on every run, and CNL stores tensor
*shape* only — `_resolve_tensor` (`neurocnl/nir_cnl/compiler.py:392-397`)
zero-fills any weight matrix whose node carries no `weight_init` metadata, which
nothing in the app ever sets. Every synaptic weight was 0.0, so no neuron could
reach threshold.

Measured against the dev backend, 8→8 LIF, `firing_rate` 0.9, 50 timesteps:

| weights | snntorch_sim | lava_sim | sc_neurocore_sim |
|---|---|---|---|
| CNL default (zeros) | 0 | 0 | 0 |
| same spec + `weight_init "xavier"` | 162 | 165 | 50 |

This is the same gap the PYNQ deploy path closed in
`backend/app/services/pynq_trained_weights.py` — the module's own docstring
describes it — but the simulator path never got the fix.

## Fix

**Backend.** `apply_trained_weights_to_graph(compiled, trained)` is a
NIRGraph→NIRGraph sibling of the existing `apply_trained_weights`, reusing
`_weighted_nodes` / `_in_graph_order`, so both consumers match layers by
**position, not name**. `SimulatorRunRequest` gained `trained_nir_base64` and
`SimulatorRunResult` gained `trained_weights`. `run_simulation` overlays the
graph between compile and classify; an unreadable file is `invalid_trained_nir`
and a mismatched one is `trained_nir_mismatch` (separate codes — one is
re-exported, the other re-trained). With no trained graph *and* an all-zero
compiled graph, the result leads with a warning naming the cause.

**Frontend.** `TrainedNirArtifact` (shared; `PynqTrainedNir` is now a typedef)
and `TrainedWeightStatus` in `nmtk_ui_core` (`PynqTrainedWeightStatus` likewise).
`simulatorTrainedNirProvider` fetches the same
`/notebook/artifacts/latest-trained-nir` the PYNQ path uses, so a network trained
once feeds both. `SimulatorRunGate` resolves Run availability once for both the
full run bar and the compact deploy toolbar — untrained means Run is disabled
with the NIR-Exporter instruction rather than a blank chart. An empty raster now
renders the run's own warnings instead of the bare string.

**Consistency.** Lava dropped the population key entirely on a silent run
(`spikes = {}`) and sc-neurocore dropped it when the monitor was empty, so those
two landed in a different empty state than snnTorch for the same outcome. Both
now keep the key with an empty value.

## Verification

Live, against `192.168.2.90:9000` after `make dev-update`:

| backend | no trained NIR | with trained NIR |
|---|---|---|
| snntorch_sim | 0 spikes + zero-weight warning | 500 spikes, `applied: true` |
| lava_sim | 0 spikes + zero-weight warning | 192 spikes, `applied: true` |
| sc_neurocore_sim | 0 spikes + zero-weight warning | 100 spikes, `applied: true` |

- `pytest neurocnl/backend/tests/test_simulators_router.py` — 28 pass (4 new).
- `pytest neurocnl/backend/tests/test_pynq_trained_weights.py` — 18 pass (6 new).
- `pytest neurocnl/neurocnl/runtime/test_lava_simulator.py` and
  `test_sc_neurocore_simulator.py` — pass.
- `flutter test` in `neurocnl/frontend` — 1815 pass, 3 new. One failure,
  `studio_responsive_audit_test.dart`, is **not** from this change: an
  uncommitted edit to `lava_workspace.dart` added a `runConfig == 'sim'` early
  return whose dock action id is `lava-sim-run`, while the test still expects
  `lava-readiness`, which that branch can never produce.
- `flutter test` in `nmtk_ui_core` — 202 pass.
- `flutter analyze lib test` clean in both packages.

## Not done

`supports_voltage_trace` is `False` for lava and snnTorch
(`backend/app/routers/simulators.py:101`, `:130`) but snnTorch demonstrably
returns voltage traces. Left alone — it does not cause the empty result and it
touches the capabilities contract.
