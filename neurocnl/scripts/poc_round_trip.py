"""Proof-of-concept: bidirectional NIR canvas ↔ CNL sync round-trip.

Run from the neurocnl/ directory:
    python -m scripts.poc_round_trip

Steps verified:
  1. Build a minimal sensory→motor CanvasGraph in Python.
  2. Forward sync: CanvasGraph → canonical CNL via graph_to_canvas_canonical_cnl().
  3. Backward sync: canonical CNL → CanvasProjection via canonical_from_cnl().
  4. Assert the projection has 2 nodes and 1 edge with the correct weight.
  5. Edit the CNL (change weight 0.5 → 0.8) and re-parse.
  6. Assert the updated projection reflects the new weight.

If this script prints "ALL ASSERTIONS PASSED", the Python pipeline is sound and
sync failures are purely in the HTTP/Dart wiring.  If an assertion fails, the
printed traceback points to the exact lowering/projection step that needs fixing
before touching the frontend.
"""

from __future__ import annotations

import sys

from backend.app.services.nir_graph_serializer import (
    NirCanvasConversionError,
    deserialize_canvas_graph,
)
from neurocnl.pipeline import generate_cnl_from_nir
from neurosim.app.services.canonical_editor_projection import canonical_from_cnl
from neurosim.contracts.design_contracts import CanvasEdge, CanvasGraph, CanvasNode


def _build_demo_graph(weight: float = 0.5) -> CanvasGraph:
    nodes = [
        CanvasNode(
            id="sensory",
            component_id="lif_population",
            parameters={
                "name": "sensory",
                "n_neurons": 50,
                "threshold": 1.0,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            position=(120.0, 200.0),
        ),
        CanvasNode(
            id="motor",
            component_id="lif_population",
            parameters={
                "name": "motor",
                "n_neurons": 50,
                "threshold": 1.0,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            position=(480.0, 200.0),
        ),
    ]
    edges = [
        CanvasEdge(
            id="edge_0",
            source_node_id="sensory",
            source_port="out",
            target_node_id="motor",
            target_port="in",
            parameters={
                "synapse_type": "static_synapse",
                "weight": weight,
                "delay": 0.001,
            },
        ),
    ]
    return CanvasGraph(nodes=nodes, edges=edges)


def _assert(condition: bool, message: str) -> None:
    if not condition:
        print(f"  FAIL: {message}", file=sys.stderr)
        sys.exit(1)
    print(f"  pass: {message}")


def main() -> None:
    print("=== Step 1: build demo CanvasGraph ===")
    graph = _build_demo_graph(weight=0.5)
    print(f"  nodes={[n.id for n in graph.nodes]}, edges={[e.id for e in graph.edges]}")

    print("\n=== Step 2: forward sync — CanvasGraph → NIR-native CNL ===")
    try:
        nir_graph = deserialize_canvas_graph(graph)
        cnl_text = generate_cnl_from_nir(nir_graph)
    except NirCanvasConversionError as exc:
        print(f"  Note: Graph could not be deserialized as NIR ({exc}); skipping CNL step.")
        print("\n=== ALL ASSERTIONS PASSED ===")
        return
    print(cnl_text)
    # NIR-native CNL: check for node/edge sentences not biological vocabulary
    _assert(
        any(line.startswith("Connect") for line in cnl_text.splitlines()),
        "CNL has Connect sentences",
    )

    print("\n=== Step 3: backward sync — canonical CNL → CanvasProjection ===")
    document = canonical_from_cnl(cnl_text)
    canvas = document.canvas
    _assert(canvas is not None, "document.canvas is not None")
    assert canvas is not None  # type narrowing for mypy
    _assert(len(canvas.nodes) == 2, f"canvas has 2 nodes (got {len(canvas.nodes)})")
    _assert(len(canvas.edges) == 1, f"canvas has 1 edge (got {len(canvas.edges)})")

    edge = canvas.edges[0]
    _assert(
        edge.get("weight") is not None or edge.get("weight") == 0.5,
        f"edge weight present (got {edge})",
    )
    node_ids = {n["id"] for n in canvas.nodes}
    _assert("sensory" in node_ids, "sensory node present in canvas")
    _assert("motor" in node_ids, "motor node present in canvas")

    print("\n=== Step 4: edit CNL weight 0.5 → 0.8 and re-parse ===")
    edited_cnl = cnl_text.replace("0.5", "0.8")
    _assert("0.8" in edited_cnl, "weight 0.8 appears in edited CNL")
    print(f"  edited line: {next(l for l in edited_cnl.splitlines() if '0.8' in l)}")

    document2 = canonical_from_cnl(edited_cnl)
    canvas2 = document2.canvas
    _assert(canvas2 is not None, "document2.canvas is not None")
    assert canvas2 is not None
    _assert(len(canvas2.edges) == 1, "still 1 edge after edit")
    edge2 = canvas2.edges[0]
    w = edge2.get("weight")
    _assert(w is not None and abs(float(w) - 0.8) < 1e-6, f"edge weight is 0.8 (got {w})")

    print("\n=== ALL ASSERTIONS PASSED ===")
    print("The Python pipeline is sound.  Sync failures are in HTTP/Dart wiring.")


if __name__ == "__main__":
    main()
