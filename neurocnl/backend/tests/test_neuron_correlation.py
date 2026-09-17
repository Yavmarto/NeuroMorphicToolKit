"""Tests for per-neuron spike-train correlation (CEL-142).

Covers the pure NumPy service directly and the
``GET /training/jobs/{job_id}/neuron_correlation`` route that exposes it.
"""

from __future__ import annotations

import base64
import io
import zipfile
from unittest.mock import AsyncMock, patch

import numpy as np
import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.app.services.neuron_correlation import (
    available_activity_layers,
    compute_neuron_correlation,
    load_layer_spikes,
)

client = TestClient(app)


def _spike_zip_b64(arrays: dict[str, np.ndarray]) -> str:
    """Base64 a captured-activity zip whose entries are ``{name}.npy``."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as archive:
        for name, array in arrays.items():
            npy = io.BytesIO()
            np.save(npy, array)
            archive.writestr(f"{name}.npy", npy.getvalue())
    return base64.b64encode(buf.getvalue()).decode()


def _complete_job_row(job_id: str, metadata: dict) -> dict:
    return {
        "job_id": job_id,
        "status": "complete",
        "result": {"notebook_path": "nb.ipynb", "metadata": metadata},
        "error": None,
        "request_id": None,
    }


# ── pure computation ────────────────────────────────────────────────────────


def test_identical_trains_correlate_positively():
    """Two neurons that always fire together get r = 1."""
    x = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    spikes = np.stack([x, x], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=2)
    assert len(result.links) == 1
    link = result.links[0]
    assert (link.source, link.target) == (0, 1)
    assert link.correlation == pytest.approx(1.0)
    assert link.co_active_samples == 8
    assert result.clusters == [[0, 1]]


def test_anti_correlated_trains_correlate_negatively():
    """A neuron that fires exactly when the other is silent gets r = -1."""
    x = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    spikes = np.stack([x, 1 - x], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=2)
    assert len(result.links) == 1
    assert result.links[0].correlation == pytest.approx(-1.0)
    # Negative correlation must not cluster them together.
    assert result.clusters == []


def test_constant_neuron_is_excluded():
    """A neuron that never fires has undefined correlation and is dropped."""
    x = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    spikes = np.stack([x, x, np.zeros(8)], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=2)
    assert result.analyzed_neuron_count == 3
    assert [(link.source, link.target) for link in result.links] == [(0, 1)]


def test_min_samples_gate_suppresses_links():
    """Fewer timesteps than ``min_samples`` yields no links."""
    x = np.array([1, 0, 1], dtype=float)
    spikes = np.stack([x, x], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=8)
    assert result.time_samples == 3
    assert result.links == []
    assert result.clusters == []


def test_chain_clusters_into_one_group():
    """0~1 and 1~2 at/above threshold collapse into one cluster."""
    a = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    b = a.copy()
    c = a.copy()
    spikes = np.stack([a, b, c], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=2, threshold=0.5)
    assert result.clusters == [[0, 1, 2]]


def test_truncation_keeps_most_active_neurons():
    """Over ``max_neurons``, only the busiest neurons are correlated."""
    t = 8
    counts = [4, 3, 2, 1, 0]
    spikes = np.zeros((t, len(counts)))
    for neuron, count in enumerate(counts):
        spikes[:count, neuron] = 1
    result = compute_neuron_correlation(spikes, min_samples=2, max_neurons=2)
    assert result.neuron_count == 5
    assert result.analyzed_neuron_count == 2
    assert result.truncated is True
    assert result.neuron_indices == [0, 1]
    assert result.spike_counts == [4, 3]


def test_max_links_caps_response_but_not_clusters():
    """The link cap only trims the payload; grouping is over every pair."""
    x = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    spikes = np.stack([x, x, x, x], axis=1)
    result = compute_neuron_correlation(spikes, min_samples=2, max_links=1)
    assert result.total_pairs == 6
    assert len(result.links) == 1
    assert result.clusters == [[0, 1, 2, 3]]


def test_single_neuron_has_no_links():
    result = compute_neuron_correlation(np.array([1, 0, 1, 0]), min_samples=2)
    assert result.analyzed_neuron_count == 1
    assert result.links == []


def test_extra_dims_flatten_into_neuron_axis():
    """Captured conv activity flattens to ``(T, N)`` before correlating."""
    matrix = np.array(
        [
            [1, 1, 0, 0, 1, 1, 0, 0],
            [1, 1, 0, 0, 1, 1, 0, 0],
            [0, 0, 1, 1, 0, 0, 1, 1],
            [0, 0, 1, 1, 0, 0, 1, 1],
            [1, 0, 1, 0, 1, 0, 1, 0],
            [1, 0, 1, 0, 1, 0, 1, 0],
            [0, 1, 0, 1, 0, 1, 0, 1],
            [0, 1, 0, 1, 0, 1, 0, 1],
        ],
        dtype=float,
    )
    spikes = np.stack([matrix, matrix], axis=1)  # (T=8, 2, 8) -> (8, 16)
    result = compute_neuron_correlation(spikes, min_samples=2)
    assert result.neuron_count == 16
    assert result.time_samples == 8
    assert len(result.links) > 0


# ── zip loading ─────────────────────────────────────────────────────────────


def test_load_layer_spikes_exact_and_prefix_match():
    matrix = np.array([[1, 0], [0, 1]], dtype=float)
    b64 = _spike_zip_b64({"hidden_spikes": matrix})
    loaded = load_layer_spikes(b64, "hidden_spikes")
    assert loaded is not None
    assert np.array_equal(loaded, matrix)
    # A prefix also resolves to the stored entry.
    assert load_layer_spikes(b64, "hidden") is not None


def test_load_layer_spikes_missing_layer_returns_none():
    b64 = _spike_zip_b64({"hidden_spikes": np.zeros((2, 2))})
    assert load_layer_spikes(b64, "output") is None


def test_available_activity_layers_lists_stems():
    b64 = _spike_zip_b64(
        {"hidden_spikes": np.zeros((2, 2)), "out_spikes": np.zeros((2, 1))}
    )
    assert available_activity_layers(b64) == ["hidden", "out"]


# ── GET /training/jobs/{job_id}/neuron_correlation ──────────────────────────


def test_endpoint_returns_per_neuron_links():
    job_id = "job-correlation-ok"
    x = np.array([1, 1, 0, 0, 1, 1, 0, 0], dtype=float)
    matrix = np.stack([x, x], axis=1)
    metadata = {
        "activity_npy_b64_by_epoch": {"1": _spike_zip_b64({"hidden_spikes": matrix})}
    }
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/neuron_correlation")
    assert resp.status_code == 200
    body = resp.json()
    assert body["job_id"] == job_id
    assert body["epoch"] == 1
    assert body["neuron_count"] == 2
    assert body["analyzed_neuron_count"] == 2
    assert body["time_samples"] == 8
    assert body["truncated"] is False
    assert body["clusters"] == [[0, 1]]
    assert len(body["links"]) == 1
    assert body["links"][0]["correlation"] == pytest.approx(1.0)
    assert body["neuron_indices"] == [0, 1]


def test_endpoint_unknown_layer_reports_available():
    job_id = "job-correlation-missing-layer"
    metadata = {
        "activity_npy_b64_by_epoch": {
            "1": _spike_zip_b64({"hidden_spikes": np.zeros((8, 2))})
        }
    }
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(
            f"/api/training/jobs/{job_id}/neuron_correlation?layer=output_spikes"
        )
    assert resp.status_code == 404
    assert "Available layers" in resp.json()["detail"]
    assert "hidden" in resp.json()["detail"]


def test_endpoint_unknown_epoch_reports_available():
    job_id = "job-correlation-bad-epoch"
    metadata = {
        "activity_npy_b64_by_epoch": {
            "1": _spike_zip_b64({"hidden_spikes": np.zeros((8, 2))})
        }
    }
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=_complete_job_row(job_id, metadata)),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/neuron_correlation?epoch=3")
    assert resp.status_code == 404
    assert "epoch 3" in resp.json()["detail"]


def test_endpoint_incomplete_job_rejected():
    job_id = "job-correlation-running"
    row = {
        "job_id": job_id,
        "status": "running",
        "result": None,
        "error": None,
        "request_id": None,
    }
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=row),
    ):
        resp = client.get(f"/api/training/jobs/{job_id}/neuron_correlation")
    assert resp.status_code == 400


def test_endpoint_unknown_job_404():
    with patch(
        "backend.app.services.job_store.job_store.get",
        new=AsyncMock(return_value=None),
    ):
        resp = client.get("/api/training/jobs/nope/neuron_correlation")
    assert resp.status_code == 404
