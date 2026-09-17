"""Shape repairs for NIR graphs compiled from CNL.

CNL states a neuron's parameters once for a whole layer — "Define a LIF neuron
named nir.LIF_1 with time constant 0.002 … and firing threshold 1.0" — so the
compiled graph carries one-element arrays for ``tau``, ``v_threshold`` and the
rest. NIR infers a layer's width from those arrays, so a graph written straight
out reads back as one neuron wide and fails its own type check:

    type mismatch: nir.Input_1.output: [[784]] -> nir.LIF_1.input: [[1]]

The values are correct; they are simply not repeated per neuron. This module
repeats them, using the two shapes in the graph that genuinely determine a
width: an input port's declared shape, and a weight matrix's row count.
"""

from __future__ import annotations

from typing import Any

import numpy as np


def neuron_widths(graph: Any) -> dict[str, int]:
    """Width of each node's output, walked forward from the graph's edges.

    Only the two shapes that actually determine a width are read: an input port
    declares its own, and a weight matrix's row count is the width of whatever it
    feeds. Everything else inherits from its predecessor, which is exactly how a
    feedforward chain behaves.
    """
    width_of: dict[str, int] = {}
    for name, node in graph.nodes.items():
        # Only ports and weight matrices are trusted as sources. A neuron node's
        # own output_type is exactly the value in question — NIR derived it from
        # the one-element parameter arrays, so reading it back would re-seed the
        # width as 1 and defeat the repair.
        if type(node).__name__ in {"Input", "Output"}:
            declared = (getattr(node, "output_type", None) or {}).get("output")
            if declared is not None and np.size(declared) > 0:
                width_of[name] = int(np.prod(np.asarray(declared)))
            continue
        weight = getattr(node, "weight", None)
        if weight is not None and np.asarray(weight).ndim == 2:
            width_of[name] = int(np.asarray(weight).shape[0])

    successors: dict[str, list[str]] = {}
    for edge in graph.edges:
        successors.setdefault(str(edge[0]), []).append(str(edge[1]))

    # Repeat until stable rather than topologically sorting: these graphs are a
    # handful of nodes, and a chain resolves in one pass.
    for _ in range(len(graph.nodes) + 1):
        for source, targets in successors.items():
            if source not in width_of:
                continue
            for target in targets:
                width_of.setdefault(target, width_of[source])
    return width_of


def broadcast_neuron_parameters(graph: Any) -> Any:
    """Widen single-value neuron parameters to the width of their layer.

    The NIR Exporter writes the graph compiled from CNL, and CNL states a neuron's
    time constant and threshold once for the whole layer — so every LIF lands in
    the file with ``tau``/``v_threshold`` of length 1. NIR then infers that layer
    as one neuron wide and refuses the graph: "type mismatch:
    nir.Input_1.output: [[784]] -> nir.LIF_1.input: [[1]]". The values are right,
    the arrays are just not repeated per neuron, so repeat them.
    """
    width_of = neuron_widths(graph)
    for name, node in graph.nodes.items():
        width = width_of.get(name)
        if width is None or width <= 1:
            continue
        widened = False
        for field, value in list(vars(node).items()):
            if not isinstance(value, np.ndarray) or value.shape != (1,):
                continue
            setattr(node, field, np.repeat(value, width))
            widened = True
        if not widened:
            continue
        # The port types were derived from the one-element arrays when the node
        # was built, so they still claim a width of 1 and the type check would
        # fail on exactly the edge this repair exists to fix.
        for attribute, key in (("input_type", "input"), ("output_type", "output")):
            declared = getattr(node, attribute, None)
            if isinstance(declared, dict) and key in declared:
                declared[key] = np.array([width])
    return graph
