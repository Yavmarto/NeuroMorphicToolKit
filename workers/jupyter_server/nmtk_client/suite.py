"""Notebook helper for the suite_api gateway (port 9000).

Provides lightweight wrappers around the suite_api so notebooks can reach
any NMTK module (NeuroStudio, NeuroBench, NeuroSense, etc.) without writing
raw HTTP.

Usage::

    from nmtk_client import suite

    print(suite.health())
    result = suite.post("/api/neurocnl/parse", {"cnl": "..."})

The suite_api URL is read from the ``SUITE_API_URL`` environment variable
(default: ``http://suite_api:9000``).
"""
from __future__ import annotations

from ._base import NmtkServiceClient

_client = NmtkServiceClient(
    env_var="SUITE_API_URL",
    service_name="suite_api",
    default_url="http://suite_api:9000",
)


def health() -> dict:
    """Return the suite_api health response."""
    return _client._get("/api/suite/health")


def get(path: str, *, timeout: float = 30.0) -> dict:
    """Issue a GET request to suite_api and return the parsed JSON response."""
    return _client._get(path, timeout=timeout)


def post(path: str, body: object, *, timeout: float = 60.0) -> dict:
    """Issue a POST request to suite_api and return the parsed JSON response."""
    return _client._post(path, json=body, timeout=timeout)
