from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)

# ---------------------------------------------------------------------------
# Canonical NIR-native graph fixture
# ---------------------------------------------------------------------------
# Uses NIR-native nir_type values and safe node IDs (no Biological_Grammar
# reserved keywords like "sensory" or "motor").

VALID_GRAPH = {
    "nodes": [
        {
            "id": "pop_a",
            "component_id": "lif_population",
            "nir_type": "nir.LIF",
            "parameters": {
                "name": "pop_a",
                "n_neurons": 1,
                "tau": 0.02,
                "tau_rc": 0.02,
                "r": 1.0,
                "v_leak": 0.0,
                "threshold": 1.0,
            },
            "position": [0, 0],
        },
        {
            "id": "pop_b",
            "component_id": "lif_population",
            "nir_type": "nir.LIF",
            "parameters": {
                "name": "pop_b",
                "n_neurons": 1,
                "tau": 0.02,
                "tau_rc": 0.02,
                "r": 1.0,
                "v_leak": 0.0,
                "threshold": 0.8,
            },
            "position": [320, 0],
        },
    ],
    "edges": [
        {
            "id": "edge_0",
            "source_node_id": "pop_a",
            "source_port": "out",
            "target_node_id": "pop_b",
            "target_port": "in",
            "parameters": {},
        },
    ],
    "metadata": {},
}

# ---------------------------------------------------------------------------
# NIR-native CNL fixture: two LIF neurons with input/output ports
# ---------------------------------------------------------------------------

_NIR_NATIVE_CNL = """\
Define an input port named in1 with shape (1,).
Define a LIF neuron named pop_a with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a LIF neuron named pop_b with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 0.8.
Define an output port named out1 with shape (1,).
in1 connects to pop_a.
pop_a connects to pop_b.
pop_b connects to out1.
"""


def test_generate_cnl() -> None:
    """generate-cnl on a canonical NIR graph returns NIR-native CNL format."""
    response = client.post("/api/neurosim/generate-cnl", json=VALID_GRAPH)
    assert response.status_code == 200
    result = response.json()
    cnl = result["cnl_spec"]
    # NIR-native format: "Define a LIF neuron named ..."
    assert "Define a LIF neuron named pop_a" in cnl
    assert "Define a LIF neuron named pop_b" in cnl
    assert "pop_a connects to pop_b" in cnl
    # Must NOT emit legacy Biological_Grammar tokens
    assert "MUST" not in cnl
    assert "The sensory" not in cnl


def test_generate_cnl_rejects_non_canonical_graphs() -> None:
    """generate-cnl returns 422 with unsupported_concepts for unknown nir_type."""
    graph = {
        "nodes": [
            {
                "id": "adaptive_node",
                "component_id": "adaptive_lif",
                "nir_type": "nir.AdaptiveLIF",  # not in NIR_CANVAS_TYPE_SPECS
                "parameters": {"name": "adaptive", "n_neurons": 100},
                "position": [0, 0],
            },
            {
                "id": "pop_b",
                "component_id": "lif_population",
                "nir_type": "nir.LIF",
                "parameters": {
                    "name": "pop_b",
                    "n_neurons": 1,
                    "tau": 0.02,
                    "r": 1.0,
                    "v_leak": 0.0,
                    "threshold": 0.8,
                },
                "position": [320, 0],
            },
        ],
        "edges": [
            {
                "id": "edge_0",
                "source_node_id": "adaptive_node",
                "source_port": "out",
                "target_node_id": "pop_b",
                "target_port": "in",
                "parameters": {},
            },
        ],
        "metadata": {},
    }

    response = client.post("/api/neurosim/generate-cnl", json=graph)

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert "nir.AdaptiveLIF" in detail["unsupported_concepts"]


def test_parse_cnl() -> None:
    """parse-cnl on NIR-native CNL returns a well-formed canvas graph."""
    response = client.post(
        "/api/neurosim/parse-cnl",
        json={"cnl_spec": _NIR_NATIVE_CNL},
    )
    assert response.status_code == 200
    graph = response.json()

    node_ids = {n["id"] for n in graph["nodes"]}
    assert "pop_a" in node_ids
    assert "pop_b" in node_ids

    # Threshold values are preserved in serialised parameters.
    pop_a = next(n for n in graph["nodes"] if n["id"] == "pop_a")
    pop_b = next(n for n in graph["nodes"] if n["id"] == "pop_b")
    assert abs(pop_a["parameters"]["threshold"] - 1.0) < 1e-6
    assert abs(pop_b["parameters"]["threshold"] - 0.8) < 1e-6

    # At least one edge must exist (pop_a → pop_b at minimum).
    assert len(graph["edges"]) > 0


def test_parse_cnl_rejects_legacy_must_format() -> None:
    """parse-cnl returns 422 with legacy_grammar diagnostics for MUST-format CNL.

    This documents intentional rejection: MUST-format (Biological_Grammar) is
    no longer accepted by the NIR-native pipeline.
    """
    must_cnl = (
        "The evidence population MUST encode input using 12 neurons.\n"
        "The choice_A population MUST encode input using 12 neurons.\n"
    )
    response = client.post(
        "/api/neurosim/parse-cnl",
        json={"cnl_spec": must_cnl},
    )
    assert response.status_code == 422
    detail = response.json()["detail"]
    # Diagnostics must mention legacy_grammar or syntax_error.
    diag_codes = {d["code"] for d in detail.get("diagnostics", [])}
    assert diag_codes & {
        "legacy_grammar",
        "syntax_error",
    }, f"Expected legacy_grammar/syntax_error diagnostics, got: {diag_codes}"


