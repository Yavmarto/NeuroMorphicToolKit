import os
import tempfile
from pathlib import Path

import numpy as np
import numpy.typing as npt

from app.schemas.robustness import PerturbationCurve
from app.services.benchmark_runner import benchmark_runner


class PerturbationSweeper:
    """Handles input noise injection sweeps."""

    def _apply_gaussian(
        self,
        data: npt.NDArray[np.float64],
        level: float,
    ) -> npt.NDArray[np.float64]:
        """Applies Gaussian noise to the data."""
        noise = np.random.normal(0, level, data.shape)
        return np.asarray(data + noise, dtype=np.float64)

    def _apply_salt_and_pepper(
        self,
        data: npt.NDArray[np.float64],
        level: float,
    ) -> npt.NDArray[np.float64]:
        """Applies salt and pepper noise to the data."""
        perturbed = data.copy()
        # level is the probability of noise
        mask = np.random.random(data.shape) < level
        # half salt, half pepper
        salt = mask & (np.random.random(data.shape) < 0.5)
        pepper = mask & ~salt
        perturbed[salt] = 1.0
        perturbed[pepper] = 0.0
        return perturbed

    def _apply_poisson(
        self,
        data: npt.NDArray[np.float64],
        level: float,
    ) -> npt.NDArray[np.float64]:
        """Applies Poisson noise to the data."""
        # For spike trains or rate-based data, Poisson noise adds random variations.
        noise = np.random.poisson(level, data.shape)
        return np.asarray(data + noise, dtype=np.float64)

    def _load_and_perturb_dataset(self, dataset_path: str, noise_type: str, level: float) -> str:
        """Loads dataset, applies perturbation, and returns path to temporary perturbed file."""
        if not Path(dataset_path).exists():
            raise FileNotFoundError(f"Dataset path '{dataset_path}' not found.")

        try:
            data = np.asarray(np.load(dataset_path), dtype=np.float64)
        except Exception as e:
            raise ValueError(f"Failed to load dataset from '{dataset_path}': {e}") from e

        if noise_type == "gaussian":
            perturbed_data = self._apply_gaussian(data, level)
        elif noise_type == "salt_and_pepper":
            perturbed_data = self._apply_salt_and_pepper(data, level)
        elif noise_type == "poisson":
            perturbed_data = self._apply_poisson(data, level)
        else:
            raise ValueError(f"Unsupported noise type: {noise_type}")

        # Save to a temporary file
        fd, path = tempfile.mkstemp(suffix=".npy")
        try:
            with os.fdopen(fd, "wb") as tmp:
                np.save(tmp, perturbed_data)
        except Exception:
            Path(path).unlink()
            raise

        return path

    def sweep_perturbation(
        self,
        cnl_spec_path: str,
        benchmark_id: str,
        dataset_path: str,
        noise_type: str = "gaussian",
        noise_levels: list[float] | None = None,
    ) -> PerturbationCurve:
        """Runs an input perturbation sweep.

        Args:
            cnl_spec_path (str): Path to the .cnl network specification file.
            benchmark_id (str): The ID of the benchmark definition to run.
            dataset_path (str): The path to the benchmark's sensory dataset.
            noise_type (str): The type of noise to inject (gaussian, salt_and_pepper, poisson).
            noise_levels (list[float] | None): List of noise levels to sweep.

        Returns:
            PerturbationCurve: The generated results of the perturbation sweep.

        Raises:
            ValueError: If an unsupported noise_type is provided or array lengths mismatch.
        """
        if noise_levels is None:
            noise_levels = [0.0, 0.05, 0.1, 0.15, 0.2]

        supported_types = ["gaussian", "salt_and_pepper", "poisson"]
        if noise_type not in supported_types:
            raise ValueError(f"Unsupported noise_type '{noise_type}'. Supported: {supported_types}")

        accuracies = []
        for level in noise_levels:
            # Load, perturb and get temporary path
            perturbed_path = self._load_and_perturb_dataset(dataset_path, noise_type, level)

            try:
                # Run real SNN evaluation via simulation pipeline
                result = benchmark_runner.run_benchmark(
                    benchmark_id=benchmark_id,
                    network_path=cnl_spec_path,
                    params={
                        "noise_type": noise_type,
                        "noise_level": level,
                        "perturbed_dataset_path": perturbed_path,
                    },
                )

                # Record accuracy
                accuracy = result.metrics.get("accuracy")
                accuracies.append(float(accuracy) if accuracy is not None else 0.0)
            finally:
                if Path(perturbed_path).exists():
                    Path(perturbed_path).unlink()

        if len(noise_levels) != len(accuracies):
            raise ValueError(
                "PerturbationCurve array lengths for noise_levels and accuracies must be identical"
            )

        return PerturbationCurve(
            noise_type=noise_type,
            noise_levels=noise_levels,
            accuracies=accuracies,
        )


# Expose a singleton instance
perturbation_sweeper = PerturbationSweeper()
