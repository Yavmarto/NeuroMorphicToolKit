"""Snapshot tests for Neurobench adapter — diff engine and result-store round-trip.

`DiffEngine.compute_diff` is the primary data-processing function that
the Neurobench router exposes to Flutter.  Snapshots pin the exact
MetricDiff and DiffResult field values so that any change to the
statistical comparison logic is immediately visible.

PYTHONPATH must include NeuroMorphicToolKit/Neurobench/neurobench so that
`app.*` and `contracts.*` are importable.
"""

from __future__ import annotations



# ---------------------------------------------------------------------------
# Shared deterministic BenchmarkResult factories
# ---------------------------------------------------------------------------

_TIMESTAMP = "2024-01-15T12:00:00"
_HASH = "abc123def456"


def _make_result(
    result_id: str,
    accuracy: float,
    latency_ms: float,
    seed: int = 0,
) -> object:
    """Construct a fully-specified BenchmarkResult with no dynamic fields."""
    # Import here so PYTHONPATH is already configured when this runs
    from contracts import BenchmarkResult

    return BenchmarkResult(
        id=result_id,
        benchmark_id="bench-lif-drop",
        network_spec_hash=_HASH,
        timestamp=_TIMESTAMP,
        target_id="teensy41",
        quantization_bits=8,
        encoding_method="rate",
        params={"duration": 1.0, "n_neurons": 50},
        metrics={"accuracy": accuracy, "latency_ms": latency_ms},
        wall_time_seconds=0.25,
        seed=seed,
    )


# ---------------------------------------------------------------------------
# 1. DiffEngine.compute_diff — no regression
# ---------------------------------------------------------------------------


def test_diff_engine_no_regression_snapshot(snapshot: object) -> None:
    """Pin DiffResult when current equals baseline (no change)."""
    from app.services.diff_engine import diff_engine

    baseline = _make_result("base-1", accuracy=0.92, latency_ms=12.5)
    current = _make_result("curr-1", accuracy=0.92, latency_ms=12.5)
    result = diff_engine.compute_diff(baseline, current)
    assert result.model_dump() == snapshot


def test_diff_engine_accuracy_regression_snapshot(snapshot: object) -> None:
    """Pin DiffResult when accuracy drops by 5 pp — threshold_violated=True."""
    from app.services.diff_engine import diff_engine

    baseline = _make_result("base-2", accuracy=0.95, latency_ms=10.0)
    current = _make_result("curr-2", accuracy=0.90, latency_ms=10.0)
    result = diff_engine.compute_diff(baseline, current)
    assert result.model_dump() == snapshot


def test_diff_engine_latency_improvement_snapshot(snapshot: object) -> None:
    """Pin DiffResult when latency improves (lower is better) by 20%."""
    from app.services.diff_engine import diff_engine

    baseline = _make_result("base-3", accuracy=0.90, latency_ms=20.0)
    current = _make_result("curr-3", accuracy=0.90, latency_ms=16.0)
    result = diff_engine.compute_diff(baseline, current)
    assert result.model_dump() == snapshot


# ---------------------------------------------------------------------------
# 2. ResultStore — save then retrieve round-trip
# ---------------------------------------------------------------------------


def test_result_store_roundtrip_snapshot(snapshot: object, tmp_path: object) -> None:
    """Pin the BenchmarkResult retrieved after a save→get round-trip."""
    from app.services.result_store import ResultStore

    db_file = str(tmp_path / "neurobench_test.sqlite")  # type: ignore[operator]
    store = ResultStore(db_path=db_file)

    original = _make_result("roundtrip-1", accuracy=0.88, latency_ms=14.0)
    store.save_result(original)

    retrieved = store.get_result("roundtrip-1")
    assert retrieved is not None
    # Snapshot the retrieved model so any deserialization mutation is caught
    assert retrieved.model_dump() == snapshot
