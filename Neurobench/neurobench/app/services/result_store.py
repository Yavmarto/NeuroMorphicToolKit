"""Typed SQLAlchemy persistence for NeuroBench jobs, results, and baselines."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Protocol, cast

from sqlalchemy import Float, Integer, String, Text, create_engine, inspect, select
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from app.schemas.benchmarks import BenchmarkJob, JobStatus
from app.schemas.results import BenchmarkResult


def _default_db_path() -> str:
    """Resolve NeuroBench-owned storage without silently moving legacy data."""
    module_dir = os.environ.get("NEUROBENCH_DATA_DIR", "").strip()
    legacy_dir = os.environ.get("NEUROCNL_DATA_DIR", "").strip()
    data_root = os.environ.get("NMTK_DATA_DIR", "").strip()
    if module_dir:
        directory = Path(module_dir).expanduser()
    elif legacy_dir:
        directory = Path(legacy_dir).expanduser()
    elif data_root:
        directory = Path(data_root).expanduser() / "neurobench"
    else:
        directory = Path(".")
    return str(directory / "neurobench.sqlite")


class _Base(DeclarativeBase):
    pass


class _ResultFields(Protocol):
    id: str
    benchmark_id: str
    network_spec_hash: str
    timestamp: str
    target_id: str | None
    quantization_bits: int | None
    encoding_method: str | None
    params: str
    metrics: str
    spike_data: str | None
    wall_time_seconds: float
    seed: int
    metric_provenance: str


class _ResultRow(_Base):
    __tablename__ = "results"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    benchmark_id: Mapped[str] = mapped_column(String, nullable=False)
    network_spec_hash: Mapped[str] = mapped_column(String, nullable=False)
    timestamp: Mapped[str] = mapped_column(String, nullable=False)
    target_id: Mapped[str | None] = mapped_column(String)
    quantization_bits: Mapped[int | None] = mapped_column(Integer)
    encoding_method: Mapped[str | None] = mapped_column(String)
    params: Mapped[str] = mapped_column(Text, nullable=False)
    metrics: Mapped[str] = mapped_column(Text, nullable=False)
    spike_data: Mapped[str | None] = mapped_column(Text)
    wall_time_seconds: Mapped[float] = mapped_column(Float, nullable=False)
    seed: Mapped[int] = mapped_column(Integer, nullable=False)
    metric_provenance: Mapped[str] = mapped_column(
        String, nullable=False, default="cpu_estimated", server_default="cpu_estimated"
    )


class _BaselineRow(_Base):
    __tablename__ = "baselines"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    benchmark_id: Mapped[str] = mapped_column(String, nullable=False)
    network_spec_hash: Mapped[str] = mapped_column(String, nullable=False)
    timestamp: Mapped[str] = mapped_column(String, nullable=False)
    target_id: Mapped[str | None] = mapped_column(String)
    quantization_bits: Mapped[int | None] = mapped_column(Integer)
    encoding_method: Mapped[str | None] = mapped_column(String)
    params: Mapped[str] = mapped_column(Text, nullable=False)
    metrics: Mapped[str] = mapped_column(Text, nullable=False)
    spike_data: Mapped[str | None] = mapped_column(Text)
    wall_time_seconds: Mapped[float] = mapped_column(Float, nullable=False)
    seed: Mapped[int] = mapped_column(Integer, nullable=False)
    metric_provenance: Mapped[str] = mapped_column(
        String, nullable=False, default="cpu_estimated", server_default="cpu_estimated"
    )


class _JobRow(_Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    benchmark_id: Mapped[str] = mapped_column(String, nullable=False)
    network_path: Mapped[str] = mapped_column(Text, nullable=False)
    params: Mapped[str | None] = mapped_column(Text)
    seed: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, nullable=False)
    result_id: Mapped[str | None] = mapped_column(String)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[str] = mapped_column(String, nullable=False)
    updated_at: Mapped[str] = mapped_column(String, nullable=False)


class ResultStore:
    """Single persistence authority for benchmark jobs, results, and baselines."""

    def __init__(self, db_path: str | None = None) -> None:
        """Open one SQLite database and apply additive schema migrations."""
        self.db_path = db_path or _default_db_path()
        self._engine = create_engine(f"sqlite:///{self.db_path}")
        self._sessions = sessionmaker(self._engine, expire_on_commit=False)
        self._init_db()

    def _init_db(self) -> None:
        """Create current tables and migrate legacy provenance columns in place."""
        _Base.metadata.create_all(self._engine)
        inspector = inspect(self._engine)
        for table_name in ("results", "baselines"):
            columns = {column["name"] for column in inspector.get_columns(table_name)}
            if "metric_provenance" not in columns:
                with self._engine.begin() as connection:
                    connection.exec_driver_sql(
                        f"ALTER TABLE {table_name} ADD COLUMN "
                        "metric_provenance TEXT NOT NULL DEFAULT 'cpu_estimated'"
                    )

    @staticmethod
    def _result_payload(result: BenchmarkResult) -> dict[str, Any]:
        payload = result.model_dump(mode="json")
        return {
            "id": result.id,
            "benchmark_id": result.benchmark_id,
            "network_spec_hash": result.network_spec_hash,
            "timestamp": result.timestamp,
            "target_id": result.target_id,
            "quantization_bits": result.quantization_bits,
            "encoding_method": result.encoding_method,
            "params": json.dumps(payload["params"]),
            "metrics": json.dumps(payload["metrics"]),
            "spike_data": (
                json.dumps(payload["spike_data"]) if payload.get("spike_data") is not None else None
            ),
            "wall_time_seconds": result.wall_time_seconds,
            "seed": result.seed,
            "metric_provenance": str(payload["metric_provenance"]),
        }

    @staticmethod
    def _row_to_benchmark_result(row: _ResultFields) -> BenchmarkResult:
        return BenchmarkResult(
            id=row.id,
            benchmark_id=row.benchmark_id,
            network_spec_hash=row.network_spec_hash,
            timestamp=row.timestamp,
            target_id=row.target_id,
            quantization_bits=row.quantization_bits,
            encoding_method=row.encoding_method,
            params=json.loads(row.params),
            metrics=json.loads(row.metrics),
            spike_data=json.loads(row.spike_data) if row.spike_data else None,
            wall_time_seconds=row.wall_time_seconds,
            seed=row.seed,
            metric_provenance=row.metric_provenance,
        )

    def get_result(self, result_id: str) -> BenchmarkResult | None:
        with self._sessions() as session:
            row = session.get(_ResultRow, result_id)
            return self._row_to_benchmark_result(row) if row is not None else None

    def get_all_results(self) -> list[BenchmarkResult]:
        with self._sessions() as session:
            rows = session.scalars(select(_ResultRow)).all()
            return [self._row_to_benchmark_result(row) for row in rows]

    def save_result(self, result: BenchmarkResult) -> None:
        with self._sessions.begin() as session:
            session.merge(_ResultRow(**self._result_payload(result)))

    def get_all_baselines(self) -> list[BenchmarkResult]:
        with self._sessions() as session:
            rows = session.scalars(select(_BaselineRow)).all()
            return [self._row_to_benchmark_result(row) for row in rows]

    def save_baseline(self, result: BenchmarkResult) -> None:
        with self._sessions.begin() as session:
            session.merge(_BaselineRow(**self._result_payload(result)))

    def save_job(self, job: BenchmarkJob) -> None:
        with self._sessions.begin() as session:
            session.merge(
                _JobRow(
                    id=job.id,
                    benchmark_id=job.benchmark_id,
                    network_path=job.network_path,
                    params=json.dumps(job.params) if job.params is not None else None,
                    seed=job.seed,
                    status=job.status.value,
                    result_id=job.result_id,
                    error=job.error,
                    created_at=job.created_at,
                    updated_at=job.updated_at,
                )
            )

    def get_job(self, job_id: str) -> BenchmarkJob | None:
        with self._sessions() as session:
            row = session.get(_JobRow, job_id)
            if row is None:
                return None
            return BenchmarkJob(
                id=row.id,
                benchmark_id=row.benchmark_id,
                network_path=row.network_path,
                params=json.loads(row.params) if row.params else None,
                seed=row.seed,
                status=JobStatus(row.status),
                result_id=row.result_id,
                error=row.error,
                created_at=row.created_at,
                updated_at=row.updated_at,
            )


class _LazyResultStore:
    """Construct the store on first use so import never touches durable storage."""

    _store: ResultStore | None = None

    def __getattr__(self, name: str) -> Any:
        if _LazyResultStore._store is None:
            _LazyResultStore._store = ResultStore()
        return getattr(_LazyResultStore._store, name)


result_store: ResultStore = cast(ResultStore, _LazyResultStore())
