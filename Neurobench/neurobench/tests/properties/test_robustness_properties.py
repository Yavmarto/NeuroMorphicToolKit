import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from contracts.robustness_contracts import RobustnessCurve
from tests.properties.strategies import robustness_curve_strategy


@given(curve=robustness_curve_strategy())
@settings(max_examples=100)
def test_robustness_curve_contract_validity(curve: RobustnessCurve) -> None:
    """Property: robustness_curve_strategy generates valid RobustnessCurve instances."""
    # If we got here, it means the strategy successfully created a valid RobustnessCurve
    # which passed Pydantic validation (n_seeds >= 5 and matching list lengths).
    assert isinstance(curve, RobustnessCurve)
    assert curve.n_seeds >= 5
    assert len(curve.fault_rates) == len(curve.accuracies_mean)
    assert len(curve.accuracies_mean) == len(curve.accuracies_ci_lower)
    assert len(curve.accuracies_ci_lower) == len(curve.accuracies_ci_upper)


@given(
    n_seeds=st.integers(max_value=4),
    fault_type=st.text(min_size=1, max_size=20),
)
@settings(max_examples=100)
def test_robustness_curve_invalid_seeds_fails(n_seeds: int, fault_type: str) -> None:
    """Property: RobustnessCurve validation fails when n_seeds < 5."""
    with pytest.raises(ValidationError):
        RobustnessCurve(
            fault_type=fault_type,
            fault_rates=[0.0],
            accuracies_mean=[0.9],
            accuracies_ci_lower=[0.8],
            accuracies_ci_upper=[1.0],
            n_seeds=n_seeds,
        )


@given(
    fault_rates=st.lists(st.floats(), min_size=1, max_size=5),
    accuracies_mean=st.lists(st.floats(), min_size=6, max_size=10),
)
@settings(max_examples=100)
def test_robustness_curve_mismatched_lengths_fails(
    fault_rates: list[float], accuracies_mean: list[float]
) -> None:
    """Property: RobustnessCurve validation fails when list lengths are mismatched."""
    with pytest.raises(ValidationError):
        RobustnessCurve(
            fault_type="dead_neuron",
            fault_rates=fault_rates,
            accuracies_mean=accuracies_mean,
            accuracies_ci_lower=[0.8] * len(fault_rates),
            accuracies_ci_upper=[1.0] * len(fault_rates),
            n_seeds=5,
        )
