# CEL-222: Fix Lava + SC-NeuroCore simulator spike collection

## Root cause

CNL-compiled `nir.LIF` nodes use scalar `tau` (`size == 1`). True width is in adjacent `nir.Linear` weights. `sc_neurocore_simulator` used `tau.size` → simulated 1 neuron → 0 spikes. snnTorch was unaffected (reads weight shapes).

## Fix

- `neurocnl/runtime/population_sizes.py` — shared `reconcile_population_sizes_from_linear_weights`
- `sc_neurocore_simulator.py` — use reconciled widths when building `Population`
- `lava_io.py` — delegate to shared helper
- Lava monitor fallback when process name ≠ monitor key (`lava_simulator.py`, `Neurochip/lava_backend.py`)

## Verify

`shd_digit_classifier_akida.cnl` sc_neurocore: 0 → 36 spikes @ 100 timesteps.

```bash
cd neurocnl && PYTHONPATH=. pytest neurocnl/runtime/test_population_sizes.py neurocnl/runtime/test_sc_neurocore_simulator.py -q
```

Deploy: `make dev-update`
