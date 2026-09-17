from fastapi.testclient import TestClient

from backend.app.main import app


def test_health_check():
    client = TestClient(app)
    response = client.get("/health")

    # Depending on environment, it could be 200 or 503
    # In this environment, we expect most dependencies to be present
    assert response.status_code in [200, 503]

    data = response.json()
    assert "status" in data
    assert "neurocnl_version" in data
    assert "timestamp" in data

    if response.status_code == 200:
        assert data["status"] == "ok"
    else:
        assert data["status"] == "degraded"


def test_health_check_keys():
    client = TestClient(app)
    response = client.get("/health")
    data = response.json()

    # Check for expected keys based on current implementation
    expected_keys = ["status", "neurocnl_version", "timestamp", "modules"]
    for key in expected_keys:
        assert key in data

    # Check for module readiness reports
    modules = data["modules"]
    for mod in [
        "nengo",
        "nengo_loihi",
        "mujoco",
        "neuroml",
        "pyneuroml",
        "neurodreamhand",
    ]:
        assert mod in modules
        assert "available" in modules[mod]


def test_health_check_reports_canvas_status():
    client = TestClient(app)
    response = client.get("/health")
    data = response.json()

    assert "canvas_store" in data
    assert "canvas_components" in data
    assert isinstance(data["canvas_store"], bool)
    assert isinstance(data["canvas_components"], bool)
