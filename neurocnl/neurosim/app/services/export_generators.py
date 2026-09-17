"""Service containing graph-to-format generation logic for all export targets.

Each public function takes a CanvasGraph and returns a string (or raises
HTTPException for optional deps that are missing at runtime).
"""

import base64
import html
import importlib
import io
import re
import tempfile
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from backend.app.services.nir_graph_serializer import deserialize_canvas_graph

from ...contracts.design_contracts import CanvasGraph
from .components import load_components


def import_nir() -> Any:
    """Import the optional NIR dependency; raises HTTPException if unavailable."""
    try:
        return importlib.import_module("nir")
    except ModuleNotFoundError as exc:
        raise HTTPException(
            status_code=503,
            detail=(
                "NIR export is unavailable because the 'nir' package is not installed "
                "in the active backend environment."
            ),
        ) from exc


def to_python_identifier(raw: str) -> str:
    """Convert an arbitrary string to a valid Python identifier.

    Args:
        raw (str): The raw string to convert.

    Returns:
        str: A valid Python identifier derived from the input.
    """
    safe = re.sub(r"[^A-Za-z0-9_]", "_", raw)
    if safe and safe[0].isdigit():
        safe = f"n_{safe}"
    return safe or "node"


def generate_python_nengo(graph: CanvasGraph) -> str:
    """Generate a runnable Nengo Python script from the CanvasGraph.

    Args:
        graph (CanvasGraph): The network graph to export.

    Returns:
        str: A Python source string that runs the network with Nengo.
    """
    components = load_components()
    node_vars = {node.id: to_python_identifier(node.id) for node in graph.nodes}
    lines = [
        "import nengo",
        "import numpy as np",
        "",
        "model = nengo.Network(label='Exported Design')",
        "with model:",
    ]

    # Create ensembles
    for node in graph.nodes:
        block = components.get(node.component_id)
        if not block:
            lines.append(f"    # Unknown component type for node {node.id}: {node.component_id}")
            continue

        params = {p.name: p.default for p in block.parameters}
        params.update(node.parameters)

        n_neurons = params.get("n_neurons", 100)
        tau_rc = params.get("tau_rc", 0.02)
        tau_ref = params.get("tau_ref", 0.002)

        if node.component_id == "adaptive_lif":
            neuron_model = f"nengo.AdaptiveLIF(tau_rc={tau_rc}, tau_ref={tau_ref})"
        else:
            neuron_model = f"nengo.LIF(tau_rc={tau_rc}, tau_ref={tau_ref})"

        node_var = node_vars[node.id]
        lines.append(f"    # Node: {node.id} ({block.name})")
        lines.append(f"    {node_var} = nengo.Ensemble(")
        lines.append(f"        n_neurons={n_neurons},")
        lines.append("        dimensions=1,")
        lines.append(f"        neuron_type={neuron_model},")
        lines.append(f"        label='{node.id}',")
        lines.append("    )")
        lines.append(f"    {node_var}_spikes = nengo.Probe({node_var}.neurons, 'spikes')")
        lines.append("")

    # Create connections
    for edge in graph.edges:
        weight = edge.parameters.get("weight", 1.0)
        delay = edge.parameters.get("delay", 0.001)

        lines.append(f"    # Connection: {edge.id}")
        lines.append("    nengo.Connection(")
        lines.append(f"        {node_vars[edge.source_node_id]},")
        lines.append(f"        {node_vars[edge.target_node_id]},")
        lines.append(f"        transform={weight},")
        lines.append(f"        synapse={delay},")
        lines.append("    )")
        lines.append("")

    lines.extend(
        [
            "if __name__ == '__main__':",
            "    with nengo.Simulator(model) as sim:",
            "        sim.run(0.5)",
            "    print('Simulation complete.')",
        ],
    )

    return "\n".join(lines)


def generate_nir(graph: CanvasGraph) -> str:
    """Generate a NIR graph representation as a base64-encoded HDF5 string.

    Args:
        graph (CanvasGraph): The network graph to export.

    Returns:
        str: Base64-encoded HDF5 content of the NIR graph.

    Raises:
        HTTPException: 503 if the ``nir`` package is not installed.
    """
    nir = import_nir()
    nir_graph = deserialize_canvas_graph(graph)
    buffer = io.BytesIO()
    nir.write(buffer, nir_graph)
    return base64.b64encode(buffer.getvalue()).decode("utf-8")


def generate_mlir_export(graph: CanvasGraph, *, quantize: bool = False) -> str:
    """Generate SNN-MLIR dialect text for the graph via ``neurocnl``'s snn-mlir generator.

    Args:
        graph (CanvasGraph): The network graph to export.
        quantize (bool): When True, emit int8 + Q12 fixed-point MLIR.

    Returns:
        str: SNN-MLIR dialect text.

    Raises:
        HTTPException: 503 if the ``nir`` package is not installed, 400 if
            ``snn-mlir`` can't represent this graph's topology.
    """
    from neurocnl.generation.snn_mlir_generator import generate_mlir

    nir = import_nir()
    nir_graph = deserialize_canvas_graph(graph)

    with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        nir.write(tmp_path, nir_graph)
        return generate_mlir(tmp_path, quantize=quantize)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    finally:
        tmp_path.unlink(missing_ok=True)


def generate_neuroml(graph: CanvasGraph) -> str:
    """Generate a minimal NeuroML-like XML serialization for the graph.

    Args:
        graph (CanvasGraph): The network graph to export.

    Returns:
        str: A NeuroML XML string.
    """
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<neuroml xmlns="http://www.neuroml.org/schema/neuroml2">',
    ]
    for node in graph.nodes:
        safe_id = html.escape(str(node.id), quote=True)
        safe_name = html.escape(str(node.parameters.get("name", node.id)), quote=True)
        lines.append(
            f'  <population id="{safe_id}" component="{safe_name}" '
            f'size="{node.parameters.get("n_neurons", 100)}"/>',
        )
    lines.append("</neuroml>")
    return "\n".join(lines)


def generate_svg(graph: CanvasGraph) -> str:
    """Generate a simple SVG layout export for the graph.

    Args:
        graph (CanvasGraph): The network graph to export.

    Returns:
        str: An SVG string representing the graph layout.
    """
    lines = ['<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg">']
    for node in graph.nodes:
        x, y = node.position
        safe_label = html.escape(str(node.parameters.get("name", node.id)))
        lines.append(f'  <circle cx="{x}" cy="{y}" r="20" fill="blue" />')
        lines.append(f'  <text x="{x}" y="{y + 30}" font-size="12">{safe_label}</text>')
    lines.append("</svg>")
    return "\n".join(lines)
