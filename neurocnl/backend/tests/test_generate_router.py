"""Tests for the /api/generate endpoint — NIR-native CNL contract."""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# NIR-native 3-layer feedforward network used throughout this suite.
VALID_SPEC = "\n".join(
    [
        "Define a network named feedforward.",
        "Define an input port named input with shape (4,).",
        "Define a linear transformation named w_input_hidden with weight matrix shape (3, 4).",
        "Define a LIF neuron named hidden "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_output with weight matrix shape (2, 3).",
        "Define a LIF neuron named output_layer "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_input_hidden.",
        "w_input_hidden connects to hidden.",
        "hidden connects to w_hidden_output.",
        "w_hidden_output connects to output_layer.",
        "output_layer connects to output.",
    ]
)


def test_generate_valid_spec_returns_nir_and_roundtrip_cnl() -> None:
    """A valid NIR-native spec returns a topology, roundtrip CNL, and JSON NIR code."""
    resp = client.post("/api/generate", json={"spec": VALID_SPEC})
    assert resp.status_code == 200
    data = resp.json()

    assert "network" in data
    assert "cnl_document" in data
    assert "nir_code" in data
    assert len(data["network"]["nodes"]) > 0
    assert len(data["network"]["edges"]) > 0
    # NIR code is JSON with a "type" key at the top level.
    assert '"type"' in data["nir_code"]
    # CNL document is valid NIR-native text (begins with Define or # comments).
    assert data["cnl_document"].strip().startswith("Define")


def test_generate_invalid_spec_returns_parse_failure() -> None:
    """Unrecognised text returns 400 parse_failed."""
    resp = client.post("/api/generate", json={"spec": "not valid cnl"})
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail["error"] == "parse_failed"
    assert detail["items"][0]["line"] == 1


def test_generate_no_valid_sentences() -> None:
    """Whitespace-only spec returns 422 validation_failed."""
    resp = client.post("/api/generate", json={"spec": "   \n  "})
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert detail["messages"] == ["No valid CNL sentences found."]


def test_generate_serialization_mapping() -> None:
    """Each node and edge in the network has the required structural fields."""
    resp = client.post("/api/generate", json={"spec": VALID_SPEC})
    assert resp.status_code == 200
    network = resp.json()["network"]

    for node in network["nodes"]:
        assert "id" in node
        assert "type" in node
        assert "label" in node
        assert "params" in node
        if node["position"]:
            assert "x" in node["position"]
            assert "y" in node["position"]

    for edge in network["edges"]:
        assert "id" in edge
        assert "source" in edge
        assert "target" in edge
        assert "params" in edge


def test_generate_roundtrip_cnl_recompiles_to_nir() -> None:
    """The cnl_document returned by generate re-compiles without errors."""
    from neurocnl.compile import compile_to_nir

    resp = client.post("/api/generate", json={"spec": VALID_SPEC})
    assert resp.status_code == 200

    roundtrip_cnl = resp.json()["cnl_document"]
    graph = compile_to_nir(roundtrip_cnl)
    assert graph is not None
    assert len(graph.nodes) > 0


def test_generate_returns_422_for_compile_conflict() -> None:
    """An edge referencing an undeclared node triggers a 422 lowering_failed error."""
    conflicting_spec = "\n".join(
        [
            "Define a network named test.",
            "Define a LIF neuron named sensor "
            "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            # 'undefined_node' is never declared — ghost node reference
            "sensor connects to undefined_node.",
        ]
    )
    resp = client.post("/api/generate", json={"spec": conflicting_spec})
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "lowering_failed"
    assert detail["items"][0]["code"] is not None
    assert detail["items"][0]["message"] is not None
