from typing import Literal

from pydantic import BaseModel, Field

from contracts import ReportGenerationResult


class ReportRequest(BaseModel):
    """Schema for a report generation request."""

    format: Literal["pdf", "html", "json"] = Field(
        default="pdf", description="Format of the report to generate"
    )
    summary: str = Field(
        default="Executive summary of the benchmark run.", description="Executive summary"
    )
    methodology: str = Field(
        default="Standard SNN evaluation methodology used.",
        description="Methodology description",
    )
    results: dict[str, float] = Field(
        default_factory=lambda: {"accuracy": 0.95, "latency_ms": 12.5},
        description="Benchmark results mapping metrics to values",
    )
    recommendations: str = Field(
        default="Consider deploying to target hardware.",
        description="Recommendations based on the results",
    )
    result_id: str | None = Field(
        default=None, description="The ID of the benchmark result to include in the report"
    )
    new_baseline: bool = Field(
        default=False, description="Flag indicating if this report should establish a new baseline"
    )


__all__ = ["ReportGenerationResult", "ReportRequest"]
