import base64
import io

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import neurosim.app.services.export_generators as export_generators_mod
from neurosim.app.main import app

client = TestClient(app)

from typing import Any

VALID_GRAPH: dict[str, Any] = {"nodes": [], "edges": [], "metadata": {}}


def test_export_cnl() -> None:
    """Test exporting the graph to CNL format."""
    response = client.post("/api/neurosim/export/cnl", json=VALID_GRAPH)
    assert response.status_code == 200
    result = response.json()
    assert result["format"] == "cnl"
    assert result["backend_support"]["verdict"] == "faithful"


def test_export_python() -> None:
    response = client.post(
        "/api/neurosim/export/python?allow_approximate=true",
        json=VALID_GRAPH,
    )
    assert response.status_code == 200
    result = response.json()
    assert result["format"] == "python"
    assert "import nengo" in result["content"]
    assert result["backend_support"]["verdict"] == "approximate"


def test_export_python_preflight_returns_backend_support() -> None:
    response = client.post(
        "/api/neurosim/export/python?preflight=true", json=VALID_GRAPH
    )
    assert response.status_code == 200
    result = response.json()
    assert result["content"] == ""
    assert result["backend_support"]["verdict"] == "approximate"


def test_export_c_is_blocked_as_unsupported() -> None:
    response = client.post("/api/neurosim/export/c", json=VALID_GRAPH)
    assert response.status_code == 400
    detail = response.json()["detail"]
    assert detail["backend_support"]["verdict"] == "unsupported"
    assert "unsupported" in detail["message"].lower()


def test_export_nir() -> None:
    """Test exporting the graph to NIR format."""
    nir = pytest.importorskip("nir")
    graph = {
        "nodes": [
            {
                "id": "node1",
                "component_id": "lif_population",
                "parameters": {"n_neurons": 10, "tau_rc": 0.05},
                "position": [0, 0],
            },
            {
                "id": "node2",
                "component_id": "lif_population",
                "parameters": {"n_neurons": 10},
                "position": [100, 100],
            },
        ],
        "edges": [
            {
                "id": "edge1",
                "source_node_id": "node1",
                "source_port": "out",
                "target_node_id": "node2",
                "target_port": "in",
                "parameters": {"weight": 0.5},
            }
        ],
        "metadata": {},
    }
    response = client.post(
        "/api/neurosim/export/nir?allow_approximate=true", json=graph
    )
    assert response.status_code == 200
    result = response.json()
    assert result["format"] == "nir"
    assert result["content"]
    assert result["backend_support"]["verdict"] == "approximate"

    # Verify NIR content
    nir_bytes = base64.b64decode(result["content"])
    buffer = io.BytesIO(nir_bytes)
    nir_graph = nir.read(buffer)

    assert isinstance(nir_graph, nir.NIRGraph)
    # nir_graph_serializer produces: node1, node2, input_node1, output_node2
    # (no separate Affine node — weight is embedded in the LIF connection)
    assert len(nir_graph.nodes) >= 2
    assert "node1" in nir_graph.nodes
    assert "node2" in nir_graph.nodes

    # Check node1 is a LIF
    node1 = nir_graph.nodes["node1"]
    assert isinstance(node1, nir.LIF)


def test_export_mlir() -> None:
    """Test exporting the graph to SNN-MLIR format (generator mocked — snn-mlir not installed here)."""
    pytest.importorskip("nir")
    import neurocnl.generation.snn_mlir_generator as snn_mlir_generator_mod

    def _fake_generate_mlir(nir_path: Any, *, quantize: bool = False) -> str:
        return "module { snn.network @net {} }"

    original = snn_mlir_generator_mod.generate_mlir
    snn_mlir_generator_mod.generate_mlir = _fake_generate_mlir
    try:
        response = client.post(
            "/api/neurosim/export/mlir?allow_approximate=true", json=VALID_GRAPH
        )
    finally:
        snn_mlir_generator_mod.generate_mlir = original

    assert response.status_code == 200
    result = response.json()
    assert result["format"] == "mlir"
    assert result["content"] == "module { snn.network @net {} }"
    assert result["backend_support"]["verdict"] == "approximate"


