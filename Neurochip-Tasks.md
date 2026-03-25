# Neurochip — Concrete Tasks to 100% POC Readiness

1. **Fix Missing Frontend Models**
   - *Description:* The Dart frontend fails to compile due to missing model imports (`HardwareProfile`, `ConstraintReport`, `PowerEstimate`). Create these models in `frontend/lib/models/` matching the FastAPI JSON schemas.
   - *Impact:* Unblocks the compilation and rendering of the frontend UI.

2. **Implement QuantizationExplorer Widget**
   - *Description:* Build the interactive slider for bit-width selection and wire it to the `/api/prosthetic/quantize` endpoint.
   - *Impact:* Provides a key interactive feature for hardware deployment demos.

3. **Implement ConstraintReportCard Widget**
   - *Description:* Display constraint analysis results (memory, compute) fetched from the backend.
   - *Impact:* Completes the hardware analysis UI.
