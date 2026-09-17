"""Tests for neurocnl.handoff.dreamhand_verification_hook."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock, patch

import pytest

from neurocnl.handoff.dreamhand_verification_hook import (
    DreamHandNotAvailableError,
    run_dreamhand_verification_handoff,
)

# ---------------------------------------------------------------------------
# Helpers — minimal VerificationReport stand-in for assertions
# ---------------------------------------------------------------------------


def _fake_report(passed: bool = True, summary: str = "Smoke check passed") -> MagicMock:
    report = MagicMock()
    report.passed = passed
    report.summary = summary
    return report


# ---------------------------------------------------------------------------
# DreamHandNotAvailableError — neurodreamhand not importable
# ---------------------------------------------------------------------------


def test_raises_when_neurodreamhand_not_installed() -> None:
    """Blocking sys.modules entry for neurodreamhand.toolkit_handoff triggers the error."""
    with (
        patch.dict(
            sys.modules,
            {
                "neurodreamhand": None,
                "neurodreamhand.toolkit_handoff": None,
            },
        ),
        pytest.raises(DreamHandNotAvailableError) as exc_info,
    ):
        run_dreamhand_verification_handoff("/dev/ttyACM0")

    assert "neurodreamhand" in str(exc_info.value).lower()
    assert "pip install" in str(exc_info.value)


def test_dreamhand_not_available_error_is_runtime_error() -> None:
    assert issubclass(DreamHandNotAvailableError, RuntimeError)


# ---------------------------------------------------------------------------
# Successful delegation
# ---------------------------------------------------------------------------


def test_delegates_to_verify_post_flash_runtime() -> None:
    fake_report = _fake_report()
    mock_module = MagicMock()
    mock_module.verify_post_flash_runtime.return_value = fake_report
    mock_module.VerificationOptions = MagicMock

    with patch.dict(
        sys.modules,
        {
            "neurodreamhand": MagicMock(),
            "neurodreamhand.toolkit_handoff": mock_module,
        },
    ):
        result = run_dreamhand_verification_handoff("/dev/ttyACM0")

    mock_module.verify_post_flash_runtime.assert_called_once_with("/dev/ttyACM0", None)
    assert result is fake_report


def test_passes_opts_through_to_verify() -> None:
    fake_report = _fake_report()
    mock_opts = MagicMock()
    mock_module = MagicMock()
    mock_module.verify_post_flash_runtime.return_value = fake_report
    mock_module.VerificationOptions = type(mock_opts)

    with patch.dict(
        sys.modules,
        {
            "neurodreamhand": MagicMock(),
            "neurodreamhand.toolkit_handoff": mock_module,
        },
    ):
        result = run_dreamhand_verification_handoff("/dev/ttyUSB1", opts=mock_opts)

    mock_module.verify_post_flash_runtime.assert_called_once_with(
        "/dev/ttyUSB1", mock_opts
    )
    assert result is fake_report


def test_passes_through_exception_from_verify() -> None:
    """Non-ImportError exceptions from verify_post_flash_runtime propagate unchanged."""
    mock_module = MagicMock()
    mock_module.verify_post_flash_runtime.side_effect = RuntimeError("serial error")
    mock_module.VerificationOptions = MagicMock

    with (
        patch.dict(
            sys.modules,
            {
                "neurodreamhand": MagicMock(),
                "neurodreamhand.toolkit_handoff": mock_module,
            },
        ),
        pytest.raises(RuntimeError, match="serial error"),
    ):
        run_dreamhand_verification_handoff("/dev/ttyACM0")
