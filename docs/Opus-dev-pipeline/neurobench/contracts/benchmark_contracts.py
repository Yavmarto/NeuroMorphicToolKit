"""Domain contracts for NeuroBench benchmarking framework.

Converts neurobench_spec.md into enforceable contracts.

Source: Neurobench/neurobench_spec.md (NB-B1 through NB-RE1)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class BenchmarkDefinitionContract(BaseModel):
    """Contract for benchmark definition (NB-B1, NB-B3)."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    task_type: Literal[
        "grip_stability",
        "spike_classification",
        "reaction_latency",
        "wake_word",
        "pattern_recognition",
        "custom",
    ]
    scoring_metric: str
    higher_is_better: bool = True
    pass_threshold: float | None = None

    @field_validator("id")
    @classmethod
    def non_empty_id(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Benchmark ID must not be empty.")
        return v


class BenchmarkResultContract(BaseModel):
    """Contract for benchmark result (NB-B1)."""

    model_config = ConfigDict(frozen=True)

    benchmark_id: str
    metrics: dict[str, float]
    wall_time_seconds: float
    seed: int | None = None

    @field_validator("wall_time_seconds")
    @classmethod
    def positive_time(cls, v: float) -> float:
        if v < 0:
            raise ValueError(f"Wall time must be >= 0, got {v}")
        return v


class RegressionCheckContract(BaseModel):
    """Contract for regression detection (NB-B2, NB-R2)."""

    model_config = ConfigDict(frozen=True)

    metric_name: str
    baseline_value: float
    current_value: float
    threshold_pct: float = 1.0  # default 1% noise threshold
    higher_is_better: bool = True

    @property
    def status(self) -> Literal["improved", "regressed", "unchanged"]:
        if self.baseline_value == 0:
            return "unchanged"
        delta_pct = (
            (self.current_value - self.baseline_value) / abs(self.baseline_value)
        ) * 100
        if self.higher_is_better:
            if delta_pct > self.threshold_pct:
                return "improved"
            elif delta_pct < -self.threshold_pct:
                return "regressed"
        else:
            if delta_pct < -self.threshold_pct:
                return "improved"
            elif delta_pct > self.threshold_pct:
                return "regressed"
        return "unchanged"

    @property
    def threshold_violated(self) -> bool:
        return self.status == "regressed"


class RobustnessCurveContract(BaseModel):
    """Contract for fault sweep robustness curve (NB-RP1)."""

    model_config = ConfigDict(frozen=True)

    fault_type: Literal["dead_neuron", "stuck_at", "weight_noise"]
    fault_rates: list[float]
    accuracies_mean: list[float]
    accuracies_ci_lower: list[float]
    accuracies_ci_upper: list[float]
    n_seeds: int

    @model_validator(mode="after")
    def consistent_lengths(self) -> RobustnessCurveContract:
        n = len(self.fault_rates)
        for name, lst in [
            ("accuracies_mean", self.accuracies_mean),
            ("accuracies_ci_lower", self.accuracies_ci_lower),
            ("accuracies_ci_upper", self.accuracies_ci_upper),
        ]:
            if len(lst) != n:
                raise ValueError(
                    f"{name} length ({len(lst)}) != fault_rates length ({n})."
                )
        return self

    @field_validator("n_seeds")
    @classmethod
    def minimum_seeds(cls, v: int) -> int:
        if v < 5:
            raise ValueError(
                f"Need >= 5 seeds for confidence intervals, got {v}. "
                "Spec requires N=5 per point."
            )
        return v


class CrossTargetComparisonContract(BaseModel):
    """Contract for cross-target comparison (NB-CT1)."""

    model_config = ConfigDict(frozen=True)

    target_id: str
    accuracy: float
    latency_us: float
    power_mw: float
    memory_bytes: int
    spike_fidelity: float
    quantization_loss: float

    @field_validator("accuracy", "spike_fidelity")
    @classmethod
    def unit_range(cls, v: float) -> float:
        if v < 0 or v > 1:
            raise ValueError(f"Metric must be in [0, 1], got {v}")
        return v
