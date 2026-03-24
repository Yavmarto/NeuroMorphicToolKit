# Agent Rules for Neuro-Dream-Hand

## Non-Negotiable

1. **NEVER modify fault injection to mutate weights in-place.** SPEC 5.1 requires copies.
2. **NEVER change the serial protocol packet format** without human approval. Hardware depends on exact byte layout.
3. **ALWAYS validate grip commands are in [0.0, 1.0]** before sending to Teensy. Out-of-range values can damage the servo.
4. **ALWAYS check GUARDRAILS.md** before starting implementation.
5. **NEVER skip the HITL latency benchmark** when changing serial communication code.

## Domain Rules

6. dt must always be 0.002 to match Nengo simulation timestep.
7. EMG bandpass filter high cutoff must respect Ganglion Nyquist (100 Hz at 200 Hz sample rate).
8. Crossbar conductances must be normalized to [g_min, g_max] range.
9. Drop-test protocol uses 20 trials per condition per environment.
10. Sleep/wake consolidation uses PES learning rule with learning_rate ~1e-4.

## When to Stop and Ask

- Any change to the serial bridge packet protocol
- Any change to EMG electrode placement or channel mapping
- Sim-to-real survival rate gap exceeding 15 percentage points
- Any Loihi 2 deployment (requires Intel SDK access)
- Any change to MuJoCo model parameters
