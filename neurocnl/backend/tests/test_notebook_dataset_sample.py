"""GET /api/notebook/artifacts/dataset-sample — one eval sample as an input frame.

The endpoint exists because a fixed-function overlay takes a whole frame, one
word per input neuron, and the app's only other stimulus was a hand-typed list
of spike indices — unusable at 784 inputs, and the reason a deploy could only
ever be run against a single pixel.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest
import torch
from fastapi.testclient import TestClient
from torch.utils.data import TensorDataset

from backend.app.routers import notebook as notebook_router


@pytest.fixture(autouse=True)
def _clear_cache() -> None:
    notebook_router._eval_dataset_cache.clear()


def _write_eval_dataset(
    notebooks_dir: Path,
    *,
    name: str = "eval_testloader_mnist_val.pt",
    samples: int = 3,
    width: int = 8,
) -> Path:
    notebooks_dir.mkdir(parents=True, exist_ok=True)
    data = torch.zeros(samples, width)
    for index in range(samples):
        # Sample i lights up pixel i and pixel i+1, so a frame is checkable by eye.
        data[index, index] = 0.75
        data[index, index + 1] = 1.0
    labels = torch.arange(samples, dtype=torch.long)
    path = notebooks_dir / name
    torch.save(TensorDataset(data, labels), path)
    return path


def test_returns_a_binary_frame_and_its_label(client: TestClient, tmp_path: Path) -> None:
    _write_eval_dataset(tmp_path / "my-ws" / "notebooks")

    with patch.object(notebook_router, "NOTEBOOK_DIR", tmp_path):
        response = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws", "index": 1},
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["sample_index"] == 1
    assert body["sample_count"] == 3
    assert body["input_width"] == 8
    assert body["label"] == 1
    # One word per input neuron, 1 where it spikes — never a list of indices.
    assert body["input_spikes"] == [0, 1, 1, 0, 0, 0, 0, 0]
    assert body["spike_count"] == 2


def test_prefers_the_eval_set_over_a_newer_model_file(client: TestClient, tmp_path: Path) -> None:
    notebooks = tmp_path / "my-ws" / "notebooks"
    _write_eval_dataset(notebooks)
    # `best_model.pt` is a model, not data, and is usually the newer of the two.
    (notebooks / "best_model.pt").write_bytes(b"not a dataset")

    with patch.object(notebook_router, "NOTEBOOK_DIR", tmp_path):
        response = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws"},
        )

    assert response.status_code == 200, response.text
    assert response.json()["filename"] == "eval_testloader_mnist_val.pt"


def test_missing_eval_set_says_which_step_writes_it(client: TestClient, tmp_path: Path) -> None:
    (tmp_path / "my-ws" / "notebooks").mkdir(parents=True)

    with patch.object(notebook_router, "NOTEBOOK_DIR", tmp_path):
        response = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws"},
        )

    assert response.status_code == 404
    assert "Evaluate step" in response.json()["detail"]


def test_index_past_the_end_names_the_range(client: TestClient, tmp_path: Path) -> None:
    _write_eval_dataset(tmp_path / "my-ws" / "notebooks")

    with patch.object(notebook_router, "NOTEBOOK_DIR", tmp_path):
        response = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws", "index": 99},
        )

    assert response.status_code == 404
    assert "numbered 0 to 2" in response.json()["detail"]


def test_stepping_the_index_does_not_re_read_the_file(client: TestClient, tmp_path: Path) -> None:
    """A click on "next sample" must not refetch and re-decode megabytes."""
    notebooks = tmp_path / "my-ws" / "notebooks"
    dataset = _write_eval_dataset(notebooks)

    with patch.object(notebook_router, "NOTEBOOK_DIR", tmp_path):
        first = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws", "index": 0},
        )
        # Deleting the file proves the second request never touched storage.
        dataset.unlink()
        second = client.get(
            "/api/notebook/artifacts/dataset-sample",
            params={"workspace_folder": "my-ws", "index": 2},
        )

    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert second.json()["label"] == 2
