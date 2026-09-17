from typing import Annotated

from pydantic import BaseModel, Field, model_validator


class RobustnessCurve(BaseModel):
    """Contract for robustness curve results."""

    fault_type: str
    fault_rates: list[float]
    accuracies_mean: list[float]
    accuracies_ci_lower: list[float]
    accuracies_ci_upper: list[float]
    threshold_90pct: float | None = None
    n_seeds: Annotated[int, Field(ge=5)]

    @model_validator(mode="after")
    def validate_list_lengths(self) -> "RobustnessCurve":
        """Ensures all data lists have the same length."""
        lengths = {
            len(self.fault_rates),
            len(self.accuracies_mean),
            len(self.accuracies_ci_lower),
            len(self.accuracies_ci_upper),
        }
        if len(lengths) > 1:
            raise ValueError(
                f"All robustness curve lists must have the same length. Got: {lengths}"
            )
        return self


class PerturbationCurve(BaseModel):
    """Contract for input perturbation sweep results."""

    noise_type: str
    noise_levels: list[float]
    accuracies: list[float]
