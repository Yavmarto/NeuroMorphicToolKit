"""Verify that suite_api serves Neurobench routes with same schema as original service.
Run with backends on ports 8003 and 9000.
"""
import json
import pathlib

import httpx
import pytest

ORIGINAL = "http://localhost:8003"
SUITE    = "http://localhost:9000"

SKIP_PATHS = {"/health", "/metrics", "/docs", "/redoc", "/openapi.json"}


def test_health_parity() -> None:
    orig = httpx.get(f"{ORIGINAL}/health", timeout=5).json()
    suite = httpx.get(f"{SUITE}/api/neurobench/health", timeout=5).json()
    assert orig.get("status") == suite.get("status")


def test_openapi_routes_present() -> None:
    contract = json.loads(
        pathlib.Path("docs/api/contracts/neurobench-openapi.json").read_text()
    )
    original_paths = set(contract.get("paths", {}).keys())
    suite_spec = httpx.get(f"{SUITE}/openapi.json", timeout=5).json()
    suite_paths = set(suite_spec.get("paths", {}).keys())

    # Neurobench routers use explicit prefixes matching the contract directly
    for path in original_paths:
        if path in SKIP_PATHS:
            continue
        assert path in suite_paths, (
            f"Missing Neurobench route {path} in suite_api"
        )
