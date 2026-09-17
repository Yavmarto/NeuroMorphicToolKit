# Adding a New Benchmark Metric

This guide provides developers with the steps needed to add a new benchmark metric to both the NeuroBench backend and frontend.

## Overview

A metric is a numerical value calculated from a benchmark simulation (e.g., `spike_fidelity`, `power_mw`, `accuracy`).

## Step 1: Backend Contract (Pydantic Model)

Update the `BenchmarkSuite` contract in `neurobench/contracts/benchmark_contracts.py` to include your new metric in the allowed literals.

```python
# neurobench/contracts/benchmark_contracts.py

class BenchmarkSuite(BaseModel):
    # ...
    metric: Literal[
        "accuracy", "latency_ms", "power_mw", "memory_kb", "spike_fidelity", "stopping_distance", "my_new_metric"
    ]
```

## Step 2: Implement Calculation in BenchmarkRunner

The `BenchmarkRunner` service calculates metrics from the `neurocnl` simulation report.

```python
# neurobench/app/services/benchmark_runner.py

class BenchmarkRunner:
    def run_benchmark(self, ...):
        # ...
        report = run_pipeline(tmp_spec_path)

        metrics = {
            # ...
            "my_new_metric": float(report.get("my_new_metric", 0.0)),
        }
        # ...
```

Ensure your metric calculation logic is correctly integrated into the `metrics` dictionary.

## Step 3: Define Metrics in JSON Benchmarks

If your metric should be the **primary metric** for a specific benchmark, update its JSON definition in `neurobench/benchmarks/builtin/`.

```json
{
  "id": "my_benchmark",
  "scoring": {
    "primary_metric": "my_new_metric",
    "secondary_metrics": ["accuracy", "latency_ms"],
    "higher_is_better": true,
    "pass_threshold": 0.9
  }
}
```

## Step 4: Frontend Data Model (Dart)

Update the `BenchmarkResult` class in `frontend/lib/models/result.dart` if necessary. Since `metrics` is already a `Map<String, double>`, it should handle new metrics automatically, but ensure any UI components that expect specific metrics are updated.

## Step 5: Update Result Summary Widget

To display your new metric with an interpretation, add it to the `ResultsSummaryCard` tooltips in `frontend/lib/widgets/results_summary_card.dart`.

```dart
// frontend/lib/widgets/results_summary_card.dart

String getMetricDescription(String metricName) {
  switch (metricName) {
    case 'my_new_metric':
      return 'Description of what my_new_metric measures.';
    // ...
  }
}
```

## Step 6: Testing

Add a test case in `neurobench/tests/` to verify that your new metric is correctly calculated and returned by the API.

```python
def test_my_new_metric(client):
    response = client.post("/api/neurobench/run", json={
        "benchmark_id": "my_benchmark",
        "network_path": "path/to/test.cnl"
    })
    assert "my_new_metric" in response.json()["metrics"]
```

Run tests using:
```bash
cd neurobench
export PYTHONPATH=$PYTHONPATH:$(pwd):$(pwd)/app
poetry run pytest
```
