from __future__ import annotations

import pytest

from neurosense.app.services.benchmark_pipeline import benchmark_flagship_pipeline


@pytest.mark.anyio
async def test_benchmark_flagship_pipeline_reports_expected_metrics(
    canonical_session_path,
) -> None:
    result = await benchmark_flagship_pipeline(
        canonical_session_path, iterations=2, chunk_samples=25
    )

    assert result["artifact_schema_version"] == "1.0"
    assert result["channels"] == 2
    assert result["sampling_rate_hz"] == 200
    assert result["artifact_load_ms_avg"] >= 0.0
    assert result["filter_ms_avg"] >= 0.0
    assert result["encode_ms_avg"] >= 0.0
    assert result["replay_chunks"] > 0
    assert result["replay_throughput_samples_per_second"] > 0.0
    assert result["spike_batch_count"] >= 1
    assert result["spike_event_count"] >= 1


@pytest.mark.anyio
async def test_benchmark_flagship_pipeline_enforces_regression_thresholds(
    canonical_session_path,
) -> None:
    result = await benchmark_flagship_pipeline(canonical_session_path, iterations=2)

    assert result["artifact_load_ms_avg"] < 10.0
    assert result["filter_ms_avg"] < 5.0
    assert result["encode_ms_avg"] < 5.0
    assert result["replay_throughput_samples_per_second"] > 10000.0


@pytest.mark.anyio
async def test_benchmark_flagship_pipeline_rejects_invalid_iterations(
    canonical_session_path,
) -> None:
    with pytest.raises(ValueError, match="iterations must be at least 1"):
        await benchmark_flagship_pipeline(canonical_session_path, iterations=0)
