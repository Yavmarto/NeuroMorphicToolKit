import importlib
import sqlite3
from pathlib import Path

import pytest
from sqlalchemy.exc import OperationalError

from app.services.clock import utc_now_iso
from app.services.result_store import ResultStore
from contracts.benchmark_contracts import (
    BenchmarkJob,
    BenchmarkResult,
    JobStatus,
    MetricProvenance,
)


def test_import_does_not_touch_the_database(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    """A bad DB path must fail at first use, not at import — see suite_api outage 2026-07-29."""
    monkeypatch.setenv("NEUROCNL_DATA_DIR", str(tmp_path / "does" / "not" / "exist"))
    mod = importlib.reload(importlib.import_module("app.services.result_store"))
    try:
        with pytest.raises(OperationalError):
            mod.result_store.get_all_results()
    finally:
        monkeypatch.undo()
        importlib.reload(mod)


def test_result_store_roundtrips_metric_provenance(tmp_path: Path) -> None:
    """metric_provenance persists through save and reload."""
    store = ResultStore(db_path=str(tmp_path / "test.sqlite"))

    result = BenchmarkResult(
        id="res_rt_001",
        benchmark_id="bench_001",
        network_spec_hash="hash_001",
        timestamp="2026-01-01T00:00:00Z",
        params={"p": 1},
        metrics={"accuracy": 0.95},
        wall_time_seconds=2.5,
        seed=42,
        metric_provenance=MetricProvenance.ON_DEVICE,
    )
    store.save_result(result)

    loaded = ResultStore(db_path=store.db_path).get_result("res_rt_001")
    assert loaded is not None
    assert loaded.metric_provenance == MetricProvenance.ON_DEVICE


def test_result_store_defaults_cpu_estimated_for_legacy_rows(tmp_path: Path) -> None:
    """Rows inserted before the migration (no metric_provenance column) load as cpu_estimated."""
    db_path = str(tmp_path / "legacy.sqlite")
    # Manually create old-style table without metric_provenance
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE results (
                id TEXT PRIMARY KEY,
                benchmark_id TEXT NOT NULL,
                network_spec_hash TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                target_id TEXT,
                quantization_bits INTEGER,
                encoding_method TEXT,
                params TEXT NOT NULL,
                metrics TEXT NOT NULL,
                spike_data TEXT,
                wall_time_seconds REAL NOT NULL,
                seed INTEGER NOT NULL
            )
        """)
        conn.execute("""
            INSERT INTO results VALUES
            ('res_legacy', 'bench', 'hash', '2025-01-01T00:00:00Z',
             NULL, NULL, NULL, '{"p":1}', '{"acc":0.8}', NULL, 1.0, 1)
        """)

    store = ResultStore(db_path=db_path)
    loaded = store.get_result("res_legacy")
    assert loaded is not None
    assert loaded.metric_provenance == MetricProvenance.CPU_ESTIMATED


def test_result_store_uses_owner_specific_data_root(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.delenv("NEUROBENCH_DATA_DIR", raising=False)
    monkeypatch.delenv("NEUROCNL_DATA_DIR", raising=False)
    monkeypatch.setenv("NMTK_DATA_DIR", str(tmp_path))
    (tmp_path / "neurobench").mkdir()

    store = ResultStore()

    assert store.db_path == str(tmp_path / "neurobench" / "neurobench.sqlite")


def test_result_store_roundtrips_job_and_baseline(tmp_path: Path) -> None:
    store = ResultStore(db_path=str(tmp_path / "authority.sqlite"))
    job = BenchmarkJob(
        id="job-1",
        benchmark_id="bench-1",
        network_path="workspace/model.nir",
        params={"batch_size": 8},
        seed=7,
        status=JobStatus.RUNNING,
        created_at="2026-08-25T12:00:00Z",
        updated_at="2026-08-25T12:00:01Z",
    )
    baseline = BenchmarkResult(
        id="baseline-1",
        benchmark_id="bench-1",
        network_spec_hash="sha256",
        timestamp="2026-08-25T12:00:02Z",
        params={"batch_size": 8},
        metrics={"accuracy": 0.9},
        wall_time_seconds=1.5,
        seed=7,
        metric_provenance=MetricProvenance.ON_DEVICE,
    )

    store.save_job(job)
    store.save_baseline(baseline)

    restarted = ResultStore(db_path=store.db_path)
    assert restarted.get_job(job.id) == job
    assert restarted.get_all_baselines() == [baseline]


def test_persisted_timestamp_is_aware_utc() -> None:
    timestamp = utc_now_iso()

    assert timestamp.endswith("Z")
    assert "+00:00Z" not in timestamp
