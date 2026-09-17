"""Shared UTC timestamp contract for persisted NeuroBench records."""

from datetime import UTC, datetime


def utc_now_iso() -> str:
    """Return an aware ISO-8601 timestamp while preserving the public ``Z`` suffix."""
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")
