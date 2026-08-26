"""Public Suite API error envelope tests."""

from fastapi.testclient import TestClient

from suite_api.main import app


def test_unknown_route_has_correlated_structured_error() -> None:
    response = TestClient(app).get(
        "/api/does-not-exist", headers={"X-Request-ID": "missing-route-1"}
    )

    assert response.status_code == 404
    assert response.json() == {
        "detail": {
            "code": "not_found",
            "message": "Not Found",
            "request_id": "missing-route-1",
            "retryable": False,
        }
    }
