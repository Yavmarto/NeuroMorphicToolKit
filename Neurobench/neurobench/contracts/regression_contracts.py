from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator


class RunResult(BaseModel):
    """Contract for benchmark run results."""

    score: Annotated[float, Field(ge=0)]
    timestamp: str
    hardware_tag: Annotated[str, Field(min_length=1)]

    @field_validator("timestamp")
    @classmethod
    def validate_timestamp(cls, v: str) -> str:
        """Validates that the timestamp is ISO-8601 compliant."""
        if "T" not in v:
            raise ValueError("Timestamp must be ISO-8601 compliant (missing 'T')")
        try:
            datetime.fromisoformat(v)
        except ValueError as e:
            raise ValueError(f"Timestamp must be ISO-8601 compliant: {e}") from e
        return v


class RegressionThreshold(BaseModel):
    """Contract for regression thresholds."""

    tolerance: Annotated[float, Field(ge=0)]
    comparison_direction: Literal["higher_is_better", "lower_is_better"]


class RegressionCriteria(BaseModel):
    """Criteria for detecting regressions across multiple metrics."""

    default_threshold: RegressionThreshold
    overrides: dict[str, RegressionThreshold] = {}


class MetricDiff(BaseModel):
    """Represents the difference for a single metric between baseline and current result."""

    name: str
    baseline_value: float
    current_value: float
    delta: float
    delta_pct: float
    status: Literal["improved", "regressed", "unchanged"]
    threshold_violated: bool
    # Statistical fields
    p_value_ttest: float | None = None
    p_value_wilcoxon: float | None = None
    is_significant: bool | None = None
    baseline_std: float | None = None
    current_std: float | None = None
    baseline_ci: tuple[float, float] | None = None
    current_ci: tuple[float, float] | None = None


class DiffResult(BaseModel):
    """Represents the difference between a baseline and a current benchmark result."""

    baseline_id: str | list[str]
    current_id: str | list[str]
    metrics: list[MetricDiff]
    has_regression: bool = False


class TrendPoint(BaseModel):
    """A single point in a historical trend."""

    timestamp: str
    result_id: str
    metrics: dict[str, float]


class TrendAnalysisResult(BaseModel):
    """Historical trend analysis for a benchmark."""

    benchmark_id: str
    metric_names: list[str]
    history: list[TrendPoint]
