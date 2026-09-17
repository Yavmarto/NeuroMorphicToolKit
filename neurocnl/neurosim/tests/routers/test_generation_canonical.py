"""Tests for canonical editor sync endpoints."""

from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)

REFLEX_ARC_CNL = "\n".join(
    [
        "Define a network named reflexarc.",
        "",
        "# Layers:",
        "Define an input port named input with shape (1,).",
        "Define a LIF neuron named sensory_input with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a LIF neuron named motor_output with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 0.8.",
        "Define an output port named output with shape (1,).",
        "",
        "# Connections:",
        "input connects to sensory_input.",
        "sensory_input connects to motor_output.",
        "motor_output connects to output.",
    ]
)


def test_parse_cnl_canonical_returns_200() -> None:
    resp = client.post(
        "/api/neurosim/parse-cnl-canonical", json={"spec_text": REFLEX_ARC_CNL}
    )
    assert resp.status_code == 200


def test_parse_cnl_canonical_returns_ir_json_and_canvas() -> None:
    resp = client.post(
        "/api/neurosim/parse-cnl-canonical", json={"spec_text": REFLEX_ARC_CNL}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert "document" in data
    doc = data["document"]
    # NIR-native CNL parses into a NIR graph, then imports to IR; populations
    # should include sensory_input and motor_output LIF nodes
    populations = doc["ir_json"]["populations"]
    assert "sensory_input" in populations
    assert "motor_output" in populations
    assert doc["canvas"] is not None
    assert len(doc["canvas"]["nodes"]) >= 1


def test_parse_cnl_canonical_single_lif_returns_document() -> None:
    # A network with just one LIF node and explicit I/O ports
    cnl = "\n".join(
        [
            "Define a network named test_net.",
            "",
            "# Layers:",
            "Define an input port named input with shape (1,).",
            "Define a LIF neuron named pop_a with "
            "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            "Define an output port named output with shape (1,).",
            "",
            "# Connections:",
            "input connects to pop_a.",
            "pop_a connects to output.",
        ]
    )
    resp = client.post("/api/neurosim/parse-cnl-canonical", json={"spec_text": cnl})
    assert resp.status_code == 200
    data = resp.json()
    doc = data["document"]
    # Document is valid; fidelity annotations may be empty for simple LIF graphs
    assert "ir_json" in doc
    assert "canvas" in doc


def test_generate_cnl_canonical_returns_cnl_from_document() -> None:
    parse_resp = client.post(
        "/api/neurosim/parse-cnl-canonical", json={"spec_text": REFLEX_ARC_CNL}
    )
    assert parse_resp.status_code == 200
    doc = parse_resp.json()["document"]

    gen_resp = client.post(
        "/api/neurosim/generate-cnl-canonical", json={"document": doc}
    )
    assert gen_resp.status_code == 200
    body = gen_resp.json()
    # The generated CNL must contain the node names
    assert "sensory_input" in body["cnl_text"] or "motor_output" in body["cnl_text"]
