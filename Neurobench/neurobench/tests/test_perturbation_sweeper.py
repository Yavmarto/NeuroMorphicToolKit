from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.schemas.results import BenchmarkResult
from app.services.perturbation_sweeper import perturbation_sweeper


@pytest.fixture
def mock_benchmark_result() -> BenchmarkResult:
    return BenchmarkResult(
        id="res_test",
        benchmark_id="test_bench",
        network_spec_hash="hash_test",
        timestamp="2024-01-01T00:00:00Z",
        params={},
        metrics={"accuracy": 0.85},
        wall_time_seconds=1.0,
        seed=42,
    )


def test_sweep_perturbation_gaussian(mock_benchmark_result: BenchmarkResult) -> None:
    with (
        patch("app.services.benchmark_runner.benchmark_runner.run_benchmark") as mock_run,
        patch("app.services.perturbation_sweeper.Path.exists", return_value=True),
        patch("numpy.load", return_value=np.ones((10, 10))),
        patch("numpy.save"),
        patch("os.fdopen", MagicMock()),
        patch("tempfile.mkstemp", return_value=(1, "temp.npy")),
        patch("app.services.perturbation_sweeper.Path.unlink"),
    ):
        mock_run.return_value = mock_benchmark_result

        result = perturbation_sweeper.sweep_perturbation(
            cnl_spec_path="test.cnl",
            benchmark_id="test_bench",
            dataset_path="test_data.npy",
            noise_type="gaussian",
            noise_levels=[0.0, 0.1],
        )

        assert result.noise_type == "gaussian"
        assert result.noise_levels == [0.0, 0.1]
        assert result.accuracies == [0.85, 0.85]
        assert mock_run.call_count == 2

        # Verify params passed to run_benchmark
        args, kwargs = mock_run.call_args
        assert kwargs["params"]["noise_type"] == "gaussian"
        assert "perturbed_dataset_path" in kwargs["params"]


def test_sweep_perturbation_salt_and_pepper(mock_benchmark_result: BenchmarkResult) -> None:
    with (
        patch("app.services.benchmark_runner.benchmark_runner.run_benchmark") as mock_run,
        patch("app.services.perturbation_sweeper.Path.exists", return_value=True),
        patch("numpy.load", return_value=np.ones((10, 10))),
        patch("numpy.save"),
        patch("os.fdopen", MagicMock()),
        patch("tempfile.mkstemp", return_value=(1, "temp.npy")),
        patch("app.services.perturbation_sweeper.Path.unlink"),
    ):
        mock_run.return_value = mock_benchmark_result

        result = perturbation_sweeper.sweep_perturbation(
            cnl_spec_path="test.cnl",
            benchmark_id="test_bench",
            dataset_path="test_data.npy",
            noise_type="salt_and_pepper",
            noise_levels=[0.05],
        )

        assert result.noise_type == "salt_and_pepper"
        assert result.accuracies == [0.85]
        assert mock_run.call_count == 1


def test_sweep_perturbation_poisson(mock_benchmark_result: BenchmarkResult) -> None:
    with (
        patch("app.services.benchmark_runner.benchmark_runner.run_benchmark") as mock_run,
        patch("app.services.perturbation_sweeper.Path.exists", return_value=True),
        patch("numpy.load", return_value=np.ones((10, 10))),
        patch("numpy.save"),
        patch("os.fdopen", MagicMock()),
        patch("tempfile.mkstemp", return_value=(1, "temp.npy")),
        patch("app.services.perturbation_sweeper.Path.unlink"),
    ):
        mock_run.return_value = mock_benchmark_result

        result = perturbation_sweeper.sweep_perturbation(
            cnl_spec_path="test.cnl",
            benchmark_id="test_bench",
            dataset_path="test_data.npy",
            noise_type="poisson",
            noise_levels=[0.1],
        )

        assert result.noise_type == "poisson"
        assert result.accuracies == [0.85]


def test_sweep_perturbation_invalid_type() -> None:
    with pytest.raises(ValueError, match="Unsupported noise_type"):
        perturbation_sweeper.sweep_perturbation(
            cnl_spec_path="test.cnl",
            benchmark_id="test_bench",
            dataset_path="test_data.npy",
            noise_type="invalid",
        )


def test_augmentation_methods() -> None:
    data = np.ones((10, 10))

    # Gaussian
    perturbed_g = perturbation_sweeper._apply_gaussian(data, 0.1)
    assert perturbed_g.shape == data.shape
    assert not np.array_equal(perturbed_g, data)

    # Salt and pepper
    perturbed_sp = perturbation_sweeper._apply_salt_and_pepper(data, 0.2)
    assert perturbed_sp.shape == data.shape
    assert np.any((perturbed_sp == 0.0) | (perturbed_sp == 1.0))

    # Poisson
    perturbed_p = perturbation_sweeper._apply_poisson(data, 0.1)
    assert perturbed_p.shape == data.shape


def test_load_and_perturb_dataset_creation() -> None:
    with (
        patch("numpy.save") as mock_save,
        patch("numpy.load", return_value=np.ones((10, 10))),
        patch("app.services.perturbation_sweeper.Path.exists", return_value=True),
        patch("os.fdopen", MagicMock()),
    ):
        # Mocking tempfile.mkstemp to avoid actual file creation
        with patch("tempfile.mkstemp", return_value=(1, "temp.npy")):
            path = perturbation_sweeper._load_and_perturb_dataset("existing.npy", "gaussian", 0.1)
            assert path == "temp.npy"
            assert mock_save.called


def test_load_and_perturb_dataset_not_found() -> None:
    with patch("app.services.perturbation_sweeper.Path.exists", return_value=False):
        with pytest.raises(FileNotFoundError, match="not found"):
            perturbation_sweeper._load_and_perturb_dataset("non_existent.npy", "gaussian", 0.1)
