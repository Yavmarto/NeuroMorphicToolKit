import pytest

from neurosim.app.schemas.canvas import CanvasGraph, CanvasNode
from neurosim.app.schemas.sweep import SweepRequest
from neurosim.app.services.sweep_runner import run_sweep, update_graph_parameter


def test_run_sweep_mock() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="lif_population",
                parameters={"name": "P1", "tau_rc": 0.02},
                position=(0, 0),
            ),
        ],
        edges=[],
        metadata={},
    )
    request = SweepRequest(
        graph=graph,
        parameter_path="nodes.n1.tau_rc",
        start=0.01,
        end=0.03,
        steps=3,
        simulation_duration_ms=50,
    )
    response = run_sweep(request)

    assert response.status == "completed"
    assert response.parameter_path == "nodes.n1.tau_rc"
    assert response.steps is not None
    assert len(response.steps) == 3
    assert response.steps[0].parameter_value == pytest.approx(0.01)
    assert response.steps[1].parameter_value == pytest.approx(0.02)
    assert response.steps[2].parameter_value == pytest.approx(0.03)

    for step in response.steps:
        assert step.result.status in ["completed", "queued"]
        if step.result.status == "completed":
            assert isinstance(step.result.results, dict)
            assert "n1" in step.result.results


def test_run_sweep_single_step() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="lif_population",
                parameters={"name": "P1"},
                position=(0, 0),
            ),
        ],
        edges=[],
        metadata={},
    )
    request = SweepRequest(
        graph=graph,
        parameter_path="nodes.n1.tau_rc",
        start=0.01,
        end=0.03,
        steps=1,
        simulation_duration_ms=50,
    )
    response = run_sweep(request)
    assert response.steps is not None
    assert len(response.steps) == 1
    assert response.steps[0].parameter_value == 0.01


def test_update_graph_parameter_rejects_malformed_path() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="lif_population",
                parameters={"name": "P1"},
                position=(0, 0),
            ),
        ],
        edges=[],
        metadata={},
    )

    with pytest.raises(ValueError, match="Invalid parameter path"):
        update_graph_parameter(graph, "invalid.path", 0.1)


def test_update_graph_parameter_rejects_non_numeric_param() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="lif_population",
                parameters={"name": "P1"},
                position=(0, 0),
            ),
        ],
        edges=[],
        metadata={},
    )

    with pytest.raises(ValueError, match="not a supported sweep target"):
        update_graph_parameter(graph, "nodes.n1.name", 0.1)
