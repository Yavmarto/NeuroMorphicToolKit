import hashlib
import importlib
import logging
import math
import random
import tempfile
import time
import uuid
from collections.abc import Mapping
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast

if TYPE_CHECKING:
    from app.services.neurobench_executor import NeuroBenchExecutorService

import httpx
import numpy as np
from neurocnl.simulation.run_simulation import run_pipeline  # type: ignore

from app.config import settings
from app.exceptions import (
    BenchmarkExecutionError,
    BenchmarkTimeoutError,
    OptionalDependencyError,
    SpikeFidelityError,
)
from app.schemas.benchmarks import BenchmarkDefinition
from app.schemas.results import BenchmarkResult
from app.services.benchmark_loader import benchmark_loader
from app.services.clock import utc_now_iso
from app.services.metric_normalizer import normalize_metrics
from app.services.neurosense_artifact import summarize_neurosense_artifact
from app.services.result_store import result_store
from contracts.benchmark_contracts import _provenance_from_target_id

logger = logging.getLogger(__name__)


def _get_neurobench_executor() -> "NeuroBenchExecutorService":
    """Import the optional NeuroBench executor only when required at runtime."""
    try:
        module = importlib.import_module("app.services.neurobench_executor")
    except ModuleNotFoundError as exc:
        if exc.name == "app.services.neurobench_executor":
            raise
        missing_dependency = exc.name or "unknown"
        raise OptionalDependencyError(
            "NeuroBench executor dependencies are not installed. Install the "
            "NeuroBench wrapper with the 'executor' extra to run benchmarks "
            "declared with executor='neurobench'. Missing module: "
            f"{missing_dependency}."
        ) from exc
    except ImportError as exc:
        raise OptionalDependencyError(
            "NeuroBench executor dependencies could not be imported. Install the "
            "NeuroBench wrapper with the 'executor' extra, or use an executor-enabled "
            f"worker image. Original error: {exc}"
        ) from exc
    return cast("NeuroBenchExecutorService", module.neurobench_executor)


