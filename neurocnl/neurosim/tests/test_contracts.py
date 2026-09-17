import pytest
from pydantic import ValidationError

from neurosim.contracts.design_contracts import (
    CanvasEdge,
    CanvasGraph,
    CanvasNode,
    PreviewRequest,
    SweepRequest,
)


def test_preview_request_duration_validation() -> None:
    # Should pass
    PreviewRequest(graph=CanvasGraph(nodes=[], edges=[]), duration_ms=500.0)

    # Should fail
    with pytest.raises(ValidationError) as excinfo:
        PreviewRequest(graph=CanvasGraph(nodes=[], edges=[]), duration_ms=500.1)
    assert "Preview duration cannot exceed 500ms" in str(excinfo.value)


def test_sweep_request_steps_validation() -> None:
    # Should pass
    SweepRequest(
        graph=CanvasGraph(nodes=[], edges=[]),
        parameter_path="nodes.a.tau",
        start=0.01,
        end=0.1,
        steps=20,
    )

    # Should fail
    with pytest.raises(ValidationError) as excinfo:
        SweepRequest(
            graph=CanvasGraph(nodes=[], edges=[]),
            parameter_path="nodes.a.tau",
            start=0.01,
            end=0.1,
            steps=21,
        )
    assert "Sweep steps cannot exceed 20" in str(excinfo.value)


def test_canvas_graph_integrity_validation() -> None:
    node1 = CanvasNode(id="node1", component_id="comp", parameters={}, position=(0, 0))
    node2 = CanvasNode(
        id="node2", component_id="comp", parameters={}, position=(10, 10)
    )

    # Valid edge
    valid_edge = CanvasEdge(
        id="edge1",
        source_node_id="node1",
        source_port="out",
        target_node_id="node2",
        target_port="in",
        parameters={},
    )
    CanvasGraph(nodes=[node1, node2], edges=[valid_edge])

    # Invalid edge (dangling source)
    invalid_edge_source = CanvasEdge(
        id="edge2",
        source_node_id="nonexistent",
        source_port="out",
        target_node_id="node2",
        target_port="in",
        parameters={},
    )
    with pytest.raises(ValidationError) as excinfo:
        CanvasGraph(nodes=[node1, node2], edges=[invalid_edge_source])
    assert "references non-existent source node 'nonexistent'" in str(excinfo.value)

    # Invalid edge (dangling target)
    invalid_edge_target = CanvasEdge(
        id="edge3",
        source_node_id="node1",
        source_port="out",
        target_node_id="nonexistent",
        target_port="in",
        parameters={},
    )
    with pytest.raises(ValidationError) as excinfo:
        CanvasGraph(nodes=[node1, node2], edges=[invalid_edge_target])
    assert "references non-existent target node 'nonexistent'" in str(excinfo.value)
