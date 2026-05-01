"""Baseline health check for all six module backends.
These tests must pass before any migration step in Phase 1+.
Run with: python3 -m pytest tests/integration/test_phase0_health_baseline.py -v
"""
import httpx
import pytest

HEALTH_ENDPOINTS = [
    ("neurocnl",   "http://localhost:8000/health"),
    ("neurosim",   "http://localhost:8000/health"),
    ("neurochip",  "http://localhost:8002/health"),
    ("neurobench", "http://localhost:8003/health"),
    ("neurosense", "http://localhost:8004/health"),
    ("neurohub",   "http://localhost:8005/api/neurohub/health"),
]

@pytest.mark.parametrize("name,url", HEALTH_ENDPOINTS)
def test_module_health(name: str, url: str) -> None:
    response = httpx.get(url, timeout=5.0)
    assert response.status_code == 200, (
        f"{name} health check failed: {response.status_code} {response.text}"
    )
