"""Tests for the /api/parse endpoint — NIR-native CNL contract.

The NIR-native parser returns one ParseResult record per NIR primitive (node
or edge).  Concept values are NIR type names ("LIF", "Input", "Output",
"Linear", "Connect", …).  Network declarations and comment lines are skipped
by the adapter.
"""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# ---------------------------------------------------------------------------
# Minimal single-node / single-edge specs used in focused contract tests
# ---------------------------------------------------------------------------

_SINGLE_LIF = (
    "Define a LIF neuron named sensor "
    "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0."
)

_SINGLE_EDGE = "sensor connects to actuator."


def test_parse_valid_spec():
    """A single LIF node definition produces one valid ParseResult record."""
    resp = client.post("/api/parse", json={"spec": _SINGLE_LIF})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["errors"] == 0
    sent = data["sentences"][0]
    assert sent["valid"] is True
    assert sent["parsed"]["concept"] == "LIF"
    assert sent["parsed"]["verb"] == "Define"
    assert sent["parsed"]["subject"] == "sensor"


def test_parse_edge_contract_fields():
    """An edge declaration produces a Connect record with source and target."""
    resp = client.post("/api/parse", json={"spec": _SINGLE_EDGE})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["errors"] == 0
    sent = data["sentences"][0]
    assert sent["valid"] is True
    assert sent["parsed"]["concept"] == "Connect"
    assert sent["parsed"]["verb"] == "Connect"
    assert sent["parsed"]["subject"] == "sensor"
    assert sent["parsed"]["condition"] == "actuator"


def test_parse_input_output_ports():
    """Input and Output port definitions produce their NIR primitive concepts."""
    spec = "\n".join(
        [
            "Define an input port named input with shape (1,).",
            "Define an output port named output with shape (1,).",
        ]
    )
    resp = client.post("/api/parse", json={"spec": spec})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 2
    assert data["errors"] == 0
    concepts = [s["parsed"]["concept"] for s in data["sentences"]]
    assert "Input" in concepts
    assert "Output" in concepts


def test_parse_linear_transformation():
    """A linear transformation declaration produces concept 'Linear'."""
    resp = client.post(
        "/api/parse",
        json={"spec": "Define a linear transformation named w1 with weight matrix shape (3, 4)."},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    sent = data["sentences"][0]
    assert sent["parsed"]["concept"] == "Linear"
    assert sent["parsed"]["subject"] == "w1"


def test_parse_multiline():
    """A 2-node + 1-edge spec produces exactly 3 records, no errors.

    Comment lines are stripped; network declaration is skipped by the adapter.
    """
    spec = "\n".join(
        [
            "# comment line — stripped",
            "Define a LIF neuron named sensor "
            "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            "Define a LIF neuron named actuator "
            "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 0.8.",
            "sensor connects to actuator.",
        ]
    )
    resp = client.post("/api/parse", json={"spec": spec})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 3
    assert data["errors"] == 0
    concepts = [s["parsed"]["concept"] for s in data["sentences"]]
    assert concepts.count("LIF") == 2
    assert concepts.count("Connect") == 1


def test_parse_invalid_spec():
    """Unrecognised text returns one error record, not a 4xx HTTP error."""
    resp = client.post("/api/parse", json={"spec": "This is not valid CNL"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 1
    assert data["errors"] == 1
    assert data["sentences"][0]["valid"] is False
    assert data["sentences"][0]["error"] is not None
    assert data["sentences"][0]["error_detail"]["code"] is not None
    assert data["sentences"][0]["error_detail"]["message"] is not None
    assert data["sentences"][0]["error_detail"]["line"] == 1


def test_parse_empty_spec():
    """An empty spec produces no sentences and no errors."""
    resp = client.post("/api/parse", json={"spec": ""})
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] == 0
    assert data["errors"] == 0
