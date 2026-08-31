"""Tests for Neurobench adapter outgoing HTTP calls."""

from __future__ import annotations

import pathlib
import sys
from unittest.mock import MagicMock, patch

import pytest

# Neurobench uses the bare `app` package name, not `neurobench.app`.
# Add its source root so `from app.services... import` works.
_NEUROBENCH_ROOT = pathlib.Path(__file__).resolve().parents[1] / "Neurobench" / "neurobench"
if str(_NEUROBENCH_ROOT) not in sys.path:
    sys.path.insert(0, str(_NEUROBENCH_ROOT))

# Stub app.config BEFORE any neurobench import runs Settings()
_mock_settings = MagicMock()
_mock_settings.neurosim_api_url = "http://neurosim-backend:8001/execute"
_mock_settings.neurochip_api_url = "http://neurochip-backend:8002/execute"
_mock_settings.hardware_timeout_seconds = 30.0

_mock_config_module = MagicMock()
_mock_config_module.settings = _mock_settings

if "app.config" not in sys.modules:
    sys.modules["app.config"] = _mock_config_module

_MINIMAL_CNL = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
)


def _mock_httpx_response(data: dict) -> MagicMock:
    m = MagicMock()
    m.json.return_value = data
    m.raise_for_status = MagicMock()
    return m


def test_hardware_runner_neurosim_target(tmp_path: pathlib.Path) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    from app.services.benchmark_runner import BenchmarkRunner

    runner = BenchmarkRunner()
    mock_resp = _mock_httpx_response(
        {"assertions_passed": 5, "assertions_failed": 0, "latency_ms": 5.5,
         "energy_uj": 1.2, "accuracy": 0.95, "mujoco_steps": 100}
    )

    with patch("httpx.Client.post", return_value=mock_resp):
        result = runner._run_hardware_target(
            url="http://neurosim-backend:8001/execute",
            target_name="neurosim",
            spec_path=str(spec_file),
            params={"seed": 42},
        )

    assert result["assertions_passed"] == 5.0
    assert result["latency_ms"] == 5.5
    assert result["accuracy"] == 0.95
    assert result["mujoco_steps"] == 100.0


def test_hardware_runner_neurochip_target(tmp_path: pathlib.Path) -> None:
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    from app.services.benchmark_runner import BenchmarkRunner

    runner = BenchmarkRunner()
    mock_resp = _mock_httpx_response(
        {"assertions_passed": 4, "assertions_failed": 1, "latency_ms": 2.1,
         "energy_uj": 0.8, "accuracy": 0.87, "mujoco_steps": 0}
    )

    with patch("httpx.Client.post", return_value=mock_resp):
        result = runner._run_hardware_target(
            url="http://neurochip-backend:8002/execute",
            target_name="neurochip",
            spec_path=str(spec_file),
            params={"seed": 7},
        )

    assert result["assertions_passed"] == 4.0
    assert result["assertions_failed"] == 1.0
    assert result["accuracy"] == 0.87


def test_hardware_runner_timeout_raises(tmp_path: pathlib.Path) -> None:
    import httpx
    from app.exceptions import BenchmarkTimeoutError
    from app.services.benchmark_runner import BenchmarkRunner

    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    runner = BenchmarkRunner()

    with patch("httpx.Client.post", side_effect=httpx.TimeoutException("timed out")):
        with pytest.raises(BenchmarkTimeoutError, match="timed out"):
            runner._run_hardware_target(
                url="http://neurosim-backend:8001/execute",
                target_name="neurosim",
                spec_path=str(spec_file),
                params={},
            )
