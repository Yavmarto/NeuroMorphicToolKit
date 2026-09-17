from enum import StrEnum
from pathlib import Path
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

AllowedMetric = Literal[
    "accuracy",
    "latency_ms",
    "power_mw",
    "memory_kb",
    "spike_fidelity",
    "stopping_distance",
    "joules_per_spike",
    "energy_uj",
    # Upstream NeuroBench library metrics
    "mse",
    "r2",
    "smape",
    "activation_sparsity",
    "synaptic_operations",
    "membrane_updates",
    "parameter_count",
    "connection_sparsity",
]


class InputSpec(BaseModel):
    """Specification for benchmark input generation or source."""

    type: Literal["synthetic", "recording", "custom", "timeseries", "neural_recording"]
    synthetic_config: dict[str, Any] | None = None
    recording_session_id: str | None = None
    data_path: str | None = None


class ScoringConfig(BaseModel):
    """Configuration for benchmark scoring and success thresholds."""

    primary_metric: AllowedMetric
    secondary_metrics: list[AllowedMetric]
    higher_is_better: bool
    pass_threshold: float


class BenchmarkDefinition(BaseModel):
    """Definition of a benchmark test suite."""

    id: str
    name: str
    description: str
    task_type: str
    input_spec: InputSpec
    assertions: list[str]
    scoring: ScoringConfig
    default_params: dict[str, Any]
    builtin: bool
    executor: str = "cnl"  # "cnl" for neurocnl simulation, "neurobench" for upstream library


class BenchmarkSuite(BaseModel):
    """Contract for benchmark suite definitions."""

    task_name: Annotated[str, Field(min_length=1)]
    dataset_path: str
    metric: AllowedMetric

    @field_validator("dataset_path")
    @classmethod
    def validate_dataset_path(cls, v: str) -> str:
        """Validates that the dataset path exists."""
        if not Path(v).exists():
            raise ValueError(f"Dataset path does not exist: {v}")
        return v


class MetricProvenance(StrEnum):
    """Provenance of metrics in a BenchmarkResult.

    CPU_ESTIMATED — metrics computed via CPU-based simulation; NOT measured on target hardware.
    ON_DEVICE     — metrics measured on real neuromorphic hardware (SpiNNaker2, PYNQ, SynSense, etc.).
    """

    CPU_ESTIMATED = "cpu_estimated"
    ON_DEVICE = "on_device"


# Hardware target IDs whose metrics are measured on physical neuromorphic chips.
# NOTE: "akida" is intentionally excluded — modules.json sets localModeFallback: simulator_only,
# meaning Akida benchmarks run on CPU simulation in all standard configurations.
_HARDWARE_TARGET_IDS: frozenset[str] = frozenset({"spinnaker2", "synsense", "pynq"})


def _provenance_from_target_id(target_id: str | None) -> MetricProvenance:
    """Classify a result's provenance from its target_id string.

    Any target in _HARDWARE_TARGET_IDS produced metrics on physical hardware.
    Everything else (simulation, library, recording input) ran on CPU.
    """
    if target_id in _HARDWARE_TARGET_IDS:
        return MetricProvenance.ON_DEVICE
    return MetricProvenance.CPU_ESTIMATED


class BenchmarkResult(BaseModel):
    """Represents the result of a single benchmark run."""

    model_config = ConfigDict(ser_json_inf_nan="null")

    id: str
    benchmark_id: str
    network_spec_hash: str
    timestamp: str
    target_id: str | None = None
    quantization_bits: int | None = None
    encoding_method: str | None = None
    params: dict[str, Any]
    metrics: dict[str, float | None]
    spike_data: dict[str, Any] | None = None
    wall_time_seconds: float
    seed: int
    metric_provenance: MetricProvenance = MetricProvenance.CPU_ESTIMATED


class JobStatus(StrEnum):
    """Status of a benchmark execution job."""

    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"
    CANCELLED = "CANCELLED"


class BenchmarkJob(BaseModel):
    """Represents a queued benchmark execution job."""

    id: str
    benchmark_id: str
    network_path: str
    params: dict[str, Any] | None = None
    seed: int | None = None
    status: JobStatus = JobStatus.PENDING
    result_id: str | None = None
    error: str | None = None
    created_at: str
    updated_at: str
