from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_read_root() -> None:
    response = client.get("/")
    assert response.status_code == 200
    content_type = response.headers.get("content-type", "")
    if "application/json" in content_type:
        assert "NeuroStudio API" in response.json()["message"]
    else:
        assert "text/html" in content_type
        assert "<html" in response.text.lower()


def test_api_components_accessible_without_authentication() -> None:
    response = client.get("/api/neurosim/components")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_health_endpoint_accessible() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert "canvas_store" in payload
    assert "canvas_components" in payload
