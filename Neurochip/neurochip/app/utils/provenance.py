"""Provenance metadata helpers for NeuroChip API responses.

Every artifact or analysis response should carry three pieces of provenance:

- ``X-Neurochip-Generated-At``   — UTC ISO-8601 timestamp of the response.
- ``X-Neurochip-Version``        — Installed package version of ``neurochip``.
- ``X-Neurochip-Validation-Status`` — One of:
    ``artifact_validated``  the artifact passed its own contract validator.
    ``schema_validated``    the request was validated against a payload contract
                            but no artifact-level validation was performed.
    ``scaffold_export``     the artifact is a scaffold/stub; no validation was
                            performed and the output may require further tooling.

Use :func:`provenance_headers` to inject these into ``fastapi.Response`` objects.
"""

from __future__ import annotations

import importlib.metadata
from datetime import datetime

from ..._compat import UTC


def get_service_version() -> str:
    """Return the installed ``neurochip`` package version, or ``"unknown"``."""
    try:
        return importlib.metadata.version("neurochip")
    except importlib.metadata.PackageNotFoundError:
        return "unknown"


def now_utc_iso() -> str:
    """Return the current UTC time as an ISO-8601 string."""
    return datetime.now(UTC).isoformat()


def provenance_headers(validation_status: str = "scaffold_export") -> dict[str, str]:
    """Return standard provenance HTTP headers for binary (ZIP) responses.

    Args:
        validation_status: One of ``"artifact_validated"``, ``"schema_validated"``,
            or ``"scaffold_export"``.  Defaults to ``"scaffold_export"`` so callers
            that omit the argument never accidentally claim stronger guarantees.

    Returns:
        A dict of three header name → value pairs ready to be spread into
        ``fastapi.Response(headers={...})``.
    """
    return {
        "X-Neurochip-Generated-At": now_utc_iso(),
        "X-Neurochip-Version": get_service_version(),
        "X-Neurochip-Validation-Status": validation_status,
    }
