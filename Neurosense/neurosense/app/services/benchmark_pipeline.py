"""Benchmark helpers for the flagship NeuroSense signal-to-spike workflow."""

from __future__ import annotations

import asyncio
import statistics
import time
from pathlib import Path
from typing import Any
from unittest.mock import patch

from ..schemas.encoding import build_encoding_config
from ..schemas.presets import FilterConfig
from .filter_pipeline import filter_pipeline
from .replay_service import ReplayService
from .session_artifact import load_artifact_data, load_artifact_metadata, load_spike_summary
from .spike_encoder import spike_encoder

_FLAGSHIP_FILTER = FilterConfig(
    bandpass_low_hz=20.0,
    bandpass_high_hz=100.0,
    notch_hz=50.0,
    artifact_rejection=False,
)
_FLAGSHIP_ENCODING = build_encoding_config("delta", delta_threshold=0.1)


def _average_ms(samples: list[float]) -> float:
    if not samples:
        return 0.0
    return round(statistics.fmean(samples), 3)


async def benchmark_flagship_pipeline(
    artifact_path: Path,
    *,
    iterations: int = 5,
    chunk_samples: int = 50,
) -> dict[str, Any]:
    """Measure artifact load, filtering, encoding, and replay throughput."""
    if iterations < 1:
        raise ValueError("iterations must be at least 1")

    metadata = load_artifact_metadata(artifact_path)
    raw_data, _, _ = load_artifact_data(artifact_path)
    if raw_data is None:
        raise ValueError(f"Artifact does not contain replayable signal data: {artifact_path}")

    sampling_rate_hz = float(metadata["sampling_rate_hz"])
    filter_pipeline.configure(_FLAGSHIP_FILTER, sampling_rate_hz)
    spike_encoder.configure(_FLAGSHIP_ENCODING, sampling_rate_hz, seed=7)

    load_timings: list[float] = []
    filter_timings: list[float] = []
    encode_timings: list[float] = []

    for _ in range(iterations):
        load_start = time.perf_counter()
        reloaded_data, _, _ = load_artifact_data(artifact_path)
        load_timings.append((time.perf_counter() - load_start) * 1000)

        if reloaded_data is None:
            raise ValueError(f"Artifact did not reload correctly: {artifact_path}")

        filter_start = time.perf_counter()
        filtered = filter_pipeline.apply(reloaded_data.copy())
        filter_timings.append((time.perf_counter() - filter_start) * 1000)

        encode_start = time.perf_counter()
        spike_encoder.encode(filtered)
        encode_timings.append((time.perf_counter() - encode_start) * 1000)

    replay_service = ReplayService()
    replay_elapsed_ms = 0.0
    replay_samples = 0
    replay_chunks = 0

    async def fast_sleep(_: float) -> None:
        return None

    with (
        patch("neurosense.app.services.replay_service._RECORDINGS_DIR", artifact_path.parent),
        patch("asyncio.sleep", new=fast_sleep),
    ):
        replay_start = time.perf_counter()
        await replay_service.start(artifact_path.stem, speed=10.0)
        async for chunk in replay_service.stream_chunks(chunk_samples=chunk_samples):
            replay_samples += int(chunk.shape[1])
            replay_chunks += 1
        replay_elapsed_ms = (time.perf_counter() - replay_start) * 1000

    replay_throughput = 0.0
    if replay_elapsed_ms > 0:
        replay_throughput = round(replay_samples / (replay_elapsed_ms / 1000), 3)

    spike_summary = load_spike_summary(artifact_path)
    return {
        "artifact_path": str(artifact_path),
        "artifact_schema_version": metadata["artifact_schema_version"],
        "capture_mode": metadata["capture_mode"],
        "support_level": metadata["support_level"],
        "channels": metadata["channels"],
        "sampling_rate_hz": metadata["sampling_rate_hz"],
        "duration_seconds": metadata["duration_seconds"],
        "artifact_load_ms_avg": _average_ms(load_timings),
        "filter_ms_avg": _average_ms(filter_timings),
        "encode_ms_avg": _average_ms(encode_timings),
        "replay_wall_ms": round(replay_elapsed_ms, 3),
        "replay_chunks": replay_chunks,
        "replay_throughput_samples_per_second": replay_throughput,
        "spike_batch_count": spike_summary["batch_count"],
        "spike_event_count": spike_summary["total_spike_events"],
        "benchmark_iterations": iterations,
    }


def benchmark_flagship_pipeline_sync(
    artifact_path: Path,
    *,
    iterations: int = 5,
    chunk_samples: int = 50,
) -> dict[str, Any]:
    """Synchronous wrapper for scripts and tests."""
    return asyncio.run(
        benchmark_flagship_pipeline(
            artifact_path,
            iterations=iterations,
            chunk_samples=chunk_samples,
        )
    )
