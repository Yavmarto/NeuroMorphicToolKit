"""Tests for the simulation runner."""

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from neurocnl.simulation.run_simulation import (
    _format_report_table,
    _validate_batch,
    run_pipeline,
)


@pytest.fixture
def mock_pipeline_result() -> MagicMock:
    result = MagicMock()
    result.validation = {
        "layer1": {
            "raw": {
                "overall": True,
                "passed": ["check1", "check2"],
                "failed": [],
            }
        },
        "layer2": {
            "raw": {
                "overall": True,
                "checks_passed": ["checkA"],
                "checks_failed": [],
            }
        },
    }
    result.simulation = {
        "wall_time_seconds": 1.5,
        "motor_output": [[0.5], [0.6]],
    }
    result.assertions = {"passed": 2, "failed": 0}
    result.overall_pass = True
    result.errors = []
    result.parsed = [MagicMock()] * 5
    return result


def test_run_pipeline_success(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    with patch(
        "neurocnl.simulation.run_simulation.core_run_pipeline",
        return_value=mock_pipeline_result,
    ):
        report = run_pipeline(str(spec_file))

    assert report["overall_pass"] is True
    assert report["mujoco_steps"] >= 0
    assert "error" not in report


def test_run_pipeline_with_errors(
    tmp_path: Path, mock_pipeline_result: MagicMock
) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")
    mock_pipeline_result.overall_pass = False
    mock_pipeline_result.errors = ["Some error"]

    with patch(
        "neurocnl.simulation.run_simulation.core_run_pipeline",
        return_value=mock_pipeline_result,
    ):
        report = run_pipeline(str(spec_file))

    assert report["overall_pass"] is False
    assert report["error"] == "Some error"


def test_run_pipeline_mujoco_fallback(
    tmp_path: Path, mock_pipeline_result: MagicMock
) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    # Mock mujoco import to fail
    with (
        patch.dict("sys.modules", {"mujoco": None}),
        patch(
            "neurocnl.simulation.run_simulation.core_run_pipeline",
            return_value=mock_pipeline_result,
        ),
    ):
        report = run_pipeline(str(spec_file))

    assert "mujoco_note" in report
    assert "MuJoCo integration" in report["mujoco_note"]


def test_format_report_table() -> None:
    report = {
        "spec_file": "test.cnl",
        "backend": "nengo",
        "layer1_validation": {
            "overall": False,
            "passed": ["p1"],
            "failed": [{"name": "f1", "reason": "r1"}],
        },
        "layer2_validation": {
            "overall": True,
            "checks_passed": ["cp1"],
            "checks_failed": [],
        },
        "simulation_duration": 1.234,
        "assertions_passed": 5,
        "assertions_failed": 1,
        "overall_pass": False,
        "error": "Final error",
    }
    table = _format_report_table(report)
    assert "test.cnl" in table
    assert "p1" in table
    assert "f1: r1" in table
    assert "cp1" in table
    assert "1.234s" in table
    assert "5 passed, 1 failed" in table
    assert "OVERALL FAIL" in table
    assert "Final error" in table


def test_format_report_table_minimal() -> None:
    report = {"overall_pass": True}
    table = _format_report_table(report)
    assert "OVERALL PASS" in table


def test_validate_batch(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    f1 = tmp_path / "f1.cnl"
    f1.write_text("s1")
    f2 = tmp_path / "f2.cnl"
    f2.write_text("s2")

    with patch(
        "neurocnl.simulation.run_simulation.core_run_pipeline",
        return_value=mock_pipeline_result,
    ):
        exit_code = _validate_batch([str(f1), str(f2)])

    assert exit_code == 0


def test_validate_batch_fail(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    f1 = tmp_path / "f1.cnl"
    f1.write_text("s1")
    mock_pipeline_result.overall_pass = False
    mock_pipeline_result.errors = ["Err"]

    with patch(
        "neurocnl.simulation.run_simulation.core_run_pipeline",
        return_value=mock_pipeline_result,
    ):
        exit_code = _validate_batch([str(f1)])

    assert exit_code == 1


def test_main_simulation_success(
    tmp_path: Path, mock_pipeline_result: MagicMock
) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    # We need to mock sys.argv and main's calls
    with (
        patch("sys.argv", ["neurocnl", str(spec_file), "--format", "table"]),
        patch(
            "neurocnl.simulation.run_simulation.run_pipeline",
            return_value={
                "overall_pass": True,
                "spec_file": str(spec_file),
                "backend": "nengo",
                "simulation_report": "simulation_report.json",
            },
        ),
        patch("sys.exit") as mock_exit,
    ):
        from neurocnl.simulation.run_simulation import main

        main()
        mock_exit.assert_called_with(0)


def test_main_validate_only(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    with (
        patch("sys.argv", ["neurocnl", "--validate-only", str(spec_file)]),
        patch(
            "neurocnl.simulation.run_simulation.core_run_pipeline",
            return_value=mock_pipeline_result,
        ),
        patch("sys.exit") as mock_exit,
    ):
        from neurocnl.simulation.run_simulation import main

        main()
        mock_exit.assert_called_with(0)


def test_main_simulation_fail(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    with (
        patch("sys.argv", ["neurocnl", str(spec_file), "--quiet"]),
        patch(
            "neurocnl.simulation.run_simulation.run_pipeline",
            return_value={
                "overall_pass": False,
                "spec_file": str(spec_file),
                "backend": "nengo",
            },
        ),
        patch("sys.exit") as mock_exit,
    ):
        from neurocnl.simulation.run_simulation import main

        main()
        mock_exit.assert_called_with(1)


def test_main_verbose(tmp_path: Path, mock_pipeline_result: MagicMock) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text("Test spec")

    with (
        patch(
            "sys.argv", ["neurocnl", str(spec_file), "--verbose", "--format", "json"]
        ),
        patch(
            "neurocnl.simulation.run_simulation.run_pipeline",
            return_value={
                "overall_pass": True,
                "spec_file": str(spec_file),
                "backend": "nengo",
            },
        ),
        patch("sys.exit") as mock_exit,
    ):
        from neurocnl.simulation.run_simulation import main

        main()
        mock_exit.assert_called_with(0)


def test_main_multiple_files_warning(
    tmp_path: Path, mock_pipeline_result: MagicMock
) -> None:
    f1 = tmp_path / "f1.cnl"
    f1.write_text("s1")
    f2 = tmp_path / "f2.cnl"
    f2.write_text("s2")

    with (
        patch("sys.argv", ["neurocnl", str(f1), str(f2)]),
        patch(
            "neurocnl.simulation.run_simulation.run_pipeline",
            return_value={
                "overall_pass": True,
                "spec_file": str(f1),
                "backend": "nengo",
            },
        ),
        patch("sys.exit") as mock_exit,
    ):
        from neurocnl.simulation.run_simulation import main

        main()
        mock_exit.assert_called_with(0)
