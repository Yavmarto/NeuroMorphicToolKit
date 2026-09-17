import textwrap
from collections.abc import Iterator
from pathlib import Path

import pytest

from neurosim.app.services.components import _invalidate_cache

CUSTOM_LIF_SOURCE = textwrap.dedent(
    """
    import nengo
    from nmtk_sdk import CustomNode, param, port

    class CustomLIF(CustomNode):
        name = "Custom LIF"
        category = "neurons"
        canvases = ["model"]
        frameworks = ["nengo"]
        author = "tester"

        @param(type="float", default=0.02, label="tau_rc")
        def tau_rc(self): ...

        @param(type="float", default=0.002, label="tau_ref")
        def tau_ref(self): ...

        @port(direction="input", label="In")
        def spikes_in(self): ...

        def to_nengo(self, params):
            return nengo.LIF(
                tau_rc=params.get("tau_rc", 0.02),
                tau_ref=params.get("tau_ref", 0.002),
            )
"""
)

DELEGATED_LIF_SOURCE = textwrap.dedent(
    """
    from nmtk_sdk import CustomNode, param

    class DelegatedLIF(CustomNode):
        node_id = "custom_delegated_lif_12345678"
        name = "Delegated LIF"
        category = "neurons"
        canvases = ["model"]
        frameworks = ["nengo"]
        base_component_id = "lif_population"

        @param(type="float", default=0.02, label="tau_rc")
        def tau_rc(self): ...

        @param(type="float", default=0.002, label="tau_ref")
        def tau_ref(self): ...
"""
)


@pytest.fixture(autouse=True)
def _reset_cache() -> Iterator[None]:  # noqa: ANN202
    _invalidate_cache()
    yield
    _invalidate_cache()


def test_custom_node_runs_in_preview(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "custom_lif.py").write_text(CUSTOM_LIF_SOURCE)

    import neurosim.app.services.components as svc

    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    _invalidate_cache()

    from neurosim.app.services.preview_runner import run_preview
    from neurosim.contracts.design_contracts import (
        CanvasGraph,
        CanvasNode,
        PreviewRequest,
        SimulationStatus,
    )

    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="custom_tester_custom_lif",
                parameters={"tau_rc": 0.02, "tau_ref": 0.002, "n_neurons": 10},
                position=(0.0, 0.0),
            )
        ],
        edges=[],
    )
    request = PreviewRequest(graph=graph, duration_ms=10.0)
    response = run_preview(request)
    assert response.status == SimulationStatus.COMPLETED


def test_delegated_builtin_custom_node_runs_without_framework_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    custom_dir = tmp_path / "custom_nodes"
    custom_dir.mkdir()
    (custom_dir / "delegated_lif.py").write_text(DELEGATED_LIF_SOURCE)

    import neurosim.app.services.components as svc

    monkeypatch.setattr(svc, "CUSTOM_NODES_DIR", custom_dir)
    _invalidate_cache()

    from neurosim.app.services.preview_runner import run_preview
    from neurosim.contracts.design_contracts import (
        CanvasGraph,
        CanvasNode,
        PreviewRequest,
        SimulationStatus,
    )

    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="custom_delegated_lif_12345678",
                parameters={"tau_rc": 0.02, "tau_ref": 0.002, "n_neurons": 10},
                position=(0.0, 0.0),
            )
        ],
        edges=[],
    )

    response = run_preview(PreviewRequest(graph=graph, duration_ms=10.0))

    assert response.status == SimulationStatus.COMPLETED
