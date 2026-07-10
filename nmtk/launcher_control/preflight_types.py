"""Shared preflight result type.

Split out from module_environment.py so suite_api_service.py can depend on
PreflightResult without creating a cycle: module_environment.py depends on
suite_api_service.py (for DEFAULT_SUITE_API_PORT), so PreflightResult can't
live in a module that suite_api_service.py would need to import back from.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class PreflightResult:
    """Outcome of a non-network module readiness probe."""

    status: str
    message: str | None = None
    capability_warnings: list[str] = field(default_factory=list)
    environment_fingerprint: str | None = None

    def state_fields(self) -> dict[str, Any]:
        return {
            "preflightStatus": self.status,
            "preflightMessage": self.message,
            "capabilityWarnings": list(self.capability_warnings),
            "environmentFingerprint": self.environment_fingerprint,
        }