class BenchmarkRunner:
    """Orchestrates the running of benchmarks.

    Loads the network, simulates, and scores against assertions.
    """

    @staticmethod
    def _build_metrics(report: dict[str, Any], primary_metric: str) -> dict[str, float | None]:
        """Build benchmark result metrics with canonical keys plus supported extras."""
        # Normalized metrics are numeric; we widen the value type for the result contract.
        metrics = cast(dict[str, float | None], normalize_metrics(report).values.copy())

        if "simulation_duration" in report:
            metrics["simulation_duration"] = float(report["simulation_duration"])

        if "spike_fidelity" in report:
            sf = float(report["spike_fidelity"])
            if math.isnan(sf) or math.isinf(sf):
                raise SpikeFidelityError(f"Computed spike fidelity is invalid ({sf}).")
            metrics["spike_fidelity"] = sf

        if primary_metric in report:
            metrics[primary_metric] = float(report[primary_metric])
        elif "overall_pass" in report:
            metrics["accuracy"] = 1.0 if report["overall_pass"] else 0.0

        return metrics

    def _run_neurosim(self, spec_path: str, params: dict[str, Any]) -> dict[str, Any]:
        """Executes the benchmark on the Neurosim backend."""
        return self._run_hardware_target(settings.neurosim_api_url, "neurosim", spec_path, params)

    def _run_neurochip(self, spec_path: str, params: dict[str, Any]) -> dict[str, Any]:
        """Executes the benchmark on the Neurochip hardware API."""
        return self._run_hardware_target(settings.neurochip_api_url, "neurochip", spec_path, params)

    def _run_hardware_target(
        self, url: str, target_name: str, spec_path: str, params: dict[str, Any]
    ) -> dict[str, Any]:
        """Internal helper to execute a benchmark on a hardware API target."""
        with open(spec_path) as f:
            spec_content = f.read()

        payload = {
            "spec": spec_content,
            "params": params,
        }

        try:
            with httpx.Client(timeout=settings.hardware_timeout_seconds) as client:
                response = client.post(url, json=payload)
                response.raise_for_status()
                raw_report = response.json()
                return normalize_metrics(raw_report).values
        except httpx.TimeoutException as e:
            logger.error("%s execution timed out at %s", target_name, url)
            raise BenchmarkTimeoutError(f"{target_name} execution timed out: {e}") from e
        except httpx.HTTPStatusError as e:
            logger.exception(
                "%s backend returned error %d: %s",
                target_name,
                e.response.status_code,
                e.response.text,
            )
            raise BenchmarkExecutionError(
                f"{target_name} backend returned error {e.response.status_code}: {e.response.text}"
            ) from e
        except Exception as e:
            logger.exception("Failed to connect to %s backend at %s", target_name, url)
            raise BenchmarkExecutionError(f"Failed to connect to {target_name} backend: {e}") from e

    def _run_recording_input_benchmark(
        self,
        benchmark_id: str,
        artifact_path: str,
        run_params: dict[str, Any],
        seed: int,
    ) -> BenchmarkResult:
        """Execute a contract benchmark against a NeuroSense recording artifact."""
        ingest_start = time.time()
        artifact_summary = summarize_neurosense_artifact(artifact_path)
        ingest_latency_ms = (time.time() - ingest_start) * 1000

        metrics: dict[str, float | None] = {
            "latency_ms": round(ingest_latency_ms, 3),
            "spike_fidelity": 1.0 if artifact_summary["spike_event_count"] > 0 else 0.0,
            "recording_duration_seconds": float(artifact_summary["duration_seconds"]),
            "input_channels": float(artifact_summary["channels"]),
            "input_spike_batches": float(artifact_summary["spike_batch_count"]),
            "input_spike_events": float(artifact_summary["spike_event_count"]),
        }

        result = BenchmarkResult(
            id=f"res_{uuid.uuid4().hex[:8]}",
            benchmark_id=benchmark_id,
            network_spec_hash=hashlib.sha256(artifact_path.encode()).hexdigest(),
            timestamp=utc_now_iso(),
            target_id="neurosense_recording",
            params=run_params,
            metrics=metrics,
            spike_data=artifact_summary,
            wall_time_seconds=round(ingest_latency_ms / 1000, 6),
            seed=seed,
            metric_provenance=_provenance_from_target_id("neurosense_recording"),
        )
        result_store.save_result(result)
        return result

    def _run_neurobench_library(
        self,
        benchmark_id: str,
        benchmark_def: BenchmarkDefinition,
        network_path: str | None,
        run_params: dict[str, object],
        seed: int,
    ) -> BenchmarkResult:
        """Execute a benchmark using the upstream NeuroBench library.

        Args:
            benchmark_id: The benchmark ID (must be in neurobench_executor.BENCHMARK_REGISTRY).
            benchmark_def: The BenchmarkDefinition loaded from JSON.
            network_path: Path to a saved PyTorch model (.pt or .pth). Required.
            run_params: Merged run parameters (default_params + caller overrides).
            seed: Random seed for reproducibility.

        Returns:
            BenchmarkResult persisted to the result store.

        Raises:
            ValueError: If network_path is None or the model file is not a .pt/.pth.
        """
        if not network_path:
            raise ValueError(
                f"Benchmark '{benchmark_id}' uses the NeuroBench executor and requires a "
                "network_path pointing to a PyTorch model file (.pt or .pth)."
            )

        model_path = Path(network_path)
        network_hash = hashlib.sha256(network_path.encode()).hexdigest()

        logger.info(
            "Routing benchmark '%s' to NeuroBench library executor (model: %s)",
            benchmark_id,
            network_path,
        )

        start_time = time.time()
        # The executor returns numeric metrics; widen them to the persisted contract type.
        metrics = cast(
            dict[str, float | None],
            _get_neurobench_executor().run(
                benchmark_id=benchmark_id,
                model_path=model_path,
                params=run_params,
                seed=seed,
            ),
        )
        wall_time = time.time() - start_time

        result = BenchmarkResult(
            id=f"res_{uuid.uuid4().hex[:8]}",
            benchmark_id=benchmark_id,
            network_spec_hash=network_hash,
            timestamp=utc_now_iso(),
            target_id="neurobench",
            params=run_params,
            metrics=metrics,
            wall_time_seconds=wall_time,
            seed=seed,
            metric_provenance=_provenance_from_target_id("neurobench"),
        )
        result_store.save_result(result)

        logger.info(
            "NeuroBench benchmark '%s' result persisted: %s (wall_time=%.2fs)",
            benchmark_id,
            result.id,
            wall_time,
        )
        return result

    def run_benchmark(
        self,
        benchmark_id: str,
        network_path: str | None = None,
        network_content: str | None = None,
        params: Mapping[str, object] | None = None,
        seed: int | None = None,
        target: str = "simulation",
    ) -> BenchmarkResult:
        """Executes a real benchmark for a given benchmark definition and target.

        Args:
            benchmark_id (str): The ID of the benchmark definition to run.
            network_path (str | None): Server-side file path to a .cnl spec or a .pt/.pth
                PyTorch model file. When a benchmark has executor="neurobench" and a .pt
                file is provided, the upstream NeuroBench library is used as the execution
                engine. CNL specs (.cnl) continue to use the neurocnl simulation path.
            network_content (str | None): Inline CNL spec content (CNL Studio integration).
            params (dict[str, Any] | None): Optional override parameters for the benchmark.
            seed (int | None): Seed for reproducibility.
            target (str): The execution target (simulation, neurosim, neurochip, spinnaker2).

        Returns:
            BenchmarkResult: The result of the benchmark run.

        Raises:
            ValueError: If the benchmark definition is not found, target is invalid, or
                neither network_path nor network_content is provided.
        """
        if not network_path and not network_content:
            raise ValueError("Either network_path or network_content must be provided.")

        benchmark_def = benchmark_loader.get(benchmark_id)
        if not benchmark_def:
            raise ValueError(f"Benchmark definition '{benchmark_id}' not found.")

        # Merge default parameters with overrides
        run_params: dict[str, object] = benchmark_def.default_params.copy()
        if params:
            run_params.update(params)

        # Use seed control
        if seed is None:
            seed = random.randint(0, 2**32 - 1)
        random.seed(seed)
        np.random.seed(seed)

        if benchmark_def.input_spec.type == "recording":
            artifact_path = (
                str(run_params.get("artifact_path"))
                if run_params.get("artifact_path") is not None
                else benchmark_def.input_spec.data_path
            )
            if not artifact_path:
                raise ValueError(
                    "Recording benchmarks require params['artifact_path'] or input_spec.data_path."
                )
            return self._run_recording_input_benchmark(
                benchmark_id=benchmark_id,
                artifact_path=artifact_path,
                run_params=run_params,
                seed=seed,
            )

        # Route to the upstream NeuroBench library when the benchmark declares executor="neurobench"
        if benchmark_def.executor == "neurobench":
            return self._run_neurobench_library(
                benchmark_id=benchmark_id,
                benchmark_def=benchmark_def,
                network_path=network_path,
                run_params=run_params,
                seed=seed,
            )

        # Resolve network spec — either from file path or inline content
        if network_content is not None:
            network_spec = network_content
        else:
            with open(network_path) as f:  # type: ignore[arg-type]
                network_spec = f.read()

        combined_spec = network_spec.strip() + "\n"
        for assertion in benchmark_def.assertions:
            combined_spec += f"{assertion}\n"

        # Calculate network spec hash
        network_hash = hashlib.sha256(network_spec.encode()).hexdigest()

        logger.info(
            "Starting benchmark execution: %s",
            benchmark_id,
            extra={
                "benchmark_id": benchmark_id,
                "network_path": network_path or "<inline>",
                "seed": seed,
            },
        )

        start_time = time.time()
        with tempfile.NamedTemporaryFile(mode="w", suffix=".cnl", delete=False) as tmp_spec:
            tmp_spec.write(combined_spec)
            tmp_spec_path = tmp_spec.name

        try:
            # Route to target
            sim_start = time.time()
            if target == "simulation":
                report = run_pipeline(tmp_spec_path)
            elif target == "neurosim":
                report = self._run_neurosim(tmp_spec_path, run_params)
            elif target in ("neurochip", "akida"):
                report = self._run_neurochip(tmp_spec_path, run_params)
            elif target == "spinnaker2":
                # Special handling for SpiNNaker2 hardware target
                from app.runners.spinnaker2_runner import spinnaker2_runner

                spinnaker2_result = spinnaker2_runner.run_benchmark(
                    benchmark_id=benchmark_id,
                    network_path=tmp_spec_path,
                    params=run_params,
                    seed=seed,
                )
                # Return the native result directly and skip the generic flow below.
                return spinnaker2_result
            else:
                raise ValueError(f"Invalid target: {target}")

            sim_duration = time.time() - sim_start
            wall_time = time.time() - start_time

            logger.info(
                "Execution completed on target '%s' for benchmark: %s",
                target,
                benchmark_id,
                extra={
                    "benchmark_id": benchmark_id,
                    "target": target,
                    "execution_duration_seconds": sim_duration,
                },
            )

            if "baseline_firing_rate" in report:
                baseline_rate = float(report["baseline_firing_rate"])
                if baseline_rate == 0.0:
                    raise SpikeFidelityError(
                        "Baseline firing rate is completely silent "
                        "(0 spikes across the simulation window)."
                    )
                if baseline_rate >= 1000.0 or math.isinf(baseline_rate):
                    raise SpikeFidelityError(
                        "Baseline firing rate is fully saturated "
                        "(at or above the Nyquist limit for the simulation timestep)."
                    )

            metrics = self._build_metrics(report, benchmark_def.scoring.primary_metric)

            result = BenchmarkResult(
                id=f"res_{uuid.uuid4().hex[:8]}",
                benchmark_id=benchmark_id,
                network_spec_hash=network_hash,
                timestamp=utc_now_iso(),
                params=run_params,
                metrics=metrics,
                wall_time_seconds=wall_time,
                seed=seed,
                metric_provenance=_provenance_from_target_id(None),
            )

            # Persist the result
            result_store.save_result(result)

            logger.info(
                "Benchmark execution completed: %s",
                benchmark_id,
                extra={
                    "benchmark_id": benchmark_id,
                    "result_id": result.id,
                    "total_wall_time_seconds": wall_time,
                    "metrics": metrics,
                },
            )

            return result

        finally:
            if Path(tmp_spec_path).exists():
                Path(tmp_spec_path).unlink()


# Expose a singleton instance
benchmark_runner = BenchmarkRunner()
