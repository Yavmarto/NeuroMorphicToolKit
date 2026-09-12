# CEL-224: Nengo + Sinabs simulator runtime backends

Phase 2 of [CEL-221](/CEL/issues/CEL-221) — wire `nengo_sim` and `sinabs_sim` through `/api/simulators/run`.

## Backend

- `neurocnl/neurocnl/runtime/nengo_simulator.py` — builds live Nengo network via `NengoIO.from_nir`, runs `nengo.Simulator`
- `neurocnl/neurocnl/runtime/sinabs_simulator.py` — dispatches through `sinabs.nir.from_nir`
- `nir_support.SIMULATOR_RUNTIME_BACKENDS` now includes `nengo_sim`, `sinabs_sim`
- `simulators.py` — capabilities + run dispatch; Sinabs rejects zero-weight graphs without trained NIR

## UI

- Deploy catalog ids: `nengo_sim`, `sinabs_sim` (replacing codegen-only `nengo` / `sinabs` rows)
- `kSimulatorDeployBackends` extended — Review step shows spike rasters for both

## Verification

- Nengo adapter smoke test passes locally when `nengo` is installed
- Sinabs adapter skips locally when `sinabs` is not installed (expected in dev container)
