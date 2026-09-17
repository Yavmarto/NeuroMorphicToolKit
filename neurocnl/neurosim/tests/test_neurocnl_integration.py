"""Integration tests for NeuroSim NIR-native CNL semantics.

Replaces the former biological-bridge integration tests after the neurocnl_bridge
module was removed as part of the NIR-native CNL migration.
"""

from neurocnl.layers.layer1_validator import validate
from neurosim.app.services.nir_support import (
    assess_preview_support,
    assess_validation_support,
    validate_semantics,
)
from neurosim.contracts.design_contracts import CanvasEdge, CanvasGraph, CanvasNode


def test_validation_semantics_rejects_invalid_biological_params() -> None:
    """validate_semantics should report errors for invalid lif_population params."""
    neurosim_params = {
        "tau_rc": -0.01,  # Invalid: negative tau
        "tau_ref": 0.002,
        "threshold": 0.0,  # Invalid: threshold <= resting
    }

    neurocnl_params = {
        "tau": -0.01,
        "refractory_period": 0.002,
        "threshold": 0.0,
        "resting_potential": 0.0,
        "reset_potential": 0.0,
        "current_voltage": 0.5,
    }

    cnl_validation = validate([], neurocnl_params)
    bridge_errors = validate_semantics(neurosim_params)

    assert not cnl_validation["overall"]
    assert len(cnl_validation["failed"]) == len(bridge_errors)

    failed_names = [f["name"] for f in cnl_validation["failed"]]
    for error in bridge_errors:
        assert any(name in error for name in failed_names)


def test_preview_support_returns_approximate_for_biological_nodes() -> None:
    """Biological lif_population nodes (no nir_type) should get approximate support."""
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="sensory",
                component_id="lif_population",
                parameters={"name": "sensory", "n_neurons": 50},
                position=(0.0, 0.0),
            ),
            CanvasNode(
                id="motor",
                component_id="lif_population",
                parameters={"name": "motor", "n_neurons": 50},
                position=(320.0, 0.0),
            ),
        ],
        edges=[
            CanvasEdge(
                id="edge_0",
                source_node_id="sensory",
                source_port="out",
                target_node_id="motor",
                target_port="in",
                parameters={"weight": 1.0, "delay": 0.001},
            ),
        ],
        metadata={},
    )

    support, fidelity = assess_preview_support(graph)

    # Biological-only nodes have no nir_type — local preview fallback
    assert support.verdict == "approximate"
    # Edges with delay get an axonal_delay fidelity annotation
    assert fidelity is not None
    assert any(ann.concept == "axonal_delay" for ann in fidelity.annotations)


def test_preview_support_returns_faithful_for_nir_nodes() -> None:
    """NIR-type nodes should get faithful support."""
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="x",
                component_id="nir_input",
                nir_type="Input",
                parameters={},
                position=(0.0, 0.0),
            ),
        ],
        edges=[],
        metadata={},
    )

    support, _ = assess_preview_support(graph)
    assert support.verdict == "faithful"


def test_validation_support_returns_faithful_for_nir_nodes() -> None:
    """NIR-type nodes should get faithful validation support."""
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="x",
                component_id="nir_input",
                nir_type="Input",
                parameters={},
                position=(0.0, 0.0),
            ),
        ],
        edges=[],
        metadata={},
    )

    support, _ = assess_validation_support(graph)
    assert support.verdict == "faithful"
