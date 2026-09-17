import os
from typing import Any
from unittest.mock import MagicMock, patch

import httpx
import pytest

from app.config import settings
from app.exceptions import BenchmarkExecutionError, BenchmarkTimeoutError, SpikeFidelityError
from app.services.benchmark_runner import BenchmarkRunner


@pytest.fixture
def runner() -> BenchmarkRunner:
    return BenchmarkRunner()


@pytest.fixture
def spec_path() -> str:
    return os.path.join(os.path.dirname(__file__), "test_network.cnl")


@pytest.fixture
def params() -> dict[str, str]:
    return {"param1": "value1"}


@patch("httpx.Client.post")
def test_run_neurosim_success(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    # Setup mock response with nested results
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "results": {
            "assertions_passed": 10,
            "assertions_failed": 0,
            "latency_ms": 5.5,
            "energy_uj": 1.2,
            "accuracy": 0.99,
            "mujoco_steps": 100,
        }
    }
    mock_post.return_value = mock_response

    # Execute
    report = runner._run_neurosim(spec_path, params)

    # Verify
    assert report["latency_ms"] == 5.5
    assert report["mujoco_steps"] == 100
    mock_post.assert_called_once()
    args, kwargs = mock_post.call_args
    assert args[0] == settings.neurosim_api_url
    assert kwargs["json"]["params"] == params


@patch("httpx.Client.post")
def test_run_neurochip_success(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    # Setup mock response with flat results
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "assertions_passed": 5,
        "assertions_failed": 1,
        "latency_ms": 1.5,
        "energy_uj": 0.2,
        "accuracy": 0.85,
    }
    mock_post.return_value = mock_response

    # Execute
    report = runner._run_neurochip(spec_path, params)

    # Verify
    assert report["accuracy"] == 0.85
    mock_post.assert_called_once()
    args, kwargs = mock_post.call_args
    assert args[0] == settings.neurochip_api_url


@patch("httpx.Client.post")
def test_run_hardware_target_uses_metrics_container(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "results": {"assertions_passed": "2", "latency_ms": 8, "accuracy": 0.5},
        "metrics": {"assertions_passed": 999},
    }
    mock_post.return_value = mock_response

    report = runner._run_neurosim(spec_path, params)

    assert report == {
        "assertions_passed": 2.0,
        "assertions_failed": 0.0,
        "latency_ms": 8.0,
        "energy_uj": 0.0,
        "accuracy": 0.5,
        "mujoco_steps": 0.0,
    }


@patch("httpx.Client.post")
def test_run_hardware_target_wraps_invalid_metric_payload(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"metrics": {"latency_ms": True}}
    mock_post.return_value = mock_response

    with pytest.raises(BenchmarkExecutionError, match="boolean value"):
        runner._run_neurosim(spec_path, params)


@patch("app.services.benchmark_runner.result_store.save_result")
@patch("app.services.benchmark_runner.run_pipeline")
@patch("app.services.benchmark_runner.benchmark_loader.get")
def test_run_benchmark_uses_canonical_metric_helper_for_simulation_payload(
    mock_get_def: MagicMock,
    mock_run_pipeline: MagicMock,
    mock_save_result: MagicMock,
    runner: BenchmarkRunner,
    spec_path: str,
) -> None:
    mock_def = MagicMock()
    mock_def.default_params = {}
    mock_def.assertions = []
    mock_def.scoring.primary_metric = "accuracy"
    mock_def.input_spec.type = "synthetic"
    mock_get_def.return_value = mock_def
    mock_run_pipeline.return_value = {
        "results": {
            "assertions_passed": "2",
            "latency_ms": "5.5",
            "energy_uj": 8,
        },
        "metrics": {
            "assertions_passed": 99,
            "accuracy": 0.9,
        },
        "overall_pass": True,
        "simulation_duration": 1.25,
        "spike_fidelity": 0.98,
    }

    result = runner.run_benchmark("bench1", spec_path, target="simulation")

    assert result.metrics == {
        "assertions_passed": 2.0,
        "assertions_failed": 0.0,
        "latency_ms": 5.5,
        "energy_uj": 8.0,
        "accuracy": 1.0,
        "mujoco_steps": 0.0,
        "simulation_duration": 1.25,
        "spike_fidelity": 0.98,
    }
    mock_save_result.assert_called_once()


@patch("httpx.Client.post")
def test_hardware_timeout(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    # Setup mock to raise timeout
    mock_post.side_effect = httpx.TimeoutException("Timed out")

    # Execute and verify
    with pytest.raises(BenchmarkTimeoutError):
        runner._run_neurosim(spec_path, params)


@patch("httpx.Client.post")
def test_hardware_error_status(
    mock_post: MagicMock, runner: BenchmarkRunner, spec_path: str, params: dict[str, str]
) -> None:
    # Setup mock response with error status
    mock_response = MagicMock()
    mock_response.status_code = 500
    mock_response.text = "Internal Server Error"
    mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        "Error", request=MagicMock(), response=mock_response
    )
    mock_post.return_value = mock_response

    # Execute and verify
    with pytest.raises(BenchmarkExecutionError) as excinfo:
        runner._run_neurosim(spec_path, params)
    assert "500" in str(excinfo.value)