def test_export_mlir_missing_snn_mlir_returns_400() -> None:
    """Real (unmocked) path — snn-mlir isn't installed in this environment, so the
    route should fail closed with a 400 rather than 500 or a silent wrong export."""
    pytest.importorskip("nir")
    response = client.post(
        "/api/neurosim/export/mlir?allow_approximate=true", json=VALID_GRAPH
    )
    assert response.status_code == 400
    assert "snn-mlir" in response.json()["detail"].lower()


def test_export_nir_missing_dependency_returns_503(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Test NIR export fails gracefully when the optional dependency is unavailable."""

    def _raise_missing_nir() -> None:
        raise HTTPException(
            status_code=503,
            detail="NIR export is unavailable because the 'nir' package is not installed.",
        )

    monkeypatch.setattr(export_generators_mod, "import_nir", _raise_missing_nir)

    response = client.post(
        "/api/neurosim/export/nir?allow_approximate=true", json=VALID_GRAPH
    )

    assert response.status_code == 503
    assert "nir" in response.json()["detail"].lower()


def test_export_python_fails_closed_for_multi_node_graphs() -> None:
    graph = {
        "nodes": [
            {
                "id": "sensory_input",
                "component_id": "lif_population",
                "parameters": {"name": "sensory_input", "n_neurons": 10},
                "position": [0, 0],
            },
            {
                "id": "relay",
                "component_id": "lif_population",
                "parameters": {"name": "relay", "n_neurons": 10},
                "position": [100, 0],
            },
            {
                "id": "motor_output",
                "component_id": "lif_population",
                "parameters": {"name": "motor_output", "n_neurons": 10},
                "position": [200, 0],
            },
        ],
        "edges": [
            {
                "id": "edge0",
                "source_node_id": "sensory_input",
                "source_port": "out",
                "target_node_id": "relay",
                "target_port": "in",
                "parameters": {"weight": 0.5},
            },
            {
                "id": "edge1",
                "source_node_id": "relay",
                "source_port": "out",
                "target_node_id": "motor_output",
                "target_port": "in",
                "parameters": {"weight": 0.5},
            },
        ],
        "metadata": {},
    }

    response = client.post(
        "/api/neurosim/export/python?allow_approximate=true",
        json=graph,
    )

    assert response.status_code == 200
    result = response.json()
    assert result["backend_support"]["verdict"] == "approximate"
    assert (
        "local_export_serializer" in result["backend_support"]["approximated_concepts"]
    )


def test_python_export_hyphenated_id_is_valid_python() -> None:
    graph = {
        "nodes": [
            {
                "id": "sensor-1",
                "component_id": "lif_population",
                "parameters": {"name": "sensor-1"},
                "position": [0, 0],
            }
        ],
        "edges": [],
        "metadata": {},
    }

    response = client.post(
        "/api/neurosim/export/python?allow_approximate=true", json=graph
    )
    assert response.status_code == 200
    compile(response.json()["content"], "<neurosim-export>", "exec")


def test_neuroml_export_escapes_quotes_in_name() -> None:
    graph = {
        "nodes": [
            {
                "id": "node1",
                "component_id": "lif_population",
                "parameters": {"name": 'test" id="x'},
                "position": [0, 0],
            }
        ],
        "edges": [],
        "metadata": {},
    }

    response = client.post(
        "/api/neurosim/export/neuroml?allow_approximate=true", json=graph
    )
    assert response.status_code == 200
    assert 'test" id="x' not in response.json()["content"]
    assert "&quot;" in response.json()["content"]


def test_svg_export_escapes_angle_brackets() -> None:
    graph = {
        "nodes": [
            {
                "id": "node1",
                "component_id": "lif_population",
                "parameters": {"name": "<script>"},
                "position": [0, 0],
            }
        ],
        "edges": [],
        "metadata": {},
    }

    response = client.post(
        "/api/neurosim/export/svg?allow_approximate=true", json=graph
    )
    assert response.status_code == 200
    assert "<script>" not in response.json()["content"]
    assert "&lt;script&gt;" in response.json()["content"]
