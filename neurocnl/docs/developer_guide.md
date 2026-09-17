# Adding a New NIR Exporter

This guide explains how to add a new export backend to `neurocnl`.

> **Important architectural note:** The primary compile surface in `neurocnl`
> is the direct `CNL → IR → NIR` pipeline. Exporters receive a
> `nir.NIRGraph` or a `NetworkIR` — **not** a `nengo.Network`.
> The Nengo-based exporter path is a legacy internal path that is no longer
> part of the supported product surface.

---

## Introduction

In `neurocnl`, exporters translate a compiled `nir.NIRGraph` (or the
intermediate `NetworkIR`) into a target-specific format such as a Python
deployment script, a C header, or a hardware-vendor SDK call. The starting
point for any new exporter is always the NIR graph produced by
`compile_to_nir()`.

---

## Step 1: Understand the Input

New exporters receive one of two inputs:

| Input type | When used | How to obtain |
|---|---|---|
| `nir.NIRGraph` | After full compilation | `from neurocnl import compile_to_nir; graph = compile_to_nir(spec)` |
| `NetworkIR` | Mid-pipeline (before materialization) | `from neurocnl.ir import lower_to_ir; ir = lower_to_ir(parsed)` |

Prefer `nir.NIRGraph` unless you need access to IR-level metadata (e.g.
learning rules, neuromodulation rules) that are not forwarded into the NIR
graph nodes.

The NIR graph structure you will work with:

```python
import nir

graph: nir.NIRGraph  # returned by compile_to_nir()

# Nodes are keyed by sanitized label strings
for name, node in graph.nodes.items():
    if isinstance(node, nir.LIF):
        print(f"LIF population: {name}, tau={node.tau}")
    elif isinstance(node, nir.Linear):
        print(f"Weight node: {name}, shape={node.weight.shape}")
    elif isinstance(node, nir.Input):
        print(f"Input node: {name}")
    elif isinstance(node, nir.Output):
        print(f"Output node: {name}")
    elif isinstance(node, nir.Delay):
        print(f"Delay node: {name}, delay={node.delay}")

# Edges are (source_label, target_label) tuples
for src, dst in graph.edges:
    print(f"  {src} → {dst}")

# Advisory metadata lives in graph.metadata
summary = graph.metadata.get("nir_lowering_summary", {})
```

---

## Step 2: Create a New Exporter File

All exporters live in `neurocnl/export/`. Create a new file, e.g.
`neurocnl/export/my_target_exporter.py`:

```python
"""Export a nir.NIRGraph to My Target format."""

from __future__ import annotations

import nir
import numpy as np


def export_my_target(graph: nir.NIRGraph, **kwargs) -> str:
    """Convert a compiled NIR graph to My Target format.

    Parameters
    ----------
    graph : nir.NIRGraph
        The compiled NIR graph produced by ``compile_to_nir()``.
    **kwargs
        Format-specific options (e.g. ``precision="int8"``).

    Returns
    -------
    str
        The target-format output as a string.
    """
    lines = ["# My Target Export", ""]

    for name, node in graph.nodes.items():
        if isinstance(node, nir.LIF):
            size = int(node.tau.shape[0])
            threshold = float(node.v_threshold[0])
            tau = float(node.tau[0])
            lines.append(f"neuron_group {name} size={size} tau={tau} thresh={threshold}")

        elif isinstance(node, nir.Linear):
            rows, cols = node.weight.shape
            lines.append(f"weight_layer {name} shape=({rows},{cols})")

        elif isinstance(node, nir.Input):
            size = int(node.input_type["input"][0])
            lines.append(f"input {name} size={size}")

        elif isinstance(node, nir.Output):
            size = int(node.output_type["output"][0])
            lines.append(f"output {name} size={size}")

    lines.append("")
    for src, dst in graph.edges:
        lines.append(f"connect {src} -> {dst}")

    return "\n".join(lines)
```

---

## Step 3: Register Your Exporter

Register the exporter in `neurocnl/export/__init__.py`:

```python
from neurocnl.export.my_target_exporter import export_my_target

EXPORTERS = {
    # ... existing exporters ...
    "my_target": export_my_target,
}
```

---

## Step 4: Wire into the REST API (optional)

If the exporter should be accessible via `POST /api/export`, add it to the
backend router in `backend/app/routers/export.py` following the pattern used
by existing backends (lava, spinnaker, etc.). The router calls
`compile_to_nir()` internally and then dispatches to the registered exporter.

---

## Step 5: Test Your Exporter

Add a test in `neurocnl/neurocnl/export/test_nir_integration.py` (or create
`tests/export/test_my_target_exporter.py`):

```python
from neurocnl import compile_to_nir
from neurocnl.export.my_target_exporter import export_my_target

_MINIMAL_SPEC = """
The network MUST operate WITH timestep of 1 ms
The network MUST contain an excitatory input population of 4 neurons
The network MUST contain an excitatory output population of 2 neurons
The input MUST project to output
The connection from input to output MUST have WITH synaptic weight of 0.5
The input membrane potential MUST decay WITH time constant of 0.02 seconds
The output membrane potential MUST decay WITH time constant of 0.02 seconds
The input MUST fire ONLY IF membrane potential exceeds 1.0
The output MUST fire ONLY IF membrane potential exceeds 1.0
"""


def test_my_target_exporter_basic():
    graph = compile_to_nir(_MINIMAL_SPEC)
    result = export_my_target(graph)
    assert "neuron_group input" in result
    assert "neuron_group output" in result
    assert "weight_layer" in result


def test_my_target_exporter_no_nengo_import():
    """Confirm the exporter never imports nengo."""
    import importlib
    import neurocnl.export.my_target_exporter as mod

    src = importlib.util.find_spec("neurocnl.export.my_target_exporter")
    with open(src.origin) as f:
        assert "nengo" not in f.read(), "Exporters must not import nengo"
```

---

## Accessing NIR-Metadata-Only Semantics

Some CNL concepts lower to IR but produce advisory metadata rather than
executable NIR structure (e.g. `refractory_period`, `stdp_learning`,
`timing_declaration`). If your target backend supports these natively, read
them from the NIR node metadata:

```python
for name, node in graph.nodes.items():
    if isinstance(node, nir.LIF):
        # Refractory period — stored in node metadata, not nir.LIF field
        tau_ref = node.metadata.get("refractory_period")
        if tau_ref is not None:
            print(f"  {name}: refractory_period = {tau_ref}s")

# Graph-level: STDP learning rules
for rule in graph.metadata.get("unscoped_learning_rules", []):
    print(f"STDP rule: {rule}")

# Graph-level: timing declarations
for decl in graph.metadata.get("timing_declarations", []):
    print(f"Timing: {decl['kind']} = {decl['value']} {decl['unit']}")
```

---

## Summary

1. Start from a `nir.NIRGraph` produced by `compile_to_nir()` — never from `nengo.Network`.
2. Iterate `graph.nodes` and `graph.edges` for the executable structure.
3. Read `node.metadata` and `graph.metadata` for advisory semantics (refractory period, STDP, timing).
4. Place your exporter in `neurocnl/export/` and register it in `EXPORTERS`.
5. Test with the `compile_to_nir()` → `export_my_target(graph)` call chain; assert no Nengo import.
