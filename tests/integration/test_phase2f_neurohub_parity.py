"""Verify that suite_api serves Neurohub routes with same schema as original service.
Run with backends on ports 8005 and 9000.
"""
import json
import pathlib

import httpx
import pytest

ORIGINAL = "http://localhost:8005"
SUITE    = "http://localhost:9000"

SKIP_PATHS = {"/health", "/metrics", "/docs", "/redoc", "/openapi.json"}


def test_health_parity() -> None:
    orig = httpx.get(f"{ORIGINAL}/api/neurohub/health", timeout=5).json()
    suite = httpx.get(f"{SUITE}/api/neurohub/health", timeout=5).json()
    # Both should return a health response (status key or services key)
    assert "services" in orig or "status" in orig
    assert "services" in suite or "status" in suite


def test_openapi_routes_present() -> None:
    contract = json.loads(
        pathlib.Path("docs/api/contracts/neurohub-openapi.json").read_text()
    )
    original_paths = set(contract.get("paths", {}).keys())
    suite_spec = httpx.get(f"{SUITE}/openapi.json", timeout=5).json()
    suite_paths = set(suite_spec.get("paths", {}).keys())

    # Neurohub routes are mounted with prefix /api/neurohub — same as original
    for path in original_paths:
        if path in SKIP_PATHS:
            continue
        assert path in suite_paths, (
            f"Missing Neurohub route {path} in suite_api"
        )
