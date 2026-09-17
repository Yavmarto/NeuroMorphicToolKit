# Writing your first CNL spec

This guide will walk you through the process of writing your first Controlled Natural Language (CNL) specification for a neuromorphic model using `neurocnl`.

## What is CNL?

Controlled Natural Language (CNL) is a subset of English with a restricted grammar and vocabulary. In `neurocnl`, we use CNL to describe the behavior and structure of spiking neural networks in a way that is both human-readable and machine-parseable.

## Basic Sentence Structure

Every valid CNL sentence in `neurocnl` follows this general pattern:

```
[Article] <subject> <VERB> <action> [<CONDITION_VERB> <condition>]
```

- **Article**: "The" or "A" (optional, case-insensitive).
- **subject**: The neuron, connection, or population being described (e.g., "The sensory neuron").
- **VERB**: One of the core CNL verbs: `MUST`, `MUST NOT`, `ONLY IF`, `DURING`, `AFTER`, `WITH`.
- **action**: The behavior or property being specified (e.g., "fire").
- **condition**: An optional qualifying clause (e.g., "ONLY IF membrane potential exceeds 1.0").

## Core Concepts

### 1. Threshold Firing
Specify when a neuron should emit a spike.
*Example:* `The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0`

### 2. Refractory Period
Define the period during which a neuron cannot fire again after a spike.
*Example:* `The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds`

### 3. Membrane Potential Decay
Define how quickly a neuron's membrane potential returns to its resting state.
*Example:* `The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds`

### 4. Synaptic Weight
Specify the strength of a connection between two neural populations.
*Example:* `The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0`

### 5. Axonal Delay
Model the transmission latency between neurons.
*Example:* `The connection from sensory neuron to motor neuron MUST transmit WITH delay of 3ms`

## Creating a Simple Reflex Arc

To create a complete model, you combine several of these sentences. Here is a simple example of a sensory-motor reflex arc:

```text
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
The connection from sensory neuron to motor neuron MUST transmit WITH delay of 5ms
```

## Tips for Success

- **Be Specific**: Use numeric values (e.g., `0.002 seconds`, `1.5`) instead of vague terms like "fast" or "strong".
- **Use the Right Verbs**: Stick to the allowed CNL verbs (`MUST`, `MUST NOT`, etc.).
- **Check Your Subjects**: Ensure that the names of your populations are consistent throughout your specification.

## Interpreting Backend Support Output

After validation, Studio and the backend API may show a backend support panel:

- `faithful` means the current backend is a strong match for the spec
- `approximate` means the spec is still usable, but the backend depends on heuristics, timing assumptions, or simplified mappings
- `unsupported` means the current target backend should not be treated as deployable for that spec

Example:

```json
{
  "backend_support": {
    "backend": "loihi",
    "verdict": "approximate",
    "warnings": [
      "Declared network_timestep (0.002) differs from Loihi timing resolution (0.001)."
    ]
  }
}
```

**Interpreting this example:**
When you target the `loihi` backend with a specification that includes a timestep of 0.002 seconds, the parser successfully processes the request, and the biological validation passes. However, because the Loihi chip operates with a fixed timing resolution of 1 millisecond (0.001s), the generated simulation or export must approximate your 0.002s timestep. The `approximate` verdict means you can still export and run this model, but you must be aware that the hardware will enforce its own 0.001s resolution under the hood, potentially altering precise temporal dynamics.

Read parser and validation success separately from backend support. A spec can be syntactically valid and biologically consistent, while still being only `approximate` for a given hardware target. Note that an exporter's availability does not imply production-ready hardware support.

## Choosing a Backend

The supported NeuroCNL product surface is now NIR-first. The canonical compile path is direct
`CNL -> IR -> NIR`, and round-tripping back to a `.cnl` document uses a reserved embedded metadata
block to preserve exact low-level details that the human grammar does not expose directly.

Legacy Nengo-based generation and simulation are no longer part of the supported product surface.
Hardware export and deploy backends have varying levels of readiness.

For the current support state of each backend — including environment requirements
and known limitations — see the [Backend Support Matrix](support_matrix.md).

Key limitations to be aware of:

- **sinabs**: sequential topologies only. Branching networks raise `NotImplementedError` at runtime.
- **Rockpool**: `from_neurocnl` conversion has unfixed bugs and is not usable. Do not target Rockpool in production.
- **PYNQ Z2**: produces an overlay ZIP export. The FINN compilation pipeline is a Phase 2 placeholder and is not yet wired.
- **Akida**: the `akida` package does not support macOS. Akida1 requires strictly sequential topology.
- **SpiNNaker2**: I/O modules are stubs; the exporter generates projection code but live data paths are not implemented.
