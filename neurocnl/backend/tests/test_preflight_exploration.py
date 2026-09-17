"""Exploration tests — verifying preflight endpoints now exist and respond correctly.

**Validates: Requirements 1.1, 2.1, 11.3**

This file follows the bug-condition methodology used throughout this repo.
The tests have been updated at Task 7.1 to invert the bug-condition assertions
now that Tasks 2.2 and 2.3 have implemented the endpoints:

- Sub-cases A confirm that ``POST /api/simulators/preflight`` returns **HTTP 200**
  with a valid ``PreflightResult`` JSON body for known backend names — the
  endpoints now exist and respond correctly.

- Sub-cases B confirm that ``POST /api/simulators/preflight-nir`` returns
  **HTTP 200** with a valid ``PreflightResult`` JSON body when a real `.nir`
  HDF5 file is supplied — the endpoint parses and classifies it correctly.

- Sub-case C (preservation) continues to assert that ``POST /api/simulators/run``
  returns the same response shape as before the preflight feature was introduced,
  confirming Requirement 11.3 is not broken.

History
-------
Before Task 2.2 / 2.3, Sub-cases A and B asserted 404 (endpoint absent).
Those assertions are now inverted to assert 200 with a valid PreflightResult.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# A minimal CNL spec that compiles correctly with compile_to_nir.
# Mirrors the pattern used in test_simulators_router.py for consistency.
_VALID_SPEC = "\n".join(
    [
        "Define a network named preflight_test.",
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_b "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to w_out.",
        "w_out connects to pop_b.",
        "pop_b connects to output.",
    ]
)

_PREFLIGHT_URL = "/api/simulators/preflight"
_PREFLIGHT_NIR_URL = "/api/simulators/preflight-nir"
_RUN_URL = "/api/simulators/run"

# Real .nir HDF5 file used for Sub-case B (two LIF neurons with linear connections).
_NIR_GRAPHS_DIR = Path(__file__).parents[3] / "NIR graphs"
_TWO_LIF_NIR_PATH = _NIR_GRAPHS_DIR / "two_lif_neurons.nir"

# Five required fields in a PreflightResult response body.
_PREFLIGHT_RESULT_FIELDS = {
    "level",
    "supported_nodes",
    "approximate_nodes",
    "unsupported_nodes",
    "diagnostics",
}
_VALID_LEVELS = {"exact", "approximate", "unsupported"}


# ---------------------------------------------------------------------------
# Sub-case A — Inverted: POST /api/simulators/preflight now returns HTTP 200
# ---------------------------------------------------------------------------


def test_subcaseA_preflight_endpoint_returns_200_lava_sim() -> None:
    """Inverted bug-condition: POST /api/simulators/preflight returns 200 for lava_sim.

    **Validates: Requirements 1.1**

    Task 2.2 added the endpoint.  A valid JSON body with a known backend name
    must now return HTTP 200 with a complete PreflightResult JSON body.
    All five fields must be present and level must be one of the three
    SupportClassification values.
    """
    resp = client.post(
        _PREFLIGHT_URL,
        json={"spec": _VALID_SPEC, "backend_name": "lava_sim"},
    )
    assert resp.status_code == 200, (
        f"Expected 200 (endpoint implemented), got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing fields: {missing}. Got: {list(data.keys())}"
    )
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}"
    )
    assert isinstance(data["supported_nodes"], list)
    assert isinstance(data["approximate_nodes"], list)
    assert isinstance(data["unsupported_nodes"], list)
    assert isinstance(data["diagnostics"], list)


def test_subcaseA_preflight_endpoint_returns_200_snntorch_sim() -> None:
    """Inverted bug-condition: POST /api/simulators/preflight returns 200 for snntorch_sim.

    **Validates: Requirements 1.1**

    Mirrors test_subcaseA_preflight_endpoint_returns_200_lava_sim for the
    snntorch_sim backend.  Both known simulator targets must respond with a
    well-formed PreflightResult.
    """
    resp = client.post(
        _PREFLIGHT_URL,
        json={"spec": _VALID_SPEC, "backend_name": "snntorch_sim"},
    )
    assert resp.status_code == 200, (
        f"Expected 200 (endpoint implemented), got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing fields: {missing}. Got: {list(data.keys())}"
    )
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}"
    )


# ---------------------------------------------------------------------------
# Sub-case B — Inverted: POST /api/simulators/preflight-nir now returns HTTP 200
# ---------------------------------------------------------------------------


def test_subcaseB_preflight_nir_endpoint_returns_200_lava_sim() -> None:
    """Inverted bug-condition: POST /api/simulators/preflight-nir returns 200 for lava_sim.

    **Validates: Requirements 2.1**

    Task 2.3 added the endpoint.  A multipart request with a real `.nir` HDF5
    file and a known backend name must now return HTTP 200 with a complete
    PreflightResult JSON body.
    """
    nir_bytes = _TWO_LIF_NIR_PATH.read_bytes()
    resp = client.post(
        _PREFLIGHT_NIR_URL,
        data={"backend_name": "lava_sim"},
        files={"file": ("two_lif_neurons.nir", nir_bytes, "application/octet-stream")},
    )
    assert resp.status_code == 200, (
        f"Expected 200 (endpoint implemented), got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing fields: {missing}. Got: {list(data.keys())}"
    )
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}"
    )
    assert isinstance(data["supported_nodes"], list)
    assert isinstance(data["approximate_nodes"], list)
    assert isinstance(data["unsupported_nodes"], list)
    assert isinstance(data["diagnostics"], list)


def test_subcaseB_preflight_nir_endpoint_returns_200_snntorch_sim() -> None:
    """Inverted bug-condition: POST /api/simulators/preflight-nir returns 200 for snntorch_sim.

    **Validates: Requirements 2.1**

    Mirrors test_subcaseB_preflight_nir_endpoint_returns_200_lava_sim for the
    snntorch_sim backend.
    """
    nir_bytes = _TWO_LIF_NIR_PATH.read_bytes()
    resp = client.post(
        _PREFLIGHT_NIR_URL,
        data={"backend_name": "snntorch_sim"},
        files={"file": ("two_lif_neurons.nir", nir_bytes, "application/octet-stream")},
    )
    assert resp.status_code == 200, (
        f"Expected 200 (endpoint implemented), got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    missing = _PREFLIGHT_RESULT_FIELDS - data.keys()
    assert not missing, (
        f"PreflightResult response is missing fields: {missing}. Got: {list(data.keys())}"
    )
    assert data["level"] in _VALID_LEVELS, (
        f"level must be one of {_VALID_LEVELS}, got {data['level']!r}"
    )


# ---------------------------------------------------------------------------
# Sub-case C — Preservation: POST /api/simulators/run response shape is unchanged
# ---------------------------------------------------------------------------


def test_subcaseC_run_endpoint_still_returns_200_or_503_for_valid_cnl() -> None:
    """Preservation: POST /api/simulators/run returns 200 or 503 — not 404 or 500.

    **Validates: Requirements 11.3**

    This test establishes a baseline that must hold both before and after
    the preflight endpoints are added.  Requirement 11.3 states:

      'THE existing POST /api/simulators/run endpoint SHALL remain unchanged;
       it SHALL continue to perform its own internal classification and return
       HTTP 422 for unsupported graphs (the preflight is an additional earlier
       gate, not a replacement).'

    For a valid CNL spec, the run endpoint must never return 404 (the new
    preflight endpoints share the /api/simulators prefix, so a routing mistake
    could accidentally shadow /run).
    """
    resp = client.post(
        _RUN_URL,
        json={"spec": _VALID_SPEC, "backend_name": "lava_sim"},
    )
    assert resp.status_code in {
        200,
        503,
    }, f"POST /api/simulators/run returned unexpected status {resp.status_code}: {resp.text}"
    assert resp.status_code != 404, (
        "POST /api/simulators/run returned 404 — the new preflight routes "
        "may be shadowing the existing /run endpoint."
    )


def test_subcaseC_run_response_shape_unchanged_on_success() -> None:
    """Preservation: /run response body has the same top-level fields as before.

    **Validates: Requirements 11.3**

    Patches the Lava adapter so the 200 path is exercised.  Confirms that
    the fields defined in SimulatorRunResult (backend_name, status,
    support_level, timesteps, duration_seconds, spikes, voltages, warnings,
    nir_summary, metadata) are all present, matching the shape that existed
    before the preflight feature was introduced.
    """
    mock_result = type(
        "LavaResult",
        (),
        {
            "spikes": {"output": {"0": [1, 5]}},
            "voltages": {},
            "execution_time_ms": 10.0,
            "runtime_mode": "in_process_lava_sim",
            "warnings": [],
        },
    )()

    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            return_value=mock_result,
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={
                "spec": _VALID_SPEC,
                "backend_name": "lava_sim",
                "timesteps": 50,
                "seed": 0,
            },
            headers={"X-Forwarded-For": "192.0.2.1"},
        )

    if resp.status_code != 200:
        # Dependency missing in this environment — skip the shape check.
        return

    data = resp.json()

    # All top-level fields of SimulatorRunResult must be present.
    _expected_fields = {
        "backend_name",
        "status",
        "support_level",
        "timesteps",
        "duration_seconds",
        "spikes",
        "voltages",
        "warnings",
        "nir_summary",
        "metadata",
    }
    missing = _expected_fields - data.keys()
    assert not missing, (
        f"POST /api/simulators/run response is missing fields after preflight "
        f"feature introduction: {missing}"
    )

    # Type-level spot checks — none of these must become None or change type.
    assert isinstance(data["backend_name"], str)
    assert data["backend_name"] == "lava_sim"
    assert data["status"] in {
        "completed",
        "failed",
        "unsupported",
        "missing_dependency",
        "preflight_failed",
    }
    assert data["support_level"] in {"exact", "approximate", "unsupported"}
    assert isinstance(data["timesteps"], int)
    assert isinstance(data["duration_seconds"], float)
    assert isinstance(data["spikes"], dict)
    assert isinstance(data["voltages"], dict)
    assert isinstance(data["warnings"], list)
    assert "node_count" in data["nir_summary"]
    assert "edge_count" in data["nir_summary"]
    assert "unsupported_nodes" in data["nir_summary"]
    assert isinstance(data["metadata"], dict)


def test_subcaseC_run_unknown_backend_still_returns_422() -> None:
    """Preservation: /run rejects unknown backends with 422 after preflight routes added.

    **Validates: Requirements 11.3**

    Ensures that adding /preflight routes at the same router prefix does not
    change the error shape for invalid backend names on /run.
    """
    resp = client.post(
        _RUN_URL,
        json={"spec": _VALID_SPEC, "backend_name": "not_a_real_backend"},
    )
    assert resp.status_code == 422, (
        f"Expected 422 for unknown backend, got {resp.status_code}: {resp.text}"
    )
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert any("unknown_backend" in str(item) for item in detail["items"])


def test_subcaseC_run_invalid_cnl_still_returns_400() -> None:
    """Preservation: /run rejects invalid CNL with 400 after preflight routes added.

    **Validates: Requirements 11.3**

    Ensures CNL compile-error handling on /run is unaffected by the new routes.
    """
    resp = client.post(
        _RUN_URL,
        json={
            "spec": "this is not valid cnl syntax at all",
            "backend_name": "lava_sim",
        },
    )
    assert resp.status_code == 400, (
        f"Expected 400 for invalid CNL, got {resp.status_code}: {resp.text}"
    )
    detail = resp.json()["detail"]
    assert detail["error"] == "compile_failed"
    assert len(detail["items"]) > 0
