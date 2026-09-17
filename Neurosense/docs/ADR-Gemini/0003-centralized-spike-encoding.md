# ADR 0003: Centralized Spike Encoding

## Status
Accepted

## Context
When sensor data (like EMG) arrives, it must be encoded into spike trains (Rate, Temporal, or Delta). Performing this encoding on the frontend client provides UI flexibility but locks down computational throughput in Flutter's isolate models, reducing mobile/embedded performance.

## Decision
Spike encoding calculations are pushed fundamentally to the FastAPI Python backend utilizing `neurocnl` libraries. The resulting spike vectors are then streamed via WebSockets down to the UI or directly inserted into downstream simulation endpoints over HTTP/WS bridges.

## Consequences
- **Positive:** Heavy vectorization and DSP processing leverage native Python numerical bindings (`scipy`, `numpy`), freeing the Flutter UI from excessive rendering locks.
- **Negative:** Tightly couples Neurosense's backend to `neurocnl` encoding logic, meaning updates in CNL spike specs directly impact the Neurosense service.

## Status Update (2026-07-16 audit)
Same finding as the ADR-claude 0002 status update: `neurosense/app/services/spike_encoder.py`
does not actually import or call `neurocnl` in any executable path (only a docstring mention),
and `neurocnl` is not a declared dependency of `neurosense`. Encoding runs unconditionally on
pure NumPy/SciPy — the tight coupling to `neurocnl` this ADR describes as the backend's design
does not exist in the current code. See the cross-referenced ADR for full verification detail
rather than repeating it here.
