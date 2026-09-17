from hypothesis import strategies as st

from contracts import (
    BenchmarkResult,
    BenchmarkSuite,
    RegressionThreshold,
    RobustnessCurve,
)
from contracts.regression_contracts import RunResult

# Strategies for primitive types and constraints
st_timestamp = st.datetimes().map(lambda dt: dt.isoformat())
st_metrics = st.dictionaries(
    keys=st.text(min_size=1, max_size=10),
    values=st.one_of(
        st.none(), st.floats(min_value=1e-6, max_value=1e6, allow_infinity=False, allow_nan=False)
    ),
)
st_params = st.dictionaries(
    keys=st.text(min_size=1, max_size=10),
    values=st.one_of(st.text(max_size=10), st.integers(), st.floats(), st.booleans()),
)
# SQLite INTEGER is max 64-bit signed
st_sqlite_int = st.integers(min_value=-(2**63), max_value=2**63 - 1)


@st.composite
def benchmark_result_strategy(draw: st.DrawFn) -> BenchmarkResult:
    """Strategy to generate BenchmarkResult instances."""
    return BenchmarkResult(
        id=draw(st.uuids().map(str)),
        benchmark_id=draw(st.text(min_size=1, max_size=10)),
        network_spec_hash=draw(st.text(min_size=1, max_size=10)),
        timestamp=draw(st_timestamp),
        target_id=draw(st.one_of(st.none(), st.text(min_size=1, max_size=10))),
        quantization_bits=draw(st.one_of(st.none(), st.integers(min_value=1, max_value=32))),
        encoding_method=draw(st.one_of(st.none(), st.text(min_size=1, max_size=10))),
        params=draw(st_params),
        metrics=draw(st_metrics),
        spike_data=None,
        wall_time_seconds=draw(
            st.floats(min_value=0, max_value=1e6, allow_infinity=False, allow_nan=False)
        ),
        seed=draw(st_sqlite_int),
    )


@st.composite
def benchmark_suite_strategy(draw: st.DrawFn, dataset_exists: bool = True) -> BenchmarkSuite:
    """Strategy to generate BenchmarkSuite instances."""
    # We use a path that we know exists if dataset_exists is True
    path = "pyproject.toml" if dataset_exists else "non_existent_path"
    return BenchmarkSuite(
        task_name=draw(st.text(min_size=1, max_size=20)),
        dataset_path=path,
        metric=draw(
            st.sampled_from(
                [
                    "accuracy",
                    "latency_ms",
                    "power_mw",
                    "memory_kb",
                    "spike_fidelity",
                    "stopping_distance",
                ]
            )
        ),
    )


@st.composite
def run_result_strategy(draw: st.DrawFn) -> RunResult:
    """Strategy to generate RunResult instances."""
    return RunResult(
        score=draw(st.floats(min_value=0, max_value=1e6, allow_infinity=False, allow_nan=False)),
        timestamp=draw(st_timestamp),
        hardware_tag=draw(st.text(min_size=1, max_size=20)),
    )


@st.composite
def regression_threshold_strategy(draw: st.DrawFn) -> RegressionThreshold:
    """Strategy to generate RegressionThreshold instances."""
    return RegressionThreshold(
        tolerance=draw(
            st.floats(min_value=0.0, max_value=100.0, allow_infinity=False, allow_nan=False)
        ),
        comparison_direction=draw(st.sampled_from(["higher_is_better", "lower_is_better"])),
    )


@st.composite
def robustness_curve_strategy(draw: st.DrawFn) -> RobustnessCurve:
    """Strategy to generate RobustnessCurve instances."""
    size = draw(st.integers(min_value=1, max_value=20))
    # Generate lists of the same length
    fault_rates = draw(
        st.lists(
            st.floats(min_value=0, max_value=1.0, allow_infinity=False, allow_nan=False),
            min_size=size,
            max_size=size,
        )
    )
    accuracies_mean = draw(
        st.lists(
            st.floats(min_value=0, max_value=1.0, allow_infinity=False, allow_nan=False),
            min_size=size,
            max_size=size,
        )
    )
    accuracies_ci_lower = draw(
        st.lists(
            st.floats(min_value=0, max_value=1.0, allow_infinity=False, allow_nan=False),
            min_size=size,
            max_size=size,
        )
    )
    accuracies_ci_upper = draw(
        st.lists(
            st.floats(min_value=0, max_value=1.0, allow_infinity=False, allow_nan=False),
            min_size=size,
            max_size=size,
        )
    )

    return RobustnessCurve(
        fault_type=draw(st.text(min_size=1, max_size=20)),
        fault_rates=fault_rates,
        accuracies_mean=accuracies_mean,
        accuracies_ci_lower=accuracies_ci_lower,
        accuracies_ci_upper=accuracies_ci_upper,
        threshold_90pct=draw(
            st.one_of(
                st.none(),
                st.floats(min_value=0, max_value=1.0, allow_infinity=False, allow_nan=False),
            )
        ),
        n_seeds=draw(st.integers(min_value=5, max_value=100)),
    )