def test_parse_cnl_with_graph_payload_returns_valid_graph() -> None:
    """parse-cnl accepts a 'graph' field in the payload without error.

    The graph field is used for position hints (currently assigned
    auto-positions by the serialiser).  The response must be a valid
    canvas graph with nodes at numeric positions.
    """
    response = client.post(
        "/api/neurosim/parse-cnl",
        json={
            "cnl_spec": _NIR_NATIVE_CNL,
            "graph": {
                "nodes": [
                    {
                        "id": "pop_a",
                        "component_id": "lif_population",
                        "parameters": {"name": "pop_a"},
                        "position": [42.0, 84.0],
                    },
                ],
                "edges": [],
                "metadata": {},
            },
        },
    )
    assert response.status_code == 200

    graph = response.json()
    node_ids = {n["id"] for n in graph["nodes"]}
    assert "pop_a" in node_ids
    assert "pop_b" in node_ids

    # All nodes must have numeric [x, y] positions.
    for node in graph["nodes"]:
        assert isinstance(node["position"], list)
        assert len(node["position"]) == 2
        assert all(isinstance(v, int | float) for v in node["position"])


def test_generate_cnl_includes_threshold_for_all_nodes() -> None:
    """generate-cnl includes firing-threshold values for all LIF nodes."""
    response = client.post("/api/neurosim/generate-cnl", json=VALID_GRAPH)

    assert response.status_code == 200
    cnl = response.json()["cnl_spec"]
    # NIR-native threshold format: "firing threshold <value>"
    assert "firing threshold 1.0" in cnl
    assert "firing threshold 0.8" in cnl


# ---------------------------------------------------------------------------
# Legacy STP template rejection tests (T0-D regression documenting removal)
# ---------------------------------------------------------------------------

# A minimal excerpt from the dopamine_stp_decision template that covers
# short-term facilitation, short-term depression, and the population-level
# projection sentences.  This MUST-format CNL is intentionally rejected by
# the NIR-native pipeline.
_STP_TEMPLATE_EXCERPT = """\
# Dopamine STP Decision Circuit (excerpt)
The network MUST operate WITH timestep of 1 ms

The network MUST contain an excitatory evidence population of 12 neurons
The network MUST contain an excitatory choice_A population of 12 neurons
The network MUST contain an excitatory choice_B population of 12 neurons

The evidence population MUST project to choice_A population
The evidence population MUST project to choice_B population

The connection from evidence population to choice_A population MUST have WITH synaptic weight of 0.65
The connection from evidence population to choice_B population MUST have WITH synaptic weight of 0.6

The connection from evidence population to choice_A population MUST exhibit short-term facilitation WITH recovery time of 0.05 seconds
The connection from evidence population to choice_B population MUST exhibit short-term depression WITH recovery time of 0.12 seconds
"""


def test_parse_cnl_rejects_stp_must_template() -> None:
    """parse-cnl returns 422 for STP MUST-format templates (T0-D).

    STP short-term plasticity in MUST-format CNL is no longer accepted by
    the NIR-native pipeline.  This test documents that the rejection is
    clean (422 with diagnostics) and not a crash (500).
    """
    response = client.post(
        "/api/neurosim/parse-cnl",
        json={"cnl_spec": _STP_TEMPLATE_EXCERPT},
    )
    assert (
        response.status_code == 422
    ), f"Expected 422 for MUST-format STP CNL, got {response.status_code}: {response.text}"
    detail = response.json()["detail"]
    # Must return structured diagnostics, not a bare error string.
    assert (
        "diagnostics" in detail
    ), f"Expected 'diagnostics' key in 422 response, got: {list(detail.keys())}"
    assert len(detail["diagnostics"]) > 0


def test_nir_native_cnl_round_trip_preserves_node_count() -> None:
    """Round-trip: NIR-native CNL → parse-cnl graph → generate-cnl CNL.

    The round-trip must succeed and the generated CNL must reference the
    same hidden-layer nodes (pop_a, pop_b) so the editor can display a
    meaningful graph.
    """
    # Step 1: CNL → graph via parse-cnl.
    parse_response = client.post(
        "/api/neurosim/parse-cnl",
        json={"cnl_spec": _NIR_NATIVE_CNL},
    )
    assert parse_response.status_code == 200, parse_response.text
    graph = parse_response.json()
    # Expected nodes: in1, pop_a, pop_b, out1.
    assert len(graph["nodes"]) == 4

    # Step 2: graph → CNL via generate-cnl.
    gen_response = client.post("/api/neurosim/generate-cnl", json=graph)
    assert (
        gen_response.status_code == 200
    ), f"generate-cnl returned {gen_response.status_code}: {gen_response.text}"
    gen_cnl = gen_response.json()["cnl_spec"]
    assert "pop_a" in gen_cnl
    assert "pop_b" in gen_cnl
