from pydantic import BaseModel, ConfigDict


class TargetMetrics(BaseModel):
    """Represents metrics for a specific hardware target."""

    model_config = ConfigDict(ser_json_inf_nan="null")

    target_id: str
    target_name: str
    quantization_bits: int
    accuracy: float
    accuracy_loss_pct: float
    estimated_power_mw: float
    estimated_latency_us: float
    memory_kb: float
    spike_fidelity: float
    warnings: list[str]


class TargetComparisonResult(BaseModel):
    """Represents the result of a cross-target comparison."""

    benchmark_id: str
    network_spec_hash: str
    targets: list[TargetMetrics]
    pareto_optimal: list[str]


class EncodingMetrics(BaseModel):
    """Metrics for a specific spike encoding scheme."""

    method: str
    accuracy: float
    spike_rate_hz: float
    efficiency_bits_per_spike: float
    computation_cost_relative: float


class EncodingComparisonResult(BaseModel):
    """Result of comparing multiple encoding schemes."""

    benchmark_id: str
    metrics: list[EncodingMetrics]
    recommendation: str
