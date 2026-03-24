# Guardrails — Neuro-Dream-Hand

Known failure patterns. Agents MUST read this before every implementation task.

---

## Sign #1 — 2026-03-23

**DO NOT mutate weight arrays in FaultInjector.**
What happened: Early implementation modified the original weight matrix when injecting dead neurons. This corrupted the source network for all subsequent fault injection runs.
Caught by: Unit test comparing original weights before/after injection.

## Sign #2 — 2026-03-23

**DO NOT send grip values outside [0.0, 1.0] to serial bridge.**
What happened: A float rounding error produced grip=1.0000001 which mapped to uint16=65536 (overflow). Teensy received garbage.
Caught by: Contract validator on SerialBridgeContract.

## Sign #3 — 2026-03-23

**DO NOT set EMG bandpass high cutoff above 100 Hz for Ganglion.**
What happened: Agent set bandpass to 20-450 Hz (standard EMG range) but Ganglion samples at 200 Hz. Nyquist = 100 Hz. Aliasing artifacts corrupted the signal.
Caught by: EMGStreamContract validator.
