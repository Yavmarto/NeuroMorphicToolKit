# NeuroCNL — Concrete Tasks to 100% POC Readiness

This module is the most complete (95%+). Tasks here are minor polish.

1. **Fix Import in Analysis Router**
   - *Description:* The `neurocnl/backend/app/routers/prosthetic/analysis.py` file has an issue with the `analyze_quantization` import. It should properly import and use `run_quantization_sweep` from `neurodreamhand.hardware.quantization`.
   - *Impact:* Fixes runtime failures on the `/quantize` endpoint.

2. **Expand Edge-Case Invariants**
   - *Description:* Add more Layer 2 structural validation checks for extreme cases (e.g., negative thresholds without inhibition).
   - *Impact:* Hardens the compiler against malformed natural language input.
