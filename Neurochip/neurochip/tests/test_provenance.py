"""Tests for the provenance metadata helpers."""

from neurochip.app.utils.provenance import get_service_version, now_utc_iso, provenance_headers


def test_get_service_version_returns_string():
    version = get_service_version()
    assert isinstance(version, str)
    assert len(version) > 0


def test_now_utc_iso_is_valid_iso():
    ts = now_utc_iso()
    assert isinstance(ts, str)
    # Must parse without error and include timezone offset
    from datetime import datetime

    parsed = datetime.fromisoformat(ts)
    assert parsed.tzinfo is not None


def test_provenance_headers_default_status():
    headers = provenance_headers()
    assert set(headers.keys()) == {
        "X-Neurochip-Generated-At",
        "X-Neurochip-Version",
        "X-Neurochip-Validation-Status",
    }
    assert headers["X-Neurochip-Validation-Status"] == "scaffold_export"


def test_provenance_headers_artifact_validated():
    headers = provenance_headers("artifact_validated")
    assert headers["X-Neurochip-Validation-Status"] == "artifact_validated"


def test_provenance_headers_schema_validated():
    headers = provenance_headers("schema_validated")
    assert headers["X-Neurochip-Validation-Status"] == "schema_validated"


def test_provenance_headers_version_matches_service():
    headers = provenance_headers()
    assert headers["X-Neurochip-Version"] == get_service_version()


def test_provenance_headers_generated_at_is_fresh():
    """Two calls must produce different timestamps (or at worst equal — not older)."""
    from datetime import datetime

    h1 = provenance_headers()
    h2 = provenance_headers()
    t1 = datetime.fromisoformat(h1["X-Neurochip-Generated-At"])
    t2 = datetime.fromisoformat(h2["X-Neurochip-Generated-At"])
    assert t2 >= t1
