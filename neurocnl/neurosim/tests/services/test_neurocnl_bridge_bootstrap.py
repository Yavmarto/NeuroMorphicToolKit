"""Tests for the NIR-native support assessment module (replaces neurocnl_bridge tests)."""

from neurosim.app.schemas.canvas import CanvasEdge, CanvasGraph, CanvasNode
from neurosim.app.services.nir_support import (
    NEUROCNL_ROOT,
    assess_validation_support,
    can_use_neurocnl_generator,
)


def test_nir_support_resolves_neurocnl_root_with_ir_package() -> None:
    assert (NEUROCNL_ROOT / "ir" / "__init__.py").exists()


def _biological_graph() -> CanvasGraph:
    return CanvasGraph(
        nodes=[
            CanvasNode(
                id="sensory",
                component_id="lif_population",
                parameters={"name": "sensory", "n_neurons": 10},
                position=(0, 0),
            ),
            CanvasNode(
                id="motor",
                component_id="lif_population",
                parameters={"name": "motor", "n_neurons": 10},
                position=(100, 0),
            ),
        ],
        edges=[
            CanvasEdge(
                id="edge1",
                source_node_id="sensory",
                source_port="out",
                target_node_id="motor",
                target_port="in",
                parameters={"weight": 0.5, "delay": 0.005},
            ),
        ],
        metadata={},
    )


def test_can_use_neurocnl_generator_always_false() -> None:
    """Biological Nengo generator is removed; always returns False."""
    assert can_use_neurocnl_generator(_biological_graph()) is False


def test_biological_graph_gets_approximate_validation_support() -> None:
    """Biological lif_population graphs (no nir_type) get approximate validation."""
    graph = _biological_graph()
    support, _ = assess_validation_support(graph)
    assert support.verdict == "approximate"
