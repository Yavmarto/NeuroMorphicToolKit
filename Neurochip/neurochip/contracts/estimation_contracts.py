from typing import Any

from pydantic import BaseModel, Field, model_validator


class PowerEstimate(BaseModel):
    """
    Contract for power estimates, ensuring non-negative energy consumption.
    """

    target_id: str
    total_energy_pj: float = Field(ge=0.0)
    per_population_breakdown: list[dict[str, Any]]
    power_envelope_mw: float = Field(ge=0.0)
    exceeds_envelope: bool
    notes: str
    method: str | None = None
    is_estimate: bool = False
    accuracy_note: str | None = None


class LatencyEstimate(BaseModel):
    """
    Contract for latency estimates, enforcing monotonic ordering (best <= typical <= worst).
    """

    target_id: str
    network_depth: int
    best_case_us: float
    typical_us: float
    worst_case_us: float
    clock_speed_mhz: float
    inter_core_overhead_us: float

    @model_validator(mode="after")
    def validate_monotonic_latency(self) -> "LatencyEstimate":
        """
        Enforce invariant: best_case_us <= typical_us <= worst_case_us.
        """
        if not (self.best_case_us <= self.typical_us <= self.worst_case_us):
            raise ValueError(
                f"Latency order violation: best={self.best_case_us}, "
                f"typical={self.typical_us}, worst={self.worst_case_us}. "
                "Expected best <= typical <= worst."
            )
        return self
