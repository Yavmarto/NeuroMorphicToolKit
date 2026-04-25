"""Snapshot tests for Neurosim adapter — CNL ↔ canvas-graph conversion.

These tests pin the exact CanvasGraph structure produced by the
`cnl_to_graph` service, which is the core Neurosim data boundary
consumed by the Flutter canvas frontend.  Any silent rename of node/
edge fields or change to default position layout will be caught here.

PYTHONPATH must include NeuroMorphicToolKit/Neurosim so that
`neurosim.app.*` is importable.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Fixture CNL specs
# ---------------------------------------------------------------------------

_TWO_POP_CNL = (
    "Create a population 'sensory' of 100 LIF neurons.\n"
    "Create a population 'motor' of 50 LIF neurons.\n"
    "Connect 'sensory' to 'motor' with a static synapse of weight 0.5."
)

_SINGLE_POP_CNL = "Create a population 'input' of 200 LIF neurons."

_THREE_POP_CNL = (
    "Create a population 'encoder' of 64 LIF neurons.\n"
    "Create a population 'hidden' of 128 LIF neurons.\n"
    "Create a population 'decoder' of 32 LIF neurons.\n"
    "Connect 'encoder' to 'hidden' with a static synapse of weight 0.3.\n"
    "Connect 'hidden' to 'decoder' with a static synapse of weight 0.7."
)


# ---------------------------------------------------------------------------
# 1. cnl_to_graph — canonical graph structure
# ---------------------------------------------------------------------------


def test_cnl_to_graph_two_population_snapshot(snapshot: object) -> None:
    """Pin the full CanvasGraph for a two-population sensory→motor network."""
    from neurosim.app.services.cnl_to_graph import cnl_to_graph

    graph = cnl_to_graph(_TWO_POP_CNL)
    assert graph.model_dump() == snapshot


def test_cnl_to_graph_single_population_snapshot(snapshot: object) -> None:
    """Pin the CanvasGraph for a single population (no edges)."""
    from neurosim.app.services.cnl_to_graph import cnl_to_graph

    graph = cnl_to_graph(_SINGLE_POP_CNL)
    assert graph.model_dump() == snapshot


def test_cnl_to_graph_three_population_chain_snapshot(snapshot: object) -> None:
    """Pin the CanvasGraph for a three-population encoder→hidden→decoder chain."""
    from neurosim.app.services.cnl_to_graph import cnl_to_graph

    graph = cnl_to_graph(_THREE_POP_CNL)
    assert graph.model_dump() == snapshot


def test_cnl_to_graph_node_count_and_edge_count(snapshot: object) -> None:
    """Pin the node/edge counts for the two-population graph."""
    from neurosim.app.services.cnl_to_graph import cnl_to_graph

    graph = cnl_to_graph(_TWO_POP_CNL)
    summary = {"node_count": len(graph.nodes), "edge_count": len(graph.edges)}
    assert summary == snapshot


def test_cnl_to_graph_with_position_hints_snapshot(snapshot: object) -> None:
    """Pin the CanvasGraph when explicit position hints are supplied."""
    from neurosim.app.services.cnl_to_graph import cnl_to_graph

    hints = {"sensory": (50.0, 150.0), "motor": (450.0, 150.0)}
    graph = cnl_to_graph(_TWO_POP_CNL, position_hints=hints)
    # Only snapshot node positions and ids — the full graph structure is
    # already covered by test_cnl_to_graph_two_population_snapshot.
    positions = {n.id: n.position for n in graph.nodes}
    assert positions == snapshot
