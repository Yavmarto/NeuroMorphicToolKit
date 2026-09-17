"""Tests for the /api/validate endpoint — NIR-native CNL contract."""

from pathlib import Path

from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.neurocnl_bridge import validate_spec as bridge_validate_spec

client = TestClient(app)

# The canonical reflex-arc template is already in NIR-native format.
REFLEX_ARC_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()


def test_validate_valid_spec():
    """A well-formed NIR-native spec passes both layer 1 and layer 2."""
    resp = client.post("/api/validate", json={"spec": REFLEX_ARC_SPEC})
    assert resp.status_code == 200
    data = resp.json()
    assert data["overall"] is True
    assert data["layer1"]["overall"] is True
    assert data["layer2"]["overall"] is True
    assert len(data["layer2"]["neurons_found"]) > 0
    assert data["backend_support"]["backend"] == "nir"
    assert data["backend_support"]["verdict"] in {"faithful", "approximate"}


def test_validate_with_params():
    """User params are accepted; validation still passes for a valid spec."""
    resp = client.post(
        "/api/validate",
        json={
            "spec": REFLEX_ARC_SPEC,
            "params": {"threshold": 1.0, "tau": 0.02},
        },
    )
    assert resp.status_code == 200
    assert resp.json()["overall"] is True


def test_validate_empty_spec():
    """An empty spec is accepted (no invariants to fail) and returns a bool result."""
    resp = client.post("/api/validate", json={"spec": ""})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["overall"], bool)


def test_validate_returns_layer2_failure_for_orphan_neuron():
    """A neuron declared but not connected triggers an orphan_population L2 failure."""
    # sensor is declared but never appears in any 'connects to' statement.
    spec = "\n".join(
        [
            "Define an input port named input with shape (1,).",
            "Define a LIF neuron named sensor "
            "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
            # sensor intentionally has no edges
            "Define a LIF neuron named actuator "
            "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 0.8.",
            "Define an output port named output with shape (1,).",
            "input connects to actuator.",
            "actuator connects to output.",
        ]
    )
    resp = client.post("/api/validate", json={"spec": spec})
    assert resp.status_code == 200
    data = resp.json()
    assert data["overall"] is False
    failure_codes = [f.get("check") or f.get("code") for f in data["layer2"]["checks_failed"]]
    assert "orphan_population" in failure_codes


def test_validate_parse_failures_stay_actionable():
    """An invalid spec returns L2 failures with code, message, hint, examples."""
    resp = client.post("/api/validate", json={"spec": "This is not valid CNL"})
    assert resp.status_code == 200
    data = resp.json()
    failure = data["layer2"]["checks_failed"][0]
    assert failure["code"] is not None
    assert failure["message"] is not None
    assert failure["hint"]
    assert failure["examples"]
    assert failure["line"] == 1


def test_bridge_validate_spec_includes_advisory_planner() -> None:
    """The bridge returns a non-None planner with backend='nir' for NIR-native specs."""
    result = bridge_validate_spec(REFLEX_ARC_SPEC, {}, backend="nir")
    assert "planner" in result
    assert result["planner"] is not None
    assert result["planner"].backend == "nir"
    assert result["planner"].verdict in {"faithful", "approximate"}


def test_validate_returns_backend_support_fields() -> None:
    """Validate with explicit backend returns backend_support with all required fields."""
    resp = client.post("/api/validate", json={"spec": REFLEX_ARC_SPEC, "backend": "loihi"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["overall"] is True
    bs = data["backend_support"]
    assert bs["backend"] == "loihi"
    assert bs["verdict"] in {"faithful", "approximate"}
    assert isinstance(bs["supported_concepts"], list)
    assert isinstance(bs["approximated_concepts"], list)
    assert isinstance(bs["unsupported_concepts"], list)
    assert isinstance(bs["warnings"], list)


def test_validate_backend_support_always_populated_on_parse_failure():
    """An unparseable spec still returns backend_support with verdict='unsupported'."""
    resp = client.post("/api/validate", json={"spec": "This is not valid CNL"})
    assert resp.status_code == 200
    data = resp.json()
    bs = data["backend_support"]
    assert bs is not None, "backend_support must never be null"
    assert bs["verdict"] == "unsupported"
    assert isinstance(bs["warnings"], list)
    assert len(bs["warnings"]) > 0


# ── Shape-only LIF declarations must validate, not 500 ─────────────────────────

SHAPE_ONLY_LIF_SPEC = "\n".join(
    [
        "Define a network named graph.",
        "Define an input port named nir.Input_1 with shape (32,).",
        "Define a LIF neuron named nir.LIF_1 with time constant shape (32,), "
        "resistance shape (32,), leak voltage shape (32,), and firing threshold shape (32,).",
        "Define a linear transformation named nir.Linear_1 with weight matrix shape (4, 32).",
        "Define a LIF neuron named nir.LIF_2 with time constant shape (4,), "
        "resistance shape (4,), leak voltage shape (4,), and firing threshold shape (4,).",
        "Define an output port named nir.Output_1 with shape (4,).",
        "nir.Input_1 connects to nir.LIF_1.",
        "nir.LIF_1 connects to nir.Linear_1.",
        "nir.Linear_1 connects to nir.LIF_2.",
        "nir.LIF_2 connects to nir.Output_1.",
    ]
)


def test_validate_shape_only_lif_params_does_not_500():
    """Regression: a shape-only LIF declaration used to answer a bare 500.

    'with time constant shape (32,)' parses to an ArraySpec carrying no values.
    That object was forwarded to the scalar invariants, float() raised TypeError,
    and the resulting failure dict had no 'name' — which InvariantResult requires,
    so the response died as an unhandled pydantic error. Every canvas-authored
    network declares its LIF params this way, so Validate was unusable for them.
    """
    resp = client.post("/api/validate", json={"spec": SHAPE_ONLY_LIF_SPEC})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["layer1"]["overall"] is True
    assert data["layer1"]["failed"] == []
    # Shape-only params carry no value, so they are skipped rather than checked —
    # but the invariants that CAN run must still be reported as passing.
    assert len(data["layer1"]["passed"]) > 0


def test_validate_layer1_failure_carries_a_name():
    """Every layer-1 invariant failure must expose a 'name', or the response 500s.

    Guards the second half of the same bug: it is not enough for ArraySpec to be
    skipped, because any other layer-1 failure built the same name-less dict.
    """
    from backend.app.schemas.validate import InvariantResult
    from backend.app.utils.cnl_errors import normalize_cnl_error_item

    raw_failure = {
        "invariant": "nir_lif_time_constant_positive",
        "node": "nir.LIF_1",
        "primitive": "LIF",
        "reason": "nir_lif_time_constant_positive violated for node 'nir.LIF_1'",
    }
    item = {**normalize_cnl_error_item(raw_failure, source="layer1"), "result": False}
    result = InvariantResult(**item)
    assert result.name == "nir.LIF_1/nir_lif_time_constant_positive"
    # The code must identify the invariant, not collapse to a generic label.
    assert item["code"] == "nir_lif_time_constant_positive"
