"""suite_api smoke tests — Phase 1.
Run with: python3 -m pytest tests/integration/test_phase1_suite_api.py -v
Requires suite_api running on port 9000.
"""
import httpx

SUITE_BASE = "http://localhost:9000"


def test_suite_health() -> None:
    r = httpx.get(f"{SUITE_BASE}/api/suite/health", timeout=5)
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_modules_health_endpoint_exists() -> None:
    r = httpx.get(f"{SUITE_BASE}/api/suite/health/modules", timeout=10)
    assert r.status_code == 200
    body = r.json()
    assert "modules" in body
