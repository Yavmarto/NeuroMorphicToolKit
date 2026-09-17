"""Integration layer for the upstream NeuroBench benchmarking library.

This module bridges NMTK's benchmark runner with the open-source NeuroBench
package (https://github.com/NeuroBench/neurobench). It owns all imports of
that library, the benchmark registry, and the Speech2Spikes guard.

Speech2Spikes (S2SPreProcessor) is proprietary Accenture technology and is
explicitly blocked at both import and runtime levels in this module.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import torch  # type: ignore
import torch.utils.data  # type: ignore
from neurobench.benchmarks import Benchmark  # type: ignore
from neurobench.datasets import WISDM, MackeyGlass, PrimateReaching, SpeechCommands  # type: ignore
from neurobench.metrics.static import (  # type: ignore
    connection_sparsity,
    footprint,
    parameter_count,
)
from neurobench.metrics.workload import (  # type: ignore
    activation_sparsity,
    classification_accuracy,
    membrane_updates,
    mse,
    r2,
    smape,
    synaptic_operations,
)
from neurobench.models import NeuroBenchModel  # type: ignore
from neurobench.processors.preprocessors import MFCCPreProcessor  # type: ignore

# NOTE: Speech2Spikes / S2SPreProcessor is intentionally never imported here.
# It is proprietary (Accenture) and must not be used anywhere in NMTK.

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Speech2Spikes runtime guard
# ---------------------------------------------------------------------------

BLOCKED_PREPROCESSORS: frozenset[str] = frozenset({"Speech2Spikes", "S2SPreProcessor"})


def _assert_no_blocked_preprocessors(params: dict[str, Any]) -> None:
    """Raise ValueError if any param value references a blocked preprocessor.

    Args:
        params: The benchmark run parameters dict to inspect.

    Raises:
        ValueError: If a proprietary preprocessor name is detected in params.
    """
    for _key, val in params.items():
        if isinstance(val, str) and val in BLOCKED_PREPROCESSORS:
            raise ValueError(
                f"Preprocessor '{val}' is proprietary (Accenture Speech2Spikes) and is "
                "blocked in this installation. Use 'MFCCPreProcessor' for audio tasks instead."
            )
        if isinstance(val, list):
            for item in val:
                if isinstance(item, str) and item in BLOCKED_PREPROCESSORS:
                    raise ValueError(
                        f"Preprocessor '{item}' is proprietary (Accenture Speech2Spikes) and is "
                        "blocked in this installation. Use 'MFCCPreProcessor' instead."
                    )


# ---------------------------------------------------------------------------
# Benchmark registry
# ---------------------------------------------------------------------------
# Maps NMTK benchmark IDs to their upstream NeuroBench configuration.
# Each entry contains:
#   dataset_cls        - the NeuroBench dataset class to instantiate
#   dataset_kwargs     - default kwargs forwarded to the dataset constructor
#   preprocessors      - list of preprocessor classes to instantiate (NOT instances)
#   postprocessors     - list of postprocessor instances (usually empty)
#   static_metrics     - list of static metric functions (model properties)
#   workload_metrics   - list of workload metric functions (runtime performance)

_BenchmarkConfig = dict[str, Any]

BENCHMARK_REGISTRY: dict[str, _BenchmarkConfig] = {
    "mackey_glass": {
        "dataset_cls": MackeyGlass,
        "dataset_kwargs": {},
        "preprocessors": [],
        "postprocessors": [],
        "static_metrics": [parameter_count, connection_sparsity],
        "workload_metrics": [mse, r2, smape],
    },
    "primate_reaching": {
        "dataset_cls": PrimateReaching,
        "dataset_kwargs": {},
        "preprocessors": [],
        "postprocessors": [],
        "static_metrics": [parameter_count, connection_sparsity],
        "workload_metrics": [r2, mse],
    },
    "nehar": {
        "dataset_cls": WISDM,
        "dataset_kwargs": {},
        "preprocessors": [],
        "postprocessors": [],
        "static_metrics": [parameter_count, connection_sparsity, footprint],
        "workload_metrics": [classification_accuracy, activation_sparsity, synaptic_operations],
    },
    "keyword_spotting": {
        "dataset_cls": SpeechCommands,
        "dataset_kwargs": {},
        # MFCCPreProcessor only — Speech2Spikes is blocked
        "preprocessors": [MFCCPreProcessor],
        "postprocessors": [],
        "static_metrics": [parameter_count, connection_sparsity, footprint],
        "workload_metrics": [
            classification_accuracy,
            activation_sparsity,
            synaptic_operations,
            membrane_updates,
        ],
    },
}

# ---------------------------------------------------------------------------
# Metric key normalisation
# ---------------------------------------------------------------------------
# Maps upstream NeuroBench metric function __name__ values → NMTK AllowedMetric keys.

METRIC_KEY_MAP: dict[str, str] = {
    "classification_accuracy": "accuracy",
    "mse": "mse",
    "r2": "r2",
    "smape": "smape",
    "activation_sparsity": "activation_sparsity",
    "synaptic_operations": "synaptic_operations",
    "membrane_updates": "membrane_updates",
    "parameter_count": "parameter_count",
    "connection_sparsity": "connection_sparsity",
    "footprint": "memory_kb",
}


# ---------------------------------------------------------------------------
# Executor service
# ---------------------------------------------------------------------------


class NeuroBenchExecutorService:
    """Runs benchmarks using the upstream NeuroBench library.

    Accepts a path to a saved PyTorch model (.pt / .pth), loads it, wraps it in
    a NeuroBenchModel, and evaluates it against the registered dataset and metrics
    for the given benchmark_id.
    """

    def run(
        self,
        benchmark_id: str,
        model_path: Path,
        params: dict[str, Any],
        seed: int,
    ) -> dict[str, float]:
        """Execute a NeuroBench benchmark and return a normalised metrics dict.

        Args:
            benchmark_id: NMTK benchmark ID (must be in BENCHMARK_REGISTRY).
            model_path: Path to a saved PyTorch model file (.pt or .pth).
            params: Run-time parameters. May contain 'batch_size' and
                'dataset_kwargs'. Inspected for blocked preprocessors.
            seed: Random seed for reproducibility.

        Returns:
            Dict mapping NMTK AllowedMetric keys to float values.

        Raises:
            ValueError: If benchmark_id is not in the registry, the model file
                does not exist, or a blocked preprocessor is referenced.
            RuntimeError: If the upstream Benchmark.run() call fails.
        """
        _assert_no_blocked_preprocessors(params)

        config = BENCHMARK_REGISTRY.get(benchmark_id)
        if config is None:
            raise ValueError(
                f"Benchmark '{benchmark_id}' is not registered in the NeuroBench executor. "
                "Registered IDs: "
                + ", ".join(sorted(BENCHMARK_REGISTRY))
                + ". For custom CNL simulation benchmarks, submit a .cnl network spec instead."
            )

        if not model_path.exists():
            raise ValueError(f"Model file not found: {model_path}")

        if model_path.suffix not in {".pt", ".pth"}:
            raise ValueError(
                f"Expected a PyTorch model file (.pt or .pth), got '{model_path.suffix}'. "
                "For CNL network specs, use the simulation target without a .pt extension."
            )

        logger.info(
            "NeuroBenchExecutor: starting benchmark '%s' with model '%s' (seed=%d)",
            benchmark_id,
            model_path,
            seed,
        )

        torch.manual_seed(seed)

        # Load the PyTorch model
        try:
            raw_model = torch.load(str(model_path), weights_only=False)  # type: ignore[arg-type]
        except Exception as exc:
            raise RuntimeError(f"Failed to load model from '{model_path}': {exc}") from exc

        model = NeuroBenchModel(raw_model)

        # Build dataset
        dataset_kwargs: dict[str, Any] = {
            **config["dataset_kwargs"],
            **params.get("dataset_kwargs", {}),
        }
        try:
            dataset = config["dataset_cls"](**dataset_kwargs)
        except Exception as exc:
            raise RuntimeError(
                f"Failed to instantiate dataset for benchmark '{benchmark_id}': {exc}"
            ) from exc

        batch_size: int = int(params.get("batch_size", 32))
        dataloader = torch.utils.data.DataLoader(
            dataset,
            batch_size=batch_size,
            shuffle=False,
        )

        # Instantiate preprocessors (class → instance)
        preprocessors = [
            p() if (isinstance(p, type) and callable(p)) else p for p in config["preprocessors"]
        ]
        postprocessors: list[Any] = list(config["postprocessors"])

        benchmark = Benchmark(
            model,
            dataloader,
            preprocessors,
            postprocessors,
            metric_list=[config["static_metrics"], config["workload_metrics"]],
        )

        try:
            raw_results: dict[str, Any] = benchmark.run()
        except Exception as exc:
            raise RuntimeError(
                f"NeuroBench benchmark.run() failed for '{benchmark_id}': {exc}"
            ) from exc

        # Normalise keys to NMTK AllowedMetric names and coerce to float
        normalised: dict[str, float] = {}
        for raw_key, value in raw_results.items():
            nmtk_key = METRIC_KEY_MAP.get(raw_key, raw_key)
            if value is not None:
                try:
                    normalised[nmtk_key] = float(value)
                except (TypeError, ValueError):
                    logger.warning(
                        "Could not convert metric '%s' value '%s' to float — skipping.",
                        raw_key,
                        value,
                    )

        logger.info(
            "NeuroBenchExecutor: benchmark '%s' completed. Metrics: %s",
            benchmark_id,
            normalised,
        )
        return normalised


# Module-level singleton
neurobench_executor = NeuroBenchExecutorService()
