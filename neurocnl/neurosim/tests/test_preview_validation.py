from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_preview_duration_cap_validation() -> None:
    """Test that PreviewRequest enforces 500ms duration cap."""
    # 600ms should fail with 422
    payload = {"graph": {"nodes": [], "edges": []}, "duration_ms": 600.0}
    response = client.post("/api/neurosim/preview", json=payload)
    assert response.status_code == 422
    assert "cannot exceed 500ms" in response.text


def test_preview_duration_boundary() -> None:
    """Test that PreviewRequest accepts 500ms duration."""
    payload = {"graph": {"nodes": [], "edges": []}, "duration_ms": 500.0}
    response = client.post("/api/neurosim/preview", json=payload)
    # Should not be 422. It might be 200 if simulation starts.
    assert response.status_code != 422