@patch("app.services.benchmark_runner.run_pipeline")
@patch.object(BenchmarkRunner, "_run_neurosim")
@patch.object(BenchmarkRunner, "_run_neurochip")
@patch("app.services.benchmark_runner.benchmark_loader.get")
def test_run_benchmark_routing(
    mock_get_def: MagicMock,
    mock_run_neurochip: MagicMock,
    mock_run_neurosim: MagicMock,
    mock_run_pipeline: MagicMock,
    runner: BenchmarkRunner,
    spec_path: str,
) -> None:
    # Mock benchmark definition
    mock_def = MagicMock()
    mock_def.default_params = {}
    mock_def.assertions = []
    mock_def.scoring.primary_metric = "accuracy"
    mock_get_def.return_value = mock_def

    # Mock results
    mock_report = {"assertions_passed": 1, "assertions_failed": 0, "accuracy": 1.0}
    mock_run_pipeline.return_value = mock_report
    mock_run_neurosim.return_value = mock_report
    mock_run_neurochip.return_value = mock_report

    # Test simulation routing
    runner.run_benchmark("bench1", spec_path, target="simulation")
    mock_run_pipeline.assert_called_once()
    mock_run_neurosim.assert_not_called()
    mock_run_neurochip.assert_not_called()

    mock_run_pipeline.reset_mock()

    # Test neurosim routing
    runner.run_benchmark("bench1", spec_path, target="neurosim")
    mock_run_neurosim.assert_called_once()
    mock_run_pipeline.assert_not_called()
    mock_run_neurochip.assert_not_called()

    mock_run_neurosim.reset_mock()

    # Test neurochip routing
    runner.run_benchmark("bench1", spec_path, target="neurochip")
    mock_run_neurochip.assert_called_once()

    # Test akida routing
    runner.run_benchmark("bench1", spec_path, target="akida")
    assert mock_run_neurochip.call_count == 2
    mock_run_pipeline.assert_not_called()
    mock_run_neurosim.assert_not_called()


def test_invalid_target(runner: BenchmarkRunner, spec_path: str) -> None:
    with patch("app.services.benchmark_runner.benchmark_loader.get") as mock_get_def:
        mock_def = MagicMock()
        mock_def.default_params = {}
        mock_def.assertions = []
        mock_get_def.return_value = mock_def

        with pytest.raises(ValueError, match="Invalid target"):
            runner.run_benchmark("bench1", spec_path, target="invalid")


@pytest.mark.parametrize(
    ("report", "expected_message"),
    [
        (
            {"assertions_passed": 1, "assertions_failed": 0, "baseline_firing_rate": 0.0},
            "completely silent",
        ),
        (
            {"assertions_passed": 1, "assertions_failed": 0, "baseline_firing_rate": 1000.0},
            "fully saturated",
        ),
        (
            {"assertions_passed": 1, "assertions_failed": 0, "baseline_firing_rate": float("inf")},
            "fully saturated",
        ),
        (
            {
                "assertions_passed": 1,
                "assertions_failed": 0,
                "baseline_firing_rate": 100.0,
                "spike_fidelity": float("nan"),
            },
            "invalid",
        ),
        (
            {
                "assertions_passed": 1,
                "assertions_failed": 0,
                "baseline_firing_rate": 100.0,
                "spike_fidelity": float("inf"),
            },
            "invalid",
        ),
    ],
)
def test_run_benchmark_spike_fidelity_validation(
    runner: BenchmarkRunner,
    spec_path: str,
    report: dict[str, Any],
    expected_message: str,
) -> None:
    with (
        patch("app.services.benchmark_runner.benchmark_loader.get") as mock_get_def,
        patch("app.services.benchmark_runner.run_pipeline", return_value=report),
    ):
        mock_def = MagicMock()
        mock_def.default_params = {}
        mock_def.assertions = []
        mock_def.scoring.primary_metric = "accuracy"
        mock_get_def.return_value = mock_def

        with pytest.raises(SpikeFidelityError, match=expected_message):
            runner.run_benchmark("bench1", spec_path, target="simulation")


@patch("app.services.benchmark_runner.summarize_neurosense_artifact")
@patch("app.services.benchmark_runner.benchmark_loader.get")
def test_run_benchmark_recording_input(
    mock_get_def: MagicMock,
    mock_summarize_artifact: MagicMock,
    runner: BenchmarkRunner,
) -> None:
    mock_def = MagicMock()
    mock_def.default_params = {}
    mock_def.assertions = []
    mock_def.input_spec.type = "recording"
    mock_def.input_spec.data_path = None
    mock_get_def.return_value = mock_def
    mock_summarize_artifact.return_value = {
        "artifact_path": "/tmp/sample.hdf5",
        "session_id": "session_123",
        "artifact_schema_version": "1.0",
        "device_type": "cyton",
        "signal_type": "emg",
        "capture_mode": "live",
        "support_level": "experimental",
        "channels": 2,
        "sampling_rate_hz": 250.0,
        "duration_seconds": 1.5,
        "sample_count": 375,
        "filtered_available": True,
        "timestamp_count": 375,
        "spike_batch_count": 2,
        "spike_event_count": 17,
    }

    result = runner.run_benchmark(
        "neurosense_replay_contract",
        network_path="unused.cnl",
        params={"artifact_path": "/tmp/sample.hdf5"},
    )

    mock_summarize_artifact.assert_called_once_with("/tmp/sample.hdf5")
    assert result.target_id == "neurosense_recording"
    assert result.metrics["spike_fidelity"] == 1.0
    assert result.metrics["input_spike_events"] == 17.0
    assert result.spike_data is not None
    assert result.spike_data["session_id"] == "session_123"
