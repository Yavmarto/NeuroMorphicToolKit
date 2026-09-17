"""Tests for the /api/simulate endpoint."""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

VALID_SPEC = "\n".join(
    [
        "The network MUST contain an excitatory input population of 4 neurons",
        "The network MUST contain an excitatory output population of 2 neurons",
        "The input MUST project to output",
        "The connection from input to output MUST have WITH synaptic weight of 1.0",
    ]
)


def test_simulate_duration_limit() -> None:
    resp = client.post(
        "/api/simulate",
        json={"spec": VALID_SPEC, "duration": 20.0},
    )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert detail["items"][0]["code"] == "duration_too_large"


def test_simulate_returns_explicit_unsupported_error() -> None:
    resp = client.post(
        "/api/simulate",
        json={"spec": VALID_SPEC, "duration": 0.1},
    )
    assert resp.status_code == 410
    detail = resp.json()["detail"]
    assert detail["error"] == "nir_simulation_unsupported"
    assert detail["items"][0]["code"] == "nir_simulation_unsupported"


def test_simulate_openapi_does_not_advertise_job_response() -> None:
    schema = app.openapi()
    post = schema["paths"]["/api/simulate"]["post"]
    responses = post["responses"]

    assert "202" not in responses
    assert "410" in responses
