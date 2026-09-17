from __future__ import annotations

import importlib
import io
import json
from pathlib import Path
from typing import Any, cast
from unittest.mock import patch

from fastapi.testclient import TestClient

from neurosense.app.main import app

h5py = cast(Any, importlib.import_module("h5py"))

client = TestClient(app)


def test_export_not_found() -> None:
    response = client.post(
        "/api/neurosense/export",
        json={"session_id": "nonexistent", "format": "csv"},
        headers={"X-API-Key": "test-secret"},
    )
    assert response.status_code == 404


def test_export_csv_uses_checked_in_fixture(
    canonical_session_id: str, session_fixture_dir: Path
) -> None:
    with patch("neurosense.app.routers.export._RECORDINGS_DIR", session_fixture_dir):
        response = client.post(
            "/api/neurosense/export",
            json={
                "session_id": canonical_session_id,
                "format": "csv",
                "encoding_config": {"method": "delta", "delta_threshold": 0.2},
            },
            headers={"X-API-Key": "test-secret"},
        )
        assert response.status_code == 200
        assert response.headers["content-type"] == "text/csv; charset=utf-8"
        assert "timestamp,channel,spike_time" in response.text


def test_export_hdf5_preserves_canonical_metadata(
    canonical_session_id: str, session_fixture_dir: Path
) -> None:
    with patch("neurosense.app.routers.export._RECORDINGS_DIR", session_fixture_dir):
        response = client.post(
            "/api/neurosense/export",
            json={"session_id": canonical_session_id, "format": "hdf5"},
            headers={"X-API-Key": "test-secret"},
        )
        assert response.status_code == 200
        assert response.headers["content-type"] == "application/x-hdf5"

        buffer = io.BytesIO(response.content)
        with h5py.File(buffer, "r") as artifact:
            assert artifact.attrs["artifact_schema_version"] == "1.0"
            assert artifact.attrs["signal_type"] == "emg"
            assert artifact.attrs["capture_mode"] == "live"
            assert json.loads(artifact.attrs["channel_labels"]) == ["flexor", "extensor"]
            assert "raw" in artifact
            assert "timestamps" in artifact


def test_export_invalid_format(canonical_session_id: str, session_fixture_dir: Path) -> None:
    with patch("neurosense.app.routers.export._RECORDINGS_DIR", session_fixture_dir):
        response = client.post(
            "/api/neurosense/export",
            json={"session_id": canonical_session_id, "format": "invalid_format"},
            headers={"X-API-Key": "test-secret"},
        )
        assert response.status_code == 422
