# CEL-221: Simulator platform analysis

See Paperclip issue document `brief` for the full report.

## Headline

- **snnTorch** — only simulator producing live spikes on dev (`shd_digit_classifier_akida.cnl` → 760 spikes)
- **Lava / SC-NeuroCore** — available, runs complete, but 0 spikes on all audited models
- **Akida** — hardware deploy via Neurochip (not `/api/simulators/run`); dev neurochip healthy

## Best cross-demo model

`neurocnl/backend/app/templates/shd_digit_classifier_akida.cnl` on `snntorch_sim`.

## Codegen targets (not simulators)

Brian2, Nengo, Sinabs, Rockpool, PyNN — `kind: codegen`, notebook output only, no Review raster. All except PyNN installed on dev container.

## Follow-ups

1. Debug Lava + SC-NeuroCore silent spike collection
2. Fix local `snntorch_simulator.py` `modules[name]` → `modules.get(name)` regression vs deployed code
3. Fix `GET /api/neurocnl/notebook/target-availability` 500 on dev
