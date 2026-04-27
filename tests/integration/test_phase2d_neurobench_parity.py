"""Verify that suite_api serves Neurobench routes with same schema as original service.
Run with backends on ports 8003 and 9000.

Phase 4 note: job-dispatch routes (runner, pynq, spinnaker2) are now served
via catch-all proxy routes to the neurobench-runner-worker. The parity check
accepts a catch-all proxy path as satisfying specific sub-paths.
"""
import json
import pathlib

import httpx
import pytest

ORIGINAL = "http://localhost:8003"
SUITE    = "http://localhost:9000"

SKIP_PATHS = {"/health", "/metrics", "/docs", "/redoc", "/openapi.json"}


def _is_covered_by_proxy(path: str, suite_paths: set[str]) -> bool:
    """Return True if a catch-all proxy route in suite_paths covers this path."""
    for suite_path in suite_paths:
        if not suite_path.endswith("{path}"):
            continue
        prefix = suite_path[: -len("{path}")]
        if path.startswith(prefix):
            return True
    return False


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

    for path in original_paths:
        if path in SKIP_PATHS:
            continue
        # Also accept /api/neurobench/run (root) as covering /api/neurobench/run/* paths
        assert path in suite_paths or _is_covered_by_proxy(path, suite_paths), (
            f"Missing Neurobench route {path} in suite_api "
            "(not in OpenAPI spec and not covered by a proxy catch-all)"
        )
