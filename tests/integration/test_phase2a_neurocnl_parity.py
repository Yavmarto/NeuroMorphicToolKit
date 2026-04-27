"""Verify that suite_api serves neurocnl routes with same schema as the original service.
Run with backends on ports 8000 and 9000.
"""
import json
import pathlib

import httpx
import pytest

ORIGINAL = "http://localhost:8000"
SUITE    = "http://localhost:9000"


def test_health_parity() -> None:
    orig = httpx.get(f"{ORIGINAL}/health", timeout=5).json()
    suite = httpx.get(f"{SUITE}/api/neurocnl/health", timeout=5).json()
    assert orig.get("status") == suite.get("status")


def test_openapi_routes_present() -> None:
    contract = json.loads(
        pathlib.Path("docs/api/contracts/neurocnl-openapi.json").read_text()
    )
    original_paths = set(contract.get("paths", {}).keys())
    suite_spec = httpx.get(f"{SUITE}/openapi.json", timeout=5).json()
    suite_paths = set(suite_spec.get("paths", {}).keys())

    # neurocnl backend mounts routers under /api/ prefix; suite_api mounts them
    # under /api/neurocnl/ — so /api/parse becomes /api/neurocnl/parse.
    # Paths like /health and /metrics are non-API admin routes; skip them.
    SKIP_PATHS = {"/health", "/metrics", "/docs", "/redoc", "/openapi.json"}

    for path in original_paths:
        if path in SKIP_PATHS:
            continue
        # Strip leading /api to get the bare path, then prepend /api/neurocnl
        bare = path[len("/api"):] if path.startswith("/api") else path
        expected = f"/api/neurocnl{bare}"
        assert expected in suite_paths, (
            f"Missing route {path} (expected as {expected} in suite_api)"
        )
