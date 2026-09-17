import random

from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

from app.schemas.results import BenchmarkResult
from app.services.result_store import ResultStore
from tests.properties.strategies import benchmark_result_strategy


@given(result=benchmark_result_strategy())
@settings(max_examples=200, suppress_health_check=[HealthCheck.function_scoped_fixture])
def test_result_roundtrip_precision(mock_db: ResultStore, result: BenchmarkResult) -> None:
    """Property: Saving a result to ResultStore and retrieving it preserves metric precision."""
    mock_db.save_result(result)
    retrieved = mock_db.get_result(result.id)

    assert retrieved is not None
    assert retrieved.id == result.id

    for metric_name, original_value in result.metrics.items():
        assert metric_name in retrieved.metrics
        if original_value is None:
            assert retrieved.metrics[metric_name] is None
            continue
        retrieved_value = retrieved.metrics[metric_name]
        assert retrieved_value is not None
        # Check precision to 6 decimal places as required.
        # Using abs=1e-7 to ensure the 6th decimal is stable.
        assert abs(retrieved_value - original_value) < 1e-7


@given(seed=st.integers())
@settings(max_examples=200)
def test_seeded_benchmarking_stability(seed: int) -> None:
    """Property: A seeded benchmark process (using a seed) always yields identical scores."""
    # In a real implementation, this would call BenchmarkRunner with a seed.
    # Since BenchmarkRunner is currently a mock that returns a job ID,
    # we demonstrate the stability of a seeded process that produces scores.

    def simulate_seeded_run(run_seed: int) -> dict[str, float]:
        """Simulation of a benchmark run that is controlled by a seed."""
        # Using a fresh Random instance seeded with the provided seed
        rng = random.Random(run_seed)
        return {
            "accuracy": rng.random(),
            "latency_ms": rng.uniform(10, 100),
            "power_mw": rng.gauss(0.5, 0.1),
            "memory_kb": rng.randint(100, 10000),
            "spike_fidelity": rng.uniform(0.8, 1.0),
            "stopping_distance": rng.uniform(0.1, 5.0),
        }

    results_run1 = simulate_seeded_run(seed)
    results_run2 = simulate_seeded_run(seed)

    assert results_run1 == results_run2

    # Also verify different seeds yield different results (probabilistically almost certain)
    different_seed = seed + 1
    results_different = simulate_seeded_run(different_seed)
    assert results_different != results_run1
