# Guardrails — neurocnl

Known failure patterns. Agents MUST read this before every implementation task.
Entries are never removed, only appended.

---

## Sign #1 — 2026-03-23

**DO NOT allow threshold == resting_potential.**
What happened: Agent generated a spec where threshold equaled resting potential (both 0.0). The neuron fired continuously with zero input. Layer 1 validator caught it, but the agent wasted a full implementation cycle.
Caught by: Layer 1 invariant `threshold_above_resting`.

## Sign #2 — 2026-03-23

**DO NOT generate Nengo networks without running Layer 2 cross-sentence validation.**
What happened: Agent created a network with a connection from "interneuron" to "motor neuron" but only defined behavioral specs for "sensory neuron" and "motor neuron". The dangling connection caused a silent Nengo error.
Caught by: Layer 2 validator `_check_dangling_connections`.

## Sign #3 — 2026-03-23

**DO NOT use mock objects in Layer 3 assertion tests.**
What happened: Agent mocked nengo.Simulator to speed up tests. The mocked tests passed but the actual simulation failed because the LIF neuron type was configured incorrectly.
Caught by: Integration test with real Nengo simulator.

## Sign #4 — 2026-03-23

**DO NOT assume default parameters are always valid.**
What happened: Agent used `default_params_from_specs()` without checking if the user-supplied spec overrode the threshold to a value below resting. The defaults masked the invalid override.
Caught by: Property-based test with Hypothesis generating edge-case thresholds.
