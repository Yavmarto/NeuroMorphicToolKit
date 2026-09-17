from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from backend.app.services.notebook_paths import resolve_notebook_path


def test_resolve_relative_path_under_notebook_dir(tmp_path: Path) -> None:
    nb = tmp_path / "my-ws" / "notebooks" / "pipeline_snntorch_sim.ipynb"
    nb.parent.mkdir(parents=True)
    nb.write_text("{}", encoding="utf-8")

    with patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path):
        resolved = resolve_notebook_path("my-ws/notebooks/pipeline_snntorch_sim.ipynb")

    assert resolved == nb


def test_resolve_raises_when_missing(tmp_path: Path) -> None:
    with (
        patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path),
        pytest.raises(FileNotFoundError, match="pipeline_snntorch_sim.ipynb"),
    ):
        resolve_notebook_path("missing/notebooks/pipeline_snntorch_sim.ipynb")
