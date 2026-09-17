import base64
import hashlib
import logging
import re
import stat
import subprocess
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, cast

import httpx

from app.config import settings
from app.schemas.results import BenchmarkResult
from contracts.benchmark_contracts import MetricProvenance

logger = logging.getLogger(__name__)


class SnnMlirBenchmarkRunner:
    """Runner for the snn-mlir fast-simulation path.

    Sends a compiled ``.nir`` graph to the ``snn-mlir-compiler`` worker
    (workers/snn_mlir_compiler/), which lowers it via ``snn-opt`` and returns
    a native binary. That binary is then executed here to measure real C
    execution latency.

    Only feedforward, fully-connected networks are supported (snn-mlir's
    current constraint — see docs/snn_topologies_and_expansion.md). The
    compiled binary runs a real (non-leaky) integrate-and-fire loop
    (workers/snn_mlir_compiler/codegen.py) against a constant stimulus, so
    this runner reports latency and output spike count. ``accuracy`` stays
    ``None`` — there's no labeled dataset driving the input, so there's
    nothing to score against yet.
    """

    _SPIKE_COUNT_RE = re.compile(r"SNN_OUTPUT_SPIKES=(\d+)")

    def run_benchmark(
        self,
        benchmark_id: str,
        network_path: str,
        params: dict[str, Any] | None = None,
        seed: int | None = None,
        target: str = "snn-mlir",
    ) -> BenchmarkResult:
        """Compiles a ``.nir`` graph to native C via the snn-mlir worker and runs it.

        Args:
            benchmark_id (str): The ID of the benchmark to run.
            network_path (str): Path to the compiled ``.nir`` graph file.
            params (dict[str, Any] | None): Optional params — supports
                ``quantize`` (bool), ``n_steps`` (int), ``index_bits`` (int).
            seed (int | None): Optional random seed.
            target (str): Kept for interface parity with the other runners;
                snn-mlir only has one target (native C on the host CPU).

        Returns:
            BenchmarkResult: The standardized result of the benchmark run.
        """
        params = params or {}
        seed = seed or 42

        logger.info("Preparing snn-mlir benchmark %s (network: %s)", benchmark_id, network_path)

        start_time = time.time()

        nir_bytes = Path(network_path).read_bytes()
        network_hash = hashlib.sha256(nir_bytes).hexdigest()

        artifacts = self._compile(nir_bytes, params)
        raw_metrics = self._run_binary(artifacts["binary_b64"])

        wall_time = time.time() - start_time
        metrics = self._map_metrics(raw_metrics)
        result_id = str(uuid.uuid4())

        logger.info(
            "snn-mlir benchmark %s completed with latency %.3f ms",
            benchmark_id,
            metrics.get("latency_ms") or 0.0,
        )

        return BenchmarkResult(
            id=result_id,
            benchmark_id=benchmark_id,
            network_spec_hash="snn_mlir_" + network_hash,
            timestamp=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            target_id=target,
            quantization_bits=8 if params.get("quantize") else None,
            encoding_method="rate",
            params=params,
            metrics=metrics,
            wall_time_seconds=wall_time,
            seed=seed,
            metric_provenance=MetricProvenance.CPU_ESTIMATED,
        )

    def _compile(self, nir_bytes: bytes, params: dict[str, Any]) -> dict[str, Any]:
        """Sends the .nir graph to the snn-mlir-compiler worker and returns its artifacts."""
        payload = {
            "nir_content_b64": base64.b64encode(nir_bytes).decode("ascii"),
            "quantize": bool(params.get("quantize", False)),
            "n_steps": int(params.get("n_steps", 100)),
            "index_bits": int(params.get("index_bits", 64)),
            "compile_binary": True,
        }

        url = f"{settings.snn_mlir_compiler_url.rstrip('/')}/compile"
        try:
            with httpx.Client(timeout=settings.hardware_timeout_seconds) as client:
                response = client.post(url, json=payload)
                response.raise_for_status()
                return cast(dict[str, Any], response.json())
        except httpx.TimeoutException as e:
            raise RuntimeError(f"snn-mlir-compiler worker timed out at {url}: {e}") from e
        except httpx.HTTPStatusError as e:
            raise ValueError(
                f"snn-mlir-compiler worker rejected the graph "
                f"({e.response.status_code}): {e.response.text}"
            ) from e
        except httpx.HTTPError as e:
            raise RuntimeError(f"Failed to reach snn-mlir-compiler worker at {url}: {e}") from e

    def _run_binary(self, binary_b64: str | None) -> dict[str, float]:
        """Executes the compiled binary locally and times it."""
        if not binary_b64:
            raise RuntimeError("snn-mlir-compiler worker did not return a compiled binary.")

        with tempfile.TemporaryDirectory() as tmp_dir:
            binary_path = Path(tmp_dir) / "snn_network"
            binary_path.write_bytes(base64.b64decode(binary_b64))
            binary_path.chmod(binary_path.stat().st_mode | stat.S_IEXEC)

            run_start = time.time()
            proc = subprocess.run(
                [str(binary_path)],
                capture_output=True,
                timeout=30,
                check=False,
            )
            run_latency_ms = (time.time() - run_start) * 1000.0

            if proc.returncode != 0:
                raise RuntimeError(
                    f"Compiled snn-mlir binary exited with code {proc.returncode}: "
                    f"{proc.stderr.decode(errors='replace')}"
                )

            stdout = proc.stdout.decode(errors="replace")

        metrics: dict[str, float] = {"latency_ms": run_latency_ms}
        match = self._SPIKE_COUNT_RE.search(stdout)
        if match:
            metrics["output_spike_count"] = float(match.group(1))
        return metrics

    def _map_metrics(self, raw_metrics: dict[str, float]) -> dict[str, float | None]:
        """Maps raw execution metrics to the standard NeuroBench `BenchmarkResult` schema.

        `accuracy` is intentionally omitted (None): the constant stimulus driving the
        compiled binary has no ground-truth label, so there's nothing to score against.
        `spike_fidelity` carries the real output spike count from the IF loop when the
        binary reports one (older/stub binaries built before the loop was implemented
        won't print it, so it's left absent rather than faked).
        """
        metrics: dict[str, float | None] = {
            "latency_ms": raw_metrics.get("latency_ms"),
            "accuracy": None,
        }
        if "output_spike_count" in raw_metrics:
            metrics["spike_fidelity"] = raw_metrics["output_spike_count"]
        return metrics


# Expose a singleton instance, matching the other runners' module-level convention.
snn_mlir_runner = SnnMlirBenchmarkRunner()
