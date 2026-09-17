from pydantic import BaseModel, model_validator


class FaultSweepResult(BaseModel):
    """
    Contract for fault sweep results, enforcing a maximum fault injection rate of 30% (0.3).
    """

    fault_type: str
    fault_rates: list[float]
    accuracies: list[float]
    accuracy_ci_lower: list[float]
    accuracy_ci_upper: list[float]
    threshold_90pct: float | None = None
    method: str | None = None
    is_estimate: bool = False

    @model_validator(mode="after")
    def validate_fault_rate_limit(self) -> "FaultSweepResult":
        """
        Enforce invariant: maximum fault injection rate is 0.3 (30%).
        """
        if any(rate > 0.3 for rate in self.fault_rates):
            raise ValueError("Fault injection rate exceeds 0.3 (30%) limit.")
        return self

    @model_validator(mode="after")
    def validate_consistency(self) -> "FaultSweepResult":
        """
        Enforce invariant: all result lists must have the same length.
        """
        lengths = {
            len(self.fault_rates),
            len(self.accuracies),
            len(self.accuracy_ci_lower),
            len(self.accuracy_ci_upper),
        }
        if len(lengths) > 1:
            raise ValueError("All result lists must have the same length.")
        return self
