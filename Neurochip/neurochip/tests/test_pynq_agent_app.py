from fastapi.testclient import TestClient

from neurochip.app.pynq_agent import create_app


def test_pynq_agent_exposes_health_and_pynq_routes() -> None:
    client = TestClient(create_app())

    health = client.get("/health")
    preflight = client.get("/hardware/pynq/preflight")
    unrelated = client.get("/api/neurochip/targets")

    assert health.status_code == 200
    assert health.json()["status"] == "healthy"
    assert preflight.status_code == 200
    assert "preflight_status" in preflight.json()
    assert unrelated.status_code == 404
