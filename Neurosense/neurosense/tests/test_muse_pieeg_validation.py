from __future__ import annotations

from pathlib import Path

import pytest

from neurosense.tests.validate_muse_hardware import run_validation as run_muse_validation
from neurosense.tests.validate_pieeg_hardware import run_validation as run_pieeg_validation


@pytest.mark.anyio
async def test_mock_muse_validation_flow(tmp_path: Path) -> None:
    report = await run_muse_validation(
        mock=True,
        recordings_dir=tmp_path / "recordings",
    )

    assert report.passed is True
    assert report.artifact_path is not None
    assert report.muse_model == "muse2"


@pytest.mark.anyio
async def test_mock_pieeg_validation_flow(tmp_path: Path) -> None:
    report = await run_pieeg_validation(
        mock=True,
        recordings_dir=tmp_path / "recordings",
    )

    assert report.passed is True
    assert report.artifact_path is not None
