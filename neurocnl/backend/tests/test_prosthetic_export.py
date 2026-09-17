"""Tests for POST /api/prosthetic/export/crossbar."""

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

VALID_REQUEST = {
    "learned_weights": [[0.1, 0.5, -0.3], [0.2, -0.1, 0.8]],
    "bit_width": 8,
    "format": "json",
}


def test_crossbar_export_json():
    """Happy path: valid JSON export returns quantized weights."""
    resp = client.post("/api/prosthetic/export/crossbar", json=VALID_REQUEST)
    assert resp.status_code == 200
    data = resp.json()
    assert "quantized_weights" in data
    assert data["bit_width"] == 8
    assert "scale_factor" in data
    assert "zero_point" in data
    assert "sparsity" in data
    assert isinstance(data["quantized_weights"], list)


def test_crossbar_export_empty_weights():
    """Empty learned_weights should return 422."""
    payload = {"learned_weights": [], "bit_width": 8, "format": "json"}
    resp = client.post("/api/prosthetic/export/crossbar", json=payload)
    assert resp.status_code == 422
    assert "empty" in resp.json()["detail"].lower()


def test_crossbar_export_various_bit_widths():
    """Different bit widths should produce valid results."""
    for bw in [2, 4, 8, 16]:
        payload = {**VALID_REQUEST, "bit_width": bw}
        resp = client.post("/api/prosthetic/export/crossbar", json=payload)
        assert resp.status_code == 200
        data = resp.json()
        assert data["bit_width"] == bw
