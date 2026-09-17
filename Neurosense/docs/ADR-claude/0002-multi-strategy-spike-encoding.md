# ADR 0002: Multi-Strategy Spike Encoding

## Status
Accepted

## Context
Converting analog biosignals to spike trains requires different encoding strategies depending on signal characteristics (frequency content, amplitude range) and target hardware requirements (temporal precision, spike rate constraints).

## Decision
Implement a `SpikeEncoder` class supporting rate, temporal, and delta encoding methods, configured via `EncodingConfig` Pydantic contract. The encoder follows a configure-then-encode pattern. When the neurocnl `spike_encoding` module is unavailable, the system falls back to a pure-NumPy implementation for core encoding operations.

## Consequences
- **Positive:** Multiple encoding strategies allow users to match encoding to their signal and hardware requirements; NumPy fallback ensures the module works independently of neurocnl.
- **Negative:** Encoding strategy selection requires domain expertise; the NumPy fallback may not match neurocnl's implementation exactly, causing subtle result differences.

## Status Update (2026-07-16 audit)
There is no conditional neurocnl delegation. `neurosense/app/services/spike_encoder.py`
mentions `neurocnl` only once, in its module docstring ("When the neurocnl package is
available it delegates to its spike_encoding module..."); nothing in the executable code
imports or calls `neurocnl` anywhere in the file (confirmed via grep — the only other match
is an unrelated `importlib.import_module("scipy.signal")` call). `neurocnl` is also not a
declared dependency in `neurosense`'s `pyproject.toml`. Encoding is unconditionally pure
NumPy/SciPy today; the "falls back to NumPy when neurocnl is unavailable" behavior this ADR
describes does not exist in code.
