import base64
from pathlib import Path
from unittest.mock import MagicMock, patch

import httpx
import pytest

from app.config import settings
from app.runners.snn_mlir_runner import SnnMlirBenchmarkRunner

# A trivial "binary" — /bin/true's behavior is what matters, not real ELF
# content, since subprocess.run just needs an executable that exits 0.
_FAKE_BINARY = b"#!/bin/sh\nexit 0\n"


@pytest.fixture
def runner() -> SnnMlirBenchmarkRunner:
    return SnnMlirBenchmarkRunner()


@pytest.fixture
def nir_path(tmp_path: Path) -> str:
    path = tmp_path / "network.nir"
    path.write_bytes(b"fake-nir-graph-bytes")
    return str(path)


@patch("httpx.Client.post")
def test_run_benchmark_success(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "mlir_text": "module {}",
        "lowered_mlir_text": "module {}",
        "main_c": "int main(void) { return 0; }",
        "snn_data_h": "#define X 1",
        "binary_b64": base64.b64encode(_FAKE_BINARY).decode("ascii"),
    }
    mock_post.return_value = mock_response

    result = runner.run_benchmark("bench1", nir_path)

    assert result.target_id == "snn-mlir"
    assert result.metrics["accuracy"] is None
    assert result.metrics["latency_ms"] is not None
    assert "spike_fidelity" not in result.metrics
    assert result.quantization_bits is None

    args, kwargs = mock_post.call_args
    assert args[0] == f"{settings.snn_mlir_compiler_url}/compile"
    assert kwargs["json"]["compile_binary"] is True


@patch("httpx.Client.post")
def test_run_benchmark_parses_spike_count_from_binary_stdout(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    binary_with_spike_output = b"#!/bin/sh\necho 'SNN_OUTPUT_SPIKES=42'\nexit 0\n"
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "mlir_text": "module {}",
        "lowered_mlir_text": "module {}",
        "main_c": "",
        "snn_data_h": "",
        "binary_b64": base64.b64encode(binary_with_spike_output).decode("ascii"),
    }
    mock_post.return_value = mock_response

    result = runner.run_benchmark("bench1", nir_path)

    assert result.metrics["spike_fidelity"] == 42.0


@patch("httpx.Client.post")
def test_run_benchmark_quantized_sets_quantization_bits(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "mlir_text": "module {}",
        "lowered_mlir_text": "module {}",
        "main_c": "",
        "snn_data_h": "",
        "binary_b64": base64.b64encode(_FAKE_BINARY).decode("ascii"),
    }
    mock_post.return_value = mock_response

    result = runner.run_benchmark("bench1", nir_path, params={"quantize": True})

    assert result.quantization_bits == 8
    assert mock_post.call_args.kwargs["json"]["quantize"] is True


@patch("httpx.Client.post")
def test_compile_rejection_raises_value_error(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 400
    mock_response.text = "unsupported topology"
    mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        "Error", request=MagicMock(), response=mock_response
    )
    mock_post.return_value = mock_response

    with pytest.raises(ValueError, match="unsupported topology"):
        runner.run_benchmark("bench1", nir_path)


@patch("httpx.Client.post")
def test_worker_timeout_raises_runtime_error(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    mock_post.side_effect = httpx.TimeoutException("Timed out")

    with pytest.raises(RuntimeError, match="timed out"):
        runner.run_benchmark("bench1", nir_path)


@patch("httpx.Client.post")
def test_missing_binary_raises_runtime_error(
    mock_post: MagicMock, runner: SnnMlirBenchmarkRunner, nir_path: str
) -> None:
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "mlir_text": "module {}",
        "lowered_mlir_text": "module {}",
        "main_c": "",
        "snn_data_h": "",
        "binary_b64": None,
    }
    mock_post.return_value = mock_response

    with pytest.raises(RuntimeError, match="did not return a compiled binary"):
        runner.run_benchmark("bench1", nir_path)
